//+------------------------------------------------------------------+
//|                        NeuroTrick Pro EA v1.0                    |
//|                        Viktor AI × Michael Chapman               |
//|                                                                  |
//|  ENTRY METHODS:                                                  |
//|  1. AHSE MTF Confluence (W1/D1/H4/H1 EMA alignment)             |
//|  2. HTF Volume Spike Entry (H4/D1 volume anomaly breakout)       |
//|  3. Engulfing + RSI Reversal (Price action sniper)               |
//|  4. EMA Pullback Entry (Trend continuation on retrace)           |
//|  5. CCI Momentum Breakout (CCI crosses zero with trend)          |
//|                                                                  |
//|  PROFIT PROTECTION:                                              |
//|  - Breakeven move at 1:1                                         |
//|  - Trailing stop (ATR-based)                                     |
//|  - Partial close at 50% TP                                       |
//|  - Max drawdown kill switch                                       |
//|                                                                  |
//|  HONEST NOTE: Do not set RiskPercent above 1.5 on live accounts  |
//+------------------------------------------------------------------+
#property copyright "Viktor AI x Michael Chapman - NeuroTrick Pro v1.0"
#property version   "1.00"
#property strict

//===========================================
// MAGIC NUMBER
//===========================================
#define MAGIC_NUMBER 20240601

//===========================================
// INPUTS
//===========================================

extern string  __A__                  = "=== TRADING MODE ===";
extern bool    EnableEntry_AHSE       = true;   // Method 1: MTF Confluence
extern bool    EnableEntry_VolSpike   = true;   // Method 2: HTF Volume Spike
extern bool    EnableEntry_Engulfing  = true;   // Method 3: Engulfing Reversal
extern bool    EnableEntry_Pullback   = true;   // Method 4: EMA Pullback
extern bool    EnableEntry_CCI        = true;   // Method 5: CCI Momentum

extern string  __B__                  = "=== RISK MANAGEMENT ===";
extern double  RiskPercent            = 1.0;    // % of balance risked per trade
extern double  MaxLotSize             = 0.20;
extern double  MinLotSize             = 0.01;
extern double  MaxDrawdownPercent     = 20.0;   // Kill switch - stop trading at this DD%
extern int     MaxOpenTrades          = 3;      // Max concurrent trades

extern string  __C__                  = "=== STOP / TARGET ===";
extern double  ATR_SL_Multiplier      = 1.5;    // SL = ATR x this
extern double  RR_Ratio               = 2.0;    // TP = SL x this (1:2 default)
extern int     ATR_Period             = 14;
extern bool    UseBreakeven           = true;   // Move SL to BE at 1:1
extern bool    UseTrailingStop        = true;   // Trail after breakeven
extern double  TrailATR_Multiplier    = 1.0;    // Trail distance = ATR x this
extern bool    UsePartialClose        = true;   // Close 50% at half TP
extern bool    PartialCloseDone       = false;  // Internal flag (don't change)

extern string  __D__                  = "=== HTF FILTERS ===";
extern int     FastEMA                = 20;
extern int     SlowEMA                = 50;
extern int     RSI_Period             = 14;
extern double  RSI_OB                 = 65.0;  // Overbought threshold
extern double  RSI_OS                 = 35.0;  // Oversold threshold
extern int     CCI_Period             = 20;
extern int     Stoch_K                = 14;
extern int     Stoch_D                = 3;
extern int     Stoch_Slow             = 3;
extern int     MinConfluence          = 4;     // 4-6 recommended

extern string  __E__                  = "=== VOLUME SPIKE SETTINGS ===";
extern int     VolumeLookback         = 20;    // Bars to avg volume over
extern double  VolumeSpike_Mult       = 1.8;  // Spike = X times average volume
extern int     VolSpike_TF            = PERIOD_H4; // Timeframe to detect spikes on

extern string  __F__                  = "=== SESSION FILTER ===";
extern bool    UseSessionFilter       = true;
extern int     GMT_Offset             = 2;
// Allowed hours (server time after GMT offset)
extern int     Session_Start1         = 8;   // London open
extern int     Session_End1           = 17;  // London close
extern int     Session_Start2         = 13;  // NY open (overlap)
extern int     Session_End2           = 22;  // NY close

extern string  __G__                  = "=== DISPLAY ===";
extern bool    ShowPanel              = true;
extern int     Panel_X                = 15;
extern int     Panel_Y                = 25;

//===========================================
// GLOBAL STATE
//===========================================
double g_initialBalance   = 0;
double g_peakBalance      = 0;
int    g_totalTrades      = 0;
int    g_wins             = 0;
int    g_losses           = 0;
bool   g_killSwitch       = false;
string g_lastSignal       = "Scanning...";
string g_lastEntry        = "None";

//===========================================
// INIT
//===========================================
int OnInit()
{
   g_initialBalance = AccountBalance();
   g_peakBalance    = AccountBalance();
   g_killSwitch     = false;

   Print("NeuroTrick Pro EA v1.0 Started | Balance: $", DoubleToString(g_initialBalance, 2));
   return(INIT_SUCCEEDED);
}

//===========================================
// DEINIT
//===========================================
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "NTP_");
   Comment("");
}

//===========================================
// MAIN TICK
//===========================================
void OnTick()
{
   // Update peak balance for drawdown tracking
   if(AccountEquity() > g_peakBalance) g_peakBalance = AccountEquity();

   // KILL SWITCH CHECK
   double currentDD = (g_peakBalance - AccountEquity()) / g_peakBalance * 100.0;
   if(currentDD >= MaxDrawdownPercent)
   {
      g_killSwitch = true;
      g_lastSignal = "KILL SWITCH - Max DD Hit";
      if(ShowPanel) DrawPanel();
      return;
   }
   g_killSwitch = false;

   // MANAGE OPEN TRADES (Breakeven, Trail, Partial)
   ManageOpenTrades();

   // COUNT OPEN TRADES
   if(CountOpenTrades() >= MaxOpenTrades)
   {
      g_lastSignal = "Max trades open (" + IntegerToString(MaxOpenTrades) + ")";
      if(ShowPanel) DrawPanel();
      return;
   }

   // SESSION CHECK
   if(UseSessionFilter && !IsActiveSession())
   {
      g_lastSignal = "Outside session";
      if(ShowPanel) DrawPanel();
      return;
   }

   // Only check on new bar (prevents multiple entries same candle)
   static datetime lastBar = 0;
   if(Time[0] == lastBar)
   {
      if(ShowPanel) DrawPanel();
      return;
   }
   lastBar = Time[0];

   //------------------------------------------
   // RUN ALL ENTRY METHODS
   //------------------------------------------
   int signal = 0; // 1=Buy, -1=Sell, 0=None

   // METHOD 1: AHSE MTF Confluence
   if(EnableEntry_AHSE && signal == 0)
   {
      signal = GetAHSESignal();
      if(signal != 0) g_lastEntry = "AHSE MTF Confluence";
   }

   // METHOD 2: HTF Volume Spike
   if(EnableEntry_VolSpike && signal == 0)
   {
      signal = GetVolumeSpikeSignal();
      if(signal != 0) g_lastEntry = "HTF Volume Spike";
   }

   // METHOD 3: Engulfing Reversal
   if(EnableEntry_Engulfing && signal == 0)
   {
      signal = GetEngulfingSignal();
      if(signal != 0) g_lastEntry = "Engulfing Reversal";
   }

   // METHOD 4: EMA Pullback
   if(EnableEntry_Pullback && signal == 0)
   {
      signal = GetPullbackSignal();
      if(signal != 0) g_lastEntry = "EMA Pullback";
   }

   // METHOD 5: CCI Momentum
   if(EnableEntry_CCI && signal == 0)
   {
      signal = GetCCISignal();
      if(signal != 0) g_lastEntry = "CCI Momentum";
   }

   //------------------------------------------
   // EXECUTE TRADE
   //------------------------------------------
   if(signal == 1)
   {
      ExecuteTrade(OP_BUY);
      g_lastSignal = "BUY executed via " + g_lastEntry;
   }
   else if(signal == -1)
   {
      ExecuteTrade(OP_SELL);
      g_lastSignal = "SELL executed via " + g_lastEntry;
   }
   else
   {
      g_lastSignal = "No signal - " + g_lastEntry;
   }

   if(ShowPanel) DrawPanel();
}

//===========================================
// METHOD 1: AHSE MTF CONFLUENCE
// All 4 HTFs must align + RSI + Stoch
//===========================================
int GetAHSESignal()
{
   int buyScore = 0, sellScore = 0;

   // Weekly
   double w1f = iMA(NULL,PERIOD_W1,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double w1s = iMA(NULL,PERIOD_W1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   if(w1f > w1s) buyScore++; else sellScore++;

   // Daily
   double d1f = iMA(NULL,PERIOD_D1,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double d1s = iMA(NULL,PERIOD_D1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   if(d1f > d1s) buyScore++; else sellScore++;

   // H4
   double h4f = iMA(NULL,PERIOD_H4,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double h4s = iMA(NULL,PERIOD_H4,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   if(h4f > h4s) buyScore++; else sellScore++;

   // H1
   double h1f = iMA(NULL,PERIOD_H1,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double h1s = iMA(NULL,PERIOD_H1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   if(h1f > h1s) buyScore++; else sellScore++;

   // RSI
   double rsi = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);
   if(rsi > 50 && rsi < RSI_OB) buyScore++;
   else if(rsi < 50 && rsi > RSI_OS) sellScore++;

   // Stochastic
   double stoch = iStochastic(NULL,0,Stoch_K,Stoch_D,Stoch_Slow,MODE_SMA,0,MODE_MAIN,1);
   if(stoch > 50 && stoch < 80) buyScore++;
   else if(stoch < 50 && stoch > 20) sellScore++;

   // Current chart EMA direction (entry timeframe)
   double cf = iMA(NULL,0,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double cs = iMA(NULL,0,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   bool chartBull = (cf > cs);
   bool chartBear = (cf < cs);

   if(buyScore  >= MinConfluence && chartBull) return(1);
   if(sellScore >= MinConfluence && chartBear)  return(-1);
   return(0);
}

//===========================================
// METHOD 2: HTF VOLUME SPIKE ENTRY
// Detects abnormal volume on H4/D1 then
// trades the breakout direction
//===========================================
int GetVolumeSpikeSignal()
{
   // Calculate average volume on HTF
   double avgVol = 0;
   for(int v = 1; v <= VolumeLookback; v++)
      avgVol += (double)iVolume(NULL, VolSpike_TF, v);
   avgVol /= VolumeLookback;

   double currentVol = (double)iVolume(NULL, VolSpike_TF, 1);

   // Is this a spike?
   if(currentVol < avgVol * VolumeSpike_Mult) return(0);

   // Confirm direction with D1 trend
   double d1f = iMA(NULL,PERIOD_D1,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double d1s = iMA(NULL,PERIOD_D1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   bool d1Bull = (d1f > d1s);

   // Confirm spike candle direction on HTF
   double htfOpen  = iOpen(NULL,  VolSpike_TF, 1);
   double htfClose = iClose(NULL, VolSpike_TF, 1);
   bool spikeBull = (htfClose > htfOpen);
   bool spikeBear = (htfClose < htfOpen);

   // RSI not extreme
   double rsi = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);

   if(spikeBull && d1Bull && rsi < RSI_OB) return(1);
   if(spikeBear && !d1Bull && rsi > RSI_OS) return(-1);
   return(0);
}

//===========================================
// METHOD 3: ENGULFING REVERSAL
// Bullish/Bearish engulfing at key EMA level
// Must be oversold/overbought on RSI
//===========================================
int GetEngulfingSignal()
{
   // Candle data
   double o1 = Open[1],  c1 = Close[1];
   double o2 = Open[2],  c2 = Close[2];

   bool bullEngulf = (c1 > o1) && (c2 < o2) && // Current bull, prev bear
                     (c1 > o2) && (o1 < c2);    // Engulfs previous

   bool bearEngulf = (c1 < o1) && (c2 > o2) && // Current bear, prev bull
                     (c1 < o2) && (o1 > c2);    // Engulfs previous

   double rsi = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);

   // Must be near Fast EMA (pullback to value)
   double ema = iMA(NULL,0,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double atr = iATR(NULL,0,ATR_Period,1);
   bool nearEMA = (MathAbs(Close[1] - ema) < atr * 0.5);

   // D1 trend alignment
   double d1f = iMA(NULL,PERIOD_D1,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double d1s = iMA(NULL,PERIOD_D1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   bool d1Bull = (d1f > d1s);

   if(bullEngulf && rsi < 45 && nearEMA && d1Bull) return(1);
   if(bearEngulf && rsi > 55 && nearEMA && !d1Bull) return(-1);
   return(0);
}

//===========================================
// METHOD 4: EMA PULLBACK (TREND CONTINUATION)
// Price pulls back to FastEMA in uptrend
// then bounces — enter in trend direction
//===========================================
int GetPullbackSignal()
{
   double ema_fast = iMA(NULL,0,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double ema_slow = iMA(NULL,0,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double atr = iATR(NULL,0,ATR_Period,1);

   bool uptrend = (ema_fast > ema_slow);
   bool dntrend = (ema_fast < ema_slow);

   // Pullback: price dipped near fast EMA then closed above it
   bool pullbackBuy  = uptrend &&
                       (Low[1]  < ema_fast + atr * 0.3) &&
                       (Close[1] > ema_fast) &&
                       (Close[1] > Open[1]);

   bool pullbackSell = dntrend &&
                       (High[1] > ema_fast - atr * 0.3) &&
                       (Close[1] < ema_fast) &&
                       (Close[1] < Open[1]);

   // H4 must agree
   double h4f = iMA(NULL,PERIOD_H4,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double h4s = iMA(NULL,PERIOD_H4,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   bool h4Bull = (h4f > h4s);

   double rsi = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,1);

   if(pullbackBuy  && h4Bull && rsi > 40 && rsi < 65)  return(1);
   if(pullbackSell && !h4Bull && rsi < 60 && rsi > 35) return(-1);
   return(0);
}

//===========================================
// METHOD 5: CCI MOMENTUM BREAKOUT
// CCI crosses zero line with D1 trend
// + price closes above/below slow EMA
//===========================================
int GetCCISignal()
{
   double cci1 = iCCI(NULL,0,CCI_Period,PRICE_TYPICAL,1);
   double cci2 = iCCI(NULL,0,CCI_Period,PRICE_TYPICAL,2);

   bool cciBullCross = (cci1 > 0 && cci2 <= 0);  // Just crossed above zero
   bool cciBearCross = (cci1 < 0 && cci2 >= 0);  // Just crossed below zero

   // CCI on H4 must also be positive/negative
   double h4cci = iCCI(NULL,PERIOD_H4,CCI_Period,PRICE_TYPICAL,1);

   // D1 trend
   double d1f = iMA(NULL,PERIOD_D1,FastEMA,0,MODE_EMA,PRICE_CLOSE,0);
   double d1s = iMA(NULL,PERIOD_D1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,0);
   bool d1Bull = (d1f > d1s);

   // Price closed above slow EMA
   double sema = iMA(NULL,0,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   bool priceAbove = (Close[1] > sema);
   bool priceBelow = (Close[1] < sema);

   if(cciBullCross && h4cci > 0 && d1Bull  && priceAbove) return(1);
   if(cciBearCross && h4cci < 0 && !d1Bull && priceBelow) return(-1);
   return(0);
}

//===========================================
// EXECUTE TRADE
//===========================================
void ExecuteTrade(int orderType)
{
   double atr   = iATR(NULL, 0, ATR_Period, 1);
   double slDist = NormalizeDouble(atr * ATR_SL_Multiplier, Digits);
   double tpDist = NormalizeDouble(slDist * RR_Ratio, Digits);

   double price, sl, tp;

   if(orderType == OP_BUY)
   {
      price = Ask;
      sl    = NormalizeDouble(price - slDist, Digits);
      tp    = NormalizeDouble(price + tpDist, Digits);
   }
   else
   {
      price = Bid;
      sl    = NormalizeDouble(price + slDist, Digits);
      tp    = NormalizeDouble(price - tpDist, Digits);
   }

   double lots = CalcLotSize(slDist);
   if(lots <= 0) return;

   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   if(spread > 30) // Avoid high spread moments
   {
      g_lastSignal = "Signal blocked - spread too high (" + IntegerToString(spread) + ")";
      return;
   }

   int ticket = OrderSend(Symbol(), orderType, lots, price, 3, sl, tp,
                          "NTPro_" + g_lastEntry, MAGIC_NUMBER, 0,
                          orderType == OP_BUY ? clrLime : clrRed);

   if(ticket > 0)
   {
      g_totalTrades++;
      Print("NeuroTrick Pro: ", (orderType==OP_BUY?"BUY":"SELL"),
            " | Lots:", DoubleToString(lots,2),
            " | SL:", DoubleToString(sl,Digits),
            " | TP:", DoubleToString(tp,Digits),
            " | Entry:", g_lastEntry);
   }
   else
   {
      Print("OrderSend failed. Error: ", GetLastError(),
            " | Type:", orderType, " | Price:", price,
            " | SL:", sl, " | TP:", tp, " | Lots:", lots);
   }
}

//===========================================
// MANAGE OPEN TRADES
// Breakeven, Trailing, Partial Close
//===========================================
void ManageOpenTrades()
{
   double atr = iATR(NULL, 0, ATR_Period, 1);

   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MAGIC_NUMBER) continue;
      if(OrderSymbol() != Symbol()) continue;

      double entry  = OrderOpenPrice();
      double sl     = OrderStopLoss();
      double tp     = OrderTakeProfit();
      int    type   = OrderType();
      int    ticket = OrderTicket();
      double lots   = OrderLots();

      double slDist = MathAbs(tp - entry) / RR_Ratio; // Recalculate original SL dist

      //--- PARTIAL CLOSE at 50% TP ---
      if(UsePartialClose)
      {
         double halfTP = (type == OP_BUY) ?
                         entry + slDist * RR_Ratio * 0.5 :
                         entry - slDist * RR_Ratio * 0.5;

         bool partialHit = (type == OP_BUY  && Bid >= halfTP) ||
                           (type == OP_SELL && Ask <= halfTP);

         if(partialHit && lots > MinLotSize * 2)
         {
            double closeLots = NormalizeDouble(lots * 0.5, 2);
            if(closeLots >= MinLotSize)
            {
               OrderClose(ticket, closeLots,
                          type == OP_BUY ? Bid : Ask, 3, clrYellow);
               g_wins++; // Count partial as win
            }
         }
      }

      //--- BREAKEVEN ---
      if(UseBreakeven)
      {
         bool beNeeded = false;
         double newSL  = sl;

         if(type == OP_BUY && sl < entry && Bid >= entry + slDist)
         {
            newSL    = entry + (2 * Point); // Just above entry
            beNeeded = true;
         }
         else if(type == OP_SELL && sl > entry && Ask <= entry - slDist)
         {
            newSL    = entry - (2 * Point);
            beNeeded = true;
         }

         if(beNeeded)
            OrderModify(ticket, entry, NormalizeDouble(newSL, Digits), tp, 0, clrDodgerBlue);
      }

      //--- TRAILING STOP (ATR-based) ---
      if(UseTrailingStop)
      {
         double trailDist = atr * TrailATR_Multiplier;
         double newTrailSL = sl;
         bool   trailNeeded = false;

         if(type == OP_BUY)
         {
            double trailLevel = Bid - trailDist;
            if(trailLevel > sl && Bid > entry + slDist) // Only trail after breakeven
            {
               newTrailSL = NormalizeDouble(trailLevel, Digits);
               trailNeeded = true;
            }
         }
         else if(type == OP_SELL)
         {
            double trailLevel = Ask + trailDist;
            if(trailLevel < sl && Ask < entry - slDist)
            {
               newTrailSL = NormalizeDouble(trailLevel, Digits);
               trailNeeded = true;
            }
         }

         if(trailNeeded)
            OrderModify(ticket, entry, newTrailSL, tp, 0, clrOrange);
      }
   }
}

//===========================================
// LOT SIZE CALCULATOR
//===========================================
double CalcLotSize(double slPips)
{
   if(slPips <= 0) return(MinLotSize);

   double riskAmt   = AccountBalance() * (RiskPercent / 100.0);
   double pipValue  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double pipsInSL  = slPips / tickSize;

   double lots = riskAmt / (pipsInSL * pipValue);
   lots = MathMax(MinLotSize, MathMin(MaxLotSize, NormalizeDouble(lots, 2)));
   return(lots);
}

//===========================================
// SESSION FILTER
//===========================================
bool IsActiveSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent() + GMT_Offset * 3600, dt);
   int h = dt.hour;

   bool sess1 = (h >= Session_Start1 && h < Session_End1);
   bool sess2 = (h >= Session_Start2 && h < Session_End2);
   return(sess1 || sess2);
}

//===========================================
// COUNT OPEN TRADES
//===========================================
int CountOpenTrades()
{
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) &&
         OrderMagicNumber() == MAGIC_NUMBER &&
         OrderSymbol() == Symbol())
         count++;
   }
   return(count);
}

//===========================================
// DASHBOARD PANEL
//===========================================
void DrawPanel()
{
   int x  = Panel_X;
   int y  = Panel_Y;
   int lh = 16;

   double dd = (g_peakBalance > 0) ?
               (g_peakBalance - AccountEquity()) / g_peakBalance * 100.0 : 0;

   int total = g_wins + g_losses;
   double wr = (total > 0) ? (double)g_wins / total * 100.0 : 0;

   // Determine status color
   color statusCol = g_killSwitch ? clrRed :
                     (CountOpenTrades() > 0 ? clrLime : clrYellow);

   string statusTxt = g_killSwitch ? "KILL SWITCH ACTIVE" :
                      (CountOpenTrades() > 0 ? "TRADING ACTIVE" : "SCANNING");

   PL("NT_P00", "NEUROTRICK PRO v1.0",              x, y,      clrWhite, 11);
   PL("NT_P01", "Viktor AI x Michael Chapman",       x, y+lh,   clrGray,  8);
   PL("NT_P02", "────────────────────────",          x, y+lh*2, C'35,35,35', 8);

   PL("NT_P03", "STATUS:  " + statusTxt,             x, y+lh*3, statusCol, 9);
   PL("NT_P04", "SIGNAL:  " + g_lastSignal,          x, y+lh*4, clrSilver, 8);
   PL("NT_P05", "────────────────────────",          x, y+lh*5, C'35,35,35', 8);

   // Account stats
   PL("NT_P06", "ACCOUNT STATS:",                    x, y+lh*6,  clrSilver, 9);
   PL("NT_P07", "  Balance : $" + DoubleToString(AccountBalance(),2),
                                                      x, y+lh*7,  clrWhite,  9);
   PL("NT_P08", "  Equity  : $" + DoubleToString(AccountEquity(),2),
                                                      x, y+lh*8,
                                                      AccountEquity() >= AccountBalance() ? clrLime : clrRed, 9);
   PL("NT_P09", "  Drawdown: " + DoubleToString(dd,1) + "%",
                                                      x, y+lh*9,
                                                      dd > 10 ? clrRed : clrYellow, 9);
   PL("NT_P10", "────────────────────────",          x, y+lh*10, C'35,35,35', 8);

   // Trade stats
   PL("NT_P11", "TRADE STATS:",                      x, y+lh*11, clrSilver, 9);
   PL("NT_P12", "  Open    : " + IntegerToString(CountOpenTrades()),
                                                      x, y+lh*12, clrWhite, 9);
   PL("NT_P13", "  Wins    : " + IntegerToString(g_wins),
                                                      x, y+lh*13, clrLime, 9);
   PL("NT_P14", "  Losses  : " + IntegerToString(g_losses),
                                                      x, y+lh*14, clrRed, 9);
   PL("NT_P15", "  Win Rate: " + DoubleToString(wr,1) + "%",
                                                      x, y+lh*15,
                                                      wr >= 60 ? clrLime : clrOrange, 9);
   PL("NT_P16", "────────────────────────",          x, y+lh*16, C'35,35,35', 8);

   // Entry methods active
   PL("NT_P17", "ENTRY METHODS ACTIVE:",             x, y+lh*17, clrSilver, 9);
   PL("NT_P18", "  [" + (EnableEntry_AHSE      ? "X" : " ") + "] AHSE Confluence",   x, y+lh*18, EnableEntry_AHSE ? clrLime : clrGray, 8);
   PL("NT_P19", "  [" + (EnableEntry_VolSpike  ? "X" : " ") + "] Vol Spike",          x, y+lh*19, EnableEntry_VolSpike ? clrLime : clrGray, 8);
   PL("NT_P20", "  [" + (EnableEntry_Engulfing ? "X" : " ") + "] Engulfing",          x, y+lh*20, EnableEntry_Engulfing ? clrLime : clrGray, 8);
   PL("NT_P21", "  [" + (EnableEntry_Pullback  ? "X" : " ") + "] EMA Pullback",       x, y+lh*21, EnableEntry_Pullback ? clrLime : clrGray, 8);
   PL("NT_P22", "  [" + (EnableEntry_CCI       ? "X" : " ") + "] CCI Momentum",       x, y+lh*22, EnableEntry_CCI ? clrLime : clrGray, 8);
   PL("NT_P23", "────────────────────────",          x, y+lh*23, C'35,35,35', 8);
   PL("NT_P24", "Max DD Kill: " + DoubleToString(MaxDrawdownPercent,0) + "% | Risk: " +
                DoubleToString(RiskPercent,1) + "%",  x, y+lh*24, clrGray, 8);
}

void PL(string name, string text, int x, int y, color col, int fs=9)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetString(0,  name, OBJPROP_FONT,      "Courier New");
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
}
//+------------------------------------------------------------------+
