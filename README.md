# Quotex TradingView 1-Minute Live Signal Bot & Flutter Trading App

A high-performance trading engine and cross-platform **Flutter Desktop / Web / Mobile App** for binary trading on Quotex. The bot streams real-time 1-minute candle data directly from **TradingView** (`tvDatafeed`) with an automatic **Yahoo Finance** fallback, computes **200 EMA** and **14 RSI** indicators, and triggers live **CALL / PUT** trading alerts.

---

## 📌 Features

- **No Quotex Account / Login Required**: Directly streams live 1-minute market candles from TradingView WebSocket feeds without risk of account session expirations.
- **Multi-Asset Monitoring**: Live tracking for **EURUSD**, **GBPUSD**, **USDJPY**, **AUDUSD** (and any custom Forex pairs).
- **Strategy & Indicator Engine**:
  - **200 EMA**: Baseline trend filter.
  - **14 RSI**: Overbought ($\ge 70$) and Oversold ($\le 30$) momentum trigger.
  - **CALL (BUY) Alert**: Price above 200 EMA + RSI oversold rebound.
  - **PUT (SELL) Alert**: Price below 200 EMA + RSI overbought reversal.
- **Flutter Trading Terminal Application (`quotex_signal_app`)**:
  - **Interactive Candlestick Chart**: Custom-rendered 1-minute candlestick chart with 200 EMA overlay, real-time price tracker, and crosshair inspection.
  - **RSI 14 Sub-Panel**: Visual momentum oscillator with overbought/oversold boundaries.
  - **CALL / PUT Alert Cards**: Glowing action panels with 1-minute candle countdown timer.
  - **1-Click Quotex Execution Copy**: Instant clipboard copy with exact asset, direction, entry price, and 1-minute expiration settings.
  - **Signal Alert History Log**: Records session signals, entry prices, and indicator values.
- **FastAPI / WebSocket Engine (`api_server.py`)**: Real-time broadcast backend for the Flutter frontend.
- **Terminal CLI Mode (`app.py`)**: Lightweight console monitor with Rich tables and alert banners.

---

## 🚀 Quick Start

### 1. Install Python Dependencies
```bash
py -m pip install -r requirements.txt
```

### 2. Start the Backend Live Stream Server
```bash
py api_server.py
```
*The API server will run on `http://127.0.0.1:8000` with WebSocket stream on `ws://127.0.0.1:8000/ws/stream`.*

### 3. Launch the Flutter Application
```bash
cd quotex_signal_app
flutter run -d windows
```
*(Or run on Web / Chrome using `flutter run -d chrome`).*

---

## 💻 Running in Terminal Mode (No GUI)
If you prefer running purely in the terminal console:
```bash
py app.py
```

---

## 📂 Project Architecture
- [`api_server.py`](api_server.py) - FastAPI & WebSocket streaming backend providing real-time candles, 200 EMA, 14 RSI, and signals.
- [`app.py`](app.py) - Standalone terminal console runner with Rich tables.
- [`quotex_signal_app/`](quotex_signal_app/) - Flutter cross-platform trading dashboard.
  - `lib/main.dart` - App entry point with dark trading terminal theme.
  - `lib/screens/dashboard_screen.dart` - Main trading screen with multi-pair switcher.
  - `lib/widgets/interactive_candle_chart.dart` - Live candlestick chart + 200 EMA curve.
  - `lib/widgets/rsi_oscillator_widget.dart` - RSI 14 oscillator sub-chart.
  - `lib/widgets/signal_card.dart` - Live CALL / PUT trade cards with 1-minute countdown.
  - `lib/widgets/signal_history_panel.dart` - Session trade signals log.
  - `lib/services/signal_service.dart` - WebSocket client with auto-reconnect & REST fallback.
- [`requirements.txt`](requirements.txt) - Python dependencies (`fastapi`, `uvicorn`, `pandas`, `pandas_ta`, `tvdatafeed`, `yfinance`, `rich`).
