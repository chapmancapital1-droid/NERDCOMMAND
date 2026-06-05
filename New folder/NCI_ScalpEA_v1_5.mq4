//+------------------------------------------------------------------+
//|                         NCI_ScalpEA_v1_5.mq4                     |
//| Expert Advisor using NCI ScalpCore v1.5 shared signal engine     |
//| MACD + Volume Spike + High/Low Breakout scalping system          |
//|                                                                   |
//| REQUIRES: NCI_ScalpCore_v1_5.mqh in MQL4/Include/ folder        |
//+------------------------------------------------------------------+
#property strict
#property copyright "NCI Scalp System v1.5"
#property version   "1.50"

//====================================================================
// GENERAL SETTINGS
//====================================================================
extern string GeneralSettings = "===== General =====";
extern int    MagicNumber = 260517;
extern bool   EnableTrading = true;
extern bool   AllowBuy = true;
extern bool   AllowSell = true;
extern bool   OneTradePerCandle = true;
extern int    MaxOpenTradesPerSymbol = 1;

//====================================================================
// SHARED SIGNAL SETTINGS (must match indicator settings)
//====================================================================
extern string SignalSettings = "===== Signal Settings =====";
extern int    InpMinScore = 65;
extern int    InpDMAPeriod = 25;
extern int    InpDMAShift = 0;
extern int    InpBreakoutLookback = 2;
extern bool   InpRequireStructureBreak = true;
extern bool   InpRequireMACD = true;
extern bool   InpRequireCandle = true;

//====================================================================
// MACD / OsMA
//====================================================================
extern string MACDSettings = "===== MACD / OsMA =====";
extern int    InpMacdFast = 12;
extern int    InpMacdSlow = 26;
extern int    InpMacdSignal = 9;
extern bool   InpUseOsMAForHistogram = true;
extern bool   InpRequireMacdZeroSide = false;

//====================================================================
// VOLUME
//====================================================================
extern string VolumeSettings = "===== Volume =====";
extern bool   InpUseVolumeFilter = true;
extern bool   InpRequireVolumeSpike = true;
extern int    InpVolumeLookback = 20;
extern double InpVolumeSpikeRatio = 1.50;
extern bool   InpUseVolumeZScore = false;
extern double InpVolumeZThreshold = 1.50;

//====================================================================
// CANDLE / EXHAUSTION
//====================================================================
extern string CandleSettings = "===== Candle / Exhaustion =====";
extern double InpCloseNearHighLowPct = 35.0;
extern bool   InpUseExhaustionFilter = true;
extern int    InpAtrPeriod = 14;
extern double InpMaxSignalCandleATR = 2.20;
extern double InpMaxOppositeWickPct = 55.0;

//====================================================================
// HIGHER TIMEFRAME
//====================================================================
extern string HTFSettings = "===== Higher Timeframe =====";
extern bool   InpUseHTFConfirm = false;
extern int    InpHTFTimeframe = PERIOD_H1;
extern int    InpHTFEmaPeriod = 21;
extern bool   InpUseClosedHTFOnly = true;

//====================================================================
// ZIGZAG
//====================================================================
extern string ZigZagSettings = "===== ZigZag Optional =====";
extern bool   InpUseZigZagFilter = false;
extern string InpZigZagName = "Examples\\ZigZag";
extern int    InpZigZagDepth = 12;
extern int    InpZigZagDeviation = 5;
extern int    InpZigZagBackstep = 3;
extern int    InpZigZagLookback = 100;
extern int    InpZigZagMode = 1;
extern double InpZigZagMinDistancePips = 5.0;

//====================================================================
// RISK MANAGEMENT
//====================================================================
extern string RiskSettings = "===== Risk Management =====";
extern bool   UseRiskPercent = true;
extern double RiskPercent = 0.5;
extern double FixedLots = 0.01;
extern double MaxDailyLossPercent = 3.0;
extern int    MaxTradesPerDay = 5;

//====================================================================
// STOPS AND TARGETS
//====================================================================
extern string StopSettings = "===== Stops & Targets =====";
extern int    StopLossMode = 1;
extern double FixedSLPips = 10.0;
extern double ATR_SL_Multiplier = 1.2;
extern int    SwingLookback = 5;
extern double SwingBufferPips = 2.0;
extern int    TakeProfitMode = 1;
extern double FixedTPPips = 12.0;
extern double RewardRiskRatio = 1.3;
extern double ATR_TP_Multiplier = 2.0;

//====================================================================
// TRADE MANAGEMENT
//====================================================================
extern string TradeMgmtSettings = "===== Trade Management =====";
extern bool   UseBreakEven = true;
extern double BreakEvenAfterR = 0.8;
extern double BreakEvenLockPips = 1.0;
extern bool   UseTrailingStop = false;
extern double TrailStartPips = 8.0;
extern double TrailStepPips = 2.0;

//====================================================================
// SPREAD AND SESSION
//====================================================================
extern string FilterSettings = "===== Spread & Session =====";
extern double MaxSpreadPips = 2.0;
extern int    SlippagePips = 3;
extern bool   UseSessionFilter = true;
extern int    SessionStartHour = 7;
extern int    SessionEndHour = 20;
extern bool   AvoidFridayClose = true;
extern int    FridayCloseHour = 20;

//====================================================================
// COOLDOWN
//====================================================================
extern string CooldownSettings = "===== Cooldown =====";
extern int    CooldownBarsAfterTrade = 2;
extern int    CooldownBarsAfterLoss = 4;

//====================================================================
// DEBUG
//====================================================================
extern string DebugSettings = "===== Debug =====";
extern bool   ShowChartComment = true;
extern bool   PrintDebugLogs = true;

//====================================================================
// Include the shared signal engine AFTER extern declarations
//====================================================================
#include <NCI_ScalpCore_v1_5.mqh>

//====================================================================
// Global state
//====================================================================
datetime g_lastBarTime = 0;
datetime g_lastTradeBarTime = 0;
datetime g_lastLossBarTime = 0;
int      g_tradesToday = 0;
datetime g_lastDayChecked = 0;
double   g_dailyStartBalance = 0.0;

//+------------------------------------------------------------------+
// Calculate lot size
//+------------------------------------------------------------------+
double CalcLotSize(double slPips)
{
   double pip = NCI_PipPoint();
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);

   if(lotStep <= 0.0) lotStep = 0.01;
   if(minLot <= 0.0) minLot = 0.01;

   if(!UseRiskPercent)
      return NormalizeDouble(MathMax(minLot, FixedLots), 2);

   double riskAmount = AccountBalance() * RiskPercent / 100.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0 || slPips <= 0.0)
      return minLot;

   double slPrice = slPips * pip;
   double lots = 0.0;
   if(tickSize > 0.0 && tickValue > 0.0)
      lots = riskAmount / (slPrice / tickSize * tickValue);

   if(lots <= 0.0) return minLot;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
// Calculate stop loss price
//+------------------------------------------------------------------+
double CalcSL(int direction, double entryPrice, int signalShift)
{
   double pip = NCI_PipPoint();
   double sl = 0.0;

   if(StopLossMode == 0)
   {
      if(direction == 1) sl = entryPrice - FixedSLPips * pip;
      else               sl = entryPrice + FixedSLPips * pip;
   }
   else if(StopLossMode == 1)
   {
      double atr = iATR(Symbol(), 0, InpAtrPeriod, signalShift);
      if(atr <= 0.0) atr = FixedSLPips * pip;
      if(direction == 1) sl = entryPrice - atr * ATR_SL_Multiplier;
      else               sl = entryPrice + atr * ATR_SL_Multiplier;
   }
   else
   {
      if(direction == 1)
      {
         double swingLow = NCI_RecentLow(signalShift, SwingLookback);
         sl = swingLow - SwingBufferPips * pip;
      }
      else
      {
         double swingHigh = NCI_RecentHigh(signalShift, SwingLookback);
         sl = swingHigh + SwingBufferPips * pip;
      }
   }

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double minDist = stopLevel + pip;

   if(direction == 1 && entryPrice - sl < minDist)
      sl = entryPrice - minDist;
   if(direction == -1 && sl - entryPrice < minDist)
      sl = entryPrice + minDist;

   return NormalizeDouble(sl, Digits);
}

//+------------------------------------------------------------------+
// Calculate take profit price
//+------------------------------------------------------------------+
double CalcTP(int direction, double entryPrice, double slPrice, int signalShift)
{
   double pip = NCI_PipPoint();
   double risk = MathAbs(entryPrice - slPrice);
   double tp = 0.0;

   if(TakeProfitMode == 0)
   {
      if(direction == 1) tp = entryPrice + FixedTPPips * pip;
      else               tp = entryPrice - FixedTPPips * pip;
   }
   else if(TakeProfitMode == 1)
   {
      if(direction == 1) tp = entryPrice + risk * RewardRiskRatio;
      else               tp = entryPrice - risk * RewardRiskRatio;
   }
   else
   {
      double atr = iATR(Symbol(), 0, InpAtrPeriod, signalShift);
      if(atr <= 0.0) atr = FixedTPPips * pip;
      if(direction == 1) tp = entryPrice + atr * ATR_TP_Multiplier;
      else               tp = entryPrice - atr * ATR_TP_Multiplier;
   }

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double minDist = stopLevel + pip;

   if(direction == 1 && tp - entryPrice < minDist)
      tp = entryPrice + minDist;
   if(direction == -1 && entryPrice - tp < minDist)
      tp = entryPrice - minDist;

   return NormalizeDouble(tp, Digits);
}

//+------------------------------------------------------------------+
// Session filter
//+------------------------------------------------------------------+
bool InSession()
{
   if(!UseSessionFilter) return true;
   int h = TimeHour(TimeCurrent());
   int dow = TimeDayOfWeek(TimeCurrent());
   if(dow == 0 || dow == 6) return false;
   if(AvoidFridayClose && dow == 5 && h >= FridayCloseHour) return false;
   if(SessionStartHour <= SessionEndHour)
      return (h >= SessionStartHour && h < SessionEndHour);
   return (h >= SessionStartHour || h < SessionEndHour);
}

//+------------------------------------------------------------------+
// Spread filter
//+------------------------------------------------------------------+
bool SpreadOk()
{
   double spreadPips = MarketInfo(Symbol(), MODE_SPREAD) * Point / NCI_PipPoint();
   return (spreadPips <= MaxSpreadPips);
}

//+------------------------------------------------------------------+
// Count open trades for this symbol+magic
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
// Check daily loss limit
//+------------------------------------------------------------------+
bool DailyLossOk()
{
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   if(g_lastDayChecked != today)
   {
      g_lastDayChecked = today;
      g_tradesToday = 0;
      g_dailyStartBalance = AccountBalance();
   }
   double dailyLoss = g_dailyStartBalance - AccountBalance();
   double maxLoss = g_dailyStartBalance * MaxDailyLossPercent / 100.0;
   if(dailyLoss >= maxLoss)
   {
      if(PrintDebugLogs)
         Print("NCI EA: Daily loss limit reached. Loss=", DoubleToString(dailyLoss, 2),
               " Max=", DoubleToString(maxLoss, 2));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
// Check cooldown
//+------------------------------------------------------------------+
bool CooldownOk()
{
   if(g_lastTradeBarTime == 0) return true;
   int barsSinceTrade = iBarShift(Symbol(), 0, g_lastTradeBarTime, false);
   if(barsSinceTrade < CooldownBarsAfterTrade)
   {
      if(PrintDebugLogs)
         Print("NCI EA: Cooldown after trade. Bars=", barsSinceTrade,
               " Need=", CooldownBarsAfterTrade);
      return false;
   }
   if(g_lastLossBarTime > 0)
   {
      int barsSinceLoss = iBarShift(Symbol(), 0, g_lastLossBarTime, false);
      if(barsSinceLoss < CooldownBarsAfterLoss)
      {
         if(PrintDebugLogs)
            Print("NCI EA: Cooldown after loss. Bars=", barsSinceLoss,
                  " Need=", CooldownBarsAfterLoss);
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
// Place a trade with error handling and retry
//+------------------------------------------------------------------+
bool PlaceTrade(int direction, double sl, double tp, double lots, string reason)
{
   if(!EnableTrading)
   {
      if(PrintDebugLogs) Print("NCI EA: Trading disabled. Would ",
                               direction == 1 ? "BUY" : "SELL",
                               " @ ", DoubleToString(Ask, Digits));
      return false;
   }

   int ticket = -1;
   int retryCount = 3;
   color arrowColor = clrLime;
   if(direction == -1) arrowColor = clrMagenta;

   for(int attempt = 0; attempt < retryCount; attempt++)
   {
      RefreshRates();

      if(direction == 1)
      {
         ticket = OrderSend(Symbol(), OP_BUY, lots, Ask, SlippagePips,
                           sl, tp, "NCI v1.5 BUY", MagicNumber, 0, arrowColor);
      }
      else
      {
         ticket = OrderSend(Symbol(), OP_SELL, lots, Bid, SlippagePips,
                           sl, tp, "NCI v1.5 SELL", MagicNumber, 0, arrowColor);
      }

      if(ticket >= 0)
      {
         if(PrintDebugLogs)
            Print("NCI EA: Trade opened #", ticket,
                  " ", direction == 1 ? "BUY" : "SELL",
                  " Lots=", DoubleToString(lots, 2),
                  " SL=", DoubleToString(sl, Digits),
                  " TP=", DoubleToString(tp, Digits));

         g_lastTradeBarTime = Time[0];
         g_tradesToday++;
         return true;
      }

      int err = GetLastError();
      if(PrintDebugLogs)
         Print("NCI EA: OrderSend error ", err, " attempt ", attempt + 1, "/", retryCount);

      if(err == ERR_TRADE_CONTEXT_BUSY || err == ERR_SERVER_BUSY)
      {
         Sleep(500);
         continue;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
// Break-even management
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   if(!UseBreakEven) return;
   double pip = NCI_PipPoint();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;

      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();

      if(OrderType() == OP_BUY)
      {
         double profit = Bid - openPrice;
         double risk = openPrice - currentSL;
         if(risk <= 0.0) continue;
         double rLevel = profit / risk;
         if(rLevel >= BreakEvenAfterR)
         {
            double newSL = NormalizeDouble(openPrice + BreakEvenLockPips * pip, Digits);
            if(newSL > currentSL)
            {
               double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
               if(Bid - newSL >= stopLevel)
               {
                  if(!OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrBlue))
                  {
                     if(PrintDebugLogs) Print("NCI EA: BreakEven modify failed err=", GetLastError());
                  }
               }
            }
         }
      }
      else if(OrderType() == OP_SELL)
      {
         double profit = openPrice - Ask;
         double risk = currentSL - openPrice;
         if(risk <= 0.0) continue;
         double rLevel = profit / risk;
         if(rLevel >= BreakEvenAfterR)
         {
            double newSL = NormalizeDouble(openPrice - BreakEvenLockPips * pip, Digits);
            if(newSL < currentSL || currentSL == 0.0)
            {
               double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
               if(newSL - Ask >= stopLevel)
               {
                  if(!OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrBlue))
                  {
                     if(PrintDebugLogs) Print("NCI EA: BreakEven modify failed err=", GetLastError());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
// Trailing stop management
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!UseTrailingStop) return;
   double pip = NCI_PipPoint();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;

      double currentSL = OrderStopLoss();

      if(OrderType() == OP_BUY)
      {
         double trailLevel = NormalizeDouble(Bid - TrailStartPips * pip, Digits);
         if(trailLevel > currentSL && trailLevel > OrderOpenPrice())
         {
            double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
            if(Bid - trailLevel >= stopLevel)
            {
               if(currentSL == 0.0 || trailLevel - currentSL >= TrailStepPips * pip)
               {
                  if(!OrderModify(OrderTicket(), OrderOpenPrice(), trailLevel, OrderTakeProfit(), 0, clrBlue))
                  {
                     if(PrintDebugLogs) Print("NCI EA: Trail modify failed err=", GetLastError());
                  }
               }
            }
         }
      }
      else if(OrderType() == OP_SELL)
      {
         double trailLevel = NormalizeDouble(Ask + TrailStartPips * pip, Digits);
         if((trailLevel < currentSL || currentSL == 0.0) && trailLevel < OrderOpenPrice())
         {
            double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
            if(trailLevel - Ask >= stopLevel)
            {
               if(currentSL == 0.0 || currentSL - trailLevel >= TrailStepPips * pip)
               {
                  if(!OrderModify(OrderTicket(), OrderOpenPrice(), trailLevel, OrderTakeProfit(), 0, clrBlue))
                  {
                     if(PrintDebugLogs) Print("NCI EA: Trail modify failed err=", GetLastError());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
// Track closed trades for loss cooldown
//+------------------------------------------------------------------+
void CheckClosedTrades()
{
   static int lastCheckedOrder = 0;

   for(int i = OrdersHistoryTotal() - 1; i >= lastCheckedOrder; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderSymbol() != Symbol()) continue;

      if(OrderCloseTime() > 0 && OrderProfit() < 0.0)
      {
         g_lastLossBarTime = OrderCloseTime();
      }
   }
   lastCheckedOrder = OrdersHistoryTotal();
}

//+------------------------------------------------------------------+
// Update chart comment
//+------------------------------------------------------------------+
void UpdateChartComment(string status, string reason, int buyScore, int sellScore, int signal)
{
   if(!ShowChartComment) return;

   double spreadPips = MarketInfo(Symbol(), MODE_SPREAD) * Point / NCI_PipPoint();
   double ratio = NCI_VolumeRatio(1);
   double z = NCI_VolumeZScore(1);
   int spikeClass = NCI_SpikeClass(1);
   string spikeText = "normal";
   if(spikeClass == 3) spikeText = "EXTREME";
   else if(spikeClass == 2) spikeText = "SPIKE";
   else if(spikeClass == 1) spikeText = "elevated";

   string macdDir = "neutral";
   if(NCI_MacdBull(1)) macdDir = "BULL expand";
   else if(NCI_MacdBear(1)) macdDir = "BEAR expand";
   else if(NCI_MacdDirection(1) == 1) macdDir = "bullish";
   else if(NCI_MacdDirection(1) == -1) macdDir = "bearish";

   string sigText = "WAIT";
   if(signal == 1) sigText = "BUY";
   if(signal == -1) sigText = "SELL";

   string comment = "";
   comment = comment + "=== NCI ScalpEA v1.5 ===\n";
   comment = comment + "Status: " + status + "\n";
   comment = comment + "Signal: " + sigText + "\n";
   comment = comment + "Buy Score: " + IntegerToString(buyScore) + " | Sell Score: " + IntegerToString(sellScore) + "\n";
   comment = comment + "MACD: " + macdDir + "\n";
   comment = comment + "Volume: " + spikeText + " ratio=" + DoubleToString(ratio, 2) + " z=" + DoubleToString(z, 2) + "\n";
   comment = comment + "Spread: " + DoubleToString(spreadPips, 1) + " pips\n";
   comment = comment + "Session: " + (InSession() ? "Active" : "Off-hours") + "\n";
   comment = comment + "Open Trades: " + IntegerToString(CountOpenTrades()) + "\n";
   comment = comment + "Trades Today: " + IntegerToString(g_tradesToday) + "/" + IntegerToString(MaxTradesPerDay) + "\n";
   comment = comment + "Reason: " + reason + "\n";

   Comment(comment);
}

//+------------------------------------------------------------------+
// INIT
//+------------------------------------------------------------------+
int OnInit()
{
   if(PrintDebugLogs)
   {
      Print("NCI ScalpEA v1.5 initialized on ", Symbol(), " ", NCI_TFToString(Period()));
      Print("MagicNumber=", MagicNumber,
            " Risk%=", DoubleToString(RiskPercent, 2),
            " MaxSpread=", DoubleToString(MaxSpreadPips, 1),
            " MinScore=", InpMinScore);
   }
   g_dailyStartBalance = AccountBalance();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
// DEINIT
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(PrintDebugLogs) Print("NCI ScalpEA v1.5 removed. Reason=", reason);
}

//+------------------------------------------------------------------+
// MAIN TICK HANDLER
//+------------------------------------------------------------------+
void OnTick()
{
   ManageBreakEven();
   ManageTrailingStop();
   CheckClosedTrades();

   datetime currentBarTime = Time[0];
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   int minBars = InpDMAPeriod + 10;
   if(InpVolumeLookback + 10 > minBars) minBars = InpVolumeLookback + 10;
   if(InpMacdSlow + InpMacdSignal + 10 > minBars) minBars = InpMacdSlow + InpMacdSignal + 10;

   if(Bars <= minBars + 10)
   {
      if(PrintDebugLogs) Print("NCI EA: Not enough bars. Bars=", Bars);
      return;
   }

   int shift = 1;

   string reason = "";
   int buyScore = 0;
   int sellScore = 0;
   int signal = NCI_BuildSignal(shift, reason, buyScore, sellScore);

   string status = "OK";

   if(!EnableTrading)
      status = "TRADING DISABLED";
   else if(CountOpenTrades() >= MaxOpenTradesPerSymbol)
      status = "MAX OPEN TRADES";
   else if(g_tradesToday >= MaxTradesPerDay)
      status = "MAX TRADES TODAY";
   else if(!DailyLossOk())
      status = "DAILY LOSS LIMIT";
   else if(!InSession())
      status = "OUTSIDE SESSION";
   else if(!SpreadOk())
      status = "SPREAD TOO HIGH";
   else if(!CooldownOk())
      status = "COOLDOWN";
   else if(OneTradePerCandle && g_lastTradeBarTime > 0)
   {
      int barsSince = iBarShift(Symbol(), 0, g_lastTradeBarTime, false);
      if(barsSince < 1)
         status = "ONE TRADE PER CANDLE";
   }

   UpdateChartComment(status, reason, buyScore, sellScore, signal);

   if(status != "OK")
   {
      if(PrintDebugLogs && signal != 0)
         Print("NCI EA: Signal ", signal == 1 ? "BUY" : "SELL",
               " blocked by: ", status, " | ", reason);
      return;
   }

   if(signal == 0) return;

   if(signal == 1 && !AllowBuy)
   {
      if(PrintDebugLogs) Print("NCI EA: BUY signal but AllowBuy=false");
      return;
   }
   if(signal == -1 && !AllowSell)
   {
      if(PrintDebugLogs) Print("NCI EA: SELL signal but AllowSell=false");
      return;
   }

   double entryPrice = Ask;
   if(signal == -1) entryPrice = Bid;

   double sl = CalcSL(signal, entryPrice, shift);
   double tp = CalcTP(signal, entryPrice, sl, shift);

   double slPips = MathAbs(entryPrice - sl) / NCI_PipPoint();
   double lots = CalcLotSize(slPips);

   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   if(lots < minLot)
   {
      if(PrintDebugLogs) Print("NCI EA: Lot size below minimum. Lots=", DoubleToString(lots, 2));
      return;
   }

   if(PrintDebugLogs)
      Print("NCI EA: SIGNAL=", signal == 1 ? "BUY" : "SELL",
            " BuyScore=", buyScore, " SellScore=", sellScore,
            " | Entry=", DoubleToString(entryPrice, Digits),
            " SL=", DoubleToString(sl, Digits),
            " TP=", DoubleToString(tp, Digits),
            " Lots=", DoubleToString(lots, 2),
            " | ", reason);

   PlaceTrade(signal, sl, tp, lots, reason);
}
