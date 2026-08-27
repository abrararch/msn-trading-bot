import asyncio
import json
import os
import ssl
import websockets
from dotenv import load_dotenv

load_dotenv()
token = os.getenv("QUOTEX_SESSION")
print("Connecting with token:", token, flush=True)

async def test():
    headers = {
        "Origin": "https://market-qx.trade",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    }
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE

    url = "wss://ws2.market-qx.trade/socket.io/?EIO=3&transport=websocket"
    async with websockets.connect(url, additional_headers=headers, ssl=ssl_context) as ws:
        placeholder_queue = []
        async for raw in ws:
            msg = raw if isinstance(raw, str) else raw.decode("utf-8", errors="ignore")

            if msg.startswith("0"):
                auth_payload = {"session": token, "isDemo": 1, "tournamentId": 0}
                await ws.send(f'42["authorization",{json.dumps(auth_payload, separators=(",", ":"))}]')
                print("Sent authorization payload", flush=True)
            elif msg == "2":
                await ws.send("3")
            elif "51-" in msg and "_placeholder" in msg:
                placeholder_queue.append(msg)
                print(f"Queued placeholder: {msg[:60]}", flush=True)
            elif placeholder_queue:
                # Find start of JSON array or object
                first_bracket = msg.find("[")
                first_brace = msg.find("{")
                start_idx = -1
                if first_bracket != -1 and (first_brace == -1 or first_bracket < first_brace):
                    start_idx = first_bracket
                elif first_brace != -1:
                    start_idx = first_brace

                if start_idx != -1:
                    clean_json = msg[start_idx:]
                    header = placeholder_queue.pop(0)
                    print(f"Delivering payload to header: {header[:60]}", flush=True)
                    if "instruments" in header:
                        try:
                            raw = json.loads(clean_json)
                            if isinstance(raw, dict) and "d" in raw:
                                raw = raw["d"]
                            print(f"\n=======================================================", flush=True)
                            print(f"SUCCESS! RECEIVED {len(raw)} INSTRUMENTS FROM QUOTEX BROKER!", flush=True)
                            print(f"=======================================================", flush=True)
                            
                            parsed = []
                            for it in raw:
                                if not isinstance(it, (list, tuple)) or len(it) < 3:
                                    continue
                                sym = str(it[1]).strip()
                                name = str(it[2]).strip().replace("\n", "")
                                payout = 0
                                if len(it) > 18 and it[18] is not None:
                                    try: payout = int(float(it[18]))
                                    except: pass
                                elif len(it) > 5 and it[5] is not None:
                                    try: payout = int(float(it[5]))
                                    except: pass
                                is_open = bool(it[14]) if len(it) > 14 and it[14] is not None else False
                                is_otc = "otc" in sym.lower() or "(otc)" in name.lower()
                                parsed.append({
                                    "symbol": sym, "name": name, "payout": payout, "is_open": is_open, "is_otc": is_otc
                                })
                            
                            filtered = [i for i in parsed if i["payout"] > 77 and i["is_open"]]
                            filtered.sort(key=lambda x: x["payout"], reverse=True)
                            
                            print(f"\nTotal Open & Payout > 77%: {len(filtered)}", flush=True)
                            for f in filtered[:25]:
                                print(f"  {f['name']:<28} | Payout: {f['payout']}% | OTC: {str(f['is_otc']):<5} | Sym: {f['symbol']}", flush=True)
                            return
                        except Exception as e:
                            print(f"JSON error: {e}", flush=True)

asyncio.run(test())
