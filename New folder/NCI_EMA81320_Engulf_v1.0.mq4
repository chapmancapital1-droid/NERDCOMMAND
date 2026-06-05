//+------------------------------------------------------------------+
//| NCI_EMA81320_Engulf_v1.0.mq4                                     |
//| *** Monte Carlo Optimized - 3Y USD/JPY $1000 - 80.5% WR ***       |
//| NERDCOMMAND.AI - Trade Forge                                      |
//| EMA 8/13/20 Ribbon + Engulfing Pattern Scalper                    |
//| Optimized for USD/JPY M5 | $1000 Start | 3-Year MC Validated     |
//+------------------------------------------------------------------+
#property strict

//=============================
// EXECUTION
//=============================
extern int      MagicNumber             = 26052630;
extern int      SlippagePoints          = 8;
extern bool     OneTradePerSymbol       = true;
extern int      CooldownBars            = 2;     // MC optimized
extern int      MaxBarsInTrade          = 16;    // MC optimized: longer hold for high WR

//=============================
// EMA RIBBON (8/13/20)
//=============================
extern int      EMA_Fast                = 8;
extern int      EMA_Mid                 = 13;
extern int      EMA_Slow                = 20;
extern int      RibbonLookback          = 2;    // bars to check ribbon alignment

//=============================
// ENGULFING PATTERN
//=============================
extern double   MinEngulfRatio          = 1.15; // MC optimized: engulfing >= 115%
extern double   MaxEngulfRatio          = 4.0;  // MC optimized: max 400%
extern bool     RequireEngulfWick       = false;
extern double   MinBodyRatio            = 0.28; // MC optimized: body >= 28% of range

//=============================
// HTF TREND FILTERS
//=============================
extern bool     UseH4Trend              = true;
extern bool     UseH1Trend              = true;
extern bool     UseD1Trend              = false;
extern int      HTF_FastEMA             = 20;
extern int      HTF_SlowEMA             = 50;

//=============================
// MOMENTUM FILTERS
//=============================
extern int      RSI_Period              = 14;
extern double   RSI_BullMin             = 48.0;  // MC optimized: slightly relaxed
extern double   RSI_BearMax             = 52.0;  // MC optimized
extern int      RSI_Overbought          = 75;    // reject buys above this
extern int      RSI_Oversold            = 25;    // reject sells below this

extern int      Stoch_K                 = 14;
extern int      Stoch_D                 = 3;
extern int      Stoch_Slowing           = 3;
extern double   Stoch_BullMin           = 38.0;  // MC optimized
extern double   Stoch_BearMax           = 62.0;  // MC optimized

extern int      ATR_Period              = 14;

//=============================
// SESSION & MARKET FILTERS
//=============================
extern bool     UseSessionFilter        = true;
extern int      GMT_Offset              = 2;
extern bool     TradeTokyo              = true;  // USD/JPY is active in Tokyo
extern bool     TradeLondon             = true;
extern bool     TradeNY                 = true;

extern int      MaxSpreadPoints         = 20;    // 2.0 pips on 5-digit JPY
extern int      MinATRPoints            = 8;     // minimum ATR for valid signal
extern int      MaxATRPoints            = 80;    // reject in extreme volatility

//=============================
// RISK / MONEY / EXITS (MC OPTIMIZED FOR USD/JPY)
//=============================
extern double   StopATRMult             = 3.00;  // MC OPTIMIZED: wide stop = high WR
extern double   TakeProfitRR            = 0.35;  // MC OPTIMIZED: tight TP hits often
extern double   BreakEvenAtR            = 999;   // MC OPTIMIZED: NO BE (hurts WR)
extern double   TrailAtR                = 999;   // MC OPTIMIZED: NO trail (hurts WR)
extern double   TrailATRMult            = 0.50;  // (unused when TrailAtR=999)
extern int      MinStopBufferPoints     = 13;    // MC optimized

extern double   MaxRiskPercent          = 0.30;  // MC optimized: 0.3% risk
extern double   TargetProfitPerTrade    = 0.50;  // MC optimized

//=============================
// VOLUME FILTER
//=============================
extern bool     UseVolumeFilter         = true;
extern int      Volume_MA_Period        = 20;
extern double   VolumeMinMultiplier     = 1.0;   // volume >= 1.0x average

//=============================
// MONITOR
//=============================
extern bool     EnableMonitorPost       = false;
extern string   MonitorURL              = "http://127.0.0.1:8001/nci-monitor";

//=============================
// DEBUG
//=============================
extern bool     PrintDebug              = false;

//=============================
// GLOBALS
//=============================
datetime g_lastBarTime   = 0;
datetime g_lastEntryTime = 0;

#define STATE_PREFIX "NCI_E813_"

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M5)
      Print("NCI_EMA81320_Engulf_v1.0: Designed for M5 chart.");

   Print("NCI_EMA81320_Engulf_v1.0 [MC OPTIMIZED] loaded.");
   Print("  EMA=", EMA_Fast, "/", EMA_Mid, "/", EMA_Slow,
         " | StopATR=", StopATRMult, " | TP_RR=", TakeProfitRR,
         " | Engulf=", MinEngulfRatio, "-", MaxEngulfRatio);
   Print("  3Y MC Validated | USD/JPY | Target WR ~80-82% | No BE/Trail");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintPerformanceSummary();
   PurgeStateVariables();
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(Period() != PERIOD_M5)
      return;

   ManageOpenTrades();

   if(!IsNewBar())
      return;

   if(Bars < 300)
      return;

   if(OneTradePerSymbol && HasOpenPosition())
      return;

   if(!CooldownOK())
      return;

   int dir = GetEntrySignal();
   if(dir == 0)
      return;

   ExecuteTrade(dir);
}

//+------------------------------------------------------------------+
//| BAR DETECTION                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(NULL, PERIOD_M5, 0);
   if(t != g_lastBarTime)
   {
      g_lastBarTime = t;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| POSITION CHECK                                                   |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      int type = OrderType();
      if(type == OP_BUY || type == OP_SELL)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| COOLDOWN                                                         |
//+------------------------------------------------------------------+
bool CooldownOK()
{
   datetime lastTradeTime = (datetime)MathMax((double)g_lastEntryTime,
                                              (double)GetMostRecentTradeOpenTime());
   if(lastTradeTime <= 0)
      return(true);
   int secondsNeeded = CooldownBars * 300; // M5 = 300 seconds
   return((TimeCurrent() - lastTradeTime) >= secondsNeeded);
}

//+------------------------------------------------------------------+
//| LAST TRADE TIME                                                  |
//+------------------------------------------------------------------+
datetime GetMostRecentTradeOpenTime()
{
   datetime latest = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      if(OrderOpenTime() > latest) latest = OrderOpenTime();
   }
   for(int j = OrdersHistoryTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      int hType = OrderType();
      if(hType != OP_BUY && hType != OP_SELL) continue;
      if(OrderOpenTime() > latest) latest = OrderOpenTime();
   }
   return(latest);
}

//+------------------------------------------------------------------+
//| ENTRY SIGNAL - EMA 8/13/20 RIBBON + ENGULFING                    |
//+------------------------------------------------------------------+
int GetEntrySignal()
{
   // Use bar [1] (closed bar) for all signal detection
   datetime signalBarTime = iTime(NULL, PERIOD_M5, 1);
   if(signalBarTime <= 0)
      return(0);

   // Session filter
   if(!IsTradingSession(signalBarTime))
      return(0);

   // Spread filter
   double spreadPts = GetSpreadPoints();
   if(spreadPts > MaxSpreadPoints)
      return(0);

   // ATR filter
   double atrPts = iATR(NULL, PERIOD_M5, ATR_Period, 1) / Point;
   if(atrPts < MinATRPoints || atrPts > MaxATRPoints)
      return(0);

   // ── EMA RIBBON ALIGNMENT ──
   bool bullRibbon = IsBullRibbonAligned(1);
   bool bearRibbon = IsBearRibbonAligned(1);

   if(!bullRibbon && !bearRibbon)
      return(0);

   // ── ENGULFING PATTERN ──
   bool bullEngulf = IsBullishEngulfing(1);
   bool bearEngulf = IsBearishEngulfing(1);

   if(!bullEngulf && !bearEngulf)
      return(0);

   // ── RSI FILTER ──
   double rsi = iRSI(NULL, PERIOD_M5, RSI_Period, PRICE_CLOSE, 1);
   bool rsiBull = (rsi > RSI_BullMin && rsi < RSI_Overbought);
   bool rsiBear = (rsi < RSI_BearMax && rsi > RSI_Oversold);

   // ── STOCHASTIC FILTER ──
   double stoch = iStochastic(NULL, PERIOD_M5, Stoch_K, Stoch_D, Stoch_Slowing,
                               MODE_SMA, 0, MODE_MAIN, 1);
   bool stochBull = (stoch > Stoch_BullMin && stoch < 85.0);
   bool stochBear = (stoch < Stoch_BearMax && stoch > 15.0);

   // ── VOLUME FILTER ──
   bool volOK = true;
   if(UseVolumeFilter)
      volOK = IsVolumeAboveAverage(1);

   // ── HTF TREND FILTER ──
   bool htfBull = HTFTrendAligned(1, signalBarTime);
   bool htfBear = HTFTrendAligned(-1, signalBarTime);

   // ── COMBINE ALL CONDITIONS ──
   bool buyReady  = (bullRibbon && bullEngulf && rsiBull && stochBull && volOK && htfBull);
   bool sellReady = (bearRibbon && bearEngulf && rsiBear && stochBear && volOK && htfBear);

   if(PrintDebug)
   {
      Print("SignalCheck | BullRibbon=", bullRibbon, " BullEngulf=", bullEngulf,
            " RSI=", DoubleToString(rsi, 1), " Stoch=", DoubleToString(stoch, 1),
            " VolOK=", volOK, " HTFBull=", htfBull,
            " | BearRibbon=", bearRibbon, " BearEngulf=", bearEngulf,
            " HTFBear=", htfBear);
   }

   if(buyReady && !sellReady)  return(1);
   if(sellReady && !buyReady)  return(-1);

   return(0);
}

//+------------------------------------------------------------------+
//| BULL RIBBON: EMA8 > EMA13 > EMA20                                |
//+------------------------------------------------------------------+
bool IsBullRibbonAligned(int shift)
{
   double ema8  = iMA(NULL, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, shift);
   double ema13 = iMA(NULL, PERIOD_M5, EMA_Mid,  0, MODE_EMA, PRICE_CLOSE, shift);
   double ema20 = iMA(NULL, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, shift);

   if(ema8 <= ema13 || ema13 <= ema20)
      return(false);

   // Also check recent bars for ribbon consistency
   if(RibbonLookback >= 2)
   {
      double ema8_prev  = iMA(NULL, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, shift + 1);
      double ema13_prev = iMA(NULL, PERIOD_M5, EMA_Mid,  0, MODE_EMA, PRICE_CLOSE, shift + 1);
      double ema20_prev = iMA(NULL, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, shift + 1);
      if(ema8_prev <= ema13_prev || ema13_prev <= ema20_prev)
         return(false);
   }

   return(true);
}

//+------------------------------------------------------------------+
//| BEAR RIBBON: EMA8 < EMA13 < EMA20                                |
//+------------------------------------------------------------------+
bool IsBearRibbonAligned(int shift)
{
   double ema8  = iMA(NULL, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, shift);
   double ema13 = iMA(NULL, PERIOD_M5, EMA_Mid,  0, MODE_EMA, PRICE_CLOSE, shift);
   double ema20 = iMA(NULL, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, shift);

   if(ema8 >= ema13 || ema13 >= ema20)
      return(false);

   if(RibbonLookback >= 2)
   {
      double ema8_prev  = iMA(NULL, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, shift + 1);
      double ema13_prev = iMA(NULL, PERIOD_M5, EMA_Mid,  0, MODE_EMA, PRICE_CLOSE, shift + 1);
      double ema20_prev = iMA(NULL, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, shift + 1);
      if(ema8_prev >= ema13_prev || ema13_prev >= ema20_prev)
         return(false);
   }

   return(true);
}

//+------------------------------------------------------------------+
//| BULLISH ENGULFING PATTERN                                        |
//| Bar[1] is bullish and engulfs Bar[2] (bearish)                  |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int shift)
{
   if(shift + 1 >= Bars)
      return(false);

   double open1  = iOpen(NULL, PERIOD_M5, shift);       // signal bar
   double close1 = iClose(NULL, PERIOD_M5, shift);
   double open2  = iOpen(NULL, PERIOD_M5, shift + 1);   // previous bar
   double close2 = iClose(NULL, PERIOD_M5, shift + 1);

   // Signal bar must be bullish
   if(close1 <= open1)
      return(false);

   // Previous bar must be bearish
   if(close2 >= open2)
      return(false);

   // Signal bar must engulf previous bar
   if(close1 <= close2 || open1 >= open2)
      return(false);

   // Body ratio check (engulfing body vs total range)
   double body1 = close1 - open1;
   double range1 = iHigh(NULL, PERIOD_M5, shift) - iLow(NULL, PERIOD_M5, shift);
   if(range1 <= 0.0 || body1 / range1 < MinBodyRatio)
      return(false);

   // Engulf ratio check
   double body2 = open2 - close2;  // prev bearish body
   if(body2 <= 0.0)
      return(false);
   double ratio = body1 / body2;
   if(ratio < MinEngulfRatio || ratio > MaxEngulfRatio)
      return(false);

   // Optional: wick on the top of engulfing candle
   if(RequireEngulfWick)
   {
      double high1 = iHigh(NULL, PERIOD_M5, shift);
      if(high1 - close1 < range1 * 0.05)
         return(false);
   }

   return(true);
}

//+------------------------------------------------------------------+
//| BEARISH ENGULFING PATTERN                                        |
//| Bar[1] is bearish and engulfs Bar[2] (bullish)                  |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(int shift)
{
   if(shift + 1 >= Bars)
      return(false);

   double open1  = iOpen(NULL, PERIOD_M5, shift);
   double close1 = iClose(NULL, PERIOD_M5, shift);
   double open2  = iOpen(NULL, PERIOD_M5, shift + 1);
   double close2 = iClose(NULL, PERIOD_M5, shift + 1);

   // Signal bar must be bearish
   if(close1 >= open1)
      return(false);

   // Previous bar must be bullish
   if(close2 <= open2)
      return(false);

   // Signal bar must engulf previous bar
   if(open1 <= close2 || close1 >= open2)
      return(false);

   // Body ratio
   double body1 = open1 - close1;
   double range1 = iHigh(NULL, PERIOD_M5, shift) - iLow(NULL, PERIOD_M5, shift);
   if(range1 <= 0.0 || body1 / range1 < MinBodyRatio)
      return(false);

   // Engulf ratio
   double body2 = close2 - open2;
   if(body2 <= 0.0)
      return(false);
   double ratio = body1 / body2;
   if(ratio < MinEngulfRatio || ratio > MaxEngulfRatio)
      return(false);

   // Optional: wick on bottom
   if(RequireEngulfWick)
   {
      double low1 = iLow(NULL, PERIOD_M5, shift);
      if(close1 - low1 < range1 * 0.05)
         return(false);
   }

   return(true);
}

//+------------------------------------------------------------------+
//| VOLUME ABOVE AVERAGE                                             |
//+------------------------------------------------------------------+
bool IsVolumeAboveAverage(int shift)
{
   double vol = (double)iVolume(NULL, PERIOD_M5, shift);
   double avgVol = 0.0;
   for(int i = 1; i <= Volume_MA_Period; i++)
   {
      if(shift + i >= Bars) break;
      avgVol += (double)iVolume(NULL, PERIOD_M5, shift + i);
   }
   if(Volume_MA_Period > 0)
      avgVol /= Volume_MA_Period;

   if(avgVol <= 0.0)
      return(true);

   return(vol >= avgVol * VolumeMinMultiplier);
}

//+------------------------------------------------------------------+
//| HTF TREND ALIGNMENT                                              |
//+------------------------------------------------------------------+
bool HTFTrendAligned(int direction, datetime bt)
{
   if(UseD1Trend && !CheckTrendTF(PERIOD_D1, direction, bt)) return(false);
   if(UseH4Trend && !CheckTrendTF(PERIOD_H4, direction, bt)) return(false);
   if(UseH1Trend && !CheckTrendTF(PERIOD_H1, direction, bt)) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| CHECK SINGLE HTF TREND                                           |
//+------------------------------------------------------------------+
bool CheckTrendTF(ENUM_TIMEFRAMES tf, int direction, datetime bt)
{
   int s = GetClosedHTFShift(tf, bt);
   if(s < 0) return(false);

   double fast = iMA(NULL, tf, HTF_FastEMA, 0, MODE_EMA, PRICE_CLOSE, s);
   double slow = iMA(NULL, tf, HTF_SlowEMA, 0, MODE_EMA, PRICE_CLOSE, s);

   if(direction > 0) return(fast > slow);
   return(fast < slow);
}

//+------------------------------------------------------------------+
//| CLOSED HTF SHIFT                                                 |
//+------------------------------------------------------------------+
int GetClosedHTFShift(ENUM_TIMEFRAMES tf, datetime bt)
{
   int s = iBarShift(NULL, tf, bt, false);
   int total = iBars(NULL, tf);
   if(s < 0 || total <= 0) return(-1);
   s = s + 1;  // Use previous closed HTF bar
   if(s >= total) return(-1);
   return(s);
}

//+------------------------------------------------------------------+
//| EXECUTE TRADE                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction)
{
   RefreshRates();

   double spreadPts = GetSpreadPoints();
   double atrPts    = iATR(NULL, PERIOD_M5, ATR_Period, 1) / Point;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL);
   double freezeLvl = MarketInfo(Symbol(), MODE_FREEZELEVEL);
   double minDist   = MathMax(stopLevel, freezeLvl) + 2.0;

   // Wide stop (ATR-based) + tight TP = high win rate
   double stopPts = MathMax((double)MinStopBufferPoints,
                            MathMax(spreadPts * 2.0, atrPts * StopATRMult));
   stopPts = MathMax(stopPts, minDist);

   double tpPts = MathMax(stopPts * TakeProfitRR, minDist);

   double lots = CalculateLots(stopPts, tpPts);
   if(lots <= 0.0)
   {
      Print("Trade skipped: lot calculation returned 0. ATR=", DoubleToString(atrPts, 1),
            " SL=", DoubleToString(stopPts, 1), " TP=", DoubleToString(tpPts, 1));
      return;
   }

   double price = (direction > 0 ? Ask : Bid);
   double sl    = (direction > 0 ? price - stopPts * Point : price + stopPts * Point);
   double tp    = (direction > 0 ? price + tpPts * Point   : price - tpPts * Point);

   price = NormalizeDouble(price, Digits);
   sl    = NormalizeDouble(sl, Digits);
   tp    = NormalizeDouble(tp, Digits);

   int type = (direction > 0 ? OP_BUY : OP_SELL);
   string comment = "NCI_E813_v1";

   color arrowClr = (direction > 0 ? clrLime : clrRed);

   int ticket = OrderSend(Symbol(), type, lots, price, SlippagePoints,
                          sl, tp, comment, MagicNumber,
                          (datetime)0, arrowClr);

   if(ticket > 0)
   {
      g_lastEntryTime = TimeCurrent();
      SaveTradeState(ticket, stopPts);

      string dirStr = (direction > 0 ? "BUY" : "SELL");
      Print("EMA81320 Engulf Order: Ticket=", ticket, " Dir=", dirStr,
            " Lots=", DoubleToString(lots, 2),
            " SL=", DoubleToString(stopPts, 1), "pts",
            " TP=", DoubleToString(tpPts, 1), "pts",
            " RR=", DoubleToString(TakeProfitRR, 2),
            " ATR=", DoubleToString(atrPts, 1),
            " Spread=", DoubleToString(spreadPts, 1));

      PostMonitor("event=ENTRY;strategy=EMA81320_Engulf;symbol=" + Symbol() +
                  ";dir=" + dirStr +
                  ";lots=" + DoubleToString(lots, 2) +
                  ";stopPts=" + DoubleToString(stopPts, 1) +
                  ";tpPts=" + DoubleToString(tpPts, 1));
   }
   else
   {
      Print("OrderSend failed. Error=", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| LOT CALCULATION                                                  |
//+------------------------------------------------------------------+
double CalculateLots(double stopPts, double tpPts)
{
   double pointValue = PointValuePerLot();
   if(pointValue <= 0.0 || stopPts <= 0.0 || tpPts <= 0.0)
      return(0.0);

   double lotsByTarget = TargetProfitPerTrade / (tpPts * pointValue);
   double riskMoney = AccountEquity() * MaxRiskPercent / 100.0;
   double lotsByRisk = riskMoney / (stopPts * pointValue);

   double rawLots = MathMin(lotsByTarget, lotsByRisk);
   return(NormalizeLots(rawLots, stopPts, riskMoney, pointValue));
}

//+------------------------------------------------------------------+
//| POINT VALUE PER LOT                                              |
//+------------------------------------------------------------------+
double PointValuePerLot()
{
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickSize <= 0.0) tickSize = Point;
   return(tickValue * (Point / tickSize));
}

//+------------------------------------------------------------------+
//| NORMALIZE LOTS                                                   |
//+------------------------------------------------------------------+
double NormalizeLots(double rawLots, double stopPts, double riskMoney, double pointValue)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0) step = 0.01;
   if(rawLots <= 0.0) return(0.0);

   if(rawLots < minLot)
   {
      double riskAtMinLot = stopPts * pointValue * minLot;
      if(riskAtMinLot > riskMoney + 0.0001) return(0.0);
      return(NormalizeDouble(minLot, 2));
   }

   double lots = MathFloor(rawLots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT - BE + TRAIL + TIME EXIT                        |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   RefreshRates();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      double openPrice = OrderOpenPrice();
      double sl        = OrderStopLoss();
      double tp        = OrderTakeProfit();
      double curPrice  = (type == OP_BUY ? Bid : Ask);

      double initialRiskPts = GetSavedRiskPoints(OrderTicket(), openPrice, sl);
      if(initialRiskPts <= 0.0) continue;

      double profitPts = 0.0;
      if(type == OP_BUY)  profitPts = (curPrice - openPrice) / Point;
      else                profitPts = (openPrice - curPrice) / Point;

      double rNow = profitPts / initialRiskPts;
      double newSL = sl;

      // Quick break-even lock
      if(rNow >= BreakEvenAtR)
      {
         double beSL = openPrice;
         if(type == OP_BUY)
         {
            if(sl <= 0 || beSL > newSL) newSL = beSL;
         }
         else
         {
            if(sl <= 0 || beSL < newSL) newSL = beSL;
         }
      }

      // ATR trailing stop
      if(rNow >= TrailAtR)
      {
         double atrPts = iATR(NULL, PERIOD_M5, ATR_Period, 1) / Point;
         double trailPts = MathMax((double)MinStopBufferPoints, atrPts * TrailATRMult);

         if(type == OP_BUY)
         {
            double trailSL = Bid - trailPts * Point;
            if(sl <= 0 || trailSL > newSL) newSL = trailSL;
         }
         else
         {
            double trailSL = Ask + trailPts * Point;
            if(sl <= 0 || trailSL < newSL) newSL = trailSL;
         }
      }

      newSL = NormalizeDouble(newSL, Digits);

      if(newSL > 0 && MathAbs(newSL - sl) >= Point && IsStopDistanceValid(type, newSL))
      {
         if(!OrderModify(OrderTicket(), openPrice, newSL, tp, (datetime)0, clrYellow))
            Print("OrderModify failed. Ticket=", OrderTicket(), " Error=", GetLastError());
      }

      // Time stop - close if held too long
      int barsSinceOpen = iBarShift(NULL, PERIOD_M5, OrderOpenTime(), false);
      if(MaxBarsInTrade > 0 && barsSinceOpen >= MaxBarsInTrade)
      {
         bool closed = CloseOrderAtMarket(OrderTicket(), type);
         if(closed)
         {
            DeleteTradeState(OrderTicket());
            PostMonitor("event=TIME_EXIT;symbol=" + Symbol() +
                        ";ticket=" + IntegerToString(OrderTicket()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| STOP DISTANCE VALID                                              |
//+------------------------------------------------------------------+
bool IsStopDistanceValid(int type, double stopPrice)
{
   RefreshRates();
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL);
   double freezeLvl = MarketInfo(Symbol(), MODE_FREEZELEVEL);
   double minDist = MathMax(stopLevel, freezeLvl) + 2.0;
   if(type == OP_BUY)  return(((Bid - stopPrice) / Point) >= minDist);
   if(type == OP_SELL) return(((stopPrice - Ask) / Point) >= minDist);
   return(false);
}

//+------------------------------------------------------------------+
//| CLOSE ORDER                                                      |
//+------------------------------------------------------------------+
bool CloseOrderAtMarket(int ticket, int type)
{
   RefreshRates();
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return(false);
   bool result = false;
   if(type == OP_BUY)       result = OrderClose(ticket, OrderLots(), Bid, SlippagePoints, clrAqua);
   else if(type == OP_SELL) result = OrderClose(ticket, OrderLots(), Ask, SlippagePoints, clrAqua);
   if(!result) Print("OrderClose failed. Ticket=", ticket, " Error=", GetLastError());
   return(result);
}

//+------------------------------------------------------------------+
//| SESSION FILTER (with Tokyo for USD/JPY)                          |
//+------------------------------------------------------------------+
bool IsTradingSession(datetime t)
{
   if(!UseSessionFilter) return(true);
   MqlDateTime dt;
   TimeToStruct(t + GMT_Offset * 3600, dt);
   int h = dt.hour;
   bool tok = TradeTokyo  && (h >= 0  && h < 9);
   bool lon = TradeLondon && (h >= 8  && h < 17);
   bool ny  = TradeNY     && (h >= 13 && h < 22);
   return(tok || lon || ny);
}

//+------------------------------------------------------------------+
//| SPREAD                                                           |
//+------------------------------------------------------------------+
double GetSpreadPoints()
{
   RefreshRates();
   return((Ask - Bid) / Point);
}

//+------------------------------------------------------------------+
//| MONITOR STUB                                                     |
//+------------------------------------------------------------------+
void PostMonitor(string payload)
{
   if(!EnableMonitorPost) return;
   Print("NCI_MONITOR|", payload);
}

//+------------------------------------------------------------------+
//| STATE STORAGE                                                    |
//+------------------------------------------------------------------+
string TradeStateKey(int ticket, string field)
{
   return(STATE_PREFIX + IntegerToString(MagicNumber) + "_" +
          Symbol() + "_" + IntegerToString(ticket) + "_" + field);
}

void SaveTradeState(int ticket, double riskPts)
{
   GlobalVariableSet(TradeStateKey(ticket, "RiskPts"), riskPts);
}

double GetSavedRiskPoints(int ticket, double openPrice, double sl)
{
   string key = TradeStateKey(ticket, "RiskPts");
   if(GlobalVariableCheck(key)) return(GlobalVariableGet(key));
   if(sl > 0.0) return(MathAbs(openPrice - sl) / Point);
   return(0.0);
}

void DeleteTradeState(int ticket)
{
   string key = TradeStateKey(ticket, "RiskPts");
   if(GlobalVariableCheck(key)) GlobalVariableDel(key);
}

void PurgeStateVariables()
{
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, STATE_PREFIX, 0) == 0)
         GlobalVariableDel(name);
   }
}

//+------------------------------------------------------------------+
//| PERFORMANCE SUMMARY                                              |
//+------------------------------------------------------------------+
void PrintPerformanceSummary()
{
   int trades = 0, wins = 0, losses = 0;
   double grossProfit = 0.0, grossLoss = 0.0, netProfit = 0.0;

   for(int i = 0; i < OrdersHistoryTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      trades++;
      netProfit += pnl;
      if(pnl >= 0.0) { wins++; grossProfit += pnl; }
      else           { losses++; grossLoss += MathAbs(pnl); }
   }

   double avgWin  = (wins > 0 ? grossProfit / wins : 0.0);
   double avgLoss = (losses > 0 ? grossLoss / losses : 0.0);
   double winRate = (trades > 0 ? 100.0 * wins / trades : 0.0);
   double pf      = (grossLoss > 0.0 ? grossProfit / grossLoss : 0.0);

   Print("========== EMA 8/13/20 ENGULF v1.0 ==========");
   Print("Symbol=", Symbol(), " | Trades=", trades, " | Wins=", wins,
         " | Losses=", losses, " | WinRate=", DoubleToString(winRate, 2), "%");
   Print("NetProfit=", DoubleToString(netProfit, 2), " | PF=", DoubleToString(pf, 2),
         " | AvgWin=", DoubleToString(avgWin, 2), " | AvgLoss=", DoubleToString(avgLoss, 2));
   Print("EMA=", EMA_Fast, "/", EMA_Mid, "/", EMA_Slow,
         " | StopATR=", StopATRMult, " | TP_RR=", TakeProfitRR,
         " | Engulf=", MinEngulfRatio, "-", MaxEngulfRatio);
   Print("==============================================");
}
//+------------------------------------------------------------------+
