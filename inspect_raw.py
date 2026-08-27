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
        async for msg in ws:
            if isinstance(msg, bytes):
                msg = msg.decode("utf-8", errors="ignore")
            clean = msg.strip()
            if msg.startswith("0"):
                auth_payload = {"session": token, "isDemo": 1, "tournamentId": 0}
                await ws.send(f'42["authorization",{json.dumps(auth_payload, separators=(",", ":"))}]')
                print("Sent authorization payload", flush=True)
            elif msg.startswith("451-") or msg.startswith("452-"):
                placeholder_queue.append(msg)
                print(f"Queued placeholder (len={len(placeholder_queue)}): {msg[:60]}", flush=True)
            elif placeholder_queue and (clean.startswith("[") or clean.startswith("{")):
                header = placeholder_queue.pop(0)
                print(f"Matched payload to header: {header[:60]}", flush=True)
                if "instruments" in header:
                    raw = json.loads(clean)
                    print(f"\n==========================================", flush=True)
                    print(f"SUCCESS! RAW INSTRUMENTS COUNT: {len(raw)}", flush=True)
                    print(f"==========================================", flush=True)
                    for idx, it in enumerate(raw[:8]):
                        print(f"\n--- ITEM {idx} (len={len(it)}) ---", flush=True)
                        for field_idx, val in enumerate(it):
                            print(f"  [{field_idx}]: {val}", flush=True)
                    return
            elif msg == "2":
                await ws.send("3")

asyncio.run(test())
