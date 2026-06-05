//+------------------------------------------------------------------+
//|                                            NCI_Hybrid_v2.1.mq4    |
//|             NERDCOMMAND Core Intelligence (NCI) — Signal Reporter |
//|                                                                  |
//|  PURPOSE:                                                        |
//|    READ-ONLY dashboard feeder. Computes the REAL 15-voter        |
//|    confluence score (ported from the proven v1.4 + v1.8 trading  |
//|    logic) and writes it to the GodMode dashboard JSON files.     |
//|    Places ZERO trades — safe to run on a live account.           |
//|                                                                  |
//|  KNOWLEDGE CARRIED FORWARD:                                      |
//|    v1.4 — 12-voter confluence, DMA-break SL with ATR fallback    |
//|           guard, R:R 1.5x TP, HTF OR-gate.                       |
//|    v1.8 — +MTF stack (#13), +TTF (#14), +Vegas H4 (#15),         |
//|           ADR session-exhaustion filter, tuned thresholds.       |
//|                                                                  |
//|  OUTPUT (to MQL4\Files — bridge reads this folder):             |
//|    NCI_LiveData.json     — account state                        |
//|    signal_proposal.json  — real confluence signal (approved:false)|
//|                                                                  |
//|             (c) 2026 GangsterNerds LLC - NERDCOMMAND Trading     |
//+------------------------------------------------------------------+
#property copyright   "GangsterNerds LLC - NERDCOMMAND Trading"
#property version     "2.10"
#property description "NCI Hybrid v2.1 - Read-only 15-voter signal reporter for GodMode dashboard."
#property strict

//================================================================
// INPUTS  (defaults carried from v1.8 — the tuned, proven set)
//================================================================
//--- DMAHLBO
extern int    InpDmaLength         = 25;
extern bool   InpRequireDmaSlope   = false;     // v1.6: false — slope blocked valid entries

//--- Stochastic
extern int    InpStochK            = 25;
extern int    InpStochSmooth       = 3;
extern int    InpStochD            = 3;
extern int    InpStochBuyLo        = 30;
extern int    InpStochBuyHi        = 49;
extern int    InpStochSellLo       = 50;
extern int    InpStochSellHi       = 70;
extern int    InpStochRegimeMode   = 2;         // 0=Reversion 1=Momentum 2=Auto(ADX)
extern int    InpStochAdxPeriod    = 14;
extern int    InpStochAdxThresh    = 20;

//--- AEXD Divergence
extern bool   InpUseAEXD           = true;
extern int    InpDivLookback       = 5;
extern int    InpRsiLength         = 14;

//--- Candle patterns
extern bool   InpUseCandles        = true;
extern double InpPinTailFactor     = 2.5;

//--- ATR
extern int    InpAtrPeriod         = 14;
extern double InpAtrMinPrice       = 0.0003;    // v1.6 tuned

//--- HTF Trend (Voter #7 / gate)
extern bool   InpUseHTFTrend       = true;
extern int    InpHTFTimeframe      = PERIOD_H1;
extern int    InpHTFEmaLength      = 21;
extern int    InpHTFPersistBars    = 3;
extern bool   InpRequireHTFAgree   = true;
extern bool   InpRequireHTFSlope   = true;
extern int    InpHTFSlopeBars      = 3;
extern bool   InpHTFRequireBoth    = false;     // v1.4: OR logic

//--- Robotrick (Voter #8)
extern bool   InpUseRobotrick      = true;
extern int    InpRoboFastLen       = 10;
extern int    InpRoboSlowLen       = 34;
extern double InpRoboChanAtrMult   = 0.5;

//--- Volume (Voter #9)
extern bool   InpUseVolumeFilter   = true;
extern int    InpVolumeAvgPeriod   = 20;
extern double InpVolumeMinRatio    = 1.0;       // v1.6 tuned

//--- MACD (Voter #11)
extern bool   InpUseMACDVoter      = true;
extern int    InpMacdFast          = 12;
extern int    InpMacdSlow          = 26;
extern int    InpMacdSignal        = 9;

//--- Day Range (Voter #12)
extern bool   InpUseDayRangeVoter  = true;
extern double InpDayRangeZonePct   = 20.0;

//--- MTF Stack (Voter #13)
extern bool   InpUseMTFVoter       = true;
extern int    InpMTFEmaFast        = 20;
extern int    InpMTFEmaSlow        = 50;
extern int    InpMTFMinAligned     = 2;         // v1.6: 2/4 sufficient

//--- TTF (Voter #14)
extern bool   InpUseTTFVoter       = true;
extern int    InpTTFBars           = 8;
extern double InpTTFBullThresh     = 0.0;
extern double InpTTFBearThresh     = 0.0;

//--- Vegas H4 (Voter #15)
extern bool   InpUseVegasH4        = true;
extern int    InpVegasFast         = 8;
extern int    InpVegasSlow         = 55;

//--- ADR Exhaustion Filter
extern bool   InpUseADRFilter      = true;
extern int    InpADRPeriod         = 20;
extern double InpADRMaxPct         = 85.0;

//--- Confluence gate (report "qualifying" when >= this)
extern int    InpMinConfluence     = 6;         // v1.6 tuned (of 15)

//--- R:R for reported SL/TP (Mode 0 DMA logic, v1.4 fix)
extern double InpTPRRMultiplier    = 1.5;
extern double InpAdaptiveSlAtrMult = 1.2;

//--- Reporting cadence
extern int    InpReportEveryTicks  = 10;        // write account JSON every N ticks

//--- Logging
extern bool   InpVerboseLog        = true;

//================================================================
// GLOBALS
//================================================================
double   PipPoint;
double   PipMultiplier;
datetime LastBarTime = 0;
int      TickCounter = 0;

//================================================================
// INIT HELPERS
//================================================================
void InitPipMath()
{
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(digits == 3 || digits == 5) { PipPoint = 10*Point; PipMultiplier = 10.0; }
   else                            { PipPoint = Point;    PipMultiplier = 1.0;  }
}

bool IsNewBar()
{
   datetime t = iTime(Symbol(), Period(), 0);
   if(t != LastBarTime) { LastBarTime = t; return(true); }
   return(false);
}

double SpreadPips() { return((Ask-Bid)/PipPoint); }

//================================================================
// INDICATOR SHORTHAND  (identical to v1.8)
//================================================================
double DmaHigh (int s){ return(iMA(NULL,0,InpDmaLength,0,MODE_SMA,PRICE_HIGH,s)); }
double DmaLow  (int s){ return(iMA(NULL,0,InpDmaLength,0,MODE_SMA,PRICE_LOW, s)); }
double StochK  (int s){ return(iStochastic(NULL,0,InpStochK,InpStochD,InpStochSmooth,MODE_SMA,0,MODE_MAIN,s)); }
double Rsi     (int s){ return(iRSI(NULL,0,InpRsiLength,PRICE_CLOSE,s)); }
double Atr     (int s){ return(iATR(NULL,0,InpAtrPeriod,s)); }
double Adx     (int s){ return(iADX(NULL,0,InpStochAdxPeriod,PRICE_CLOSE,MODE_MAIN,s)); }
double HtfEma  (int s){ return(iMA(NULL,InpHTFTimeframe,InpHTFEmaLength,0,MODE_EMA,PRICE_CLOSE,s)); }
double HtfClose(int s){ return(iClose(NULL,InpHTFTimeframe,s)); }
double RoboFast(int s){ return(iMA(NULL,0,InpRoboFastLen,0,MODE_EMA,PRICE_CLOSE,s)); }
double RoboSlow(int s){ return(iMA(NULL,0,InpRoboSlowLen,0,MODE_EMA,PRICE_CLOSE,s)); }
double MTFEmaFast(int tf,int s){ return(iMA(NULL,tf,InpMTFEmaFast,0,MODE_EMA,PRICE_CLOSE,s)); }
double MTFEmaSlow(int tf,int s){ return(iMA(NULL,tf,InpMTFEmaSlow,0,MODE_EMA,PRICE_CLOSE,s)); }

//================================================================
// VOTERS  (ported verbatim from v1.4 + v1.8)
//================================================================
bool BullDivergence()
{
   if(!InpUseAEXD) return(true);
   int lb = InpDivLookback;
   double curLL  = iLow(NULL,0,iLowest(NULL,0,MODE_LOW,lb,1));
   double prevLL = iLow(NULL,0,iLowest(NULL,0,MODE_LOW,lb,1+lb));
   return(curLL < prevLL && Rsi(1) > Rsi(1+lb));
}
bool BearDivergence()
{
   if(!InpUseAEXD) return(true);
   int lb = InpDivLookback;
   double curHH  = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,lb,1));
   double prevHH = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,lb,1+lb));
   return(curHH > prevHH && Rsi(1) < Rsi(1+lb));
}

bool IsBullEngulf(){ double o0=iOpen(NULL,0,1),c0=iClose(NULL,0,1),o1=iOpen(NULL,0,2),c1=iClose(NULL,0,2); return(c0>o0 && c0>MathMax(o1,c1) && o0<MathMin(o1,c1)); }
bool IsBearEngulf(){ double o0=iOpen(NULL,0,1),c0=iClose(NULL,0,1),o1=iOpen(NULL,0,2),c1=iClose(NULL,0,2); return(c0<o0 && c0<MathMin(o1,c1) && o0>MathMax(o1,c1)); }
bool IsBullPin()   { double o=iOpen(NULL,0,1),c=iClose(NULL,0,1),l=iLow(NULL,0,1);  double body=MathAbs(c-o); if(body<=0) return(false); return((MathMin(o,c)-l) >= InpPinTailFactor*body && c>o); }
bool IsBearPin()   { double o=iOpen(NULL,0,1),c=iClose(NULL,0,1),h=iHigh(NULL,0,1); double body=MathAbs(c-o); if(body<=0) return(false); return((h-MathMax(o,c)) >= InpPinTailFactor*body && c<o); }
bool BullCandle()  { return(!InpUseCandles || IsBullEngulf() || IsBullPin()); }
bool BearCandle()  { return(!InpUseCandles || IsBearEngulf() || IsBearPin()); }

bool HtfTrendUpPersistent()
{
   if(!InpUseHTFTrend) return(true);
   for(int i=0;i<InpHTFPersistBars;i++) if(HtfClose(i) <= HtfEma(i)) return(false);
   return(true);
}
bool HtfTrendDnPersistent()
{
   if(!InpUseHTFTrend) return(true);
   for(int i=0;i<InpHTFPersistBars;i++) if(HtfClose(i) >= HtfEma(i)) return(false);
   return(true);
}

bool VolumeAboveAvg()
{
   if(!InpUseVolumeFilter) return(true);
   double sum=0;
   for(int i=2;i<2+InpVolumeAvgPeriod;i++) sum += (double)iVolume(NULL,0,i);
   double avg = sum/InpVolumeAvgPeriod;
   if(avg<=0) return(true);
   return((double)iVolume(NULL,0,1) >= avg*InpVolumeMinRatio);
}

bool MacdBullCross()
{
   if(!InpUseMACDVoter) return(false);
   double mc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,1);
   double mp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,2);
   double sc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,1);
   double sp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,2);
   double mac=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,1);
   double map=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,2);
   return(mc<0 && mc>sc && mp<sp && mac>map);
}
bool MacdBearCross()
{
   if(!InpUseMACDVoter) return(false);
   double mc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,1);
   double mp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_MAIN,2);
   double sc=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,1);
   double sp=iMACD(NULL,0,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE,MODE_SIGNAL,2);
   double mac=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,1);
   double map=iMA(NULL,0,InpMacdSlow,0,MODE_EMA,PRICE_CLOSE,2);
   return(mc>0 && mc<sc && mp>sp && mac<map);
}

int DayRangePattern()
{
   if(!InpUseDayRangeVoter) return(0);
   double pH=iHigh(NULL,PERIOD_D1,1), pL=iLow(NULL,PERIOD_D1,1);
   double pO=iOpen(NULL,PERIOD_D1,1), pC=iClose(NULL,PERIOD_D1,1);
   double rng=pH-pL;
   if(rng < Point*10) return(0);
   double zone=rng*(InpDayRangeZonePct/100.0);
   bool bull=((pH-pC)<=zone)&&((pO-pL)<=zone);
   bool bear=((pH-pO)<=zone)&&((pC-pL)<=zone);
   if(bull) return(1);
   if(bear) return(-1);
   return(0);
}

bool StochOkBuy()
{
   double k=StochK(1); int mode=InpStochRegimeMode;
   if(mode==2) mode=(Adx(1)>=InpStochAdxThresh)?1:0;
   if(mode==0) return(k>=InpStochBuyLo && k<=InpStochBuyHi);
   else        return(k>=InpStochSellLo && k<=InpStochSellHi);
}
bool StochOkSell()
{
   double k=StochK(1); int mode=InpStochRegimeMode;
   if(mode==2) mode=(Adx(1)>=InpStochAdxThresh)?1:0;
   if(mode==0) return(k>=InpStochSellLo && k<=InpStochSellHi);
   else        return(k>=InpStochBuyLo && k<=InpStochBuyHi);
}

bool MTFVoterBull()
{
   if(!InpUseMTFVoter) return(false);
   int aligned=0;
   if(MTFEmaFast(PERIOD_W1,0)>MTFEmaSlow(PERIOD_W1,0)) aligned++;
   if(MTFEmaFast(PERIOD_D1,0)>MTFEmaSlow(PERIOD_D1,0)) aligned++;
   if(MTFEmaFast(PERIOD_H4,0)>MTFEmaSlow(PERIOD_H4,0)) aligned++;
   if(MTFEmaFast(PERIOD_H1,0)>MTFEmaSlow(PERIOD_H1,0)) aligned++;
   return(aligned>=InpMTFMinAligned);
}
bool MTFVoterBear()
{
   if(!InpUseMTFVoter) return(false);
   int aligned=0;
   if(MTFEmaFast(PERIOD_W1,0)<MTFEmaSlow(PERIOD_W1,0)) aligned++;
   if(MTFEmaFast(PERIOD_D1,0)<MTFEmaSlow(PERIOD_D1,0)) aligned++;
   if(MTFEmaFast(PERIOD_H4,0)<MTFEmaSlow(PERIOD_H4,0)) aligned++;
   if(MTFEmaFast(PERIOD_H1,0)<MTFEmaSlow(PERIOD_H1,0)) aligned++;
   return(aligned>=InpMTFMinAligned);
}

bool TTFVoterBull()
{
   if(!InpUseTTFVoter) return(false);
   if(Bars < InpTTFBars*2+2) return(false);
   double buyPow  = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1+InpTTFBars));
   double sellPow = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1+InpTTFBars))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1));
   double denom = 0.5*(buyPow+sellPow);
   if(denom<=0) return(false);
   return(((buyPow-sellPow)/denom*100.0) > InpTTFBullThresh);
}
bool TTFVoterBear()
{
   if(!InpUseTTFVoter) return(false);
   if(Bars < InpTTFBars*2+2) return(false);
   double buyPow  = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1+InpTTFBars));
   double sellPow = iHigh(NULL,0,iHighest(NULL,0,MODE_HIGH,InpTTFBars,1+InpTTFBars))
                  - iLow (NULL,0,iLowest (NULL,0,MODE_LOW, InpTTFBars,1));
   double denom = 0.5*(buyPow+sellPow);
   if(denom<=0) return(false);
   return(((buyPow-sellPow)/denom*100.0) < -InpTTFBearThresh);
}

bool VegasH4Bull()
{
   if(!InpUseVegasH4) return(false);
   double sma8 =iMA(NULL,PERIOD_H4,InpVegasFast,0,MODE_SMA,PRICE_CLOSE,0);
   double sma55=iMA(NULL,PERIOD_H4,InpVegasSlow,0,MODE_SMA,PRICE_CLOSE,0);
   double cls  =iClose(NULL,PERIOD_H4,0);
   return(cls>sma55 && sma8>sma55);
}
bool VegasH4Bear()
{
   if(!InpUseVegasH4) return(false);
   double sma8 =iMA(NULL,PERIOD_H4,InpVegasFast,0,MODE_SMA,PRICE_CLOSE,0);
   double sma55=iMA(NULL,PERIOD_H4,InpVegasSlow,0,MODE_SMA,PRICE_CLOSE,0);
   double cls  =iClose(NULL,PERIOD_H4,0);
   return(cls<sma55 && sma8<sma55);
}

bool ADRExhausted()
{
   if(!InpUseADRFilter) return(false);
   double adr=0;
   for(int k=1;k<=InpADRPeriod;k++) adr += iHigh(NULL,PERIOD_D1,k)-iLow(NULL,PERIOD_D1,k);
   adr/=InpADRPeriod;
   if(adr<=0) return(false);
   double todayRange = iHigh(NULL,PERIOD_D1,0)-iLow(NULL,PERIOD_D1,0);
   return(todayRange/adr >= InpADRMaxPct/100.0);
}

//================================================================
// 15-VOTER CONFLUENCE
//================================================================
int BuyConfluenceScore()
{
   int score=0;
   if(iClose(NULL,0,1) <= DmaLow(1))                                                       score++; // DMA
   if(StochOkBuy())                                                                        score++; // Stoch
   if(!InpRequireDmaSlope || (DmaHigh(1) > DmaHigh(4)))                                     score++; // Slope
   if(BullDivergence())                                                                    score++; // Div
   if(BullCandle())                                                                        score++; // Candle
   if(Atr(1) >= InpAtrMinPrice)                                                            score++; // ATR
   if(HtfTrendUpPersistent())                                                              score++; // HTF
   if(!InpUseRobotrick || (RoboFast(1) > RoboSlow(1) + Atr(1)*InpRoboChanAtrMult))         score++; // Robo
   if(VolumeAboveAvg())                                                                    score++; // Vol
   if(Rsi(1) > Rsi(2))                                                                     score++; // RSI+
   if(MacdBullCross())                                                                     score++; // MACD
   if(DayRangePattern() == 1)                                                              score++; // DayP
   if(MTFVoterBull())                                                                      score++; // MTF
   if(TTFVoterBull())                                                                      score++; // TTF
   if(VegasH4Bull())                                                                       score++; // Vegas
   return(score);
}

int SellConfluenceScore()
{
   int score=0;
   if(iClose(NULL,0,1) >= DmaHigh(1))                                                      score++;
   if(StochOkSell())                                                                       score++;
   if(!InpRequireDmaSlope || (DmaLow(1) < DmaLow(4)))                                       score++;
   if(BearDivergence())                                                                    score++;
   if(BearCandle())                                                                        score++;
   if(Atr(1) >= InpAtrMinPrice)                                                            score++;
   if(HtfTrendDnPersistent())                                                              score++;
   if(!InpUseRobotrick || (RoboFast(1) < RoboSlow(1) - Atr(1)*InpRoboChanAtrMult))         score++;
   if(VolumeAboveAvg())                                                                    score++;
   if(Rsi(1) < Rsi(2))                                                                     score++;
   if(MacdBearCross())                                                                     score++;
   if(DayRangePattern() == -1)                                                             score++;
   if(MTFVoterBear())                                                                      score++;
   if(TTFVoterBear())                                                                      score++;
   if(VegasH4Bear())                                                                       score++;
   return(score);
}

//================================================================
// SL / TP  (v1.4 DMA logic with ATR fallback guard, R:R 1.5)
//================================================================
void ComputeBuySLTP(double entry,double &sl,double &tp)
{
   double atr=Atr(1);
   sl = DmaLow(1);
   double slDist = entry-sl;
   if(slDist < InpAtrMinPrice || slDist <= 0) sl = entry - atr*InpAdaptiveSlAtrMult;
   tp = entry + (entry-sl)*InpTPRRMultiplier;
}
void ComputeSellSLTP(double entry,double &sl,double &tp)
{
   double atr=Atr(1);
   sl = DmaHigh(1);
   double slDist = sl-entry;
   if(slDist < InpAtrMinPrice || slDist <= 0) sl = entry + atr*InpAdaptiveSlAtrMult;
   tp = entry - (sl-entry)*InpTPRRMultiplier;
}

//================================================================
// JSON WRITERS  (sandbox MQL4\Files — bridge reads this folder)
//================================================================
void WriteLiveData(int buyScore,int sellScore)
{
   double balance=AccountBalance(), equity=AccountEquity(), margin=AccountMargin();
   double dd = (balance>0) ? (equity-balance)/balance : 0.0;
   int best = MathMax(buyScore,sellScore);
   string phase = (best>=InpMinConfluence) ? "Signal Active" : "Scanning";

   string json="{";
   json += "\"balance\": "       + DoubleToStr(balance,2) + ",";
   json += "\"equity\": "        + DoubleToStr(equity,2) + ",";
   json += "\"margin\": "        + DoubleToStr(margin,2) + ",";
   json += "\"drawdown\": "      + DoubleToStr(dd,4) + ",";
   json += "\"trades_daily\": 0,";
   json += "\"consec_losses\": 0,";
   json += "\"phase\": \""        + phase + "\",";
   json += "\"buy_score\": "      + IntegerToString(buyScore) + ",";
   json += "\"sell_score\": "     + IntegerToString(sellScore) + ",";
   json += "\"atr\": "           + DoubleToStr(Atr(1),6) + ",";
   json += "\"timestamp\": \""    + TimeToStr(TimeCurrent(),TIME_DATE) + " " + TimeToStr(TimeCurrent(),TIME_SECONDS) + "\"";
   json += "}";

   int h=FileOpen("NCI_LiveData.json",FILE_WRITE|FILE_TXT,0);
   if(h!=INVALID_HANDLE){ FileWriteString(h,json); FileClose(h); }
}

void WriteSignalProposal(int buyScore,int sellScore)
{
   bool isBuy = buyScore >= sellScore;
   int  score = isBuy ? buyScore : sellScore;
   string action = isBuy ? "BUY" : "SELL";

   double entry = isBuy ? Ask : Bid;
   double sl, tp;
   if(isBuy) ComputeBuySLTP(entry,sl,tp); else ComputeSellSLTP(entry,sl,tp);

   double slPips = MathAbs(entry-sl)/PipPoint;
   double tpPips = MathAbs(tp-entry)/PipPoint;
   double rr     = (slPips>0) ? tpPips/slPips : 0.0;
   double gmScore10 = score/15.0*10.0;             // map 0..15 -> 0..10 for dashboard
   bool   qualifies = (score>=InpMinConfluence) && !ADRExhausted();

   string json="{";
   json += "\"symbol\": \""        + Symbol() + "\",";
   json += "\"action\": \""        + action + "\",";
   json += "\"mode\": \"CONFLUENCE\",";
   json += "\"godmode_score\": "    + DoubleToStr(gmScore10,2) + ",";
   json += "\"confluence\": "       + IntegerToString(score) + ",";
   json += "\"confluence_max\": 15,";
   json += "\"sl_pips\": "          + DoubleToStr(slPips,0) + ",";
   json += "\"tp_pips\": "          + DoubleToStr(tpPips,0) + ",";
   json += "\"risk_reward\": "      + DoubleToStr(rr,2) + ",";
   json += "\"qualifies\": "        + (qualifies?"true":"false") + ",";
   json += "\"adr_exhausted\": "    + (ADRExhausted()?"true":"false") + ",";
   json += "\"timestamp\": \""      + TimeToStr(TimeCurrent(),TIME_DATE) + " " + TimeToStr(TimeCurrent(),TIME_SECONDS) + "\",";
   json += "\"approved\": false";
   json += "}";

   int h=FileOpen("signal_proposal.json",FILE_WRITE|FILE_TXT,0);
   if(h!=INVALID_HANDLE){ FileWriteString(h,json); FileClose(h); }
}

//================================================================
// LIFECYCLE
//================================================================
int OnInit()
{
   InitPipMath();
   Print("===== NCI Hybrid v2.1 — Signal Reporter STARTED =====");
   Print("Account: ", AccountNumber(), "  Balance: ", AccountBalance(), "  ", AccountCompany());
   Print("Symbol: ", Symbol(), "  TF: ", Period(), "  READ-ONLY (places no trades)");
   Print("15-voter engine | MinConfluence=", InpMinConfluence, "/15 | R:R=", InpTPRRMultiplier, "x");
   int b=BuyConfluenceScore(), s=SellConfluenceScore();
   WriteLiveData(b,s);
   WriteSignalProposal(b,s);
   Print("Initial confluence  BUY=", b, "/15   SELL=", s, "/15");
   Print("===== v2.1 READY =====");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("NCI Hybrid v2.1 reporter stopped. Reason: ", reason);
}

void OnTick()
{
   TickCounter++;

   // Recompute the real confluence on every new bar (voters use closed-bar data)
   static int lastBuy=0, lastSell=0;
   if(IsNewBar())
   {
      lastBuy  = BuyConfluenceScore();
      lastSell = SellConfluenceScore();
      WriteSignalProposal(lastBuy,lastSell);
      if(InpVerboseLog)
         Print("v2.1 bar update  BUY=", lastBuy, "/15  SELL=", lastSell,
               "/15  spread=", DoubleToStr(SpreadPips(),1), "p  ADRexh=", ADRExhausted());
   }

   // Refresh account state periodically (balance/equity move intrabar)
   if(TickCounter % InpReportEveryTicks == 0)
      WriteLiveData(lastBuy,lastSell);
}
//+------------------------------------------------------------------+
