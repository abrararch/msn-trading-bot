import asyncio
import json
import time
from quotex_otc_client import Candle, CandleAggregator, QuotexOTCClient
import api_server

def test_candle_aggregator():
    print("Testing CandleAggregator...")
    agg = CandleAggregator("USDPHP_otc")
    
    # 1. First tick at minute boundary 1700000000
    t1 = 1700000000
    p1 = 128.019234
    candles = agg.update_tick(p1, t1)
    
    c1m = candles[60]
    assert c1m.open == 128.019234, f"Expected 128.019234, got {c1m.open}"
    assert c1m.high == 128.019234, f"Expected 128.019234, got {c1m.high}"
    assert c1m.low == 128.019234, f"Expected 128.019234, got {c1m.low}"
    assert c1m.close == 128.019234, f"Expected 128.019234, got {c1m.close}"
    assert agg.current_price == 128.019234
    
    # 2. Higher tick in same minute
    t2 = 1700000010
    p2 = 128.025500
    candles = agg.update_tick(p2, t2)
    c1m = candles[60]
    assert c1m.open == 128.019234
    assert c1m.high == 128.025500
    assert c1m.low == 128.019234
    assert c1m.close == 128.025500
    assert agg.current_price == 128.025500

    # 3. Lower tick in same minute
    t3 = 1700000020
    p3 = 128.010111
    candles = agg.update_tick(p3, t3)
    c1m = candles[60]
    assert c1m.open == 128.019234
    assert c1m.high == 128.025500
    assert c1m.low == 128.010111
    assert c1m.close == 128.010111

    # 4. Mid tick in same minute
    t4 = 1700000030
    p4 = 128.015000
    candles = agg.update_tick(p4, t4)
    c1m = candles[60]
    assert c1m.open == 128.019234
    assert c1m.high == 128.025500
    assert c1m.low == 128.010111
    assert c1m.close == 128.015000

    # Check to_dict float precision (unrounded float)
    d = c1m.to_dict()
    assert d["open"] == 128.019234
    assert d["high"] == 128.025500
    assert d["low"] == 128.010111
    assert d["close"] == 128.015000
    assert isinstance(d["open"], float)
    
    # 5. Tick in next minute 1700000060
    t5 = 1700000060
    p5 = 128.018888
    candles = agg.update_tick(p5, t5)
    c1m_new = candles[60]
    assert c1m_new.open == 128.018888
    assert c1m_new.high == 128.018888
    assert c1m_new.low == 128.018888
    assert c1m_new.close == 128.018888
    assert len(agg.history[60]) == 1
    assert agg.history[60][0].is_closed is True
    assert agg.history[60][0].close == 128.015000

    print("CandleAggregator test PASSED!")

async def test_client_tick_processing():
    print("Testing QuotexOTCClient tick events and callbacks...")
    received_ticks = []
    
    def on_tick(asset, price, ts):
        received_ticks.append({"asset": asset, "price": price, "timestamp": ts})
        
    client = QuotexOTCClient(
        target_assets=["USDPHP_otc", "EURUSD_otc"],
        on_tick_callback=on_tick
    )
    
    # Test s_tick event frame (dict format)
    s_tick_frame = json.dumps(["s_tick", {"asset": "USDPHP_otc", "price": 128.019234, "time": 1700000000}])
    await client._handle_event_frame(s_tick_frame)
    
    assert len(received_ticks) == 1
    assert received_ticks[0]["asset"] == "USDPHP_otc"
    assert received_ticks[0]["price"] == 128.019234
    assert received_ticks[0]["timestamp"] == 1700000000
    assert client.get_current_price("USDPHP_otc") == 128.019234
    assert client.current_price == 128.019234

    # Test tick event frame (list format with 6 decimal precision)
    tick_list_frame = json.dumps(["tick", [["EURUSD_otc", 1700000005, 0.856230]]])
    await client._handle_event_frame(tick_list_frame)
    
    assert len(received_ticks) == 2
    assert received_ticks[1]["asset"] == "EURUSD_otc"
    assert received_ticks[1]["price"] == 0.856230
    assert client.get_current_price("EURUSD_otc") == 0.856230

    print("QuotexOTCClient tick processing test PASSED!")

def test_api_server_tick_integration():
    print("Testing api_server tick handler...")
    api_server.market_state["USDPHP_otc"] = {
        "symbol": "USDPHP_otc",
        "latest_close": 100.0,
        "timestamp": "2026-08-26 12:00:00"
    }
    
    # Simulate incoming raw tick
    api_server.on_otc_tick_received("USDPHP_otc", 128.019234, 1700000000)
    
    assert api_server.market_state["USDPHP_otc"]["latest_close"] == 128.019234
    assert isinstance(api_server.market_state["USDPHP_otc"]["latest_close"], float)
    
    print("api_server integration test PASSED!")

if __name__ == "__main__":
    test_candle_aggregator()
    asyncio.run(test_client_tick_processing())
    test_api_server_tick_integration()
    print("\nALL PINPOINT LIVE PRICE TRACKING TESTS PASSED PERFECTLY!")
