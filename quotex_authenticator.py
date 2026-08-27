"""
Quotex Automated Authenticator & Token Extractor
----------------------------------------------
Automates login to Quotex via Playwright to dynamically retrieve a fresh
WebSocket session token and updates the .env configuration.
"""

import os
import re
import asyncio
import logging
from urllib.parse import urlparse
from pathlib import Path
from typing import Optional
from dotenv import load_dotenv

logger = logging.getLogger("QuotexAuth")
load_dotenv()


def update_env_token(token: str, env_path: Optional[Path] = None):
    """Updates or adds QUOTEX_SESSION in the .env file."""
    if env_path is None:
        env_path = Path(__file__).resolve().parent / ".env"

    if not env_path.exists():
        env_path.write_text(f"QUOTEX_SESSION={token}\n", encoding="utf-8")
        return

    content = env_path.read_text(encoding="utf-8")
    if "QUOTEX_SESSION=" in content:
        content = re.sub(r"QUOTEX_SESSION=.*", f"QUOTEX_SESSION={token}", content)
    else:
        content += f"\nQUOTEX_SESSION={token}\n"

    env_path.write_text(content, encoding="utf-8")
    os.environ["QUOTEX_SESSION"] = token
    logger.info("Updated QUOTEX_SESSION in .env file.")


async def get_fresh_quotex_token(
    email: Optional[str] = None,
    password: Optional[str] = None,
    headless: bool = False,
    timeout_seconds: int = 60,
) -> Optional[str]:
    """
    Launches a Playwright Chromium browser (headed by default with anti-detection args)
    to log into Quotex and extract the fresh session token.
    """
    from playwright.async_api import async_playwright

    email = email or os.getenv("QUOTEX_EMAIL", "")
    password = password or os.getenv("QUOTEX_PASSWORD", "")

    if not email or not password:
        logger.error("No Quotex credentials provided in environment or parameters.")
        return None

    domains = [
        "https://market-qx.trade",
        "https://qxbroker.com",
        "https://market-qx.pro",
        "https://quotex.io",
    ]

    extracted_token: Optional[str] = None

    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=headless,
            args=[
                "--disable-blink-features=AutomationControlled",
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--disable-dev-shm-usage",
                "--disable-accelerated-2d-canvas",
                "--no-first-run",
                "--no-zygote",
                "--hide-scrollbars",
                "--disable-background-networking",
            ],
        )

        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            viewport={"width": 1280, "height": 800},
            locale="en-US",
        )

        # Anti-detect script injection
        await context.add_init_script("""
            Object.defineProperty(navigator, 'webdriver', {
                get: () => undefined
            });
        """)

        page = await context.new_page()

        # Intercept websocket frames or network requests containing token
        def on_websocket(ws):
            nonlocal extracted_token
            def on_frame_sent(payload):
                nonlocal extracted_token
                try:
                    if isinstance(payload, str) and "authorization" in payload and "session" in payload:
                        match = re.search(r'"session":\s*"([^"]+)"', payload)
                        if match:
                            extracted_token = match.group(1)
                            logger.info(f"Captured token from WebSocket frame: {extracted_token[:8]}...")
                except Exception:
                    pass
            ws.on("framesent", on_frame_sent)

        page.on("websocket", on_websocket)

        for base_url in domains:
            try:
                sign_in_url = f"{base_url}/en/sign-in"
                logger.info(f"Attempting login via {sign_in_url}...")

                try:
                    await page.goto(sign_in_url, timeout=60000, wait_until="domcontentloaded")
                except Exception as nav_err:
                    logger.warning(f"Navigation issue on {sign_in_url}: {nav_err}")
                    continue

                await asyncio.sleep(3)

                # Proper path check to see if actually on trade room page
                parsed_path = urlparse(page.url).path.rstrip("/")
                if parsed_path.endswith("/trade"):
                    logger.info("Already on trade page. Extracting token...")
                else:
                    # Look for email input
                    email_selector = None
                    for sel in [
                        'input[name="email"]',
                        'input[type="email"]',
                        '#tab-1 input[type="email"]',
                        'input[placeholder*="Email"]',
                        'input[placeholder*="email"]',
                    ]:
                        if await page.query_selector(sel):
                            email_selector = sel
                            break

                    if email_selector:
                        await page.fill(email_selector, email)
                        await asyncio.sleep(0.5)

                        pass_selector = None
                        for sel in [
                            'input[name="password"]',
                            'input[type="password"]',
                            '#tab-1 input[type="password"]',
                            'input[placeholder*="Password"]',
                            'input[placeholder*="password"]',
                        ]:
                            if await page.query_selector(sel):
                                pass_selector = sel
                                break

                        if pass_selector:
                            await page.fill(pass_selector, password)
                            await asyncio.sleep(0.5)

                            # Click submit
                            submit_selector = None
                            for sel in ['button[type="submit"]', '.auth__form button', 'form button']:
                                if await page.query_selector(sel):
                                    submit_selector = sel
                                    break

                            if submit_selector:
                                await page.click(submit_selector)
                                logger.info("Submitted login form. Waiting for authentication and session token...")

                # Wait for token from window.settings or redirection
                for _ in range(timeout_seconds // 2):
                    if extracted_token:
                        break

                    try:
                        # Check window.settings.token
                        token_val = await page.evaluate("() => window.settings && window.settings.token ? window.settings.token : null")
                        if token_val and isinstance(token_val, str) and len(token_val) > 10:
                            extracted_token = token_val
                            logger.info(f"Extracted token from window.settings: {extracted_token[:8]}...")
                            break
                    except Exception:
                        pass

                    # Check cookies for session / token
                    cookies = await context.cookies()
                    for cookie in cookies:
                        if cookie.get("name") in ("token", "ssid", "session", "user_token") and len(cookie.get("value", "")) > 15:
                            extracted_token = cookie.get("value")
                            logger.info(f"Extracted token from cookie '{cookie.get('name')}': {extracted_token[:8]}...")
                            break

                    # Check for 2FA PIN input
                    pin_input = await page.query_selector('input[name="code"], input[name="keep_code"]')
                    if pin_input:
                        logger.warning("Quotex requested a 2FA/Email PIN code. Please complete OTP in the open browser window if prompted...")

                    await asyncio.sleep(2)

                if extracted_token:
                    update_env_token(extracted_token)
                    await browser.close()
                    return extracted_token

            except Exception as e:
                logger.warning(f"Failed to authenticate via {base_url}: {e}")
                continue

        await browser.close()

    if not extracted_token:
        logger.error("Failed to retrieve a fresh Quotex session token.")
    return extracted_token


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    token = asyncio.run(get_fresh_quotex_token(headless=False, timeout_seconds=60))
    if token:
        print(f"\nFresh Quotex Token Obtained: {token}\n")
    else:
        print("\nFailed to obtain token.\n")
