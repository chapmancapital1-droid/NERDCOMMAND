//+------------------------------------------------------------------+
//|                                            NCI_Hybrid_v1.8.mq4   |
//|             NERDCOMMAND Core Intelligence (NCI) Trading EA       |
//|    v1.8 - Scalp Mode Defined | Re-Entry | Multi-Entry Rules     |
//|                                                                  |
//|  CHANGES FROM v1.6 (1000 MT4 indicator library ingestion):      |
//|                                                                  |
//|    NEW 1 — TTF VOTER #14 (Trend Trigger Factor)                 |
//|       Source: TTF.mq4 from 1000-indicator library.               |
//|       Measures BuyPower vs SellPower over InpTTFBars (8 bars).  |
//|       TTF = (BuyPow-SellPow)/(0.5*(BuyPow+SellPow))*100        |
//|       Bull when TTF > InpTTFBullThresh (default 0 = any +)       |
//|       Bear when TTF < InpTTFBearThresh (default 0 = any -)       |
//|                                                                  |
//|    NEW 2 — VEGAS H4 VOTER #15                                   |
//|       Source: 4hVegasMetaTrader4hChart.mq4, Spiggy (2006).      |
//|       H4 SMA(8) + SMA(55). Bull = price>SMA55 AND SMA8>SMA55.  |
//|       Bear = price<SMA55 AND SMA8<SMA55.                        |
//|       2-week institutional trend view. Max score now = 15.       |
//|                                                                  |
//|    NEW 3 — CHANDELIER EXIT TRAILING STOP                        |
//|       Source: ChandelierExit.mq4 from 1000-indicator library.   |
//|       SL_long  = High[highest(N bars)] - ATR(14)*Mult           |
//|       SL_short = Low [lowest (N bars)] + ATR(14)*Mult           |
//|       Default: N=15, Mult=3.0. Anchors stop to the SWING        |
//|       high/low, not to current price — far more stable.          |
//|       Replaces old ATR-from-current-price trail formula.         |
//|                                                                  |
//|    NEW 4 — ADR SESSION EXHAUSTION FILTER                        |
//|       Source: Avg Daily Range.mq4 from 1000-indicator library.  |
//|       Blocks new entries when today's H-L range already          |
//|       consumed >= InpADRMaxPct (85%) of the 20-day ADR.         |
//|       Stops chasing moves near end of day's expected range.      |
//|                                                                  |
//|    CARRIED FORWARD FROM v1.6 (DO NOT REVERT):                   |
//|       - InpMinConfluence=6, InpRequireDmaSlope=false             |
//|       - InpVolumeMinRatio=1.0, InpAtrMinPrice=0.0003             |
//|       - MTF Voter #13 (NeuroTrick EMA stack, min 2/4)            |
//|       - Hard 15-pip profit lock (ManageHardLock)                 |
//|       - InpTPRRMultiplier=1.5, InpPartialPercent=35%             |
//|                                                                  |
//|    PAIR: GBPUSD M15 ONLY                                        |
//|    MAGIC: 24170                                                  |
//|                                                                  |
//|             (c) 2026 GangsterNerds LLC - NERDCOMMAND Trading     |
//+------------------------------------------------------------------+
#property copyright   "GangsterNerds LLC - NERDCOMMAND Trading"
#property link        "https://nerdcommand.io"
#property version     "1.80"
#property description "NCI Hybrid v1.8 - Scalp Mode + Re-Entry + 2-trade scalp. GBPUSD M15."
#property strict

//================================================================
// INPUT PARAMETERS
//================================================================
//--- Identity & Risk
extern int    InpMagicNumber            = 24180;      // Magic number (v1.8 = 24180)
extern double InpRiskPct                = 0.5;        // Risk per trade (% equity)
extern double InpFixedLots              = 0.0;
extern int    InpMaxSpreadPips          = 2;
extern int    InpMaxOpenTrades          = 1;
extern int    InpSlippage               = 3;

//--- Hard Lot Cap
extern string InpLotCapNote             = "Max $ per pip = equity * MaxLotsPerPipPctEquity / 100";
extern double InpMaxLotsPerPipPctEquity = 0.1;
extern bool   InpEnforceLotCap          = true;

//--- Trade Mode
extern string InpModeNote               = "0=DMAHLBO | 1=Scalper | 2=Adaptive ATR";
extern int    InpMode                   = 0;
extern int    InpScalperTpPips          = 5;
extern double InpScalperSlAtrMult       = 1.2;
extern double InpAdaptiveTpAtrMult      = 1.2;
extern double InpAdaptiveSlAtrMult      = 1.2;

//--- R:R Multiplier (Mode 0 only) — CARRY FORWARD FROM v1.4
extern string InpRRNote                 = "v1.4+: TP = SL_distance * InpTPRRMultiplier (Mode 0). 1.0 = old 1:1";
extern double InpTPRRMultiplier         = 1.5;

//--- DMAHLBO
extern int    InpDmaLength              = 25;
extern bool   InpRequireDmaSlope        = false;     // v1.6: false — slope blocked valid entries

//--- Stochastic
extern int    InpStochK                 = 25;
extern int    InpStochSmooth            = 3;
extern int    InpStochD                 = 3;
extern int    InpStochBuyLo             = 30;
extern int    InpStochBuyHi             = 49;
extern int    InpStochSellLo            = 50;
extern int    InpStochSellHi            = 70;

//--- Stoch Regime Mode
extern string InpStochRegNote           = "0=Reversion | 1=Momentum | 2=Auto(ADX)";
extern int    InpStochRegimeMode        = 2;
extern int    InpStochAdxPeriod         = 14;
extern int    InpStochAdxThresh         = 20;

//--- AEXD Divergence
extern bool   InpUseAEXD                = true;
extern int    InpDivLookback            = 5;
extern int    InpRsiLength              = 14;

//--- Candle Patterns
extern bool   InpUseCandles             = true;
extern double InpPinTailFactor          = 2.5;

//--- ATR
extern int    InpAtrPeriod              = 14;
extern double InpAtrMinPrice            = 0.0003;    // v1.6: was 0.0007 — allow lower ATR sessions

//--- HTF Trend Filter (H1 EMA21 — Voter #7)
extern bool   InpUseHTFTrend            = true;
extern int    InpHTFTimeframe           = PERIOD_H1;
extern int    InpHTFEmaLength           = 21;
extern int    InpHTFPersistBars         = 3;
extern string InpHTFGateNote            = "HTF Hard Gates";
extern bool   InpRequireHTFAgree        = true;
extern bool   InpRequireHTFSlope        = true;
extern int    InpHTFSlopeBars           = 3;
extern string InpHTFLogicNote           = "false=OR logic (either persist OR slope), true=AND (v1.3 behavior)";
extern bool   InpHTFRequireBoth         = false;

//--- Robotrick (Voter #8)
extern bool   InpUseRobotrick           = true;
extern int    InpRoboFastLen            = 10;
extern int    InpRoboSlowLen            = 34;
extern double InpRoboChanAtrMult        = 0.5;

//--- Volume (Voter #9)
extern bool   InpUseVolumeFilter        = true;
extern int    InpVolumeAvgPeriod        = 20;
extern double InpVolumeMinRatio         = 1.0;       // v1.6: was 1.10 — avg volume is sufficient

//--- MACD Voter (#11)
extern bool   InpUseMACDVoter           = true;
extern int    InpMacdFast               = 12;
extern int    InpMacdSlow               = 26;
extern int    InpMacdSignal             = 9;

//--- Day Range Voter (#12)
extern bool   InpUseDayRangeVoter       = true;
extern double InpDayRangeZonePct        = 20.0;

//--- *** v1.5 *** NeuroTrick MTF Stack Voter (#13)
extern string InpMTFNote                = "v1.5: W1/D1/H4/H1 EMA stack alignment voter from NeuroTrick AHSE";
extern bool   InpUseMTFVoter            = true;
extern int    InpMTFEmaFast             = 20;         // NeuroTrick fast EMA period
extern int    InpMTFEmaSlow             = 50;         // NeuroTrick slow EMA period
extern int    InpMTFMinAligned          = 2;          // v1.6: 2/4 TFs sufficient (was 3) — more setups fire

//--- Confluence Gate
extern bool   InpUseConfluence          = true;
extern int    InpMinConfluence          = 6;          // v1.6: was 8 — 6/13 opens more valid scalps

//--- 3-Strike Cooldown
extern bool   InpUseStrikeCooldown      = true;
extern int    InpStrikeLimit            = 3;
extern int    InpCooldownBars           = 24;
extern double InpPostCooldownRisk       = 0.5;

//--- Daily DD Lock
extern bool   InpUseDailyDDLock         = true;
extern double InpMaxDailyDDPct          = 3.0;

//--- Session Filter
extern bool   InpUseSessionFilter       = true;
extern int    InpSessionStartHour       = 7;
extern int    InpSessionEndHour         = 20;
extern bool   InpSkipFriday             = false;

//--- Trailing Stop
extern double InpTrailTriggerPips       = 7.0;
extern double InpTrailAtrMult           = 0.8;
extern double InpTrailFixedPips         = 6.0;
extern bool   InpUseAtrTrail            = true;

//--- *** v1.5 *** Trail Minimum Step Gate
extern string InpTrailStepNote          = "v1.5: Only update trail SL when improvement >= InpTrailMinStepPips";
extern double InpTrailMinStepPips       = 3.0;        // Eliminates tick-by-tick modify flood

//--- Partial Close + BE Lock — CARRY FORWARD FROM v1.4 FIXES
extern bool   InpUsePartialClose        = true;
extern double InpTP1AtrMult             = 1.2;        // v1.4 fix: was 1.0 — gave partial too early
extern double InpPartialPercent         = 35.0;       // v1.4 fix: was 50% — killed winners
extern double InpBEPlusPips             = 2.0;

//--- Pre-Partial Protection
extern string InpPreBENote              = "Pre-partial SL move to protect entry-to-TP1 window";
extern bool   InpUsePreBELock           = true;
extern double InpPreBETriggerFrac       = 0.5;
extern double InpPreBESLFraction        = 0.5;

//--- Safe Order Modify
extern bool   InpUseSafeModify          = true;

//--- v1.6: Hard Profit Lock — fires when profit reaches InpHardLockPips
// Source: Breakout Expert (lockProfit=20), Farhad Hill (FirstMove=20→BE),
//         Hans123 (BreakEven=30), 2EMA system (TrailingStop=15)
extern string InpHardLockNote           = "v1.6: Lock profits at InpHardLockPips regardless of ATR";
extern bool   InpUseHardLock            = true;
extern double InpHardLockPips           = 15.0;    // Pips profit to trigger hard lock
extern double InpHardLockPct            = 50.0;    // % of position to close at trigger
extern double InpHardLockSLBuf          = 1.5;     // Remainder SL = entry + spread * this buffer

//--- v1.7: TTF Voter #14 — Trend Trigger Factor
// Source: TTF.mq4 — BuyPower vs SellPower over N bars
// TTF > 0 = buyers winning (bull vote), TTF < 0 = sellers winning (bear vote)
extern string InpTTFNote               = "v1.7: Voter #14 — TTF BuyPow vs SellPow";
extern bool   InpUseTTFVoter           = true;
extern int    InpTTFBars               = 8;      // Lookback for each power period
extern double InpTTFBullThresh         = 0.0;    // TTF > this = bull vote
extern double InpTTFBearThresh         = 0.0;    // TTF < this = bear vote (negative)

//--- v1.7: Vegas H4 Voter #15 — 4H SMA(8) + SMA(55) tunnel
// Source: 4hVegasMetaTrader4hChart.mq4 (Spiggy)
// Bull = price above SMA55 AND SMA8 > SMA55 (outside tunnel, bull side)
// Bear = price below SMA55 AND SMA8 < SMA55 (outside tunnel, bear side)
extern string InpVegasNote             = "v1.7: Voter #15 — Vegas H4 SMA8/SMA55 tunnel";
extern bool   InpUseVegasH4            = true;
extern int    InpVegasFast             = 8;      // Fast SMA period on H4
extern int    InpVegasSlow             = 55;     // Slow SMA period on H4

//--- v1.7: Chandelier Exit — trailing stop anchored to swing high/low
// Source: ChandelierExit.mq4 from 1000-indicator library
// SL_long  = High[highest(N)] - ATR(14)*Mult
// SL_short = Low [lowest (N)] + ATR(14)*Mult
// Replaces old ATR-from-current-price trail formula
extern string InpChanNote              = "v1.7: Chandelier Exit replaces ATR trail";
extern bool   InpUseChandelier         = true;
extern int    InpChanRange             = 15;     // Swing high/low lookback bars
extern double InpChanATRMult           = 3.0;    // ATR multiplier for stop distance

//--- v1.7: ADR Session Exhaustion Filter
// Source: Avg Daily Range.mq4 — blocks entries when day range already consumed
extern string InpADRNote               = "v1.7: Block entries when ADR >= InpADRMaxPct consumed";
extern bool   InpUseADRFilter          = true;
extern int    InpADRPeriod             = 20;     // Days to average for ADR
extern double InpADRMaxPct             = 85.0;   // Block new entries above this % of ADR

//--- v1.8: Scalp Mode Parameters
// Scalp mode: faster entries, tighter TP/SL, more concurrent trades
// Enable via InpScalpModeEnabled=true OR send {"ts":...,"mode":"scalp","active":true} to NCI_Commands.json
// SCALP ENTRY RULES:
//   1. HTF EMA21 H1 must be in trend direction (mandatory — always checked)
//   2. RSI must be sloping in trade direction (mandatory — always checked)
//   3. Volume must be above 20-bar average (mandatory — always checked)
//   4. Total confluence >= InpScalpMinConfl from full 15-voter score
//   5. Spread <= InpScalpMaxSpread pips (tighter gate than swing)
//   6. Session: London 07-10 UTC + NY 13-16 UTC (when InpScalpSessionOnly=true)
extern string InpScalpSect            = "=== v1.8 SCALP MODE ===";
extern bool   InpScalpModeEnabled     = false;   // Turn on scalp mode from input params
extern int    InpScalpMinConfl        = 4;       // Min confluence score to fire in scalp mode
extern int    InpScalpTPPips          = 10;      // Fixed take-profit pips for scalp entries
extern double InpScalpSLMult          = 1.0;     // Stop loss = ATR(14) * this multiplier
extern int    InpScalpMaxSpread       = 2;       // Max spread pips for scalp entries
extern int    InpScalpMaxTrades       = 2;       // Max concurrent trades in scalp mode
extern bool   InpScalpSessionOnly     = true;    // Only scalp during London/NY open windows
extern int    InpScalpLonStart        = 7;       // London open start hour UTC
extern int    InpScalpLonEnd          = 10;      // London open end hour UTC
extern int    InpScalpNYStart         = 13;      // NY open start hour UTC
extern int    InpScalpNYEnd           = 16;      // NY open end hour UTC
extern bool   InpAllowReEntry         = true;    // Re-enter same direction when hard lock fires
extern int    InpReEntryMaxPerBar     = 1;       // Maximum re-entries per bar

//--- Logging
extern bool   InpVerboseLog             = true;
extern bool   InpLogConfluence          = true;

//================================================================
// GLOBAL STATE
//================================================================
double   PipPoint;
double   PipMultiplier;
datetime LastBarTime          = 0;

int      ConsecutiveLosses    = 0;
datetime CooldownUntilTime    = 0;
int      PostCooldownTradesLeft = 0;

datetime DailyAnchorTime      = 0;
double   DailyAnchorEquity    = 0.0;
bool     DailyLocked          = false;

int      TotalClosed          = 0;
int      TotalWins            = 0;
int      TotalLosses          = 0;
int      LastTotalHistory     = 0;

#define TRACK_CAP 30
int  TrackTicket[TRACK_CAP];
int  TrackState [TRACK_CAP];
int  TrackCount = 0;

//--- v1.5 Live Intelligence: runtime overrides (0 = use extern param)
double g_rt_min_confluence  = 0;   // Set from NCI_Commands.json via ReadCommandsJSON()
double g_rt_max_spread      = 0;
double g_rt_risk_pct        = 0;
double g_rt_trail_step      = 0;
datetime g_last_cmd_ts      = 0;
bool   g_scalp_mode         = false;  // Scalp mode: lower confluence, fast entries

//--- v1.8 Re-Entry State
bool     g_reentry_avail    = false;  // Hard lock fired this bar — re-entry slot open
int      g_reentry_dir      = 0;     // 1=buy re-entry, -1=sell re-entry
datetime g_reentry_bar      = 0;     // Bar time when re-entry was flagged
int      g_reentry_count    = 0;     // Re-entries fired this bar (cap at InpReEntryMaxPerBar)

//================================================================
// INIT HELPERS
//================================================================
void InitPipMath()
{
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(digits == 3 || digits == 5) { PipPoint = 10 * Point; PipMultiplier = 10.0; }
   else                            { PipPoint = Point;      PipMultiplier = 1.0;  }
}

bool IsNewBar()
{
   datetime t = iTime(Symbol(), Period(), 0);
   if(t != LastBarTime) { LastBarTime = t; return(true); }
   return(false);
}

bool IsNewDay()
{
   if(DailyAnchorTime == 0) return(true);
   return(TimeDay(TimeCurrent())   != TimeDay(DailyAnchorTime) ||
          TimeMonth(TimeCurrent()) != TimeMonth(DailyAnchorTime));
}

void ResetDailyAnchor()
{
   DailyAnchorTime   = TimeCurrent();
   DailyAnchorEquity = AccountEquity();
   DailyLocked       = false;
   if(InpVerboseLog)
      Print("=== v1.5: New trading day. Anchor equity=", DailyAnchorEquity, " ===");
}

int CountMyTrades()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() == InpMagicNumber && OrderSymbol() == Symbol()) n++;
   }
   return(n);
}

double SpreadPips() { return((Ask - Bid) / PipPoint); }

bool InSession()
{
   if(!InpUseSessionFilter) return(true);
   int h   = Hour();
   int dow = DayOfWeek();
   if(InpSkipFriday && dow == 5) return(false);
   if(dow == 0 || dow == 6) return(false);
   if(InpSessionStartHour <= InpSessionEndHour)
      return(h >= InpSessionStartHour && h < InpSessionEndHour);
   return(h >= InpSessionStartHour || h < InpSessionEndHour);
}

double NormalizeLots(double lots)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double stepLot = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(stepLot <= 0) stepLot = 0.01;
   lots = MathFloor(lots / stepLot) * stepLot;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return(NormalizeDouble(lots, 2));
}

//================================================================
// LOT CAP
//================================================================
double ApplyLotCap(double calculatedLots)
{
   if(!InpEnforceLotCap) return(calculatedLots);
   double pipValue = MarketInfo(Symbol(), MODE_TICKVALUE) * PipMultiplier;
   if(pipValue <= 0) return(calculatedLots);
   double maxDollarsPerPip = AccountEquity() * InpMaxLotsPerPipPctEquity / 100.0;
   double maxLotsByCap     = maxDollarsPerPip / pipValue;
   if(calculatedLots > maxLotsByCap)
   {
      if(InpVerboseLog)
         Print("v1.5 LotCap: requested=", DoubleToStr(calculatedLots, 2),
               " -> capped=", DoubleToStr(maxLotsByCap, 2));
      return(NormalizeLots(maxLotsByCap));
   }
   return(calculatedLots);
}

double CalcLots(double slDistPrice)
{
   if(InpFixedLots > 0.0) return(ApplyLotCap(NormalizeLots(InpFixedLots)));
   if(slDistPrice <= 0.0) return(NormalizeLots(0.01));
   double riskMult  = (PostCooldownTradesLeft > 0) ? InpPostCooldownRisk : 1.0;
   double riskMoney = AccountEquity() * (InpRiskPct * riskMult) / 100.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickSize == 0) tickSize = Point;
   double valuePerLot = (slDistPrice / tickSize) * tickValue;
   if(valuePerLot <= 0) return(NormalizeLots(0.01));
   return(ApplyLotCap(NormalizeLots(riskMoney / valuePerLot)));
}

//================================================================
// INDICATOR SHORTHAND
//================================================================
double DmaHigh (int s)          { return(iMA(NULL, 0, InpDmaLength, 0, MODE_SMA, PRICE_HIGH,  s)); }
double DmaLow  (int s)          { return(iMA(NULL, 0, InpDmaLength, 0, MODE_SMA, PRICE_LOW,   s)); }
double StochK  (int s)          { return(iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSmooth, MODE_SMA, 0, MODE_MAIN, s)); }
double Rsi     (int s)          { return(iRSI(NULL, 0, InpRsiLength, PRICE_CLOSE, s)); }
double Atr     (int s)          { return(iATR(NULL, 0, InpAtrPeriod, s)); }
double Adx     (int s)          { return(iADX(NULL, 0, InpStochAdxPeriod, PRICE_CLOSE, MODE_MAIN, s)); }
double HtfEma  (int s)          { return(iMA(NULL, InpHTFTimeframe, InpHTFEmaLength, 0, MODE_EMA, PRICE_CLOSE, s)); }
double HtfClose(int s)          { return(iClose(NULL, InpHTFTimeframe, s)); }
double RoboFast(int s)          { return(iMA(NULL, 0, InpRoboFastLen, 0, MODE_EMA, PRICE_CLOSE, s)); }
double RoboSlow(int s)          { return(iMA(NULL, 0, InpRoboSlowLen, 0, MODE_EMA, PRICE_CLOSE, s)); }

//--- v1.5 NeuroTrick MTF EMA helpers
double MTFEmaFast(int tf, int s){ return(iMA(NULL, tf, InpMTFEmaFast, 0, MODE_EMA, PRICE_CLOSE, s)); }
double MTFEmaSlow(int tf, int s){ return(iMA(NULL, tf, InpMTFEmaSlow, 0, MODE_EMA, PRICE_CLOSE, s)); }

//================================================================
// VOTERS — EXISTING #1-#12
//================================================================
bool BullDivergence()
{
   if(!InpUseAEXD) return(true);
   int    lb    = InpDivLookback;
   double curLL = iLow (NULL, 0, iLowest (NULL, 0, MODE_LOW,  lb, 1));
   double prvLL = iLow (NULL, 0, iLowest (NULL, 0, MODE_LOW,  lb, 1 + lb));
   return(curLL < prvLL && Rsi(1) > Rsi(1 + lb));
}
bool BearDivergence()
{
   if(!InpUseAEXD) return(true);
   int    lb    = InpDivLookback;
   double curHH = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, lb, 1));
   double prvHH = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, lb, 1 + lb));
   return(curHH > prvHH && Rsi(1) < Rsi(1 + lb));
}

bool IsBullEngulf() { double o0=iOpen(NULL,0,1),c0=iClose(NULL,0,1),o1=iOpen(NULL,0,2),c1=iClose(NULL,0,2); return(c0>o0 && c0>MathMax(o1,c1) && o0<MathMin(o1,c1)); }
bool IsBearEngulf() { double o0=iOpen(NULL,0,1),c0=iClose(NULL,0,1),o1=iOpen(NULL,0,2),c1=iClose(NULL,0,2); return(c0<o0 && c0<MathMin(o1,c1) && o0>MathMax(o1,c1)); }
bool IsBullPin()    { double o=iOpen(NULL,0,1),c=iClose(NULL,0,1),l=iLow(NULL,0,1);  double b=MathAbs(c-o); if(b<=0) return(false); return((MathMin(o,c)-l) >= InpPinTailFactor*b && c>o); }
bool IsBearPin()    { double o=iOpen(NULL,0,1),c=iClose(NULL,0,1),h=iHigh(NULL,0,1); double b=MathAbs(c-o); if(b<=0) return(false); return((h-MathMax(o,c)) >= InpPinTailFactor*b && c<o); }
bool BullCandle()   { return(!InpUseCandles || IsBullEngulf() || IsBullPin()); }
bool BearCandle()   { return(!InpUseCandles || IsBearEngulf() || IsBearPin()); }

bool HtfTrendUpPersistent()
{
   if(!InpUseHTFTrend) return(true);
   for(int i = 0; i < InpHTFPersistBars; i++)
      if(HtfClose(i) <= HtfEma(i)) return(false);
   return(true);
}
bool HtfTrendDnPersistent()
{
   if(!InpUseHTFTrend) return(true);
   for(int i = 0; i < InpHTFPersistBars; i++)
      if(HtfClose(i) >= HtfEma(i)) return(false);
   return(true);
}
bool HtfSlopeUp() { if(!InpUseHTFTrend || !InpRequireHTFSlope) return(true); return(HtfEma(0) > HtfEma(InpHTFSlopeBars)); }
bool HtfSlopeDn() { if(!InpUseHTFTrend || !InpRequireHTFSlope) return(true); return(HtfEma(0) < HtfEma(InpHTFSlopeBars)); }

bool HTFGateAllowBuy()
{
   if(!InpRequireHTFAgree) return(true);
   bool persist = HtfTrendUpPersistent();
   bool slope   = HtfSlopeUp();
   return(InpHTFRequireBoth ? (persist && slope) : (persist || slope));
}
bool HTFGateAllowSell()
{
   if(!InpRequireHTFAgree) return(true);
   bool persist = HtfTrendDnPersistent();
   bool slope   = HtfSlopeDn();
   return(InpHTFRequireBoth ? (persist && slope) : (persist || slope));
}

bool VolumeAboveAvg()
{
   if(!InpUseVolumeFilter) return(true);
   double sum = 0;
   for(int i = 2; i < 2 + InpVolumeAvgPeriod; i++) sum += (double)iVolume(NULL, 0, i);
   double avg = sum / InpVolumeAvgPeriod;
   if(avg <= 0) return(true);
   return((double)iVolume(NULL, 0, 1) >= avg * InpVolumeMinRatio);
}

bool MacdBullCross()
{
   if(!InpUseMACDVoter) return(false);
   double mc = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,  1);
   double mp = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,  2);
   double sc = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,1);
   double sp = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,2);
   double mac= iMA  (NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,1);
   double map= iMA  (NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,2);
   return(mc < 0 && mc > sc && mp < sp && mac > map);
}
bool MacdBearCross()
{
   if(!InpUseMACDVoter) return(false);
   double mc = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,  1);
   double mp = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,  2);
   double sc = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,1);
   double sp = iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,2);
   double mac= iMA  (NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,1);
   double map= iMA  (NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,2);
   return(mc > 0 && mc < sc && mp > sp && mac < map);
}

int DayRangePattern()
{
   if(!InpUseDayRangeVoter) return(0);
   double pH = iHigh (NULL, PERIOD_D1, 1);
   double pL = iLow  (NULL, PERIOD_D1, 1);
   double pO = iOpen (NULL, PERIOD_D1, 1);
   double pC = iClose(NULL, PERIOD_D1, 1);
   double rng = pH - pL;
   if(rng < Point * 10) return(0);
   double zone = rng * (InpDayRangeZonePct / 100.0);
   bool bull = ((pH - pC) <= zone) && ((pO - pL) <= zone);
   bool bear = ((pH - pO) <= zone) && ((pC - pL) <= zone);
   if(bull) return(1);
   if(bear) return(-1);
   return(0);
}

bool StochOkBuy()
{
   double k    = StochK(1);
   int    mode = InpStochRegimeMode;
   if(mode == 2) mode = (Adx(1) >= InpStochAdxThresh) ? 1 : 0;
   if(mode == 0) return(k >= InpStochBuyLo  && k <= InpStochBuyHi);
   else          return(k >= InpStochSellLo && k <= InpStochSellHi);
}
bool StochOkSell()
{
   double k    = StochK(1);
   int    mode = InpStochRegimeMode;
   if(mode == 2) mode = (Adx(1) >= InpStochAdxThresh) ? 1 : 0;
   if(mode == 0) return(k >= InpStochSellLo && k <= InpStochSellHi);
   else          return(k >= InpStochBuyLo  && k <= InpStochBuyHi);
}

//================================================================
// VOTER #13 — NeuroTrick MTF Stack (v1.5)
// Checks EMA(InpMTFEmaFast) vs EMA(InpMTFEmaSlow) on W1/D1/H4/H1.
// Vote fires when >= InpMTFMinAligned timeframes agree with direction.
// Prints which TFs agreed for logging and diagnostics.
//================================================================
bool MTFVoterBull(string &detail)
{
   if(!InpUseMTFVoter) { detail = "MTF:OFF"; return(false); }
   int    aligned = 0;
   string tfs     = "";

   if(MTFEmaFast(PERIOD_W1, 0) > MTFEmaSlow(PERIOD_W1, 0)) { aligned++; tfs += "W1 "; }
   if(MTFEmaFast(PERIOD_D1, 0) > MTFEmaSlow(PERIOD_D1, 0)) { aligned++; tfs += "D1 "; }
   if(MTFEmaFast(PERIOD_H4, 0) > MTFEmaSlow(PERIOD_H4, 0)) { aligned++; tfs += "H4 "; }
   if(MTFEmaFast(PERIOD_H1, 0) > MTFEmaSlow(PERIOD_H1, 0)) { aligned++; tfs += "H1 "; }

   bool fires = (aligned >= InpMTFMinAligned);
   detail = "MTF:" + IntegerToString(aligned) + "/4[" + tfs + "]";
   return(fires);
}

bool MTFVoterBear(string &detail)
{
   if(!InpUseMTFVoter) { detail = "MTF:OFF"; return(false); }
   int    aligned = 0;
   string tfs     = "";

   if(MTFEmaFast(PERIOD_W1, 0) < MTFEmaSlow(PERIOD_W1, 0)) { aligned++; tfs += "W1 "; }
   if(MTFEmaFast(PERIOD_D1, 0) < MTFEmaSlow(PERIOD_D1, 0)) { aligned++; tfs += "D1 "; }
   if(MTFEmaFast(PERIOD_H4, 0) < MTFEmaSlow(PERIOD_H4, 0)) { aligned++; tfs += "H4 "; }
   if(MTFEmaFast(PERIOD_H1, 0) < MTFEmaSlow(PERIOD_H1, 0)) { aligned++; tfs += "H1 "; }

   bool fires = (aligned >= InpMTFMinAligned);
   detail = "MTF:" + IntegerToString(aligned) + "/4[" + tfs + "]";
   return(fires);
}

//================================================================
// VOTER #14 — TTF (Trend Trigger Factor)
// Source: TTF.mq4 — compares recent BuyPower vs SellPower
// BuyPower  = High[recent N bars] - Low[older N bars]
// SellPower = High[older N bars]  - Low[recent N bars]
// TTF > 0 = buyers in control, TTF < 0 = sellers in control
//================================================================
bool TTFVoterBull()
{
   if(!InpUseTTFVoter) return(false);
   if(Bars < InpTTFBars*2 + 2) return(false);
   double buyPow  = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1+InpTTFBars));
   double sellPow = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1+InpTTFBars))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1));
   double denom   = 0.5*(buyPow+sellPow);
   if(denom <= 0) return(false);
   double ttf = (buyPow-sellPow)/denom*100.0;
   return(ttf > InpTTFBullThresh);
}

bool TTFVoterBear()
{
   if(!InpUseTTFVoter) return(false);
   if(Bars < InpTTFBars*2 + 2) return(false);
   double buyPow  = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1+InpTTFBars));
   double sellPow = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1+InpTTFBars))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1));
   double denom   = 0.5*(buyPow+sellPow);
   if(denom <= 0) return(false);
   double ttf = (buyPow-sellPow)/denom*100.0;
   return(ttf < -InpTTFBearThresh);
}

//================================================================
// VOTER #15 — VEGAS H4 TUNNEL
// Source: 4hVegasMetaTrader4hChart.mq4 (Spiggy, 2006)
// Bull = price above SMA55 AND SMA8 > SMA55 (outside tunnel, bull)
// Bear = price below SMA55 AND SMA8 < SMA55 (outside tunnel, bear)
// Price between SMA8 and SMA55 = "in the tunnel" = no vote
//================================================================
bool VegasH4Bull()
{
   if(!InpUseVegasH4) return(false);
   double sma8  = iMA(NULL,PERIOD_H4,InpVegasFast,0,MODE_SMA,PRICE_CLOSE,0);
   double sma55 = iMA(NULL,PERIOD_H4,InpVegasSlow,0,MODE_SMA,PRICE_CLOSE,0);
   double cls   = iClose(NULL,PERIOD_H4,0);
   return(cls > sma55 && sma8 > sma55);
}

bool VegasH4Bear()
{
   if(!InpUseVegasH4) return(false);
   double sma8  = iMA(NULL,PERIOD_H4,InpVegasFast,0,MODE_SMA,PRICE_CLOSE,0);
   double sma55 = iMA(NULL,PERIOD_H4,InpVegasSlow,0,MODE_SMA,PRICE_CLOSE,0);
   double cls   = iClose(NULL,PERIOD_H4,0);
   return(cls < sma55 && sma8 < sma55);
}

//================================================================
// v1.8 SCALP MODE HELPERS
//================================================================

bool IsScalpMode()
{
   return(InpScalpModeEnabled || g_scalp_mode);
}

// Returns true during London open (07-10 UTC) and NY open (13-16 UTC)
bool IsScalpSession()
{
   if(!InpScalpSessionOnly) return(true);
   int h = Hour();
   return((h >= InpScalpLonStart && h < InpScalpLonEnd) ||
          (h >= InpScalpNYStart  && h < InpScalpNYEnd));
}

// 3 mandatory core voters — must ALL pass before any scalp entry fires
// Even if confluence score >= InpScalpMinConfl, these are hard gates
bool ScalpCoreVotersBull()
{
   bool htfOk = HtfTrendUpPersistent();   // H1 EMA21 above price for 3 bars
   bool rsiOk = (Rsi(1) > Rsi(2));        // RSI rising
   bool volOk = VolumeAboveAvg();          // Volume >= 20-bar avg
   if(InpVerboseLog && IsScalpMode())
      Print("v1.8 SCALP CORE BULL: HTF=", htfOk, " RSI=", rsiOk, " Vol=", volOk);
   return(htfOk && rsiOk && volOk);
}

bool ScalpCoreVotersBear()
{
   bool htfOk = HtfTrendDnPersistent();
   bool rsiOk = (Rsi(1) < Rsi(2));
   bool volOk = VolumeAboveAvg();
   if(InpVerboseLog && IsScalpMode())
      Print("v1.8 SCALP CORE BEAR: HTF=", htfOk, " RSI=", rsiOk, " Vol=", volOk);
   return(htfOk && rsiOk && volOk);
}

// Effective max trades — scalp mode gets InpScalpMaxTrades, swing gets InpMaxOpenTrades
int ScalpMaxOpenTrades()
{
   return(IsScalpMode() ? InpScalpMaxTrades : InpMaxOpenTrades);
}

// Scalp-specific entry: fixed TP, ATR-based tight SL, tagged "SCALP" in comment
void TryOpenScalpBuy()
{
   double entry = Ask;
   double atr   = Atr(1);
   double sl    = entry - atr * InpScalpSLMult;
   double tp    = entry + InpScalpTPPips * PipPoint;

   int    stopLvl = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDist = stopLvl * Point;
   if(entry - sl < minDist) sl = entry - minDist;
   if(tp - entry < minDist) tp = entry + minDist;

   double slDist = entry - sl;
   if(slDist <= 0) { Print("v1.8 SCALP BUY: invalid SL, skip"); return; }
   double lots = CalcLots(slDist);

   int t = OrderSend(Symbol(), OP_BUY, lots, entry, InpSlippage,
                     NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                     "NCI v1.8 SCALP BUY", InpMagicNumber, 0, clrAqua);
   if(t < 0)
      Print("v1.8 SCALP BUY failed err=", GetLastError());
   else
   {
      Print("v1.8 SCALP BUY #", t,
            " lots=", DoubleToStr(lots, 2),
            " SL=", DoubleToStr(sl, Digits),
            " TP=", DoubleToStr(tp, Digits),
            " TP=", InpScalpTPPips, "p SL=",
            DoubleToStr(atr / PipPoint * InpScalpSLMult, 1), "p");
      if(PostCooldownTradesLeft > 0) PostCooldownTradesLeft--;
      EnsureTracking(t);
   }
}

void TryOpenScalpSell()
{
   double entry = Bid;
   double atr   = Atr(1);
   double sl    = entry + atr * InpScalpSLMult;
   double tp    = entry - InpScalpTPPips * PipPoint;

   int    stopLvl = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDist = stopLvl * Point;
   if(sl - entry < minDist) sl = entry + minDist;
   if(entry - tp < minDist) tp = entry - minDist;

   double slDist = sl - entry;
   if(slDist <= 0) { Print("v1.8 SCALP SELL: invalid SL, skip"); return; }
   double lots = CalcLots(slDist);

   int t = OrderSend(Symbol(), OP_SELL, lots, entry, InpSlippage,
                     NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                     "NCI v1.8 SCALP SELL", InpMagicNumber, 0, clrDeepSkyBlue);
   if(t < 0)
      Print("v1.8 SCALP SELL failed err=", GetLastError());
   else
   {
      Print("v1.8 SCALP SELL #", t,
            " lots=", DoubleToStr(lots, 2),
            " SL=", DoubleToStr(sl, Digits),
            " TP=", DoubleToStr(tp, Digits),
            " TP=", InpScalpTPPips, "p SL=",
            DoubleToStr(atr / PipPoint * InpScalpSLMult, 1), "p");
      if(PostCooldownTradesLeft > 0) PostCooldownTradesLeft--;
      EnsureTracking(t);
   }
}

//================================================================
// ADR SESSION EXHAUSTION
// Source: Avg Daily Range.mq4 from 1000-indicator library
// Returns true if today's H-L range already >= InpADRMaxPct of ADR
// Used to block new entries near end of day's expected range
//================================================================
bool ADRExhausted()
{
   if(!InpUseADRFilter) return(false);
   double adr = 0;
   for(int k = 1; k <= InpADRPeriod; k++)
      adr += iHigh(NULL,PERIOD_D1,k) - iLow(NULL,PERIOD_D1,k);
   adr /= InpADRPeriod;
   if(adr <= 0) return(false);
   double todayRange = iHigh(NULL,PERIOD_D1,0) - iLow(NULL,PERIOD_D1,0);
   bool exhausted = (todayRange / adr >= InpADRMaxPct / 100.0);
   if(exhausted && InpVerboseLog)
      Print("v1.7 ADR EXHAUSTED: today=", DoubleToStr(todayRange/PipPoint,0),
            "p / ADR=", DoubleToStr(adr/PipPoint,0), "p (",
            DoubleToStr(todayRange/adr*100,0), "%) — no new entries");
   return(exhausted);
}

//================================================================
// CONFLUENCE SCORE — 15 VOTERS (v1.7)
//================================================================
int BuyConfluenceScore(string &breakdown)
{
   int    score = 0;
   string parts = "";

   bool dmaBreak   = iClose(NULL, 0, 1) <= DmaLow(1);
   bool stochOk    = StochOkBuy();
   bool slopeOk    = !InpRequireDmaSlope || (DmaHigh(1) > DmaHigh(4));
   bool divOk      = BullDivergence();
   bool candleOk   = BullCandle();
   bool atrOk      = Atr(1) >= InpAtrMinPrice;
   bool htfOk      = HtfTrendUpPersistent();
   bool roboOk     = !InpUseRobotrick || (RoboFast(1) > RoboSlow(1) + Atr(1) * InpRoboChanAtrMult);
   bool volOk      = VolumeAboveAvg();
   bool rsiSlopeOk = Rsi(1) > Rsi(2);
   bool macdOk     = MacdBullCross();
   bool dayPatOk   = (DayRangePattern() == 1);

   string mtfDetail;
   bool   mtfOk    = MTFVoterBull(mtfDetail);
   bool   ttfOk    = TTFVoterBull();
   bool   vegasOk  = VegasH4Bull();

   if(dmaBreak)   { score++; parts += "DMA ";   }
   if(stochOk)    { score++; parts += "Stoch "; }
   if(slopeOk)    { score++; parts += "Slope "; }
   if(divOk)      { score++; parts += "Div ";   }
   if(candleOk)   { score++; parts += "Candle ";}
   if(atrOk)      { score++; parts += "ATR ";   }
   if(htfOk)      { score++; parts += "HTF ";   }
   if(roboOk)     { score++; parts += "Robo ";  }
   if(volOk)      { score++; parts += "Vol ";   }
   if(rsiSlopeOk) { score++; parts += "RSI+ ";  }
   if(macdOk)     { score++; parts += "MACD ";  }
   if(dayPatOk)   { score++; parts += "DayP ";  }
   if(mtfOk)      { score++; parts += "MTF ";   }
   if(ttfOk)      { score++; parts += "TTF ";   }
   if(vegasOk)    { score++; parts += "Vegas ";  }

   breakdown = "BUY score=" + IntegerToString(score) + "/15 [" + parts + "] " + mtfDetail;
   return(score);
}

int SellConfluenceScore(string &breakdown)
{
   int    score = 0;
   string parts = "";

   bool dmaBreak   = iClose(NULL, 0, 1) >= DmaHigh(1);
   bool stochOk    = StochOkSell();
   bool slopeOk    = !InpRequireDmaSlope || (DmaLow(1) < DmaLow(4));
   bool divOk      = BearDivergence();
   bool candleOk   = BearCandle();
   bool atrOk      = Atr(1) >= InpAtrMinPrice;
   bool htfOk      = HtfTrendDnPersistent();
   bool roboOk     = !InpUseRobotrick || (RoboFast(1) < RoboSlow(1) - Atr(1) * InpRoboChanAtrMult);
   bool volOk      = VolumeAboveAvg();
   bool rsiSlopeOk = Rsi(1) < Rsi(2);
   bool macdOk     = MacdBearCross();
   bool dayPatOk   = (DayRangePattern() == -1);

   string mtfDetail;
   bool   mtfOk    = MTFVoterBear(mtfDetail);
   bool   ttfOk    = TTFVoterBear();
   bool   vegasOk  = VegasH4Bear();

   if(dmaBreak)   { score++; parts += "DMA ";   }
   if(stochOk)    { score++; parts += "Stoch "; }
   if(slopeOk)    { score++; parts += "Slope "; }
   if(divOk)      { score++; parts += "Div ";   }
   if(candleOk)   { score++; parts += "Candle ";}
   if(atrOk)      { score++; parts += "ATR ";   }
   if(htfOk)      { score++; parts += "HTF ";   }
   if(roboOk)     { score++; parts += "Robo ";  }
   if(volOk)      { score++; parts += "Vol ";   }
   if(rsiSlopeOk) { score++; parts += "RSI- ";  }
   if(macdOk)     { score++; parts += "MACD ";  }
   if(dayPatOk)   { score++; parts += "DayP ";  }
   if(mtfOk)      { score++; parts += "MTF ";   }
   if(ttfOk)      { score++; parts += "TTF ";   }
   if(vegasOk)    { score++; parts += "Vegas ";  }

   breakdown = "SELL score=" + IntegerToString(score) + "/15 [" + parts + "] " + mtfDetail;
   return(score);
}

//================================================================
// SAFE ORDER MODIFY
//================================================================
bool SafeOrderModify(int ticket, double price, double sl, double tp,
                     datetime expiration, color arrowColor = CLR_NONE)
{
   if(!InpUseSafeModify)
      return(OrderModify(ticket, price,
                         NormalizeDouble(sl, Digits),
                         NormalizeDouble(tp, Digits),
                         expiration, arrowColor));

   int    digits    = (int)MarketInfo(Symbol(), MODE_DIGITS);
   double point     = MarketInfo(Symbol(), MODE_POINT);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * point;
   double spread    = MarketInfo(Symbol(), MODE_SPREAD)    * point;
   double minDist   = MathMax(stopLevel, spread) + point;

   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl,    digits);
   tp    = NormalizeDouble(tp,    digits);

   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(false);
   double curPrice = (OrderType() == OP_BUY) ? MarketInfo(Symbol(), MODE_BID)
                                              : MarketInfo(Symbol(), MODE_ASK);

   if(sl > 0)
   {
      if(OrderType() == OP_BUY  && (curPrice - sl) < minDist) sl = NormalizeDouble(curPrice - minDist, digits);
      if(OrderType() == OP_SELL && (sl - curPrice) < minDist) sl = NormalizeDouble(curPrice + minDist, digits);
   }
   if(tp > 0)
   {
      if(OrderType() == OP_BUY  && (tp - curPrice) < minDist) tp = NormalizeDouble(curPrice + minDist, digits);
      if(OrderType() == OP_SELL && (curPrice - tp) < minDist) tp = NormalizeDouble(curPrice - minDist, digits);
   }

   if(MathAbs(sl - OrderStopLoss())   < point &&
      MathAbs(tp - OrderTakeProfit()) < point)
      return(true);

   bool result = OrderModify(ticket, price, sl, tp, expiration, arrowColor);
   if(!result)
   {
      int err = GetLastError();
      Print("v1.5 SafeOrderModify FAILED ticket=", ticket,
            " SL=", DoubleToStr(sl, digits),
            " TP=", DoubleToStr(tp, digits),
            " err=", err);
   }
   return(result);
}

//================================================================
// PER-TICKET STATE TRACKING
//================================================================
int FindTrackingIndex(int ticket)
{
   for(int i = 0; i < TrackCount; i++)
      if(TrackTicket[i] == ticket) return(i);
   return(-1);
}

int EnsureTracking(int ticket)
{
   int idx = FindTrackingIndex(ticket);
   if(idx >= 0) return(idx);
   if(TrackCount >= TRACK_CAP)
   {
      for(int i = 0; i < TrackCount - 1; i++)
      {
         TrackTicket[i] = TrackTicket[i + 1];
         TrackState [i] = TrackState [i + 1];
      }
      TrackCount--;
   }
   TrackTicket[TrackCount] = ticket;
   TrackState [TrackCount] = 0;
   TrackCount++;
   return(TrackCount - 1);
}

void SetTrackState(int ticket, int state)
{
   int idx = EnsureTracking(ticket);
   if(idx >= 0) TrackState[idx] = state;
}

int GetTrackState(int ticket)
{
   int idx = FindTrackingIndex(ticket);
   return(idx >= 0 ? TrackState[idx] : 0);
}

void CleanupTracking()
{
   for(int i = TrackCount - 1; i >= 0; i--)
   {
      bool stillOpen = false;
      if(OrderSelect(TrackTicket[i], SELECT_BY_TICKET, MODE_TRADES))
         if(OrderCloseTime() == 0) stillOpen = true;
      if(!stillOpen)
      {
         for(int j = i; j < TrackCount - 1; j++)
         {
            TrackTicket[j] = TrackTicket[j + 1];
            TrackState [j] = TrackState [j + 1];
         }
         TrackCount--;
      }
   }
}

int FindRemainderTicket(datetime origOpenTime, double origOpenPrice, int origType)
{
   double point = MarketInfo(Symbol(), MODE_POINT);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber)        continue;
      if(OrderSymbol()      != Symbol())              continue;
      if(OrderType()        != origType)              continue;
      if(OrderOpenTime()    != origOpenTime)          continue;
      if(MathAbs(OrderOpenPrice() - origOpenPrice) > point * 2) continue;
      return(OrderTicket());
   }
   return(-1);
}

//================================================================
// SL/TP COMPUTE — with invalid SL guard (v1.4+)
//================================================================
void ComputeBuySLTP(double entry, double &sl, double &tp)
{
   double atr = Atr(1);
   if(InpMode == 0)
   {
      sl = DmaLow(1);
      double slDist = entry - sl;
      if(slDist < InpAtrMinPrice || slDist <= 0)
      {
         sl = entry - atr * InpAdaptiveSlAtrMult;
         if(InpVerboseLog)
            Print("v1.5 BUY SL guard: DMA invalid (dist=",
                  DoubleToStr(slDist / PipPoint, 1), "p) -> ATR fallback SL=", DoubleToStr(sl, Digits));
      }
      tp = entry + (entry - sl) * InpTPRRMultiplier;
   }
   else if(InpMode == 1) { sl = entry - atr * InpScalperSlAtrMult;  tp = entry + InpScalperTpPips * PipPoint; }
   else                  { sl = entry - atr * InpAdaptiveSlAtrMult; tp = entry + atr * InpAdaptiveTpAtrMult;  }
}

void ComputeSellSLTP(double entry, double &sl, double &tp)
{
   double atr = Atr(1);
   if(InpMode == 0)
   {
      sl = DmaHigh(1);
      double slDist = sl - entry;
      if(slDist < InpAtrMinPrice || slDist <= 0)
      {
         sl = entry + atr * InpAdaptiveSlAtrMult;
         if(InpVerboseLog)
            Print("v1.5 SELL SL guard: DMA invalid (dist=",
                  DoubleToStr(slDist / PipPoint, 1), "p) -> ATR fallback SL=", DoubleToStr(sl, Digits));
      }
      tp = entry - (sl - entry) * InpTPRRMultiplier;
   }
   else if(InpMode == 1) { sl = entry + atr * InpScalperSlAtrMult;  tp = entry - InpScalperTpPips * PipPoint; }
   else                  { sl = entry + atr * InpAdaptiveSlAtrMult; tp = entry - atr * InpAdaptiveTpAtrMult;  }
}

void TryOpenBuy()
{
   double entry = Ask, sl, tp;
   ComputeBuySLTP(entry, sl, tp);
   double slDist = entry - sl;
   if(slDist <= 0) { Print("v1.5: BUY SL invalid after guard — skip"); return; }
   double lots    = CalcLots(slDist);
   int    stopLvl = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDist = stopLvl * Point;
   if(entry - sl < minDist) sl = entry - minDist;
   if(tp - entry < minDist) tp = entry + minDist;
   int t = OrderSend(Symbol(), OP_BUY, lots, entry, InpSlippage,
                     NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                     "NCI v1.5 BUY", InpMagicNumber, 0, clrLime);
   if(t < 0) Print("v1.5 BUY failed err=", GetLastError());
   else
   {
      Print("v1.5 BUY #", t, " lots=", DoubleToStr(lots, 2),
            " SL=", DoubleToStr(sl, Digits), " TP=", DoubleToStr(tp, Digits),
            " R:R=1:", DoubleToStr(InpTPRRMultiplier, 1));
      if(PostCooldownTradesLeft > 0) PostCooldownTradesLeft--;
      EnsureTracking(t);
   }
}

void TryOpenSell()
{
   double entry = Bid, sl, tp;
   ComputeSellSLTP(entry, sl, tp);
   double slDist = sl - entry;
   if(slDist <= 0) { Print("v1.5: SELL SL invalid after guard — skip"); return; }
   double lots    = CalcLots(slDist);
   int    stopLvl = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDist = stopLvl * Point;
   if(sl - entry < minDist) sl = entry + minDist;
   if(entry - tp < minDist) tp = entry - minDist;
   int t = OrderSend(Symbol(), OP_SELL, lots, entry, InpSlippage,
                     NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                     "NCI v1.5 SELL", InpMagicNumber, 0, clrRed);
   if(t < 0) Print("v1.5 SELL failed err=", GetLastError());
   else
   {
      Print("v1.5 SELL #", t, " lots=", DoubleToStr(lots, 2),
            " SL=", DoubleToStr(sl, Digits), " TP=", DoubleToStr(tp, Digits),
            " R:R=1:", DoubleToStr(InpTPRRMultiplier, 1));
      if(PostCooldownTradesLeft > 0) PostCooldownTradesLeft--;
      EnsureTracking(t);
   }
}

//================================================================
// PARTIAL CLOSE + BE LOCK
//================================================================
void ManagePartialClose()
{
   if(!InpUsePartialClose) return;
   double atr = Atr(1);
   if(atr <= 0) return;
   double tp1Dist   = atr * InpTP1AtrMult;
   double preBETrig = tp1Dist * InpPreBETriggerFrac;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber || OrderSymbol() != Symbol()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int    ticket     = OrderTicket();
      bool   isBuy      = (OrderType() == OP_BUY);
      double entry      = OrderOpenPrice();
      double curPx      = isBuy ? Bid : Ask;
      double profitDist = isBuy ? (curPx - entry) : (entry - curPx);
      double origSL     = OrderStopLoss();
      double origSLDist = isBuy ? (entry - origSL) : (origSL - entry);
      int    state      = GetTrackState(ticket);

      //--- STAGE 1: Pre-BE Lock
      if(InpUsePreBELock && state < 1 && profitDist >= preBETrig && profitDist < tp1Dist)
      {
         double preBESL      = isBuy ? (entry - origSLDist * InpPreBESLFraction)
                                     : (entry + origSLDist * InpPreBESLFraction);
         bool   wouldImprove = (isBuy && preBESL > origSL) || (!isBuy && preBESL < origSL);
         if(wouldImprove)
         {
            if(SafeOrderModify(ticket, entry, preBESL, OrderTakeProfit(), 0, clrOrange))
            {
               SetTrackState(ticket, 1);
               Print("v1.5 PRE-BE LOCK #", ticket, " SL->", DoubleToStr(preBESL, Digits),
                     " profit=", DoubleToStr(profitDist / PipPoint, 1), "p");
            }
         }
      }

      //--- STAGE 2: Partial Close + Full BE
      if(profitDist >= tp1Dist && state < 2)
      {
         double curLots       = OrderLots();
         double stepLot       = MarketInfo(Symbol(), MODE_LOTSTEP);
         double minLot        = MarketInfo(Symbol(), MODE_MINLOT);
         if(stepLot <= 0) stepLot = 0.01;
         double closeLots     = MathFloor((curLots * InpPartialPercent / 100.0) / stepLot) * stepLot;
         double remainingLots = NormalizeDouble(curLots - closeLots, 2);

         if(closeLots < minLot || remainingLots < minLot)
         {
            SetTrackState(ticket, 2);
            if(InpVerboseLog) Print("v1.5 Partial skipped (lot too small) #", ticket);
            continue;
         }

         datetime origOpenTime  = OrderOpenTime();
         double   origOpenPrice = entry;
         int      origType      = OrderType();
         double   origTP        = OrderTakeProfit();
         double   closePrice    = isBuy ? Bid : Ask;

         if(OrderClose(ticket, closeLots, closePrice, InpSlippage, clrYellow))
         {
            Print("v1.5 PARTIAL CLOSE @", DoubleToStr(closePrice, Digits),
                  " closed=", DoubleToStr(closeLots, 2), " of ", DoubleToStr(curLots, 2));
            int remTicket = FindRemainderTicket(origOpenTime, origOpenPrice, origType);
            if(remTicket > 0)
            {
               double beSL = isBuy ? (origOpenPrice + InpBEPlusPips * PipPoint)
                                   : (origOpenPrice - InpBEPlusPips * PipPoint);
               if(SafeOrderModify(remTicket, origOpenPrice, beSL, origTP, 0, clrAqua))
                  Print("v1.5 BE LOCK remainder #", remTicket, " SL=", DoubleToStr(beSL, Digits));
               SetTrackState(remTicket, 2);
            }
            else Print("v1.5 WARN: remainder not found after partial on #", ticket);
            return;
         }
         else Print("v1.5 Partial close FAILED #", ticket, " err=", GetLastError());
      }
   }
}

//================================================================
// v1.6 HARD PROFIT LOCK — fires at InpHardLockPips regardless of ATR
// Closes InpHardLockPct% of position and moves remainder SL to
// entry + spread buffer so profit above spread cost is guaranteed.
// State 3 ensures it fires exactly once per ticket.
//
// Design from EA library ingestion:
//   Breakout Expert: lockProfit=20 — SL to entry+20 when up 50p
//   Farhad Hill: FirstMove=20p → BE, SecondMove=30p → lock 20p
//   Hans123: BreakEven=30p
//   2EMA System: trail starts at 15p
//================================================================
void ManageHardLock()
{
   if(!InpUseHardLock) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber || OrderSymbol() != Symbol()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int    ticket     = OrderTicket();
      bool   isBuy      = (OrderType() == OP_BUY);
      double entry      = OrderOpenPrice();
      double curPx      = isBuy ? Bid : Ask;
      double profitPips = isBuy ? (curPx - entry) / PipPoint
                                : (entry - curPx) / PipPoint;
      int    state      = GetTrackState(ticket);

      if(state >= 3) continue;               // Already hard-locked
      if(profitPips < InpHardLockPips) continue;  // Not yet at trigger

      double curLots  = OrderLots();
      double stepLot  = MarketInfo(Symbol(), MODE_LOTSTEP);
      double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
      if(stepLot <= 0) stepLot = 0.01;

      double closeLots = MathFloor((curLots * InpHardLockPct / 100.0) / stepLot) * stepLot;
      double remLots   = NormalizeDouble(curLots - closeLots, 2);

      // Compute SL that locks in profit above spread cost
      double spreadPips = SpreadPips();
      double lockBuffer = spreadPips * InpHardLockSLBuf * PipPoint;
      double lockSL     = isBuy ? entry + lockBuffer : entry - lockBuffer;

      // Can't do a partial (too small) — just move the SL and mark done
      if(closeLots < minLot || remLots < minLot)
      {
         bool wouldImprove = (isBuy  && lockSL > OrderStopLoss()) ||
                             (!isBuy && (OrderStopLoss() == 0 || lockSL < OrderStopLoss()));
         if(wouldImprove)
         {
            if(SafeOrderModify(ticket, entry, lockSL, OrderTakeProfit(), 0, clrMagenta))
               Print("v1.6 HARD LOCK (SL move only) #", ticket,
                     " SL->", DoubleToStr(lockSL, Digits),
                     " profit=", DoubleToStr(profitPips, 1), "p");
         }
         SetTrackState(ticket, 3);
         continue;
      }

      // Partial close + SL lock
      datetime origOpenTime  = OrderOpenTime();
      double   origOpenPrice = entry;
      int      origType      = OrderType();
      double   origTP        = OrderTakeProfit();
      double   closePrice    = isBuy ? Bid : Ask;

      if(OrderClose(ticket, closeLots, closePrice, InpSlippage, clrMagenta))
      {
         Print("v1.6 HARD LOCK close #", ticket,
               " closed=", DoubleToStr(closeLots, 2), "/", DoubleToStr(curLots, 2),
               " @", DoubleToStr(closePrice, Digits),
               " profit=", DoubleToStr(profitPips, 1), "p",
               " (trigger=", DoubleToStr(InpHardLockPips, 0), "p)");

         int remTicket = FindRemainderTicket(origOpenTime, origOpenPrice, origType);
         if(remTicket > 0)
         {
            if(SafeOrderModify(remTicket, origOpenPrice, lockSL, origTP, 0, clrMagenta))
               Print("v1.6 HARD LOCK SL #", remTicket,
                     " -> entry+spread_buf=", DoubleToStr(lockSL, Digits),
                     " (spread=", DoubleToStr(spreadPips, 1), "p x",
                     DoubleToStr(InpHardLockSLBuf, 1), ")");
            SetTrackState(remTicket, 3);
         }
         else
            Print("v1.6 WARN: hard lock remainder not found after partial #", ticket);

         // v1.8: flag re-entry opportunity — will be processed in OnTick new-bar block
         if(InpAllowReEntry)
         {
            g_reentry_avail = true;
            g_reentry_dir   = isBuy ? 1 : -1;
            g_reentry_bar   = Time[0];
            g_reentry_count = 0;
            Print("v1.8 RE-ENTRY FLAGGED: dir=", isBuy ? "BUY" : "SELL",
                  " bar=", TimeToStr(g_reentry_bar, TIME_DATE | TIME_MINUTES));
         }
         return;
      }
      else
         Print("v1.6 HARD LOCK close FAILED #", ticket, " err=", GetLastError());
   }
}

//================================================================
// TRAILING STOP — v1.7 uses Chandelier Exit formula
// Source: ChandelierExit.mq4 from 1000 MT4 indicator library.
// SL anchored to swing high/low of last N bars minus ATR*mult.
// Far more stable than ATR-from-current-price — only moves when
// a new swing extreme is made, not on every pip.
// v1.5 step gate retained to prevent modify floods.
//================================================================
void ManageTrailing()
{
   double atr      = Atr(0);
   double stepGate = InpTrailMinStepPips * PipPoint;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber || OrderSymbol() != Symbol()) continue;

      double openPx = OrderOpenPrice();
      double curSL  = OrderStopLoss();
      double curTP  = OrderTakeProfit();

      if(OrderType() == OP_BUY)
      {
         double profitPips = (Bid - openPx) / PipPoint;
         if(profitPips < InpTrailTriggerPips) continue;

         double newSL;
         if(InpUseChandelier)
         {
            // v1.7: Chandelier — anchored to highest high of last N bars
            int hiIdx = iHighest(NULL, 0, MODE_HIGH, InpChanRange, 0);
            newSL = iHigh(NULL, 0, hiIdx) - atr * InpChanATRMult;
         }
         else
            newSL = Bid - (InpUseAtrTrail ? atr * InpTrailAtrMult : InpTrailFixedPips * PipPoint);

         if(curSL == 0 || newSL > curSL + stepGate)
            SafeOrderModify(OrderTicket(), openPx, newSL, curTP, 0, clrYellow);
      }
      else if(OrderType() == OP_SELL)
      {
         double profitPips = (openPx - Ask) / PipPoint;
         if(profitPips < InpTrailTriggerPips) continue;

         double newSL;
         if(InpUseChandelier)
         {
            // v1.7: Chandelier — anchored to lowest low of last N bars
            int loIdx = iLowest(NULL, 0, MODE_LOW, InpChanRange, 0);
            newSL = iLow(NULL, 0, loIdx) + atr * InpChanATRMult;
         }
         else
            newSL = Ask + (InpUseAtrTrail ? atr * InpTrailAtrMult : InpTrailFixedPips * PipPoint);

         if(curSL == 0 || newSL < curSL - stepGate)
            SafeOrderModify(OrderTicket(), openPx, newSL, curTP, 0, clrYellow);
      }
   }
}

//================================================================
// EXPECTANCY TRACKING & STRIKE LOGIC
//================================================================
void UpdateExpectancyAndStrikes()
{
   int total = OrdersHistoryTotal();
   if(total <= LastTotalHistory) return;

   for(int i = LastTotalHistory; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagicNumber || OrderSymbol() != Symbol()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      TotalClosed++;
      if(pnl > 0)
      {
         TotalWins++;
         ConsecutiveLosses = 0;
      }
      else
      {
         TotalLosses++;
         ConsecutiveLosses++;
         if(InpUseStrikeCooldown && ConsecutiveLosses >= InpStrikeLimit)
         {
            int periodSec = Period() * 60;
            CooldownUntilTime      = TimeCurrent() + InpCooldownBars * periodSec;
            PostCooldownTradesLeft = 3;
            Print("*** v1.5 STRIKE COOLDOWN *** ", ConsecutiveLosses,
                  " consecutive losses. Pausing until ",
                  TimeToStr(CooldownUntilTime, TIME_DATE | TIME_MINUTES));
            ConsecutiveLosses = 0;
         }
      }
      double wr = TotalClosed > 0 ? (100.0 * TotalWins / TotalClosed) : 0.0;
      Print("[NCI WR v1.5] #", OrderTicket(), " pnl=", DoubleToStr(pnl, 2),
            " wins=", TotalWins, " losses=", TotalLosses,
            " WR=", DoubleToStr(wr, 1), "%");
   }
   LastTotalHistory = total;
}

//================================================================
// DAILY DD CIRCUIT BREAKER
//================================================================
void CheckDailyDD()
{
   if(IsNewDay()) ResetDailyAnchor();
   if(!InpUseDailyDDLock || DailyAnchorEquity <= 0) return;
   double dd = 100.0 * (DailyAnchorEquity - AccountEquity()) / DailyAnchorEquity;
   if(dd >= InpMaxDailyDDPct && !DailyLocked)
   {
      DailyLocked = true;
      Print("*** v1.5 DAILY DD LOCK *** dd=", DoubleToStr(dd, 2), "% >= ",
            InpMaxDailyDDPct, "%. EA locked until next session.");
   }
}

//================================================================
// LIFECYCLE
//================================================================
int OnInit()
{
   InitPipMath();
   ResetDailyAnchor();
   LastTotalHistory = OrdersHistoryTotal();
   TrackCount       = 0;

   g_reentry_avail = false;
   g_reentry_count = 0;

   Print("=== NCI Hybrid v1.8 INIT === GBPUSD M15 ONLY ===");
   Print("Sym=", Symbol(), " Digits=", Digits, " PipPoint=", PipPoint);
   Print("Mode=", InpMode, " Risk=", InpRiskPct, "% Magic=", InpMagicNumber);
   Print("Swing confluence min=", InpMinConfluence, "/15 | Scalp confluence min=", InpScalpMinConfl, "/15");
   Print("R:R Multiplier=", InpTPRRMultiplier, "x | Partial=", InpPartialPercent,
         "% @ ", InpTP1AtrMult, "xATR");
   Print("HTF Gate: RequireBoth=", InpHTFRequireBoth,
         " (false=OR logic)");
   Print("v1.5 MTF Voter: ", InpUseMTFVoter ? "ON" : "OFF",
         " EMA(", InpMTFEmaFast, ",", InpMTFEmaSlow,
         ") MinAligned=", InpMTFMinAligned, "/4 [W1/D1/H4/H1]");
   Print("v1.5 Trail Gate: ", InpTrailMinStepPips, " pips min step (eliminates tick flood)");
   Print("DailyDDLock=", InpUseDailyDDLock, " @", InpMaxDailyDDPct, "%");
   Print("v1.7 VOTERS: 15 total | MinConfluence=", InpMinConfluence, "/15",
         " | DmaSlope=", InpRequireDmaSlope, " | VolRatio=", InpVolumeMinRatio,
         " | MTF=", InpMTFMinAligned, "/4 | TTF=", InpUseTTFVoter,
         " | Vegas H4=", InpUseVegasH4);
   Print("v1.7 CHANDELIER: ", InpUseChandelier ? "ON" : "OFF",
         " Range=", InpChanRange, " ATRx=", InpChanATRMult);
   Print("v1.7 ADR FILTER: ", InpUseADRFilter ? "ON" : "OFF",
         " block at >", InpADRMaxPct, "% of ", InpADRPeriod, "-day ADR");
   Print("v1.6 HARD LOCK: ", InpUseHardLock ? "ON" : "OFF",
         " trigger=", InpHardLockPips, "p close=", InpHardLockPct,
         "% SL=entry+spread*", InpHardLockSLBuf);
   Print("v1.8 SCALP MODE: enabled=", InpScalpModeEnabled,
         " minConfl=", InpScalpMinConfl,
         " TP=", InpScalpTPPips, "p",
         " SL=", InpScalpSLMult, "xATR",
         " maxTrades=", InpScalpMaxTrades,
         " sessionOnly=", InpScalpSessionOnly,
         " London=", InpScalpLonStart, "-", InpScalpLonEnd,
         " NY=", InpScalpNYStart, "-", InpScalpNYEnd);
   Print("v1.8 RE-ENTRY: ", InpAllowReEntry ? "ON" : "OFF",
         " maxPerBar=", InpReEntryMaxPerBar);
   EventSetTimer(20);
   WriteLiveData();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   double wr = TotalClosed > 0 ? (100.0 * TotalWins / TotalClosed) : 0.0;
   Print("=== NCI Hybrid v1.8 STOPPED ===");
   Print("Final: wins=", TotalWins, " losses=", TotalLosses,
         " closed=", TotalClosed, " WR=", DoubleToStr(wr, 2), "%");
}

//================================================================
// v1.5 LIVE INTELLIGENCE: SIGNAL EXPORT + COMMAND READER
//================================================================

int EffectiveMinConfluence() {
   // v1.8: scalp mode uses InpScalpMinConfl (default 4) — not the standard 6
   if(IsScalpMode()) return(g_rt_min_confluence > 0 ? (int)g_rt_min_confluence : InpScalpMinConfl);
   return(g_rt_min_confluence > 0 ? (int)g_rt_min_confluence : InpMinConfluence);
}
int EffectiveMaxSpread()     { return(g_rt_max_spread     > 0 ? (int)g_rt_max_spread     : InpMaxSpreadPips); }
double EffectiveRiskPct()    { return(g_rt_risk_pct       > 0 ? g_rt_risk_pct            : InpRiskPct); }
double EffectiveTrailStep()  { return(g_rt_trail_step     > 0 ? g_rt_trail_step          : InpTrailMinStepPips); }

void WriteSignalJSON(int buyScore, int sellScore,
                     string buyBd,  string sellBd,
                     bool buyHTFOk, bool sellHTFOk)
{
   bool isBuy  = (buyScore  >= EffectiveMinConfluence() && buyScore  > sellScore);
   bool isSell = (sellScore >= EffectiveMinConfluence() && sellScore > buyScore);

   string direction  = isBuy ? "BUY" : (isSell ? "SELL" : "NONE");
   int    score      = isBuy ? buyScore : (isSell ? sellScore : MathMax(buyScore, sellScore));
   string breakdown  = isBuy ? buyBd   : (isSell ? sellBd   : buyBd);
   bool   fired      = false;
   string blocked    = "";

   if(isBuy  && !buyHTFOk)  { blocked = "HTF_GATE"; }
   if(isSell && !sellHTFOk) { blocked = "HTF_GATE"; }
   if(!isBuy && !isSell)    { blocked = "SCORE_LOW"; }
   if(DailyLocked)           { blocked = "DAILY_DD_LOCK"; }
   if(TimeCurrent() < CooldownUntilTime) { blocked = "COOLDOWN"; }

   fired = (isBuy || isSell) && StringLen(blocked) == 0;

   double atr    = iATR(Symbol(), Period(), InpAtrPeriod, 0);
   double spread = SpreadPips();

   string json = "{";
   json += "\"ts\":"          + IntegerToString((int)TimeCurrent()) + ",";
   json += "\"pair\":\""      + Symbol()    + "\",";
   json += "\"direction\":\"" + direction   + "\",";
   json += "\"score\":"       + IntegerToString(score) + ",";
   json += "\"max\":15,";
   json += "\"fired\":"       + (fired ? "true" : "false") + ",";
   json += "\"blocked_reason\":\"" + blocked + "\",";
   json += "\"voters\":\""    + breakdown  + "\",";
   json += "\"spread\":"      + DoubleToStr(spread, 2) + ",";
   json += "\"atr\":"         + DoubleToStr(atr,    5) + ",";
   json += "\"buy_score\":"   + IntegerToString(buyScore)  + ",";
   json += "\"sell_score\":"  + IntegerToString(sellScore) + ",";
   json += "\"htf_buy\":"     + (buyHTFOk  ? "true" : "false") + ",";
   json += "\"htf_sell\":"    + (sellHTFOk ? "true" : "false");
   json += "}";

   int fh = FileOpen("NCI_Signal.json", FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(fh != INVALID_HANDLE) { FileWriteString(fh, json); FileClose(fh); }
}

void WriteLiveData()
{
   // Account state
   double balance  = AccountBalance();
   double equity   = AccountEquity();
   double margin   = AccountMargin();
   double freeMargin = AccountFreeMargin();
   double drawdown = (balance > 0) ? (balance - equity) / balance * 100.0 : 0.0;

   // Daily P&L — sum all closed trades today
   double dayPnl   = 0.0;
   int    dayWins  = 0;
   int    dayLoss  = 0;
   datetime dayStart = StringToTime(TimeToStr(TimeCurrent(), TIME_DATE));
   int total = OrdersHistoryTotal();
   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagicNumber)         continue;
      if(OrderCloseTime() < dayStart)                  continue;
      dayPnl += OrderProfit() + OrderCommission() + OrderSwap();
      if(OrderProfit() > 0) dayWins++; else dayLoss++;
   }

   // Open trades snapshot
   string tradesArr = "[";
   int openCount = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber)         continue;
      if(openCount > 0) tradesArr += ",";
      string typ = (OrderType() == OP_BUY) ? "BUY" : "SELL";
      tradesArr += "{";
      tradesArr += "\"ticket\":"  + IntegerToString(OrderTicket())        + ",";
      tradesArr += "\"pair\":\""  + OrderSymbol()                         + "\",";
      tradesArr += "\"type\":\""  + typ                                   + "\",";
      tradesArr += "\"lots\":"    + DoubleToStr(OrderLots(), 2)           + ",";
      tradesArr += "\"open\":"    + DoubleToStr(OrderOpenPrice(), 5)      + ",";
      tradesArr += "\"sl\":"      + DoubleToStr(OrderStopLoss(), 5)       + ",";
      tradesArr += "\"tp\":"      + DoubleToStr(OrderTakeProfit(), 5)     + ",";
      tradesArr += "\"pnl\":"     + DoubleToStr(OrderProfit(), 2)         + ",";
      tradesArr += "\"open_time\":" + IntegerToString((int)OrderOpenTime());
      tradesArr += "}";
      openCount++;
   }
   tradesArr += "]";

   // Stats (all-time from history for this magic)
   int   allTotal = 0, allWins = 0;
   double allProfit = 0, allWinSum = 0, allLossSum = 0;
   for(int i = 0; i < OrdersHistoryTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagicNumber)         continue;
      double p = OrderProfit() + OrderCommission() + OrderSwap();
      allTotal++;
      allProfit += p;
      if(p > 0) { allWins++; allWinSum += p; }
      else       { allLossSum += MathAbs(p); }
   }
   double winRate = (allTotal > 0) ? (double)allWins / allTotal * 100.0 : 0.0;
   double avgWin  = (allWins > 0)  ? allWinSum / allWins : 0.0;
   int    losses  = allTotal - allWins;
   double avgLoss = (losses > 0)   ? allLossSum / losses : 0.0;
   double pf      = (allLossSum > 0) ? allWinSum / allLossSum : 0.0;

   string json = "{";
   json += "\"status\":\"online\",";
   json += "\"timestamp\":\""    + TimeToStr(TimeCurrent(), TIME_DATE|TIME_MINUTES) + "\",";
   json += "\"magic\":"          + IntegerToString(InpMagicNumber) + ",";
   json += "\"pair\":\""         + Symbol() + "\",";
   json += "\"balance\":"        + DoubleToStr(balance,    2) + ",";
   json += "\"equity\":"         + DoubleToStr(equity,     2) + ",";
   json += "\"margin\":"         + DoubleToStr(margin,     2) + ",";
   json += "\"free_margin\":"    + DoubleToStr(freeMargin, 2) + ",";
   json += "\"drawdown_pct\":"   + DoubleToStr(drawdown,   2) + ",";
   json += "\"daily_pnl\":"      + DoubleToStr(dayPnl,     2) + ",";
   json += "\"daily_wins\":"     + IntegerToString(dayWins)   + ",";
   json += "\"daily_losses\":"   + IntegerToString(dayLoss)   + ",";
   json += "\"open_count\":"     + IntegerToString(openCount) + ",";
   json += "\"scalp_mode\":"     + (IsScalpMode() ? "true" : "false") + ",";
   json += "\"daily_locked\":"   + (DailyLocked   ? "true" : "false") + ",";
   json += "\"trades\":"         + tradesArr + ",";
   json += "\"stats\":{";
   json += "\"total\":"          + IntegerToString(allTotal) + ",";
   json += "\"wins\":"           + IntegerToString(allWins)  + ",";
   json += "\"losses\":"         + IntegerToString(losses)   + ",";
   json += "\"win_rate\":"       + DoubleToStr(winRate, 1)   + ",";
   json += "\"avg_win\":"        + DoubleToStr(avgWin,  2)   + ",";
   json += "\"avg_loss\":"       + DoubleToStr(avgLoss, 2)   + ",";
   json += "\"profit_factor\":"  + DoubleToStr(pf,      2)   + ",";
   json += "\"total_pnl\":"      + DoubleToStr(allProfit, 2);
   json += "}}";

   int fh = FileOpen("NCI_LiveData.json", FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(fh != INVALID_HANDLE) { FileWriteString(fh, json); FileClose(fh); }
}

void ReadCommandsJSON()
{
   int fh = FileOpen("NCI_Commands.json", FILE_READ|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return;
   string raw = "";
   while(!FileIsEnding(fh)) raw += FileReadString(fh);
   FileClose(fh);
   if(StringLen(raw) < 5) return;

   int ts_pos = StringFind(raw, "\"ts\":");
   if(ts_pos < 0) return;
   string ts_str = StringSubstr(raw, ts_pos + 5, 12);
   datetime cmd_ts = (datetime)StringToInteger(ts_str);
   if(cmd_ts <= g_last_cmd_ts) return;

   // Scalp mode command: {"ts":...,"mode":"scalp","active":true/false}
   if(StringFind(raw, "\"mode\":\"scalp\"") >= 0) {
      g_scalp_mode = (StringFind(raw, "\"active\":true") >= 0);
      g_last_cmd_ts = cmd_ts;
      Print("v1.8 SCALP MODE via JSON: ", g_scalp_mode
            ? "ON (confluence=" + IntegerToString(InpScalpMinConfl) + " TP=" + IntegerToString(InpScalpTPPips) + "p maxTrades=" + IntegerToString(InpScalpMaxTrades) + ")"
            : "OFF (swing mode confluence=" + IntegerToString(InpMinConfluence) + ")");
      return;
   }

   // Parameter adjustment command: {"ts":...,"param":"InpMinConfluence","value":9}
   string param = "";
   int pp = StringFind(raw, "\"param\":\"");
   if(pp >= 0) {
      int ps = pp + 9;
      int pe = StringFind(raw, "\"", ps);
      if(pe > ps) param = StringSubstr(raw, ps, pe - ps);
   }
   double value = 0;
   int vp = StringFind(raw, "\"value\":");
   if(vp >= 0) value = StringToDouble(StringSubstr(raw, vp + 8, 20));

   if(param == "InpMinConfluence")    g_rt_min_confluence = value;
   if(param == "InpMaxSpreadPips")    g_rt_max_spread     = value;
   if(param == "InpRiskPct")          g_rt_risk_pct       = value;
   if(param == "InpTrailMinStepPips") g_rt_trail_step     = value;

   g_last_cmd_ts = cmd_ts;
   if(InpVerboseLog)
      Print("v1.5 CMD applied: ", param, "=", DoubleToStr(value, 4),
            " (effective min=", EffectiveMinConfluence(), ")");
}

//================================================================
// TIMER - heartbeat for live dashboard during quiet markets
//================================================================
void OnTimer()
{
   WriteLiveData();
}

//================================================================
// MAIN TRADING LOOP
//================================================================
void OnTick()
{
   ManageHardLock();      // v1.6: hard 15-pip lock — runs first, every tick
   ManagePartialClose();
   ManageTrailing();
   UpdateExpectancyAndStrikes();
   CheckDailyDD();
   CleanupTracking();

   if(!IsNewBar()) return;

   ReadCommandsJSON();   // Check for dashboard parameter adjustments

   if(DailyLocked)             { if(InpVerboseLog) Print("Skip: daily DD locked");           return; }
   if(TimeCurrent() < CooldownUntilTime) { if(InpVerboseLog) Print("Skip: in cooldown"); return; }
   if(!InSession())            return;

   // v1.8: scalp mode uses its own spread gate; swing uses InpMaxSpreadPips
   double spreadNow = SpreadPips();
   int    spreadGate = IsScalpMode() ? InpScalpMaxSpread : (int)EffectiveMaxSpread();
   if(spreadNow > spreadGate) { if(InpVerboseLog) Print("Skip: spread ", DoubleToStr(spreadNow, 1), " > ", spreadGate); return; }

   // v1.8: scalp mode allows InpScalpMaxTrades concurrent positions
   if(CountMyTrades() >= ScalpMaxOpenTrades()) return;

   if(ADRExhausted()) return;   // v1.7: skip if today's range >= 85% of ADR

   // v1.8: scalp mode requires active session window (London/NY open)
   bool inScalpSession = IsScalpSession();
   if(IsScalpMode() && !inScalpSession)
   {
      if(InpVerboseLog) Print("v1.8 SCALP: outside London/NY window, skip");
      return;
   }

   string buyBd, sellBd;
   int buyScore  = BuyConfluenceScore(buyBd);
   int sellScore = SellConfluenceScore(sellBd);
   if(InpLogConfluence) { Print(buyBd); Print(sellBd); }

   bool buyHTFOk  = HTFGateAllowBuy();
   bool sellHTFOk = HTFGateAllowSell();

   WriteSignalJSON(buyScore, sellScore, buyBd, sellBd, buyHTFOk, sellHTFOk);
   WriteLiveData();

   int    minConf  = EffectiveMinConfluence();
   bool   scalping = IsScalpMode();

   // v1.8 RE-ENTRY BLOCK — fires when hard lock freed a slot this bar
   // Runs before normal signal to get the re-entry in at the earliest opportunity
   if(InpAllowReEntry && g_reentry_avail && g_reentry_bar == Time[0]
      && g_reentry_count < InpReEntryMaxPerBar
      && CountMyTrades() < ScalpMaxOpenTrades())
   {
      if(g_reentry_dir == 1 && buyScore >= minConf && ScalpCoreVotersBull())
      {
         Print("v1.8 RE-ENTRY BUY — hard lock freed slot, signal=", buyScore, "/15");
         TryOpenScalpBuy();
         g_reentry_count++;
         g_reentry_avail = false;
      }
      else if(g_reentry_dir == -1 && sellScore >= minConf && ScalpCoreVotersBear())
      {
         Print("v1.8 RE-ENTRY SELL — hard lock freed slot, signal=", sellScore, "/15");
         TryOpenScalpSell();
         g_reentry_count++;
         g_reentry_avail = false;
      }
      else
      {
         if(InpVerboseLog)
            Print("v1.8 RE-ENTRY skipped: core voters or score failed for dir=", g_reentry_dir);
         g_reentry_avail = false;  // Reset — won't retry next tick
      }
   }
   // Reset stale re-entry flag from a previous bar
   if(g_reentry_avail && g_reentry_bar != Time[0])
   {
      g_reentry_avail = false;
      g_reentry_count = 0;
   }

   // NORMAL ENTRY DECISION
   if(buyScore >= minConf && buyScore > sellScore)
   {
      if(!buyHTFOk)
      {
         if(InpVerboseLog)
            Print("v1.8 SKIP BUY: HTF gate failed (persist=", HtfTrendUpPersistent(),
                  " slope=", HtfSlopeUp(), " requireBoth=", InpHTFRequireBoth,
                  ") score=", buyScore, "/15 minConf=", minConf);
         return;
      }
      // v1.8: scalp mode routes to scalp entry (mandatory core voters + fixed TP)
      if(scalping)
      {
         if(!ScalpCoreVotersBull())
         {
            if(InpVerboseLog) Print("v1.8 SCALP BUY blocked: core voters (HTF/RSI/Vol) failed");
            return;
         }
         TryOpenScalpBuy();
      }
      else
         TryOpenBuy();
      return;
   }

   if(sellScore >= minConf && sellScore > buyScore)
   {
      if(!sellHTFOk)
      {
         if(InpVerboseLog)
            Print("v1.8 SKIP SELL: HTF gate failed (persist=", HtfTrendDnPersistent(),
                  " slope=", HtfSlopeDn(), " requireBoth=", InpHTFRequireBoth,
                  ") score=", sellScore, "/15 minConf=", minConf);
         return;
      }
      if(scalping)
      {
         if(!ScalpCoreVotersBear())
         {
            if(InpVerboseLog) Print("v1.8 SCALP SELL blocked: core voters (HTF/RSI/Vol) failed");
            return;
         }
         TryOpenScalpSell();
      }
      else
         TryOpenSell();
      return;
   }

   if(InpVerboseLog)
      Print("No trade: best score=", MathMax(buyScore, sellScore), "/15 below ", minConf,
            scalping ? " [SCALP MODE]" : " [SWING MODE]");
}
//+------------------------------------------------------------------+
