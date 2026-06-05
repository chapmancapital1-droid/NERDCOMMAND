//+------------------------------------------------------------------+
//| NCI_ScalpBot_M5_v2.0.mq4                                         |
//| NERDCOMMAND Trading - M5 Scalp EA                                 |
//| Monte Carlo Optimized | 5-Year Sim | $500 Start                   |
//| Target: 82% Win Rate | Tight TP + Wide SL + BE Protection        |
//+------------------------------------------------------------------+
#property strict

//=============================
// EXECUTION
//=============================
extern int      MagicNumber             = 26052620;
extern int      SlippagePoints          = 10;
extern bool     OneTradePerSymbol       = true;
extern int      CooldownBars            = 2;
extern int      MaxBarsInTrade          = 8;

//=============================
// M5 ENTRY TIMING
//=============================
extern int      EntryFastEMA            = 9;
extern int      EntrySlowEMA            = 21;
extern int      CrossLookbackBars       = 2;   // Look back 2 bars for cross
extern bool     RequireEntryEMAAligned  = true;

//=============================
// HTF TREND FILTERS
//=============================
extern bool     UseWeeklyTrend          = false;
extern bool     UseDailyTrend           = false;
extern bool     UseH4Trend              = true;
extern bool     UseH1Trend              = true;
extern int      TrendFastEMA            = 20;
extern int      TrendSlowEMA            = 50;

//=============================
// MOMENTUM / SIGNAL SCORE
//=============================
extern int      RSI_Period              = 14;
extern double   RSI_BullLevel           = 52.0;   // Optimized from MC
extern double   RSI_BearLevel           = 48.0;   // Optimized from MC
extern int      Stoch_K                 = 14;
extern int      Stoch_D                 = 3;
extern int      Stoch_Slowing           = 3;
extern int      CCI_Period              = 20;
extern double   CCI_BullLevel           = 50.0;   // Relaxed from 100 for more signals
extern double   CCI_BearLevel           = -50.0;  // Relaxed from -100
extern int      MinConfluence           = 3;      // Optimized: 3 of 5 votes needed
extern bool     RequireCandle           = true;

//=============================
// 2ND ARROW LOGIC (relaxed from 3rd for more trades)
//=============================
extern bool     RequireConsecutiveArrows = true;
extern bool     ExactThirdArrowOnly      = false;  // Changed: allow 2+ consecutive
extern int      ArrowLookbackBars        = 5;      // Shorter lookback
extern int      ArrowCountToTrade        = 2;      // Only need 2 consecutive arrows

//=============================
// MARKET QUALITY FILTERS
//=============================
extern bool     UseSessionFilter        = true;
extern int      GMT_Offset              = 2;
extern bool     TradeTokyo              = false;
extern bool     TradeLondon             = true;
extern bool     TradeNY                 = true;

extern int      MaxSpreadPoints         = 22;   // Slightly wider for more opportunity
extern int      ATR_Period              = 14;
extern int      MinATRPoints            = 10;   // Lowered from 25 for more trades

//=============================
// RISK / MONEY / EXITS (MONTE CARLO OPTIMIZED)
//=============================
extern double   StopATRMult             = 2.50;  // WIDE stop - key to high WR
extern double   TakeProfitRR            = 0.45;  // TIGHT TP - hits often = high WR
extern double   BreakEvenAtR            = 0.25;  // Quick BE lock
extern double   TrailAtR                = 0.55;  // Trail after moderate profit
extern double   TrailATRMult            = 0.55;  // Trail distance
extern int      MinStopBufferPoints     = 10;

extern double   TargetProfitMin         = 0.10;
extern double   TargetProfitMax         = 1.00;
extern double   TargetProfitPerTrade    = 0.45;  // MC optimized
extern double   MaxRiskPercent          = 0.25;

//=============================
// MONITOR STUB
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

#define STATE_PREFIX "NCI_SB20_"

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(Period() != PERIOD_M5)
      Print("NCI_ScalpBot_M5_v2.0: attach to M5 chart only.");

   int maxScore = GetConfiguredMaxScore();
   if(MinConfluence > maxScore)
      Print("WARNING: MinConfluence(", MinConfluence, ") > max configured score(", maxScore, ").");

   Print("NCI_ScalpBot_M5_v2.0 loaded [MC OPTIMIZED]. MaxScore=", maxScore,
         " | StopATR=", StopATRMult, " | TP_RR=", TakeProfitRR,
         " | MinConf=", MinConfluence,
         " | Target WR ~82%");

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
   int secondsNeeded = CooldownBars * 300;
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
//| ENTRY SIGNAL (v2.0 - 2 consecutive arrows + relaxed confluence)  |
//+------------------------------------------------------------------+
int GetEntrySignal()
{
   datetime signalBarTime = iTime(NULL, PERIOD_M5, 1);
   if(signalBarTime <= 0)
      return(0);

   if(!IsTradingSession(signalBarTime))
      return(0);

   if(GetSpreadPoints() > MaxSpreadPoints)
      return(0);

   double atrPts = iATR(NULL, PERIOD_M5, ATR_Period, 1) / Point;
   if(atrPts < MinATRPoints)
      return(0);

   // Check for directional arrows with 2+ consecutive
   bool buyArrow  = IsDirectionalArrow(1,  1);
   bool sellArrow = IsDirectionalArrow(1, -1);

   bool buyTrigger = false;
   bool sellTrigger = false;

   if(RequireConsecutiveArrows)
   {
      // Need ArrowCountToTrade consecutive arrows
      buyTrigger = true;
      sellTrigger = true;
      for(int a = 0; a < ArrowCountToTrade; a++)
      {
         if(!IsDirectionalArrow(1 + a, 1))
            buyTrigger = false;
         if(!IsDirectionalArrow(1 + a, -1))
            sellTrigger = false;
      }
      // If exact mode, make sure previous bar is NOT an arrow
      if(ExactThirdArrowOnly)
      {
         if(IsDirectionalArrow(1 + ArrowCountToTrade, 1))
            buyTrigger = false;
         if(IsDirectionalArrow(1 + ArrowCountToTrade, -1))
            sellTrigger = false;
      }
   }
   else
   {
      buyTrigger = buyArrow;
      sellTrigger = sellArrow;
   }

   // EMA cross within lookback
   bool buyCross  = HasRecentCross( 1);
   bool sellCross = HasRecentCross(-1);

   if(RequireEntryEMAAligned)
   {
      buyCross  = buyCross  && EntryEMAAligned( 1, 1);
      sellCross = sellCross && EntryEMAAligned(-1, 1);
   }

   // HTF trend alignment
   bool buyTrend  = HTFTrendAligned( 1, signalBarTime);
   bool sellTrend = HTFTrendAligned(-1, signalBarTime);

   if(PrintDebug)
   {
      string dirStr = "NONE";
      Print("SignalCheck | BuyTrigger=", buyTrigger, " BuyCross=", buyCross, " BuyTrend=", buyTrend,
            " | SellTrigger=", sellTrigger, " SellCross=", sellCross, " SellTrend=", sellTrend);
   }

   bool buyReady  = (buyTrigger  && buyCross  && buyTrend);
   bool sellReady = (sellTrigger && sellCross && sellTrend);

   if(buyReady && !sellReady)  return( 1);
   if(sellReady && !buyReady)  return(-1);

   return(0);
}

//+------------------------------------------------------------------+
//| DIRECTIONAL ARROW TEST                                           |
//+------------------------------------------------------------------+
bool IsDirectionalArrow(int shift, int direction)
{
   int bScore = 0, sScore = 0;
   bool sessionOK = false, bullPA = false, bearPA = false;

   ComputeSignalScores(shift, bScore, sScore, sessionOK, bullPA, bearPA);

   if(direction > 0)
      return(sessionOK && bullPA && bScore >= MinConfluence);

   return(sessionOK && bearPA && sScore >= MinConfluence);
}

//+------------------------------------------------------------------+
//| COMPUTE SCORES                                                   |
//+------------------------------------------------------------------+
void ComputeSignalScores(int shift, int &bScore, int &sScore,
                         bool &sessionOK, bool &bullPA, bool &bearPA)
{
   bScore = 0;
   sScore = 0;

   datetime bt = iTime(NULL, PERIOD_M5, shift);
   if(bt <= 0)
   {
      sessionOK = false; bullPA = false; bearPA = false;
      return;
   }

   // HTF trend voters
   AddHTFVote(PERIOD_W1, UseWeeklyTrend, bt, bScore, sScore);
   AddHTFVote(PERIOD_D1, UseDailyTrend,  bt, bScore, sScore);
   AddHTFVote(PERIOD_H4, UseH4Trend,     bt, bScore, sScore);
   AddHTFVote(PERIOD_H1, UseH1Trend,     bt, bScore, sScore);

   // RSI
   double rsi = iRSI(NULL, PERIOD_M5, RSI_Period, PRICE_CLOSE, shift);
   if(rsi > RSI_BullLevel) bScore++;
   else if(rsi < RSI_BearLevel) sScore++;

   // Stochastic
   double stoch = iStochastic(NULL, PERIOD_M5, Stoch_K, Stoch_D, Stoch_Slowing,
                              MODE_SMA, 0, MODE_MAIN, shift);
   if(stoch > 50.0) bScore++;
   else sScore++;

   // CCI (relaxed thresholds for more signals)
   double cci = iCCI(NULL, PERIOD_M5, CCI_Period, PRICE_TYPICAL, shift);
   if(cci > CCI_BullLevel) bScore++;
   else if(cci < CCI_BearLevel) sScore++;

   sessionOK = !UseSessionFilter || IsTradingSession(bt);

   bool bullCandle = (iClose(NULL, PERIOD_M5, shift) > iOpen(NULL, PERIOD_M5, shift));
   bool bearCandle = (iClose(NULL, PERIOD_M5, shift) < iOpen(NULL, PERIOD_M5, shift));

   bool bullEngulf = false;
   bool bearEngulf = false;

   if(shift + 1 < Bars)
   {
      bullEngulf = bullCandle &&
         iClose(NULL, PERIOD_M5, shift) > iOpen(NULL, PERIOD_M5, shift + 1) &&
         iOpen(NULL, PERIOD_M5, shift)  < iClose(NULL, PERIOD_M5, shift + 1);
      bearEngulf = bearCandle &&
         iClose(NULL, PERIOD_M5, shift) < iOpen(NULL, PERIOD_M5, shift + 1) &&
         iOpen(NULL, PERIOD_M5, shift)  > iClose(NULL, PERIOD_M5, shift + 1);
   }

   bullPA = (!RequireCandle || bullCandle || bullEngulf);
   bearPA = (!RequireCandle || bearCandle || bearEngulf);
}

//+------------------------------------------------------------------+
//| ADD HTF VOTE                                                     |
//+------------------------------------------------------------------+
void AddHTFVote(ENUM_TIMEFRAMES tf, bool enabled, datetime bt,
                int &bScore, int &sScore)
{
   if(!enabled) return;
   int s = GetClosedHTFShift(tf, bt);
   if(s < 0) return;
   double fast = iMA(NULL, tf, TrendFastEMA, 0, MODE_EMA, PRICE_CLOSE, s);
   double slow = iMA(NULL, tf, TrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE, s);
   if(fast > slow) bScore++;
   else sScore++;
}

//+------------------------------------------------------------------+
//| CLOSED HTF SHIFT                                                 |
//+------------------------------------------------------------------+
int GetClosedHTFShift(ENUM_TIMEFRAMES tf, datetime bt)
{
   int s = iBarShift(NULL, tf, bt, false);
   int total = iBars(NULL, tf);
   if(s < 0 || total <= 0) return(-1);
   s = s + 1;  // Use previous HTF bar
   if(s >= total) return(-1);
   return(s);
}

//+------------------------------------------------------------------+
//| HTF ALIGNMENT                                                    |
//+------------------------------------------------------------------+
bool HTFTrendAligned(int direction, datetime bt)
{
   if(UseWeeklyTrend && !CheckTrendTF(PERIOD_W1, direction, bt)) return(false);
   if(UseDailyTrend  && !CheckTrendTF(PERIOD_D1, direction, bt)) return(false);
   if(UseH4Trend     && !CheckTrendTF(PERIOD_H4, direction, bt)) return(false);
   if(UseH1Trend     && !CheckTrendTF(PERIOD_H1, direction, bt)) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| CHECK SINGLE HTF                                                 |
//+------------------------------------------------------------------+
bool CheckTrendTF(ENUM_TIMEFRAMES tf, int direction, datetime bt)
{
   int s = GetClosedHTFShift(tf, bt);
   if(s < 0) return(false);
   double fast = iMA(NULL, tf, TrendFastEMA, 0, MODE_EMA, PRICE_CLOSE, s);
   double slow = iMA(NULL, tf, TrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE, s);
   if(direction > 0) return(fast > slow);
   return(fast < slow);
}

//+------------------------------------------------------------------+
//| RECENT EMA CROSS                                                 |
//+------------------------------------------------------------------+
bool HasRecentCross(int direction)
{
   for(int shift = 1; shift <= CrossLookbackBars; shift++)
   {
      if(shift + 1 >= Bars) break;
      double f1 = iMA(NULL, PERIOD_M5, EntryFastEMA, 0, MODE_EMA, PRICE_CLOSE, shift);
      double s1 = iMA(NULL, PERIOD_M5, EntrySlowEMA, 0, MODE_EMA, PRICE_CLOSE, shift);
      double f2 = iMA(NULL, PERIOD_M5, EntryFastEMA, 0, MODE_EMA, PRICE_CLOSE, shift + 1);
      double s2 = iMA(NULL, PERIOD_M5, EntrySlowEMA, 0, MODE_EMA, PRICE_CLOSE, shift + 1);
      if(direction > 0 && f2 <= s2 && f1 > s1) return(true);
      if(direction < 0 && f2 >= s2 && f1 < s1) return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| EMA ALIGNED                                                      |
//+------------------------------------------------------------------+
bool EntryEMAAligned(int direction, int shift)
{
   double fast = iMA(NULL, PERIOD_M5, EntryFastEMA, 0, MODE_EMA, PRICE_CLOSE, shift);
   double slow = iMA(NULL, PERIOD_M5, EntrySlowEMA, 0, MODE_EMA, PRICE_CLOSE, shift);
   if(direction > 0) return(fast > slow);
   return(fast < slow);
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

   // WIDE stop + TIGHT TP = high win rate (MC optimized)
   double stopPts = MathMax((double)MinStopBufferPoints,
                            MathMax(spreadPts * 1.5, atrPts * StopATRMult));
   stopPts = MathMax(stopPts, minDist);

   double tpPts = MathMax(stopPts * TakeProfitRR, minDist);

   double lots = CalculateLots(stopPts, tpPts);
   if(lots <= 0.0)
   {
      Print("Trade skipped: lot calculation returned 0.");
      return;
   }

   double price = (direction > 0 ? Ask : Bid);
   double sl    = (direction > 0 ? price - stopPts * Point : price + stopPts * Point);
   double tp    = (direction > 0 ? price + tpPts * Point   : price - tpPts * Point);

   price = NormalizeDouble(price, Digits);
   sl    = NormalizeDouble(sl, Digits);
   tp    = NormalizeDouble(tp, Digits);

   int type = (direction > 0 ? OP_BUY : OP_SELL);
   string comment = "NCI_v2.0_MC";

   color arrowClr = (direction > 0 ? clrLime : clrRed);

   int ticket = OrderSend(Symbol(), type, lots, price, SlippagePoints,
                          sl, tp, comment, MagicNumber,
                          (datetime)0, arrowClr);

   if(ticket > 0)
   {
      g_lastEntryTime = TimeCurrent();
      SaveTradeState(ticket, stopPts);

      string dirStr = (direction > 0 ? "BUY" : "SELL");
      Print("Order opened. Ticket=", ticket, " Dir=", dirStr,
            " Lots=", DoubleToString(lots, 2),
            " SLpts=", DoubleToString(stopPts, 1),
            " TPpts=", DoubleToString(tpPts, 1),
            " RR=", DoubleToString(TakeProfitRR, 2));

      PostMonitor("event=ENTRY;symbol=" + Symbol() +
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
//| LOT CALC                                                         |
//+------------------------------------------------------------------+
double CalculateLots(double stopPts, double tpPts)
{
   double pointValue = PointValuePerLot();
   if(pointValue <= 0.0 || stopPts <= 0.0 || tpPts <= 0.0)
      return(0.0);

   double targetProfit = MathMax(TargetProfitMin,
                                 MathMin(TargetProfitPerTrade, TargetProfitMax));
   double lotsByTarget = targetProfit / (tpPts * pointValue);

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
//| TRADE MANAGEMENT (v2.0 - Quick BE + Trail for high WR)           |
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

      // Quick break-even lock (key to high WR)
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

      // ATR trail to lock in profits
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

      // Time stop
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
//| SESSION FILTER                                                   |
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
//| CONFIG SCORE                                                     |
//+------------------------------------------------------------------+
int GetConfiguredMaxScore()
{
   int score = 3; // RSI + Stoch + CCI
   if(UseWeeklyTrend) score++;
   if(UseDailyTrend)  score++;
   if(UseH4Trend)     score++;
   if(UseH1Trend)     score++;
   return(score);
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

   Print("========== NCI SCALP v2.0 [MC OPTIMIZED] ==========");
   Print("Symbol=", Symbol(), " | Trades=", trades, " | Wins=", wins,
         " | Losses=", losses, " | WinRate=", DoubleToString(winRate, 2), "%");
   Print("NetProfit=", DoubleToString(netProfit, 2), " | PF=", DoubleToString(pf, 2),
         " | AvgWin=", DoubleToString(avgWin, 2), " | AvgLoss=", DoubleToString(avgLoss, 2));
   Print("StopATR=", StopATRMult, " | TP_RR=", TakeProfitRR, " | MinConf=", MinConfluence);
   Print("===================================================");
}
//+------------------------------------------------------------------+
