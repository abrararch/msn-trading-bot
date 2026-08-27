import asyncio
import websockets
import json

async def test():
    uri = 'wss://ws2.market-qx.trade/socket.io/?EIO=3&transport=websocket'
    headers = {
        'Origin': 'https://market-qx.trade',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
    }
    async with websockets.connect(uri, additional_headers=headers) as ws:
        msg = await ws.recv()
        print('Initial handshake:', msg)
        msg40 = await ws.recv()
        print('Connect frame:', msg40)

        # Test auth with fresh session token
        auth = {"session": "PuZ4xth5F94dC9pMiwCjK5hVxhPSHZYkakuXVKRU", "isDemo": 0, "tournamentId": 0}
        await ws.send('42["authorization",' + json.dumps(auth) + ']')
        
        for i in range(8):
            try:
                m = await asyncio.wait_for(ws.recv(), timeout=4.0)
                print(f'[{i}] Text:', m[:120])
            except Exception as e:
                print('Ended:', e)
                break

asyncio.run(test())
