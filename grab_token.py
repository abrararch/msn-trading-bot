"""
Quotex Session Token Grabber
- Opens browser, waits for login
- Captures 'laravel_session' cookie AND intercepts WebSocket authorization frame
- Saves the session token to .env
"""
import asyncio
import json
import re
from playwright.async_api import async_playwright

async def grab_token():
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=False,
            args=['--disable-blink-features=AutomationControlled', '--start-maximized']
        )
        ctx = await browser.new_context(
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            no_viewport=True
        )
        page = await ctx.new_page()

        ws_token = None

        def on_websocket(ws):
            def on_sent(frame):
                nonlocal ws_token
                if isinstance(frame, str) and 'authorization' in frame:
                    print(f"\n>>> WebSocket AUTH frame: {frame[:300]}")
                    try:
                        idx = frame.find('[')
                        data = json.loads(frame[idx:])
                        if len(data) > 1 and isinstance(data[1], dict):
                            token = data[1].get('session', '')
                            if token and len(token) > 10:
                                ws_token = token
                                print(f"\n✅ SESSION TOKEN CAPTURED: {token}")
                    except Exception as e:
                        print(f"Parse error: {e}")
            ws.on('framesent', on_sent)

        page.on('websocket', on_websocket)

        print("Opening Quotex login page...")
        await page.goto("https://market-qx.trade/en/sign-in", wait_until="domcontentloaded", timeout=30000)
        print(">>> PLEASE LOG IN WITH: samcolons751@gmail.com / Ab@0922")
        print(">>> Waiting up to 120 seconds after login for WebSocket connection...")

        # Wait for token from WebSocket (most reliable source)
        for i in range(120):
            await asyncio.sleep(1)
            if ws_token:
                break
            if i % 10 == 0 and i > 0:
                # Print all cookies so far
                cookies = await ctx.cookies()
                names = [c['name'] for c in cookies]
                print(f"[{i}s] Cookies so far: {names}")

        # If WebSocket didn't fire, try laravel_session and other cookies
        if not ws_token:
            print("\nWebSocket token not found. Checking cookies...")
            cookies = await ctx.cookies()
            for c in cookies:
                print(f"  Cookie: {c['name']} = {c['value'][:30]}...")
                # laravel_session is the Quotex session token
                if c['name'] == 'laravel_session':
                    ws_token = c['value']
                    print(f"\n✅ Found laravel_session cookie: {c['value']}")
                    break

        print(f"\n=== FINAL TOKEN: {ws_token} ===")

        if ws_token:
            with open(".env", "r") as f:
                content = f.read()
            content = re.sub(r"QUOTEX_SESSION=.*", f"QUOTEX_SESSION={ws_token}", content)
            with open(".env", "w") as f:
                f.write(content)
            print("✅ Token saved to .env!")
        else:
            print("❌ Could not capture token. Please try Option B.")

        input("\nPress Enter to close browser...")
        await browser.close()

asyncio.run(grab_token())
