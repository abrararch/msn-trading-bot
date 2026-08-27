import asyncio
import json
import os
import ssl
import websockets
from dotenv import load_dotenv

load_dotenv()
token = os.getenv("QUOTEX_SESSION")

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
        pending_placeholder = None
        async for msg in ws:
            if isinstance(msg, bytes):
                msg = msg.decode("utf-8", errors="ignore")
            
            clean_msg = msg.strip()

            if msg.startswith("0"):
                auth_payload = {"session": token, "isDemo": 1, "tournamentId": 0}
                await ws.send(f'42["authorization",{json.dumps(auth_payload)}]')
            elif msg.startswith("451-") or msg.startswith("452-"):
                pending_placeholder = msg
            elif pending_placeholder is not None and (clean_msg.startswith("[") or clean_msg.startswith("{")):
                if "instruments/list" in pending_placeholder:
                    try:
                        raw_list = json.loads(clean_msg)
                        if isinstance(raw_list, dict) and "d" in raw_list:
                            raw_list = raw_list["d"]
                        print(f"\n==========================================", flush=True)
                        print(f"SUCCESSFULLY PARSED {len(raw_list)} LIVE QUOTEX INSTRUMENTS!", flush=True)
                        print(f"==========================================", flush=True)
                        
                        parsed = []
                        for it in raw_list:
                            sym = str(it[1]).strip()
                            name = str(it[2]).strip().replace("\n", "")
                            payout = int(float(it[18])) if (len(it) > 18 and it[18] is not None) else int(float(it[5])) if (len(it) > 5 and it[5] is not None) else 0
                            is_open = bool(it[14]) if len(it) > 14 else True
                            is_otc = "otc" in sym.lower() or "(otc)" in name.lower()
                            parsed.append({
                                "symbol": sym,
                                "name": name,
                                "payout": payout,
                                "is_open": is_open,
                                "is_otc": is_otc
                            })
                        
                        # Filter > 77%
                        filtered = [i for i in parsed if i["payout"] > 77 and i["is_open"]]
                        filtered.sort(key=lambda x: x["payout"], reverse=True)
                        print(f"\nTotal Open & Payout > 77%: {len(filtered)}", flush=True)
                        for f in filtered[:25]:
                            print(f"  {f['name']:<25} | Sym: {f['symbol']:<15} | Payout: {f['payout']}% | OTC: {f['is_otc']}", flush=True)
                        return
                    except Exception as e:
                        print("Error parsing instruments list:", e)
                pending_placeholder = None
            elif msg == "2":
                await ws.send("3")

asyncio.run(test())
