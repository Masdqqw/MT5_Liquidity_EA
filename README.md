# MT5 Liquidity Sweep EA

This repository contains a simple MetaTrader 5 Expert Advisor that attempts to trade liquidity sweeps using key levels such as:

- previous day high/low;
- session highs/lows (Asia / London / New York);
- swing highs/lows on a higher timeframe;
- equal highs / equal lows areas;
- entry only after a sweep + trend confirmation.

## How it works

1. Builds a list of relevant liquidity levels.
2. Monitors whether the current candle sweeps a level.
3. Confirms the trend with EMA on a higher timeframe.
4. Opens a buy or sell trade only when the sweep + trend condition matches.
5. Sets a stop loss and take profit based on the level distance and fixed risk values.

## Files

- `LiquiditySweepEA.mq5` — Expert Advisor source file.

## Installation

1. Open MetaEditor in MetaTrader 5.
2. Create a new Expert Advisor.
3. Paste the content of `LiquiditySweepEA.mq5`.
4. Compile.
5. Attach the EA to a chart.
6. Use a liquid FX pair such as EURUSD, GBPUSD, USDJPY, etc.

## Recommended settings

- Pair: EURUSD or GBPUSD
- Chart: M5 or M15
- Trend filter: H1 EMA 20 / EMA 200
- Risk: 0.5% per trade
- Stop loss: 30 points
- Take profit: 60 points

## Notes

This is a simplified strategy prototype and not a guarantee of profit. It is designed as a starting point for a liquidity-based EA and should be tested thoroughly in a demo account before live use.

The logic is intentionally conservative:

- only one position at a time;
- only trades when trend and sweep agree;
- trailing stop is enabled by default.

## Important

The code uses a simplified approach to level detection and sweep detection. For a real professional liquidity indicator, it is better to integrate a custom indicator that draws and stores levels precisely, similar to the description you provided.
