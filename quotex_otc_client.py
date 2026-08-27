"""
Quotex Broker WebSocket OTC Live Data Client
-------------------------------------------
Production-ready async WebSocket client for Quotex broker OTC markets.
- Protocol: Socket.IO (Engine.IO v3)
- Authentication: Session-based handshake
- Heartbeat: EIO=3 Ping/Pong (2 -> 3) + periodic tick keep-alive
- Market Data: Live quotes, 1-min & 5-min OHLC candle streams for OTC pairs (e.g. USDPHP_otc, EURUSD_otc)
- Resilience: Auto-reconnect with exponential backoff and error recovery
"""

import asyncio
import json
import logging
import math
import os
import ssl
import sys
import time
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional, Set
from dataclasses import dataclass, field

import websockets
from websockets.exceptions import ConnectionClosed, WebSocketException
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.text import Text

# Import dynamic authenticator
try:
    from quotex_authenticator import get_fresh_quotex_token
    AUTH_AVAILABLE = True
except Exception as e:
    logger.warning(f"Could not import quotex_authenticator: {e}")
    AUTH_AVAILABLE = False

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("QuotexOTC")
console = Console()


@dataclass
class Candle:
    """Represents a standardized OHLC candle."""
    asset: str
    timeframe: int  # in seconds (e.g., 60 for 1m, 300 for 5m)
    timestamp: int  # Unix timestamp in seconds
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0
    is_closed: bool = False

    @property
    def time_str(self) -> str:
        return datetime.fromtimestamp(self.timestamp, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    def to_dict(self) -> Dict[str, Any]:
        return {
            "asset": self.asset,
            "timeframe": self.timeframe,
            "timestamp": self.timestamp,
            "time_utc": self.time_str,
            "open": float(self.open),
            "high": float(self.high),
            "low": float(self.low),
            "close": float(self.close),
            "volume": float(self.volume),
            "is_closed": self.is_closed,
        }


class CandleAggregator:
    """Aggregates incoming price ticks and candle updates into 1m & 5m OHLC bars."""

    def __init__(self, asset: str):
        self.asset = asset
        self.current_price: float = 0.0
        self.last_tick_time: int = 0
        # Maps timeframe -> current in-progress Candle
        self.active_candles: Dict[int, Candle] = {}
        # Maps timeframe -> history of completed candles
        self.history: Dict[int, List[Candle]] = {60: [], 300: []}

    def update_tick(self, price: float, timestamp: int) -> Dict[int, Candle]:
        """Updates 1m (60s) and 5m (300s) candles with a new tick price."""
        p = float(price)
        ts = int(timestamp)
        self.current_price = p
        self.last_tick_time = ts
        updated = {}
        for tf in [60, 300]:
            candle_start = (ts // tf) * tf
            curr = self.active_candles.get(tf)

            if curr is None or curr.timestamp != candle_start:
                # Close previous candle if exists
                if curr is not None:
                    curr.is_closed = True
                    self.history[tf].append(curr)
                    if len(self.history[tf]) > 500:
                        self.history[tf].pop(0)

                # Initialize new candle with first micro-tick price of that candle window
                new_candle = Candle(
                    asset=self.asset,
                    timeframe=tf,
                    timestamp=candle_start,
                    open=p,
                    high=p,
                    low=p,
                    close=p,
                    is_closed=False,
                )
                self.active_candles[tf] = new_candle
                updated[tf] = new_candle
            else:
                # Update current active candle immediately
                if p > curr.high:
                    curr.high = p
                if p < curr.low:
                    curr.low = p
                curr.close = p
                updated[tf] = curr

        return updated

    def ingest_history_candles(self, raw_candles: List[Any], tf: int = 60):
        """Parses historical candle arrays or tick series from Quotex."""
        if not raw_candles:
            return

        # Check if raw_candles is a list of ticks [timestamp, price, ...]
        if isinstance(raw_candles[0], (list, tuple)) and len(raw_candles[0]) < 5:
            minute_ticks: Dict[int, List[float]] = {}
            for t in raw_candles:
                if not isinstance(t, (list, tuple)) or len(t) < 2:
                    continue
                try:
                    ts = int(t[0])
                    if ts > 1e11:
                        ts = ts // 1000
                    p = float(t[1])
                    m_win = (ts // tf) * tf
                    if m_win not in minute_ticks:
                        minute_ticks[m_win] = []
                    minute_ticks[m_win].append(p)
                except Exception:
                    continue

            for m_ts in sorted(minute_ticks.keys()):
                prices = minute_ticks[m_ts]
                if not prices:
                    continue
                o = float(prices[0])
                c = float(prices[-1])
                h = float(max(prices))
                l = float(min(prices))
                candle = Candle(
                    asset=self.asset,
                    timeframe=tf,
                    timestamp=m_ts,
                    open=o,
                    high=h,
                    low=l,
                    close=c,
                    is_closed=True
                )
                self.history[tf].append(candle)
                self.current_price = c
                self.last_tick_time = m_ts
        else:
            for item in raw_candles:
                try:
                    # Format: [timestamp, open, close, high, low] or dict
                    if isinstance(item, (list, tuple)) and len(item) >= 5:
                        ts = int(item[0])
                        if ts > 1e11:
                            ts = ts // 1000
                        o, c, h, l = float(item[1]), float(item[2]), float(item[3]), float(item[4])
                    elif isinstance(item, dict):
                        ts = int(item.get("time", item.get("timestamp", 0)))
                        if ts > 1e11:
                            ts = ts // 1000
                        o = float(item.get("open", 0))
                        c = float(item.get("close", 0))
                        h = float(item.get("high", 0))
                        l = float(item.get("low", 0))
                    else:
                        continue

                    candle = Candle(
                        asset=self.asset,
                        timeframe=tf,
                        timestamp=ts,
                        open=o,
                        high=h,
                        low=l,
                        close=c,
                        is_closed=True
                    )
                    self.history[tf].append(candle)
                    if c > 0:
                        self.current_price = c
                        self.last_tick_time = ts
                except Exception as e:
                    logger.debug(f"Error parsing candle item: {e}")

        # Deduplicate and sort by timestamp
        if tf in self.history:
            unique = {c.timestamp: c for c in self.history[tf]}
            self.history[tf] = sorted(unique.values(), key=lambda x: x.timestamp)


class QuotexOTCClient:
    """
    Production-ready asynchronous Socket.IO EIO=3 Quotex WebSocket client.
    Handles authentication, heartbeats, subscriptions, and stream parsing.
    """

    DEFAULT_ENDPOINT = "wss://ws2.market-qx.trade/socket.io/?EIO=3&transport=websocket"
    DEFAULT_ORIGIN = "https://market-qx.trade"
    DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    def __init__(
        self,
        session_token: Optional[str] = None,
        target_assets: Optional[List[str]] = None,
        endpoint_url: str = DEFAULT_ENDPOINT,
        is_demo: int = 1,
        tournament_id: int = 0,
        on_candle_callback: Optional[Callable[[Candle], None]] = None,
        on_tick_callback: Optional[Callable[[str, float, int], None]] = None,
    ):
        self.session_token = session_token or os.getenv("QUOTEX_SESSION", "")
        self.endpoint_url = endpoint_url
        self.is_demo = is_demo
        self.tournament_id = tournament_id
        self.target_assets = target_assets or ["USDPHP_otc", "EURUSD_otc", "GBPUSD_otc"]
        self.on_candle_callback = on_candle_callback
        self.on_tick_callback = on_tick_callback
        self.ws: Optional[websockets.WebSocketClientProtocol] = None
        self.is_connected = False
        self.is_authenticated = False
        self._running = False
        self._refreshing_token = False
        self._placeholder_queue: List[str] = []
        self._last_ping_time = time.time()
        self.live_instruments: List[Dict[str, Any]] = []
        self.current_prices: Dict[str, float] = {}
        self.current_price: float = 0.0
        self._aggregators: Dict[str, CandleAggregator] = {
            asset: CandleAggregator(asset) for asset in self.target_assets
        }

    def get_current_price(self, asset: str) -> float:
        """Returns the latest unrounded float price for an asset."""
        norm = self._normalize_asset_name(asset)
        if norm in self.current_prices:
            return self.current_prices[norm]
        agg = self._aggregators.get(norm)
        if agg and agg.current_price > 0:
            return agg.current_price
        return self.current_price

    async def refresh_session_token(self) -> Optional[str]:
        """Runs Playwright login in background to obtain a fresh session token."""
        if not AUTH_AVAILABLE:
            logger.error("quotex_authenticator is not available to refresh token.")
            return None

        if self._refreshing_token:
            logger.info("Token refresh is already in progress, waiting...")
            while self._refreshing_token:
                await asyncio.sleep(1)
            return self.session_token

        self._refreshing_token = True
        try:
            logger.info("🔄 Initiating automated Quotex login via Playwright (browser visible with anti-detection)...")
            new_token = await get_fresh_quotex_token(headless=False, timeout_seconds=60)
            if new_token:
                self.session_token = new_token
                logger.info(f"✅ Dynamic token refresh succeeded: {new_token[:8]}...")
                return new_token
            else:
                logger.error("❌ Failed to obtain new session token from automated login.")
                return None
        except Exception as e:
            logger.error(f"Error during automated token refresh: {e}")
            return None
        finally:
            self._refreshing_token = False

    def _normalize_asset_name(self, asset: str) -> str:
        """Standardizes user symbol (e.g. 'USD/PHP (OTC)' -> 'USDPHP_otc')."""
        clean = asset.strip().replace(" ", "").replace("/", "").replace("(", "").replace(")", "")
        if "otc" in clean.lower() and not clean.endswith("_otc"):
            clean = clean.replace("otc", "").replace("OTC", "") + "_otc"
        elif not clean.endswith("_otc") and ("otc" in asset.lower() or "otc" in asset):
            clean = clean + "_otc"
        return clean

    async def connect(self):
        """Starts connection with token refresh, graceful shutdown on auth failure, and backoff."""
        self._running = True
        attempt = 0
        max_delay = 30
        base_delay = 2

        # Check if session token exists, otherwise fetch one immediately
        if not self.session_token:
            logger.info("No session token found. Running initial dynamic authentication...")
            token = await self.refresh_session_token()
            if not token:
                logger.error("❌ Could not obtain a valid Quotex session token. Stopping client to prevent HTTP 429 rate-limiting.")
                self._running = False
                return

        while self._running:
            try:
                attempt += 1
                logger.info(f"Connecting to Quotex WebSocket (Attempt #{attempt})...")

                headers = {
                    "Origin": self.DEFAULT_ORIGIN,
                    "User-Agent": self.DEFAULT_USER_AGENT,
                }

                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE

                async with websockets.connect(
                    self.endpoint_url,
                    additional_headers=headers,
                    ssl=ssl_context,
                    ping_interval=None,  # We manually handle Socket.IO EIO=3 '2' -> '3' pings
                    max_size=2**24,
                ) as ws:
                    self.ws = ws
                    self.is_connected = True
                    attempt = 0  # Reset backoff on successful connect
                    logger.info("Connected to WebSocket server.")

                    # Start background tasks
                    reader_task = asyncio.create_task(self._read_loop())
                    heartbeat_task = asyncio.create_task(self._periodic_tick_loop())

                    done, pending = await asyncio.wait(
                        [reader_task, heartbeat_task],
                        return_when=asyncio.FIRST_COMPLETED,
                    )

                    for task in pending:
                        task.cancel()

            except (ConnectionClosed, WebSocketException) as e:
                logger.warning(f"WebSocket connection closed: {e}")
            except Exception as e:
                logger.error(f"Unexpected connection error: {e}")
            finally:
                self.is_connected = False
                self.is_authenticated = False
                self.ws = None

            if not self._running:
                break

            delay = min(max_delay, base_delay * (2 ** min(attempt, 5)))
            logger.info(f"Reconnecting in {delay} seconds...")
            await asyncio.sleep(delay)

    async def send_frame(self, data: str):
        """Sends raw frame over WebSocket."""
        if self.ws is not None:
            try:
                await self.ws.send(data)
                logger.debug(f"TX: {data}")
            except Exception as e:
                logger.debug(f"Failed to send frame: {e}")

    async def _send_authorization(self):
        """Sends EIO=3 authorization payload."""
        auth_payload = {
            "session": self.session_token,
            "isDemo": self.is_demo,
            "tournamentId": self.tournament_id,
        }
        msg = f'42["authorization",{json.dumps(auth_payload, separators=(",", ":"))}]'
        logger.info("Sending authorization payload...")
        await self.send_frame(msg)

    async def _subscribe_otc_markets(self):
        """Subscribes to live quotes, instruments, and candle history for OTC pairs."""
        logger.info(f"Subscribing to target OTC pairs: {self.target_assets}")

        # Core instrument request
        await self.send_frame('42["instruments/get"]')
        await self.send_frame('42["chart_notification/get"]')

        for asset in self.target_assets:
            norm_asset = self._normalize_asset_name(asset)
            if norm_asset not in self._aggregators:
                self._aggregators[norm_asset] = CandleAggregator(norm_asset)

            # Request real-time stream subscription
            await self.send_frame(f'42["sub_all_size",{{"asset":"{norm_asset}"}}]')

            # Request recent 1-minute historical candles (e.g. last 300 bars)
            now_ts = int(time.time())
            offset_seconds = 300 * 60
            hist_payload = {
                "asset": norm_asset,
                "index": 1,
                "time": now_ts,
                "offset": offset_seconds,
                "period": 60,
            }
            await self.send_frame(f'42["history/load",{json.dumps(hist_payload, separators=(",", ":"))}]')

    async def refresh_instruments(self):
        """Sends an on-demand request to Quotex WebSocket to refresh instruments and payouts."""
        if self.is_connected and self.is_authenticated:
            logger.info("Requesting live instruments refresh from Quotex broker...")
            await self.send_frame('42["instruments/get"]')
            await self.send_frame('42["tick"]')

    async def _periodic_tick_loop(self):
        """Sends periodic tick keep-alive and refreshes live instruments every 15 seconds."""
        count = 0
        while self.is_connected:
            try:
                if self.is_authenticated:
                    await self.send_frame('42["tick"]')
                    count += 1
                    # Refresh instruments every 15 seconds (every 3 ticks with 5s sleep)
                    if count % 3 == 0:
                        await self.send_frame('42["instruments/get"]')
                await asyncio.sleep(5)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.debug(f"Tick loop error: {e}")
                break

    async def _read_loop(self):
        """Reads and processes incoming WebSocket messages."""
        if not self.ws:
            return

        async for raw in self.ws:
            try:
                msg_str = raw if isinstance(raw, str) else raw.decode("utf-8", errors="ignore")
                await self._handle_message(msg_str)
            except Exception as e:
                logger.error(f"Error handling message: {e}")

    async def _handle_message(self, msg: str):
        """Parses Engine.IO & Socket.IO message frames."""
        if not msg:
            return

        # 1. Engine.IO Handshake Packet (0{...})
        if msg.startswith("0"):
            logger.info("Engine.IO handshake received. Authenticating...")
            await self._send_authorization()
            return

        # 2. Engine.IO Ping Packet (2) -> Respond with Pong (3)
        if msg == "2":
            self._last_ping_time = time.time()
            await self.send_frame("3")
            logger.debug("Received PING (2) -> Sent PONG (3)")
            return

        # 3. Engine.IO Pong Packet (3)
        if msg == "3":
            logger.debug("Received PONG (3)")
            return

        # 4. Socket.IO Event Frame (42[...])
        if msg.startswith("42"):
            await self._handle_event_frame(msg[2:])
            return

        # 5. Socket.IO Binary / Placeholder frame (e.g. 451-["history/load", ...])
        if "51-" in msg and "_placeholder" in msg:
            self._placeholder_queue.append(msg)
            return

        # 6. Raw Data Payload following a placeholder frame
        if self._placeholder_queue:
            first_bracket = msg.find("[")
            first_brace = msg.find("{")
            start_idx = -1
            if first_bracket != -1 and (first_brace == -1 or first_bracket < first_brace):
                start_idx = first_bracket
            elif first_brace != -1:
                start_idx = first_brace

            if start_idx != -1:
                clean_json = msg[start_idx:]
                header = self._placeholder_queue.pop(0)
                await self._handle_placeholder_payload(header, clean_json)
                return

    async def _handle_event_frame(self, json_str: str):
        """Parses Socket.IO 42[...] event frames."""
        try:
            payload = json.loads(json_str)
            if not isinstance(payload, list) or len(payload) == 0:
                return

            event = payload[0]
            data = payload[1] if len(payload) > 1 else None

            # Authentication Success
            if event == "s_authorization":
                self.is_authenticated = True
                logger.info("✅ Quotex WebSocket Authentication SUCCESSFUL!")
                await self._subscribe_otc_markets()
                return

            # Authentication Rejection / Token Expired
            if event == "authorization/reject":
                self.is_authenticated = False
                logger.warning(
                    "❌ Authorization REJECTED by Quotex server. "
                    "Session token may be expired. Triggering automated background re-login..."
                )
                new_token = await self.refresh_session_token()
                if new_token:
                    logger.info("Retrying authorization with newly refreshed token...")
                    await self._send_authorization()
                else:
                    logger.error("❌ Re-authentication failed. Stopping client connection to protect against HTTP 429 rate limiting.")
                    self._running = False
                    if self.ws is not None:
                        try:
                            await self.ws.close()
                        except Exception:
                            pass
                return

            # Live Quote Stream (e.g., s_tick, quotes/stream, tick, sub_all_size)
            if event in ("s_tick", "tick", "quotes/stream", "s_quotes", "live/quote", "realtime/quote", "quote", "sub_all_size"):
                self._process_quote_data(data)
                return

            # Live Candle Generated Event
            if event == "candle_generated":
                self._process_candle_generated(data)
                return

            # Instruments list from Quotex
            if event == "instruments/list":
                self._process_instruments_data(data)
                return

        except Exception as e:
            logger.debug(f"Event frame parse error ({json_str[:60]}...): {e}")

    async def _handle_placeholder_payload(self, header: str, data_str: str):
        """Processes binary/placeholder payload data (e.g. candle history or instruments list)."""
        try:
            data = json.loads(data_str)
            if "instruments" in header.lower():
                logger.info("Received live instruments payload from Quotex WebSocket!")
                self._process_instruments_data(data)
                return

            if "history/load" in header or "history/list/v2" in header:
                if isinstance(data, dict):
                    asset = data.get("asset", "")
                    raw_candles = data.get("candles") or data.get("data") or data.get("history") or []
                    norm_asset = self._normalize_asset_name(asset)
                    if norm_asset in self._aggregators and raw_candles:
                        self._aggregators[norm_asset].ingest_history_candles(raw_candles, tf=60)
                        logger.info(f"Loaded {len(raw_candles)} historical candles for {norm_asset}")
        except Exception as e:
            logger.debug(f"Placeholder payload parse error: {e}")

    def _process_instruments_data(self, data: Any):
        """Extracts live instruments, names, payouts (1m & 5m), open status, and Live/OTC detection directly from Quotex broker."""
        try:
            if isinstance(data, dict) and "d" in data:
                raw_list = data["d"]
            elif isinstance(data, list):
                raw_list = data
            else:
                return

            parsed = []
            for item in raw_list:
                if not isinstance(item, (list, tuple)) or len(item) < 3:
                    continue

                sym = str(item[1]).strip()
                name = str(item[2]).strip().replace("\n", "")

                # Determine if asset is OTC or Live Forex based on broker symbol & name
                sym_lower = sym.lower()
                name_lower = name.lower()
                is_otc = sym_lower.endswith("_otc") or "_otc" in sym_lower or "(otc)" in name_lower or "otc" in sym_lower

                # Extract Open status (item[14] is boolean or 1/0)
                is_open = True
                if len(item) > 14 and item[14] is not None:
                    is_open = bool(item[14])

                # Extract 24H change (item[-10] or item[17] if available)
                change_24h = 0.0
                try:
                    if len(item) >= 10 and item[-10] is not None:
                        change_24h = round(float(item[-10]), 2)
                except Exception:
                    pass

                # Extract 1-Minute Profit (item[-9] or turbo payout item[18] or standard payout item[5])
                profit_1m = 0
                try:
                    if len(item) >= 9 and item[-9] is not None:
                        profit_1m = int(float(item[-9]))
                    elif len(item) > 18 and item[18] is not None:
                        profit_1m = int(float(item[18]))
                    elif len(item) > 5 and item[5] is not None:
                        profit_1m = int(float(item[5]))
                except Exception:
                    pass

                # Extract 5-Minute Profit (item[-8] or standard payout item[5] or turbo payout item[18])
                profit_5m = 0
                try:
                    if len(item) >= 8 and item[-8] is not None:
                        profit_5m = int(float(item[-8]))
                    elif len(item) > 5 and item[5] is not None:
                        profit_5m = int(float(item[5]))
                    elif len(item) > 18 and item[18] is not None:
                        profit_5m = int(float(item[18]))
                except Exception:
                    pass

                # Active payout (defaulting to 1m or 5m)
                active_payout = profit_1m if profit_1m > 0 else (profit_5m if profit_5m > 0 else 0)

                # Determine accurate asset category: Currencies, Crypto, Commodities, Stocks
                raw_cat = str(item[3]).lower() if len(item) > 3 and item[3] else ""
                cat = "Currencies"
                if any(c in name_lower or c in sym_lower for c in ["gold", "silver", "crude", "brent", "oil", "xau", "xag", "uscrude", "ukbrent"]) or "commodity" in raw_cat:
                    cat = "Commodities"
                elif any(c in name_lower or c in sym_lower for c in [
                    "bitcoin", "btc", "eth", "ethereum", "crypto", "ripple", "xrp", "solana", "sol",
                    "doge", "ltc", "litecoin", "cosmos", "ato", "axsh", "avax", "link", "bnb", "binance",
                    "zcash", "dash", "bch", "trx", "matic", "shib"
                ]) or "crypto" in raw_cat:
                    cat = "Crypto"
                elif any(c in name_lower or c in sym_lower for c in [
                    "boeing", "microsoft", "intel", "johnson", "mcdonald", "pfizer", "apple", "tesla",
                    "trump", "amzn", "amazon", "googl", "google", "meta", "facebook", "nvda", "nvidia", "nflx"
                ]) or "stock" in raw_cat:
                    cat = "Stocks"
                else:
                    cat = "Currencies"

                parsed.append({
                    "symbol": sym,
                    "name": name,
                    "profit_1m": profit_1m,
                    "profit_5m": profit_5m,
                    "payout": active_payout,
                    "change_24h": change_24h,
                    "is_open": is_open,
                    "is_otc": is_otc,
                    "category": cat,
                })

            if parsed:
                # Filter strictly open assets that have active trading enabled
                filtered = [i for i in parsed if i["is_open"] and (i["profit_1m"] > 0 or i["profit_5m"] > 0)]
                # Sort descending by active payout percentage
                filtered.sort(key=lambda x: max(x["profit_1m"], x["profit_5m"], x["payout"]), reverse=True)
                self.live_instruments = filtered
                logger.info(
                    f"✅ Synchronized {len(filtered)} LIVE tradeable assets directly from Quotex "
                    f"({sum(1 for i in filtered if i['is_otc'])} OTC, {sum(1 for i in filtered if not i['is_otc'])} Live)"
                )

                # Ensure candle aggregators are ready for all open assets
                for inst in filtered:
                    s = self._normalize_asset_name(inst["symbol"])
                    if s not in self._aggregators:
                        self._aggregators[s] = CandleAggregator(s)
        except Exception as e:
            logger.error(f"Error parsing instruments list: {e}")

    def _process_quote_data(self, data: Any):
        """Processes incoming tick updates from Quotex with full unrounded float precision."""
        if not data:
            return

        # Format 1: List of ticks or single tick list
        if isinstance(data, list):
            # Check if this list itself is a single tick: [asset, time/price, price/time]
            if len(data) >= 2 and isinstance(data[0], str) and not isinstance(data[1], (list, dict)):
                self._process_single_tick_list(data)
                return

            for item in data:
                if isinstance(item, list):
                    self._process_single_tick_list(item)
                elif isinstance(item, dict):
                    self._process_single_quote_dict(item)

        # Format 2: Dictionary of quotes
        elif isinstance(data, dict):
            # Check if dict contains nested ticks list
            nested = data.get("d") or data.get("data") or data.get("ticks") or data.get("quotes") or data.get("tick")
            if isinstance(nested, list):
                self._process_quote_data(nested)
                return
            self._process_single_quote_dict(data)

    def _process_single_tick_list(self, item: List[Any]):
        """Parses a tick represented as a list, e.g. [asset, time, price] or [asset, price, time] or [asset, price]."""
        if len(item) < 2:
            return
        asset = str(item[0]).strip()
        if not asset:
            return

        ts = int(time.time())
        price = 0.0

        if len(item) == 2:
            try:
                price = float(item[1])
            except Exception:
                return
        elif len(item) >= 3:
            val1 = item[1]
            val2 = item[2]
            try:
                f1 = float(val1)
                f2 = float(val2)
                # Timestamp is typically > 100,000,000 (epoch)
                if f1 > 100000000:
                    ts = int(f1 // 1000 if f1 > 1e11 else f1)
                    price = f2
                elif f2 > 100000000:
                    ts = int(f2 // 1000 if f2 > 1e11 else f2)
                    price = f1
                else:
                    ts = int(f1)
                    price = f2
            except Exception:
                return

        if asset and price > 0:
            self._on_tick(asset, price, ts)

    def _process_single_quote_dict(self, d: Dict[str, Any]):
        """Parses a single quote dictionary with 6+ decimal float precision."""
        asset = str(d.get("asset") or d.get("symbol") or d.get("pair") or d.get("s") or "")
        raw_price = d.get("price") or d.get("close") or d.get("value") or d.get("rate") or d.get("last") or d.get("p") or d.get("c")
        if raw_price is None:
            return

        try:
            price = float(raw_price)
        except (ValueError, TypeError):
            return

        raw_time = d.get("time") or d.get("timestamp") or d.get("t") or d.get("ts") or time.time()
        try:
            ts_num = float(raw_time)
            ts = int(ts_num // 1000 if ts_num > 1e11 else ts_num)
        except (ValueError, TypeError):
            ts = int(time.time())

        if asset and price > 0:
            self._on_tick(asset, price, ts)

    def _process_candle_generated(self, data: Any):
        """Processes server-generated candle broadcasts."""
        if not isinstance(data, dict):
            return

        asset = self._normalize_asset_name(str(data.get("asset", "")))
        period = int(data.get("period", 60))
        ts = int(data.get("time", 0))
        if ts > 1e11:
            ts = ts // 1000
        o = float(data.get("open", 0))
        h = float(data.get("high", 0))
        l = float(data.get("low", 0))
        c = float(data.get("close", 0))

        candle = Candle(
            asset=asset,
            timeframe=period,
            timestamp=ts,
            open=o,
            high=h,
            low=l,
            close=c,
            is_closed=False
        )

        if asset in self._aggregators:
            self._aggregators[asset].active_candles[period] = candle
            if c > 0:
                self._aggregators[asset].current_price = c
                self._aggregators[asset].last_tick_time = ts
                self.current_prices[asset] = c
                self.current_price = c

        if self.on_candle_callback:
            if asyncio.iscoroutinefunction(self.on_candle_callback):
                asyncio.create_task(self.on_candle_callback(candle))
            else:
                try:
                    self.on_candle_callback(candle)
                except Exception as e:
                    logger.debug(f"Candle callback error: {e}")

    def _on_tick(self, raw_asset: str, price: float, ts: int):
        """Handles single tick update with zero throttle, updates 1m/5m aggregators, and triggers callbacks."""
        norm_asset = self._normalize_asset_name(raw_asset)
        price_float = float(price)
        ts_int = int(ts)

        self.current_prices[norm_asset] = price_float
        self.current_price = price_float

        if norm_asset not in self._aggregators:
            self._aggregators[norm_asset] = CandleAggregator(norm_asset)

        agg = self._aggregators[norm_asset]
        updated_candles = agg.update_tick(price_float, ts_int)

        if self.on_tick_callback:
            if asyncio.iscoroutinefunction(self.on_tick_callback):
                asyncio.create_task(self.on_tick_callback(norm_asset, price_float, ts_int))
            else:
                try:
                    self.on_tick_callback(norm_asset, price_float, ts_int)
                except Exception as e:
                    logger.debug(f"Tick callback error: {e}")

        if self.on_candle_callback:
            for candle in updated_candles.values():
                if asyncio.iscoroutinefunction(self.on_candle_callback):
                    asyncio.create_task(self.on_candle_callback(candle))
                else:
                    try:
                        self.on_candle_callback(candle)
                    except Exception as e:
                        logger.debug(f"Candle callback error: {e}")

    def get_latest_candles(self, asset: str, tf: int = 60, limit: int = 10) -> List[Candle]:
        """Returns the most recent completed & active candles."""
        norm_asset = self._normalize_asset_name(asset)
        agg = self._aggregators.get(norm_asset)
        if not agg:
            return []
        candles = list(agg.history.get(tf, []))
        active = agg.active_candles.get(tf)
        if active:
            candles.append(active)
        return candles[-limit:]

    async def close(self):
        """Closes WebSocket connection gracefully."""
        self._running = False
        if self.ws is not None:
            try:
                await self.ws.close()
            except Exception:
                pass
        logger.info("Quotex OTC Client stopped.")


# ----------------------------------------------------------------------
# CLI Runner with Live Terminal Table Visualization
# ----------------------------------------------------------------------

async def run_cli():
    session = os.getenv("QUOTEX_SESSION") or None
    target_otc = ["USDPHP_otc", "EURUSD_otc", "GBPUSD_otc"]

    console.print(Panel(
        "[bold cyan]Quotex Broker WebSocket OTC Live Data Client[/bold cyan]\n"
        f"[green]Target OTC Assets: {', '.join(target_otc)}[/green]\n"
        "[dim]Protocol: Socket.IO EIO=3 | Endpoint: wss://ws2.market-qx.trade[/dim]",
        border_style="cyan",
    ))

    def on_tick(asset: str, price: float, ts: int):
        t_str = datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%H:%M:%S")
        # Print periodic tick indicator
        console.print(f"[dim]{t_str} UTC[/dim] | [bold cyan]{asset}[/bold cyan] -> [bold green]{price:.5f}[/bold green]")

    def on_candle(candle: Candle):
        # We can display updated candles
        pass

    client = QuotexOTCClient(
        session_token=session,
        target_assets=target_otc,
        on_tick_callback=on_tick,
        on_candle_callback=on_candle,
    )

    async def display_table_loop():
        while True:
            await asyncio.sleep(10)
            for asset in target_otc:
                norm = client._normalize_asset_name(asset)
                c1m = client.get_latest_candles(norm, tf=60, limit=5)
                if c1m:
                    table = Table(title=f"Live 1-Minute OTC Candles: {norm}", border_style="cyan")
                    table.add_column("Time (UTC)", justify="center", style="cyan")
                    table.add_column("Open", justify="right")
                    table.add_column("High", justify="right", style="green")
                    table.add_column("Low", justify="right", style="red")
                    table.add_column("Close", justify="right", style="bold")
                    table.add_column("Status", justify="center")

                    for c in c1m:
                        table.add_row(
                            c.time_str[-12:],
                            f"{c.open:.5f}",
                            f"{c.high:.5f}",
                            f"{c.low:.5f}",
                            f"{c.close:.5f}",
                            "CLOSED" if c.is_closed else "[yellow]LIVE[/yellow]"
                        )
                    console.print(table)

    try:
        await asyncio.gather(
            client.connect(),
            display_table_loop(),
        )
    except KeyboardInterrupt:
        logger.info("Stopping client...")
    finally:
        await client.close()


if __name__ == "__main__":
    try:
        asyncio.run(run_cli())
    except KeyboardInterrupt:
        print("\nExited.")
