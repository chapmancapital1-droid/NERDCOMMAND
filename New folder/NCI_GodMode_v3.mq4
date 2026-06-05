//+------------------------------------------------------------------+
//|                                              NCI_GodMode_v3.mq4   |
//|             NERDCOMMAND Core Intelligence (NCI) — Autonomous EA   |
//|                                                                  |
//|  THE STRATEGY (full self-operating trading system):             |
//|                                                                  |
//|   HARD GATE 0 — ABC MARKET CYCLE (Wyckoff/Weinstein regime)     |
//|       Stage A (consolidation, ADX<20 & FER<0.45) -> BLOCK       |
//|       Stage B (expansion,     ADX>=22 & FER>=0.50) -> TRADE     |
//|         - only B1/B2 (ADX rising). B3 exhaustion -> no entry    |
//|       Stage C (contraction,   ADX falling, FER<0.55) -> trail   |
//|                                                                  |
//|   ENTRY — 15-voter confluence (v1.4 base + v1.8 MTF/TTF/Vegas)  |
//|       Fires when score >= InpMinConfluence AND Stage B AND      |
//|       HTF gate agrees.                                          |
//|                                                                  |
//|   STOP-LOSS / MANAGEMENT (the rules that run the trade):       |
//|       - DMA-break SL with ATR fallback guard (v1.4)            |
//|       - TP = SL_distance * R:R (default 1.5)                    |
//|       - Pre-BE lock at 50% to TP1                              |
//|       - Partial close 35% at 1.2xATR, remainder to break-even  |
//|       - Chandelier trail: SL = swingHigh - ATR*Mult            |
//|         Stage B mult = 3.0 (loose) | Stage C mult = 2.2 (tight)|
//|       - 3-strike cooldown, daily DD lock, lot cap, sessions    |
//|                                                                  |
//|   *** RUN ON DEMO FIRST. Validate with Strategy Tester before  |
//|       any live capital. InpTradingEnabled gates execution. ***  |
//|                                                                  |
//|             (c) 2026 GangsterNerds LLC - NERDCOMMAND Trading     |
//+------------------------------------------------------------------+
#property copyright   "GangsterNerds LLC - NERDCOMMAND Trading"
#property version     "3.10"
#property description "NCI GodMode v3.1 - ABC-gated 15-voter EA + $-trigger 10-pip trailing stop & secured pyramiding."
#property strict

//================================================================
// MASTER SWITCH
//================================================================
extern string InpRunSect           = "=== MASTER ===";
extern bool   InpTradingEnabled    = true;    // false = report only (no OrderSend). Start TRUE on DEMO.
extern int    InpMagicNumber       = 24300;
extern double InpRiskPct           = 0.5;     // Risk per trade (% equity)
extern double InpFixedLots         = 0.0;
extern int    InpMaxSpreadPips     = 3;     // ".03" = 3-pip spread gate (entry + secure-trail)
extern int    InpMaxOpenTrades     = 1;
extern int    InpSlippage          = 3;

//--- Lot cap
extern double InpMaxLotsPerPipPctEquity = 0.1;
extern bool   InpEnforceLotCap     = true;

//================================================================
// ABC MARKET CYCLE — HARD GATE 0
//================================================================
extern string InpABCSect           = "=== ABC MARKET CYCLE ===";
extern bool   InpUseABCGate        = true;
extern int    InpABCAdxPeriod      = 14;
extern int    InpFERPeriod         = 10;      // bars for Fractal Efficiency Ratio
extern double InpStageA_AdxMax     = 20.0;    // ADX below this + low FER = consolidation
extern double InpStageA_FERMax     = 0.45;
extern double InpStageB_AdxMin     = 22.0;    // ADX above this + FER>=min = expansion
extern double InpStageB_FERMin     = 0.50;
extern double InpStageC_FERMax     = 0.55;
extern int    InpAdxRisingBars     = 3;       // ADX must exceed value N bars ago (block B3 exhaustion)
extern bool   InpUseHTFStage       = true;    // also require H4 not in Stage A

//================================================================
// ENTRY — confluence + indicators (v1.4 / v1.8)
//================================================================
extern string InpEntrySect         = "=== ENTRY ENGINE ===";
extern int    InpMinConfluence     = 6;       // of 15
extern int    InpDmaLength         = 25;
extern bool   InpRequireDmaSlope   = false;
extern int    InpStochK            = 25;
extern int    InpStochSmooth       = 3;
extern int    InpStochD            = 3;
extern int    InpStochBuyLo        = 30;
extern int    InpStochBuyHi        = 49;
extern int    InpStochSellLo       = 50;
extern int    InpStochSellHi       = 70;
extern int    InpStochRegimeMode   = 2;
extern int    InpStochAdxThresh    = 20;
extern bool   InpUseAEXD           = true;
extern int    InpDivLookback       = 5;
extern int    InpRsiLength         = 14;
extern bool   InpUseCandles        = true;
extern double InpPinTailFactor     = 2.5;
extern int    InpAtrPeriod         = 14;
extern double InpAtrMinPrice       = 0.0003;
extern bool   InpUseHTFTrend       = true;
extern int    InpHTFTimeframe      = PERIOD_H1;
extern int    InpHTFEmaLength      = 21;
extern int    InpHTFPersistBars    = 3;
extern bool   InpRequireHTFAgree   = true;
extern bool   InpRequireHTFSlope   = true;
extern int    InpHTFSlopeBars      = 3;
extern bool   InpHTFRequireBoth    = false;
extern bool   InpUseRobotrick      = true;
extern int    InpRoboFastLen       = 10;
extern int    InpRoboSlowLen       = 34;
extern double InpRoboChanAtrMult   = 0.5;
extern bool   InpUseVolumeFilter   = true;
extern int    InpVolumeAvgPeriod   = 20;
extern double InpVolumeMinRatio    = 1.0;
extern bool   InpUseMACDVoter      = true;
extern int    InpMacdFast          = 12;
extern int    InpMacdSlow          = 26;
extern int    InpMacdSignal        = 9;
extern bool   InpUseDayRangeVoter  = true;
extern double InpDayRangeZonePct   = 20.0;
extern bool   InpUseMTFVoter       = true;
extern int    InpMTFEmaFast        = 20;
extern int    InpMTFEmaSlow        = 50;
extern int    InpMTFMinAligned     = 2;
extern bool   InpUseTTFVoter       = true;
extern int    InpTTFBars           = 8;
extern bool   InpUseVegasH4        = true;
extern int    InpVegasFast         = 8;
extern int    InpVegasSlow         = 55;

//================================================================
// EXIT / STOP-LOSS MANAGEMENT
//================================================================
extern string InpExitSect          = "=== STOP-LOSS RULES ===";
extern double InpTPRRMultiplier    = 2.5;   // wider TP backstop; the 10-pip trail is the real exit
extern double InpAdaptiveSlAtrMult = 1.2;
extern bool   InpUsePartialClose   = false;  // OFF: amputates winners (proven PF drag)
extern double InpTP1AtrMult        = 1.2;
extern double InpPartialPercent    = 35.0;
extern double InpBEPlusPips        = 2.0;
extern bool   InpUsePreBELock      = false;  // OFF: replaced by $-trigger trail
extern double InpPreBETriggerFrac  = 0.5;
extern double InpPreBESLFraction   = 0.5;
//--- Chandelier trail (v1.8) — Stage-aware multiplier
extern bool   InpUseChandelier     = false;  // OFF: replaced by secure 10-pip trail
extern int    InpChanRange         = 15;      // swing lookback bars
extern double InpChanMultStageB    = 3.0;     // loose trail in expansion
extern double InpChanMultStageC    = 2.2;     // tight trail in contraction (PDF)
extern double InpTrailTriggerPips  = 7.0;
extern bool   InpUseSafeModify     = true;

//--- v3.1 SECURE + STACK  (+$ trigger -> fixed-pip trailing stop, then pyramid)
extern bool   InpUseSecureTrail    = true;   // arm a fixed-pip trailing stop once trade is +$ profit
extern double InpSecureProfitUSD   = 1.0;    // floating profit ($) that arms the trail
extern double InpSecureTrailPips   = 10.0;   // trail distance behind price (pips)
extern bool   InpUseStacking       = true;   // open a NEW entry once existing positions are secured
extern int    InpStackMaxTrades    = 3;      // max concurrent positions when stacking

//================================================================
// RISK GUARDS
//================================================================
extern string InpGuardSect         = "=== RISK GUARDS ===";
extern bool   InpUseStrikeCooldown = true;
extern int    InpStrikeLimit       = 3;
extern int    InpCooldownBars      = 24;
extern double InpPostCooldownRisk  = 0.5;
extern bool   InpUseDailyDDLock    = true;
extern double InpMaxDailyDDPct     = 3.0;
extern bool   InpUseSessionFilter  = true;
extern int    InpSessionStartHour  = 7;
extern int    InpSessionEndHour    = 20;
extern bool   InpSkipFriday        = false;

//================================================================
// DASHBOARD / LOGGING
//================================================================
extern bool   InpWriteDashboard    = true;    // write JSON for GodMode dashboard
extern bool   InpVerboseLog        = true;
extern bool   InpLogConfluence     = true;

//================================================================
// GLOBALS
//================================================================
double   PipPoint, PipMultiplier;
datetime LastBarTime = 0;
int      ConsecutiveLosses = 0;
datetime CooldownUntilTime = 0;
int      PostCooldownTradesLeft = 0;
datetime DailyAnchorTime = 0;
double   DailyAnchorEquity = 0.0;
bool     DailyLocked = false;
int      TotalClosed=0, TotalWins=0, TotalLosses=0, LastTotalHistory=0;

#define TRACK_CAP 30
int  TrackTicket[TRACK_CAP];
int  TrackState [TRACK_CAP];
int  TrackCount = 0;

//================================================================
// INIT / UTILITY
//================================================================
void InitPipMath()
{
   int digits=(int)MarketInfo(Symbol(),MODE_DIGITS);
   if(digits==3||digits==5){ PipPoint=10*Point; PipMultiplier=10.0; }
   else                    { PipPoint=Point;    PipMultiplier=1.0;  }
}
bool IsNewBar(){ datetime t=iTime(Symbol(),Period(),0); if(t!=LastBarTime){ LastBarTime=t; return(true);} return(false); }
bool IsNewDay(){ if(DailyAnchorTime==0) return(true); return(TimeDay(TimeCurrent())!=TimeDay(DailyAnchorTime)||TimeMonth(TimeCurrent())!=TimeMonth(DailyAnchorTime)); }
void ResetDailyAnchor(){ DailyAnchorTime=TimeCurrent(); DailyAnchorEquity=AccountEquity(); DailyLocked=false; }
double SpreadPips(){ return((Ask-Bid)/PipPoint); }
int CountMyTrades(){ int n=0; for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(OrderMagicNumber()==InpMagicNumber&&OrderSymbol()==Symbol()) n++; } return(n); }
bool InSession(){ if(!InpUseSessionFilter) return(true); int h=Hour(),dow=DayOfWeek(); if(InpSkipFriday&&dow==5) return(false); if(dow==0||dow==6) return(false); if(InpSessionStartHour<=InpSessionEndHour) return(h>=InpSessionStartHour&&h<InpSessionEndHour); return(h>=InpSessionStartHour||h<InpSessionEndHour); }
double NormalizeLots(double lots){ double mn=MarketInfo(Symbol(),MODE_MINLOT),mx=MarketInfo(Symbol(),MODE_MAXLOT),st=MarketInfo(Symbol(),MODE_LOTSTEP); if(st<=0) st=0.01; lots=MathFloor(lots/st)*st; if(lots<mn) lots=mn; if(lots>mx) lots=mx; return(NormalizeDouble(lots,2)); }
double ApplyLotCap(double l){ if(!InpEnforceLotCap) return(l); double pv=MarketInfo(Symbol(),MODE_TICKVALUE)*PipMultiplier; if(pv<=0) return(l); double maxD=AccountEquity()*InpMaxLotsPerPipPctEquity/100.0; double maxL=maxD/pv; if(l>maxL) return(NormalizeLots(maxL)); return(l); }
double CalcLots(double slDist){ if(InpFixedLots>0.0) return(ApplyLotCap(NormalizeLots(InpFixedLots))); if(slDist<=0.0) return(NormalizeLots(0.01)); double rm=(PostCooldownTradesLeft>0)?InpPostCooldownRisk:1.0; double rMoney=AccountEquity()*(InpRiskPct*rm)/100.0; double tv=MarketInfo(Symbol(),MODE_TICKVALUE),ts=MarketInfo(Symbol(),MODE_TICKSIZE); if(ts==0) ts=Point; double vpl=(slDist/ts)*tv; if(vpl<=0) return(NormalizeLots(0.01)); return(ApplyLotCap(NormalizeLots(rMoney/vpl))); }

//================================================================
// INDICATOR SHORTHAND
//================================================================
double DmaHigh(int s){ return(iMA(NULL,0,InpDmaLength,0,MODE_SMA,PRICE_HIGH,s)); }
double DmaLow (int s){ return(iMA(NULL,0,InpDmaLength,0,MODE_SMA,PRICE_LOW, s)); }
double StochK (int s){ return(iStochastic(NULL,0,InpStochK,InpStochD,InpStochSmooth,MODE_SMA,0,MODE_MAIN,s)); }
double Rsi    (int s){ return(iRSI(NULL,0,InpRsiLength,PRICE_CLOSE,s)); }
double Atr    (int s){ return(iATR(NULL,0,InpAtrPeriod,s)); }
double Adx    (int s){ return(iADX(NULL,0,InpABCAdxPeriod,PRICE_CLOSE,MODE_MAIN,s)); }
double HtfEma (int s){ return(iMA(NULL,InpHTFTimeframe,InpHTFEmaLength,0,MODE_EMA,PRICE_CLOSE,s)); }
double HtfClose(int s){ return(iClose(NULL,InpHTFTimeframe,s)); }
double RoboFast(int s){ return(iMA(NULL,0,InpRoboFastLen,0,MODE_EMA,PRICE_CLOSE,s)); }
double RoboSlow(int s){ return(iMA(NULL,0,InpRoboSlowLen,0,MODE_EMA,PRICE_CLOSE,s)); }
double MTFEmaFast(int tf,int s){ return(iMA(NULL,tf,InpMTFEmaFast,0,MODE_EMA,PRICE_CLOSE,s)); }
double MTFEmaSlow(int tf,int s){ return(iMA(NULL,tf,InpMTFEmaSlow,0,MODE_EMA,PRICE_CLOSE,s)); }

//================================================================
// ABC MARKET CYCLE DETECTOR (Hard Gate 0)
// FER = |net move over N| / sum(|bar-to-bar move|)  (Kaufman efficiency)
//================================================================
double FER(int tf,int shift)
{
   double net = MathAbs(iClose(NULL,tf,shift) - iClose(NULL,tf,shift+InpFERPeriod));
   double path = 0;
   for(int j=0;j<InpFERPeriod;j++) path += MathAbs(iClose(NULL,tf,shift+j) - iClose(NULL,tf,shift+j+1));
   return(path>0 ? net/path : 0.0);
}

double AdxTF(int tf,int shift){ return(iADX(NULL,tf,InpABCAdxPeriod,PRICE_CLOSE,MODE_MAIN,shift)); }

// 0=Stage A, 1=Stage B, 2=Stage C
int DetectABCStage(int tf,int shift)
{
   double adx = AdxTF(tf,shift);
   double fer = FER(tf,shift);
   if(adx < InpStageA_AdxMax && fer < InpStageA_FERMax)  return(0); // A consolidation
   if(adx >= InpStageB_AdxMin && fer >= InpStageB_FERMin) return(1); // B expansion
   if(adx > InpStageA_AdxMax && adx < 25.0 && fer < InpStageC_FERMax) return(2); // C contraction
   return(adx >= 25.0 ? 1 : 0);
}

bool AdxRising(int tf,int shift){ return(AdxTF(tf,shift) > AdxTF(tf,shift+InpAdxRisingBars)); }

// Returns true only if it is SAFE to open a new entry (Stage B, B1/B2)
bool ABCAllowsEntry()
{
   if(!InpUseABCGate) return(true);
   int stage = DetectABCStage(0,1);
   if(stage != 1) return(false);                 // must be expansion
   if(!AdxRising(0,1)) return(false);             // block B3 exhaustion (ADX not rising)
   if(InpUseHTFStage && DetectABCStage(PERIOD_H4,1)==0) return(false); // H4 must not be dead range
   return(true);
}
bool ABCInContraction(){ return(InpUseABCGate && DetectABCStage(0,1)==2); }

string StageLabel(int s){ if(s==0) return("A_CONSOLIDATION"); if(s==1) return("B_EXPANSION"); if(s==2) return("C_CONTRACTION"); return("UNKNOWN"); }

//================================================================
// VOTERS (v1.4 + v1.8)
//================================================================
bool BullDivergence(){ if(!InpUseAEXD) return(true); int lb=InpDivLookback; double cur=iLow(NULL,0,iLowest(NULL,0,MODE_LOW,lb,1)); double prev=iLow(NULL,0,iLowest(NULL,0,MODE_LOW,lb,1+lb)); return(cur<prev && Rsi(1)>Rsi(1+lb)); }
bool BearDivergence(){ if(!InpUseAEXD) return(true); int lb=InpDivLookback; double cur=iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,lb,1)); double prev=iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,lb,1+lb)); return(cur>prev && Rsi(1)<Rsi(1+lb)); }
bool IsBullEngulf(){ double o0=iOpen(NULL,0,1),c0=iClose(NULL,0,1),o1=iOpen(NULL,0,2),c1=iClose(NULL,0,2); return(c0>o0&&c0>MathMax(o1,c1)&&o0<MathMin(o1,c1)); }
bool IsBearEngulf(){ double o0=iOpen(NULL,0,1),c0=iClose(NULL,0,1),o1=iOpen(NULL,0,2),c1=iClose(NULL,0,2); return(c0<o0&&c0<MathMin(o1,c1)&&o0>MathMax(o1,c1)); }
bool IsBullPin(){ double o=iOpen(NULL,0,1),c=iClose(NULL,0,1),l=iLow(NULL,0,1); double b=MathAbs(c-o); if(b<=0) return(false); return((MathMin(o,c)-l)>=InpPinTailFactor*b&&c>o); }
bool IsBearPin(){ double o=iOpen(NULL,0,1),c=iClose(NULL,0,1),h=iHigh(NULL,0,1); double b=MathAbs(c-o); if(b<=0) return(false); return((h-MathMax(o,c))>=InpPinTailFactor*b&&c<o); }
bool BullCandle(){ return(!InpUseCandles||IsBullEngulf()||IsBullPin()); }
bool BearCandle(){ return(!InpUseCandles||IsBearEngulf()||IsBearPin()); }
bool HtfTrendUpPersistent(){ if(!InpUseHTFTrend) return(true); for(int i=0;i<InpHTFPersistBars;i++) if(HtfClose(i)<=HtfEma(i)) return(false); return(true); }
bool HtfTrendDnPersistent(){ if(!InpUseHTFTrend) return(true); for(int i=0;i<InpHTFPersistBars;i++) if(HtfClose(i)>=HtfEma(i)) return(false); return(true); }
bool HtfSlopeUp(){ if(!InpUseHTFTrend||!InpRequireHTFSlope) return(true); return(HtfEma(0)>HtfEma(InpHTFSlopeBars)); }
bool HtfSlopeDn(){ if(!InpUseHTFTrend||!InpRequireHTFSlope) return(true); return(HtfEma(0)<HtfEma(InpHTFSlopeBars)); }
bool HTFGateAllowBuy(){ if(!InpRequireHTFAgree) return(true); bool p=HtfTrendUpPersistent(),s=HtfSlopeUp(); if(InpHTFRequireBoth) return(p&&s); return(p||s); }
bool HTFGateAllowSell(){ if(!InpRequireHTFAgree) return(true); bool p=HtfTrendDnPersistent(),s=HtfSlopeDn(); if(InpHTFRequireBoth) return(p&&s); return(p||s); }
bool VolumeAboveAvg(){ if(!InpUseVolumeFilter) return(true); double sum=0; for(int i=2;i<2+InpVolumeAvgPeriod;i++) sum+=(double)iVolume(NULL,0,i); double avg=sum/InpVolumeAvgPeriod; if(avg<=0) return(true); return((double)iVolume(NULL,0,1)>=avg*InpVolumeMinRatio); }
bool MacdBullCross(){ if(!InpUseMACDVoter) return(false); double mc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,1),mp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,2),sc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,1),sp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,2),mac=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,1),map=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,2); return(mc<0&&mc>sc&&mp<sp&&mac>map); }
bool MacdBearCross(){ if(!InpUseMACDVoter) return(false); double mc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,1),mp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,2),sc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,1),sp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,2),mac=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,1),map=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,2); return(mc>0&&mc<sc&&mp>sp&&mac<map); }
int DayRangePattern(){ if(!InpUseDayRangeVoter) return(0); double pH=iHigh(NULL,PERIOD_D1,1),pL=iLow(NULL,PERIOD_D1,1),pO=iOpen(NULL,PERIOD_D1,1),pC=iClose(NULL,PERIOD_D1,1); double rng=pH-pL; if(rng<Point*10) return(0); double z=rng*(InpDayRangeZonePct/100.0); if(((pH-pC)<=z)&&((pO-pL)<=z)) return(1); if(((pH-pO)<=z)&&((pC-pL)<=z)) return(-1); return(0); }
bool StochOkBuy(){ double k=StochK(1); int m=InpStochRegimeMode; if(m==2) m=(Adx(1)>=InpStochAdxThresh)?1:0; if(m==0) return(k>=InpStochBuyLo&&k<=InpStochBuyHi); return(k>=InpStochSellLo&&k<=InpStochSellHi); }
bool StochOkSell(){ double k=StochK(1); int m=InpStochRegimeMode; if(m==2) m=(Adx(1)>=InpStochAdxThresh)?1:0; if(m==0) return(k>=InpStochSellLo&&k<=InpStochSellHi); return(k>=InpStochBuyLo&&k<=InpStochBuyHi); }
bool MTFVoterBull(){ if(!InpUseMTFVoter) return(false); int a=0; if(MTFEmaFast(PERIOD_W1,0)>MTFEmaSlow(PERIOD_W1,0)) a++; if(MTFEmaFast(PERIOD_D1,0)>MTFEmaSlow(PERIOD_D1,0)) a++; if(MTFEmaFast(PERIOD_H4,0)>MTFEmaSlow(PERIOD_H4,0)) a++; if(MTFEmaFast(PERIOD_H1,0)>MTFEmaSlow(PERIOD_H1,0)) a++; return(a>=InpMTFMinAligned); }
bool MTFVoterBear(){ if(!InpUseMTFVoter) return(false); int a=0; if(MTFEmaFast(PERIOD_W1,0)<MTFEmaSlow(PERIOD_W1,0)) a++; if(MTFEmaFast(PERIOD_D1,0)<MTFEmaSlow(PERIOD_D1,0)) a++; if(MTFEmaFast(PERIOD_H4,0)<MTFEmaSlow(PERIOD_H4,0)) a++; if(MTFEmaFast(PERIOD_H1,0)<MTFEmaSlow(PERIOD_H1,0)) a++; return(a>=InpMTFMinAligned); }
bool TTFVoterBull(){ if(!InpUseTTFVoter) return(false); if(Bars<InpTTFBars*2+2) return(false); double bp=iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1))-iLow(NULL,0,iLowest(NULL,0,MODE_LOW,InpTTFBars,1+InpTTFBars)); double sp=iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1+InpTTFBars))-iLow(NULL,0,iLowest(NULL,0,MODE_LOW,InpTTFBars,1)); double d=0.5*(bp+sp); if(d<=0) return(false); return(((bp-sp)/d*100.0)>0); }
bool TTFVoterBear(){ if(!InpUseTTFVoter) return(false); if(Bars<InpTTFBars*2+2) return(false); double bp=iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1))-iLow(NULL,0,iLowest(NULL,0,MODE_LOW,InpTTFBars,1+InpTTFBars)); double sp=iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1+InpTTFBars))-iLow(NULL,0,iLowest(NULL,0,MODE_LOW,InpTTFBars,1)); double d=0.5*(bp+sp); if(d<=0) return(false); return(((bp-sp)/d*100.0)<0); }
bool VegasH4Bull(){ if(!InpUseVegasH4) return(false); double a=iMA(NULL,PERIOD_H4,InpVegasFast,0,MODE_SMA,PRICE_CLOSE,0),b=iMA(NULL,PERIOD_H4,InpVegasSlow,0,MODE_SMA,PRICE_CLOSE,0),c=iClose(NULL,PERIOD_H4,0); return(c>b&&a>b); }
bool VegasH4Bear(){ if(!InpUseVegasH4) return(false); double a=iMA(NULL,PERIOD_H4,InpVegasFast,0,MODE_SMA,PRICE_CLOSE,0),b=iMA(NULL,PERIOD_H4,InpVegasSlow,0,MODE_SMA,PRICE_CLOSE,0),c=iClose(NULL,PERIOD_H4,0); return(c<b&&a<b); }

int BuyConfluenceScore()
{
   int s=0;
   if(iClose(NULL,0,1)<=DmaLow(1)) s++;
   if(StochOkBuy()) s++;
   if(!InpRequireDmaSlope||(DmaHigh(1)>DmaHigh(4))) s++;
   if(BullDivergence()) s++;
   if(BullCandle()) s++;
   if(Atr(1)>=InpAtrMinPrice) s++;
   if(HtfTrendUpPersistent()) s++;
   if(!InpUseRobotrick||(RoboFast(1)>RoboSlow(1)+Atr(1)*InpRoboChanAtrMult)) s++;
   if(VolumeAboveAvg()) s++;
   if(Rsi(1)>Rsi(2)) s++;
   if(MacdBullCross()) s++;
   if(DayRangePattern()==1) s++;
   if(MTFVoterBull()) s++;
   if(TTFVoterBull()) s++;
   if(VegasH4Bull()) s++;
   return(s);
}
int SellConfluenceScore()
{
   int s=0;
   if(iClose(NULL,0,1)>=DmaHigh(1)) s++;
   if(StochOkSell()) s++;
   if(!InpRequireDmaSlope||(DmaLow(1)<DmaLow(4))) s++;
   if(BearDivergence()) s++;
   if(BearCandle()) s++;
   if(Atr(1)>=InpAtrMinPrice) s++;
   if(HtfTrendDnPersistent()) s++;
   if(!InpUseRobotrick||(RoboFast(1)<RoboSlow(1)-Atr(1)*InpRoboChanAtrMult)) s++;
   if(VolumeAboveAvg()) s++;
   if(Rsi(1)<Rsi(2)) s++;
   if(MacdBearCross()) s++;
   if(DayRangePattern()==-1) s++;
   if(MTFVoterBear()) s++;
   if(TTFVoterBear()) s++;
   if(VegasH4Bear()) s++;
   return(s);
}

//================================================================
// SAFE ORDER MODIFY  (v1.4)
//================================================================
bool SafeOrderModify(int ticket,double price,double sl,double tp,datetime exp,color c=CLR_NONE)
{
   if(!InpUseSafeModify) return(OrderModify(ticket,price,NormalizeDouble(sl,Digits),NormalizeDouble(tp,Digits),exp,c));
   int digits=(int)MarketInfo(Symbol(),MODE_DIGITS);
   double point=MarketInfo(Symbol(),MODE_POINT),stop=MarketInfo(Symbol(),MODE_STOPLEVEL)*point,spr=MarketInfo(Symbol(),MODE_SPREAD)*point,minD=MathMax(stop,spr)+point;
   price=NormalizeDouble(price,digits); sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)) return(false);
   double cur=(OrderType()==OP_BUY)?MarketInfo(Symbol(),MODE_BID):MarketInfo(Symbol(),MODE_ASK);
   if(sl>0){ if(OrderType()==OP_BUY&&(cur-sl)<minD) sl=NormalizeDouble(cur-minD,digits); if(OrderType()==OP_SELL&&(sl-cur)<minD) sl=NormalizeDouble(cur+minD,digits); }
   if(tp>0){ if(OrderType()==OP_BUY&&(tp-cur)<minD) tp=NormalizeDouble(cur+minD,digits); if(OrderType()==OP_SELL&&(cur-tp)<minD) tp=NormalizeDouble(cur-minD,digits); }
   if(MathAbs(sl-OrderStopLoss())<point&&MathAbs(tp-OrderTakeProfit())<point) return(true);
   return(OrderModify(ticket,price,sl,tp,exp,c));
}

//================================================================
// TRACKING
//================================================================
int FindTrackingIndex(int t){ for(int i=0;i<TrackCount;i++) if(TrackTicket[i]==t) return(i); return(-1); }
int EnsureTracking(int t){ int i=FindTrackingIndex(t); if(i>=0) return(i); if(TrackCount>=TRACK_CAP){ for(int j=0;j<TrackCount-1;j++){ TrackTicket[j]=TrackTicket[j+1]; TrackState[j]=TrackState[j+1]; } TrackCount--; } TrackTicket[TrackCount]=t; TrackState[TrackCount]=0; TrackCount++; return(TrackCount-1); }
void SetTrackState(int t,int s){ int i=EnsureTracking(t); if(i>=0) TrackState[i]=s; }
int GetTrackState(int t){ int i=FindTrackingIndex(t); return(i>=0?TrackState[i]:0); }
void CleanupTracking(){ for(int i=TrackCount-1;i>=0;i--){ bool open=false; if(OrderSelect(TrackTicket[i],SELECT_BY_TICKET,MODE_TRADES)) if(OrderCloseTime()==0) open=true; if(!open){ for(int j=i;j<TrackCount-1;j++){ TrackTicket[j]=TrackTicket[j+1]; TrackState[j]=TrackState[j+1]; } TrackCount--; } } }
int FindRemainderTicket(datetime ot,double op,int oty){ for(int i=OrdersTotal()-1;i>=0;i--){ if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue; if(OrderMagicNumber()!=InpMagicNumber||OrderSymbol()!=Symbol()) continue; if(OrderType()!=oty||OrderOpenTime()!=ot) continue; if(MathAbs(OrderOpenPrice()-op)>MarketInfo(Symbol(),MODE_POINT)*2) continue; return(OrderTicket()); } return(-1); }

//================================================================
// SL/TP COMPUTE (v1.4 DMA + ATR guard, R:R)
//================================================================
void ComputeBuySLTP(double entry,double &sl,double &tp){ double atr=Atr(1); sl=DmaLow(1); double d=entry-sl; if(d<InpAtrMinPrice||d<=0) sl=entry-atr*InpAdaptiveSlAtrMult; tp=entry+(entry-sl)*InpTPRRMultiplier; }
void ComputeSellSLTP(double entry,double &sl,double &tp){ double atr=Atr(1); sl=DmaHigh(1); double d=sl-entry; if(d<InpAtrMinPrice||d<=0) sl=entry+atr*InpAdaptiveSlAtrMult; tp=entry-(sl-entry)*InpTPRRMultiplier; }

void TryOpenBuy()
{
   double entry=Ask,sl,tp; ComputeBuySLTP(entry,sl,tp);
   double slDist=entry-sl; if(slDist<=0){ Print("v3 BUY SL invalid, skip"); return; }
   double lots=CalcLots(slDist);
   double minDist=(int)MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(entry-sl<minDist) sl=entry-minDist; if(tp-entry<minDist) tp=entry+minDist;
   int t=OrderSend(Symbol(),OP_BUY,lots,entry,InpSlippage,NormalizeDouble(sl,Digits),NormalizeDouble(tp,Digits),"NCI v3 BUY",InpMagicNumber,0,clrLime);
   if(t<0) Print("v3 BUY failed err=",GetLastError());
   else { Print("v3 BUY #",t," lots=",DoubleToStr(lots,2)," SL=",DoubleToStr(sl,Digits)," TP=",DoubleToStr(tp,Digits)); if(PostCooldownTradesLeft>0) PostCooldownTradesLeft--; EnsureTracking(t); }
}
void TryOpenSell()
{
   double entry=Bid,sl,tp; ComputeSellSLTP(entry,sl,tp);
   double slDist=sl-entry; if(slDist<=0){ Print("v3 SELL SL invalid, skip"); return; }
   double lots=CalcLots(slDist);
   double minDist=(int)MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(sl-entry<minDist) sl=entry+minDist; if(entry-tp<minDist) tp=entry-minDist;
   int t=OrderSend(Symbol(),OP_SELL,lots,entry,InpSlippage,NormalizeDouble(sl,Digits),NormalizeDouble(tp,Digits),"NCI v3 SELL",InpMagicNumber,0,clrRed);
   if(t<0) Print("v3 SELL failed err=",GetLastError());
   else { Print("v3 SELL #",t," lots=",DoubleToStr(lots,2)," SL=",DoubleToStr(sl,Digits)," TP=",DoubleToStr(tp,Digits)); if(PostCooldownTradesLeft>0) PostCooldownTradesLeft--; EnsureTracking(t); }
}

//================================================================
// PARTIAL CLOSE + BE LOCK (v1.4)
//================================================================
void ManagePartialClose()
{
   if(!InpUsePartialClose) return;
   double atr=Atr(1); if(atr<=0) return;
   double tp1=atr*InpTP1AtrMult, preTrig=tp1*InpPreBETriggerFrac;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagicNumber||OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL) continue;
      int ticket=OrderTicket(); bool isBuy=(OrderType()==OP_BUY);
      double entry=OrderOpenPrice(), cur=isBuy?Bid:Ask;
      double prof=isBuy?(cur-entry):(entry-cur);
      double oSL=OrderStopLoss(), oSLd=isBuy?(entry-oSL):(oSL-entry);
      int state=GetTrackState(ticket);
      if(InpUsePreBELock&&state<1&&prof>=preTrig&&prof<tp1)
      {
         double pSL=isBuy?(entry-oSLd*InpPreBESLFraction):(entry+oSLd*InpPreBESLFraction);
         bool imp=(isBuy&&pSL>oSL)||(!isBuy&&pSL<oSL);
         if(imp&&SafeOrderModify(ticket,entry,pSL,OrderTakeProfit(),0,clrOrange)){ SetTrackState(ticket,1); Print("v3 PRE-BE #",ticket); }
      }
      if(prof>=tp1&&state<2)
      {
         double cl=OrderLots(),st=MarketInfo(Symbol(),MODE_LOTSTEP),mn=MarketInfo(Symbol(),MODE_MINLOT); if(st<=0) st=0.01;
         double clo=MathFloor(cl*(InpPartialPercent/100.0)/st)*st, rem=NormalizeDouble(cl-clo,2);
         if(clo<mn||rem<mn){ SetTrackState(ticket,2); continue; }
         datetime ot=OrderOpenTime(); double op=entry,otp=OrderTakeProfit(); int oty=OrderType(); double cp=isBuy?Bid:Ask;
         if(OrderClose(ticket,clo,cp,InpSlippage,clrYellow))
         {
            Print("v3 PARTIAL ",DoubleToStr(clo,2),"/",DoubleToStr(cl,2));
            int rt=FindRemainderTicket(ot,op,oty);
            if(rt>0){ double be=isBuy?(op+InpBEPlusPips*PipPoint):(op-InpBEPlusPips*PipPoint); if(SafeOrderModify(rt,op,be,otp,0,clrAqua)) Print("v3 BE LOCK #",rt); SetTrackState(rt,2); }
            return;
         }
      }
   }
}

//================================================================
// CHANDELIER TRAIL — Stage-aware (v1.8 + ABC)
// Stage B: loose (3.0x). Stage C: tight (2.2x) to catch the peak.
//================================================================
void ManageChandelier()
{
   if(!InpUseChandelier) return;
   double atr=Atr(0); if(atr<=0) return;
   double mult = ABCInContraction() ? InpChanMultStageC : InpChanMultStageB;
   double hi = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpChanRange,1));
   double lo = iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpChanRange,1));
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagicNumber||OrderSymbol()!=Symbol()) continue;
      double op=OrderOpenPrice(),cSL=OrderStopLoss(),cTP=OrderTakeProfit();
      if(OrderType()==OP_BUY)
      {
         if((Bid-op)/PipPoint < InpTrailTriggerPips) continue;
         double nSL=hi-atr*mult;
         if(nSL>op && (cSL==0||nSL>cSL+Point)) SafeOrderModify(OrderTicket(),op,nSL,cTP,0,clrYellow);
      }
      else if(OrderType()==OP_SELL)
      {
         if((op-Ask)/PipPoint < InpTrailTriggerPips) continue;
         double nSL=lo+atr*mult;
         if(nSL<op && (cSL==0||nSL<cSL-Point)) SafeOrderModify(OrderTicket(),op,nSL,cTP,0,clrYellow);
      }
   }
}

//================================================================
// v3.1 SECURE TRAIL + PYRAMID
// At +$InpSecureProfitUSD floating (spread<=gate): arm a fixed-pip
// trailing stop. SL only moves favorably. Once a position is secured
// (risk pulled inside the trail) the entry engine may stack a new one.
//================================================================
void ManageSecureTrail()
{
   if(!InpUseSecureTrail) return;
   if(SpreadPips()>InpMaxSpreadPips) return;          // only manage when spread tight (.03 gate)
   double trail=InpSecureTrailPips*PipPoint;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagicNumber||OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL) continue;
      double profitUSD=OrderProfit()+OrderSwap()+OrderCommission();
      if(profitUSD<InpSecureProfitUSD) continue;       // not armed until +$ profit
      double op=OrderOpenPrice(),cSL=OrderStopLoss(),cTP=OrderTakeProfit();
      if(OrderType()==OP_BUY)
      {
         double nSL=Bid-trail;
         if(cSL==0||nSL>cSL+Point) SafeOrderModify(OrderTicket(),op,nSL,cTP,0,clrAqua);
      }
      else
      {
         double nSL=Ask+trail;
         if(cSL==0||nSL<cSL-Point) SafeOrderModify(OrderTicket(),op,nSL,cTP,0,clrAqua);
      }
   }
}

// true only if EVERY open position has risk pulled inside the trail (all secured)
bool AllMyPositionsSecured()
{
   int cnt=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagicNumber||OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL) continue;
      cnt++;
      double op=OrderOpenPrice(),sl=OrderStopLoss();
      if(sl<=0) return(false);
      double riskPips=(OrderType()==OP_BUY)?(op-sl)/PipPoint:(sl-op)/PipPoint;
      if(riskPips>InpSecureTrailPips+0.5) return(false);  // this one not secured yet
   }
   return(cnt>0);
}

//================================================================
// EXPECTANCY + STRIKE COOLDOWN + DAILY DD (v1.4)
//================================================================
void UpdateExpectancyAndStrikes()
{
   int total=OrdersHistoryTotal(); if(total<=LastTotalHistory) return;
   for(int i=LastTotalHistory;i<total;i++)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagicNumber||OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL) continue;
      double pnl=OrderProfit()+OrderSwap()+OrderCommission(); TotalClosed++;
      if(pnl>0){ TotalWins++; ConsecutiveLosses=0; }
      else { TotalLosses++; ConsecutiveLosses++; if(InpUseStrikeCooldown&&ConsecutiveLosses>=InpStrikeLimit){ CooldownUntilTime=TimeCurrent()+InpCooldownBars*Period()*60; PostCooldownTradesLeft=3; Print("*** v3 STRIKE COOLDOWN *** ",ConsecutiveLosses," losses"); ConsecutiveLosses=0; } }
      double wr=TotalClosed>0?(100.0*TotalWins/TotalClosed):0.0;
      Print("[NCI WR v3] pnl=",DoubleToStr(pnl,2)," W=",TotalWins," L=",TotalLosses," WR=",DoubleToStr(wr,1),"%");
   }
   LastTotalHistory=total;
}
void CheckDailyDD()
{
   if(IsNewDay()) ResetDailyAnchor();
   if(!InpUseDailyDDLock||DailyAnchorEquity<=0) return;
   double dd=100.0*(DailyAnchorEquity-AccountEquity())/DailyAnchorEquity;
   if(dd>=InpMaxDailyDDPct&&!DailyLocked){ DailyLocked=true; Print("*** v3 DAILY DD LOCK *** ",DoubleToStr(dd,2),"%"); }
}

//================================================================
// DASHBOARD JSON
//================================================================
void WriteDashboard(int buy,int sell)
{
   if(!InpWriteDashboard) return;
   int stage=DetectABCStage(0,1); int stageH4=DetectABCStage(PERIOD_H4,1);
   double bal=AccountBalance(),eq=AccountEquity(),mg=AccountMargin(),dd=(bal>0)?(eq-bal)/bal:0.0;
   string j="{";
   j+="\"balance\": "+DoubleToStr(bal,2)+",";
   j+="\"equity\": "+DoubleToStr(eq,2)+",";
   j+="\"margin\": "+DoubleToStr(mg,2)+",";
   j+="\"drawdown\": "+DoubleToStr(dd,4)+",";
   j+="\"trades_daily\": "+IntegerToString(CountMyTrades())+",";
   j+="\"consec_losses\": "+IntegerToString(ConsecutiveLosses)+",";
   j+="\"phase\": \""+StageLabel(stage)+"\",";
   j+="\"abc_stage\": "+IntegerToString(stage)+",";
   j+="\"abc_stage_h4\": "+IntegerToString(stageH4)+",";
   j+="\"adx\": "+DoubleToStr(Adx(1),1)+",";
   j+="\"fer\": "+DoubleToStr(FER(0,1),3)+",";
   j+="\"buy_score\": "+IntegerToString(buy)+",";
   j+="\"sell_score\": "+IntegerToString(sell)+",";
   j+="\"atr\": "+DoubleToStr(Atr(1),6)+",";
   j+="\"timestamp\": \""+TimeToStr(TimeCurrent(),TIME_DATE)+" "+TimeToStr(TimeCurrent(),TIME_SECONDS)+"\"";
   j+="}";
   int h=FileOpen("NCI_LiveData.json",FILE_WRITE|FILE_TXT,0); if(h!=INVALID_HANDLE){ FileWriteString(h,j); FileClose(h); }

   bool isBuy=buy>=sell; int sc=isBuy?buy:sell; string act=isBuy?"BUY":"SELL";
   double entry=isBuy?Ask:Bid,sl,tp; if(isBuy) ComputeBuySLTP(entry,sl,tp); else ComputeSellSLTP(entry,sl,tp);
   double slP=MathAbs(entry-sl)/PipPoint, tpP=MathAbs(tp-entry)/PipPoint, rr=(slP>0)?tpP/slP:0.0;
   bool qual=(sc>=InpMinConfluence)&&ABCAllowsEntry();
   string s="{";
   s+="\"symbol\": \""+Symbol()+"\",";
   s+="\"action\": \""+act+"\",";
   s+="\"mode\": \""+StageLabel(stage)+"\",";
   s+="\"godmode_score\": "+DoubleToStr(sc/15.0*10.0,2)+",";
   s+="\"confluence\": "+IntegerToString(sc)+",";
   s+="\"confluence_max\": 15,";
   s+="\"abc_stage\": \""+StageLabel(stage)+"\",";
   s+="\"sl_pips\": "+DoubleToStr(slP,0)+",";
   s+="\"tp_pips\": "+DoubleToStr(tpP,0)+",";
   s+="\"risk_reward\": "+DoubleToStr(rr,2)+",";
   s+="\"qualifies\": "+(qual?"true":"false")+",";
   s+="\"timestamp\": \""+TimeToStr(TimeCurrent(),TIME_DATE)+" "+TimeToStr(TimeCurrent(),TIME_SECONDS)+"\",";
   s+="\"approved\": false";
   s+="}";
   int h2=FileOpen("signal_proposal.json",FILE_WRITE|FILE_TXT,0); if(h2!=INVALID_HANDLE){ FileWriteString(h2,s); FileClose(h2); }
}

//================================================================
// LIFECYCLE
//================================================================
int OnInit()
{
   InitPipMath(); ResetDailyAnchor(); LastTotalHistory=OrdersHistoryTotal(); TrackCount=0;
   Print("===== NCI GodMode v3 — AUTONOMOUS EA =====");
   Print("Account: ",AccountNumber()," Bal: ",AccountBalance()," ",AccountCompany());
   Print("Symbol: ",Symbol()," TF: ",Period()," | TradingEnabled=",InpTradingEnabled);
   Print("ABC Gate=",InpUseABCGate," | MinConfluence=",InpMinConfluence,"/15 | Risk=",InpRiskPct,"% | R:R=",InpTPRRMultiplier,"x");
   Print("Chandelier StageB=",InpChanMultStageB,"x StageC=",InpChanMultStageC,"x | DailyDD lock=",InpMaxDailyDDPct,"%");
   Print("v3.1 SECURE: trail=",InpUseSecureTrail," arm@$",InpSecureProfitUSD," dist=",InpSecureTrailPips,"p | STACK=",InpUseStacking," max=",InpStackMaxTrades," | SpreadGate=",InpMaxSpreadPips,"p");
   if(!InpTradingEnabled) Print(">>> REPORT-ONLY MODE: no orders will be placed. <<<");
   WriteDashboard(BuyConfluenceScore(),SellConfluenceScore());
   Print("===== v3 READY =====");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){ double wr=TotalClosed>0?(100.0*TotalWins/TotalClosed):0.0; Print("=== v3 stopped. WR ",TotalWins,"/",TotalClosed,"=",DoubleToStr(wr,2),"% ==="); }

void OnTick()
{
   // Manage open positions every tick (these are the stop-loss rules running the trade)
   ManagePartialClose();
   ManageChandelier();
   ManageSecureTrail();
   UpdateExpectancyAndStrikes();
   CheckDailyDD();
   CleanupTracking();

   if(!IsNewBar()) return;

   int buy=BuyConfluenceScore(), sell=SellConfluenceScore();
   WriteDashboard(buy,sell);

   // ---- ENTRY DECISION (bar close) ----
   if(DailyLocked){ if(InpVerboseLog) Print("v3 skip: daily DD locked"); return; }
   if(TimeCurrent()<CooldownUntilTime){ if(InpVerboseLog) Print("v3 skip: cooldown"); return; }
   if(!InSession()) return;
   if(SpreadPips()>InpMaxSpreadPips){ if(InpVerboseLog) Print("v3 skip: spread ",DoubleToStr(SpreadPips(),1)); return; }
   int openN=CountMyTrades();
   int maxN=InpUseStacking?InpStackMaxTrades:InpMaxOpenTrades;
   if(openN>=maxN) return;
   if(openN>0 && !InpUseStacking) return;                     // stacking off -> single position
   if(openN>0 && InpUseStacking && !AllMyPositionsSecured())  // only pyramid onto secured trades
   { if(InpVerboseLog) Print("v3 skip: prior position not secured yet"); return; }

   // HARD GATE 0 — ABC market cycle
   if(!ABCAllowsEntry())
   {
      if(InpVerboseLog) Print("v3 ABC BLOCK: stage=",StageLabel(DetectABCStage(0,1)),
                              " adx=",DoubleToStr(Adx(1),1)," fer=",DoubleToStr(FER(0,1),3),
                              " (only Stage B / ADX-rising entries allowed)");
      return;
   }

   if(InpLogConfluence) Print("v3 [Stage B] BUY=",buy,"/15 SELL=",sell,"/15");

   if(buy>=InpMinConfluence && buy>sell)
   {
      if(!HTFGateAllowBuy()){ if(InpVerboseLog) Print("v3 skip BUY: HTF gate"); return; }
      if(InpTradingEnabled) TryOpenBuy(); else Print("v3 [REPORT-ONLY] would BUY score=",buy);
      return;
   }
   if(sell>=InpMinConfluence && sell>buy)
   {
      if(!HTFGateAllowSell()){ if(InpVerboseLog) Print("v3 skip SELL: HTF gate"); return; }
      if(InpTradingEnabled) TryOpenSell(); else Print("v3 [REPORT-ONLY] would SELL score=",sell);
      return;
   }
}
//+------------------------------------------------------------------+
