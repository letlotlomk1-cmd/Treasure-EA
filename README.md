# Treasure EA

This repository contains MQL5 expert advisors for a market structure and liquidity-based trading system, focused on ICT/SMC-style trade logic. The main project file is `Treasure_EA_v3_0.mq5`, with older versioned builds also included for reference and comparison.

## Project purpose

The EA attempts to identify high-probability directional setups using:

- Higher-timeframe bias alignment
- Kill-zone timing
- Liquidity sweep detection
- MSS / displacement confirmation
- FVG or order-block zone validation
- Premium/discount filtering
- Risk-based trade sizing and exit logic

The design is built around a structured sequence of conditions before placing a trade, rather than a simple indicator-based strategy.

## Main strategy flow

The v3.0 EA is described in its source header as a sequence:

1. HTF bias: H4 / H1 structure (higher highs / higher lows or weaker opposite behavior)
2. Kill-zone check: London / New York session windows
3. Sweep: sell-side or buy-side liquidity taken with rejection back into the opposite side
4. MSS: displacement candle closes through the prior swing structure
5. Entry zone: FVG or order block formed in the displacement leg
6. Premium / discount filter: only trade in favorable value zones
7. Position management: SL beyond the sweep extreme and a target at opposing liquidity
8. Risk / portfolio control: break-even, partial exits, and daily limits

This indicates the system is intended to trade around liquidity grabs and structural breakouts, not purely on price momentum alone.

## Key files

- `Treasure_EA_v3_0.mq5` — current main EA source
- `Treasure_EA_v3_0.ex5` — compiled executable version
- `Treasure_EA_v2_2.mq5` / `.ex5` — earlier strategy iteration
- `Treasure_EA_v2_3.mq5` / `.ex5` — newer iteration before v3.0
- `Advanced_SMC_ICT_SMT_News_EA_FIXED.mq5` — another candidate variation or tuned version
- `Treasure_EA_v2.0.mq5` — empty placeholder / legacy file
- `Treasure AI v2.1.png` and `XAUUSDmicroTREASUREEAV2.1.png` — screenshots / strategy visuals

## What the EA appears to include

From the source, the EA includes:

- Risk % or fixed-lot sizing
- Max positions / active orders
- SL and TP buffer settings
- Minimum R:R checks
- Maximum spread filter
- Daily loss and daily trade limit controls
- Symbol / execution timeframe options
- Fractal-based swing detection
- H1 / H4 structure scanning
- Previous day high/low and Asian range liquidity detection
- AI-style chart dashboard with a neon HUD panel
- Optional chart theme and overlay visualizations

## Notable implementation details

The code contains several design features that are useful to understand when working with the EA:

- `CalcLots()` calculates position size based on account balance and risk percent when enabled.
- `InKillZone()` restricts trade activity to configured session windows.
- `BuildLiquidity()` constructs sweep and target levels from execution timeframe swings, H1/H4 structure, prior-day levels, and Asian range zones.
- `EvalSweep()` validates the sequence from sweep -> MSS -> zone -> premium/discount -> target.
- `PlaceOrder()` only creates limit orders when the entry is valid and the broker stop-level rules are respected.

This is much more than a simple indicator: it is a full decision engine with trade execution, risk logic, and chart overlays.

## Usage notes

- This is an MQL5 project for MetaTrader 5.
- The `.mq5` source files must be compiled before use in MT5.
- The compiled `.ex5` files are the runtime versions that can be loaded into the platform.
- The strategy is designed with execution rules for liquidity and structure, so it should be tested on a demo account before live usage.
- The code includes many configurable inputs; users should review these values before applying the EA to a live chart.

## Important caution

This repository is for algorithmic trading research and strategy experimentation. It is not a guarantee of profitability. Forex and CFD trading involve substantial risk, and any automated system should be evaluated carefully with backtesting, forward testing, and risk controls.

## Summary

Treasure EA is an MQL5 ICT/SMC trading bot focused on liquidity sweeps, displacement, market structure, and risk-managed entries. The main branch is centered on `Treasure_EA_v3_0.mq5`, with multiple historical versions and compiled builds preserved in the repository for comparison.

## Suggested next steps

- Open `Treasure_EA_v3_0.mq5` in MetaEditor
- Compile the EA in MetaTrader 5
- Test on a demo account with the default inputs first
- Review the kill-zone, spread, and risk settings before live trading
- Compare against older versions in the repo if you want to isolate changes between strategy iterations
