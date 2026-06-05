//+------------------------------------------------------------------+
//|                                         FinalWorkingEA_v1_03.mq4 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      "Your Website"
#property version   "1.03"
#property strict
#property show_inputs

//--- Input parameters for the EA
extern double LotSize = 0.01;
extern int    TakeProfitPips = 60; // Still fixed for now, will be dynamic later
extern int    Slippage       = 3;
extern int    MagicNumber    = 12348;

//--- MACD Settings
extern int    FastEMA_MACD = 5;
extern int    SlowEMA_MACD = 45;
extern int    SignalEMA_MACD = 1;
extern int    AppliedPrice_MACD = PRICE_CLOSE;

//--- MTF Periods for MACD
extern int    MTF_Period_1 = PERIOD_M15; // Fastest timeframe for entry signal
extern int    MTF_Period_2 = PERIOD_M30;
extern int    MTF_Period_3 = PERIOD_H1;
extern int    MTF_Period_4 = PERIOD_H4;  // Slowest timeframe for trend confirmation

//--- ADX Filter Settings
extern int    ADX_Period = 11;
extern double ADX_Strength_Threshold = 25.0; // Minimum ADX value for a strong trend

//--- ATR-based Dynamic Stop Loss Settings
extern int    ATR_Period = 14;           // Period for ATR calculation
extern double ATR_Multiplier_SL = 2.0;   // Multiplier for ATR to set Stop Loss
extern int    MinStopLossPips = 10;      // Minimum SL in pips, to avoid too tight SLs (e.g., 1 pip for 5-digit broker is 10 points)

//--- Global variables
double BidPrice, AskPrice;
static datetime last_bar_time = 0; // For new bar detection

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Basic validation (optional but good practice)
   if (MTF_Period_1 == 0 || MTF_Period_2 == 0 || MTF_Period_3 == 0 || MTF_Period_4 == 0)
   {
      Print("ERROR: Invalid MTF periods set. Please check EA inputs.");
      return(INIT_FAILED);
   }
   if (Period() != MTF_Period_1)
   {
      Print("WARNING: Chart timeframe (", Period(), ") is not equal to MTF_Period_1 (", MTF_Period_1, "). For optimal entry signal processing, attach EA to chart with timeframe ", MTF_Period_1, ".");
   }
   
   if (ADX_Period <= 1)
   {
       Print("ERROR: ADX_Period must be greater than 1.");
       return(INIT_FAILED);
   }
   
   if (ATR_Period <=1 || ATR_Multiplier_SL <= 0)
   {
       Print("ERROR: ATR_Period must be > 1 and ATR_Multiplier_SL must be > 0.");
       return(INIT_FAILED);
   }
   if (MinStopLossPips <= 0)
   {
       Print("ERROR: MinStopLossPips must be greater than 0.");
       return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- No specific cleanup needed for this simple EA
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. New Bar Detection: Process logic only once per new bar on the current chart's timeframe
   if (last_bar_time == Time[0])
   {
      return; // No new bar, do nothing
   }
   last_bar_time = Time[0]; // Update last bar time for the next tick

   //--- 2. Update current market prices
   BidPrice = NormalizeDouble(Bid, _Digits);
   AskPrice = NormalizeDouble(Ask, _Digits);

   //--- 3. Get MACD values
   // Ensure enough bars are available for indicator calculations
   if (Bars < MathMax(MathMax(MTF_Period_1, MTF_Period_2), MathMax(MTF_Period_3, MTF_Period_4)) + 2) { // Need at least period + 1 for shift 1, +1 for current bar
       Print("Not enough bars for MACD calculation.");
       return;
   }
   
   double macd1_curr = iMACD(NULL, MTF_Period_1, FastEMA_MACD, SlowEMA_MACD, SignalEMA_MACD, AppliedPrice_MACD, MODE_MAIN, 0);
   double macd2_curr = iMACD(NULL, MTF_Period_2, FastEMA_MACD, SlowEMA_MACD, SignalEMA_MACD, AppliedPrice_MACD, MODE_MAIN, 0);
   double macd3_curr = iMACD(NULL, MTF_Period_3, FastEMA_MACD, SlowEMA_MACD, SignalEMA_MACD, AppliedPrice_MACD, MODE_MAIN, 0);
   double macd4_curr = iMACD(NULL, MTF_Period_4, FastEMA_MACD, SlowEMA_MACD, SignalEMA_MACD, AppliedPrice_MACD, MODE_MAIN, 0);
   double macd1_prev = iMACD(NULL, MTF_Period_1, FastEMA_MACD, SlowEMA_MACD, SignalEMA_MACD, AppliedPrice_MACD, MODE_MAIN, 1);

   //--- 4. Get ADX values for the slowest timeframe (MTF_Period_4)
   // Ensure enough bars for ADX calculation
   if (Bars < ADX_Period + 2) { // Need at least period + 1 for shift 1, +1 for current bar
       Print("Not enough bars for ADX calculation.");
       return;
   }
   double adx_main_4H = iADX(NULL, MTF_Period_4, ADX_Period, PRICE_HIGH, MODE_MAIN, 0);
   double adx_plusdi_4H = iADX(NULL, MTF_Period_4, ADX_Period, PRICE_HIGH, MODE_PLUSDI, 0);
   double adx_minusdi_4H = iADX(NULL, MTF_Period_4, ADX_Period, PRICE_HIGH, MODE_MINUSDI, 0);
   
   //--- 5. Calculate ATR for dynamic Stop Loss
   // ATR of previous bar (shift 1) on entry timeframe (MTF_Period_1)
   // Ensure enough bars for ATR calculation
   if (Bars < ATR_Period + 2) { // Need at least period + 1 for shift 1, +1 for current bar
       Print("Not enough bars for ATR calculation.");
       return;
   }
   double current_ATR_value = iATR(NULL, MTF_Period_1, ATR_Period, 1); 
   
   // Robust check for valid ATR value - should be positive and not too small
   if (current_ATR_value <= 0 || current_ATR_value < 0.00001) { // Check for zero or extremely small ATR
       Print("WARNING: ATR value is zero or too small (", current_ATR_value, "). Cannot place trade. Waiting for valid ATR.");
       return;
   }
   
   double calculated_stop_loss_points = current_ATR_value / _Point * ATR_Multiplier_SL; // Convert ATR to points
   
   // Ensure minimum stop loss distance
   if (calculated_stop_loss_points < MinStopLossPips) {
       calculated_stop_loss_points = MinStopLossPips; 
       // Print("ATR-based SL too small, adjusted to MinStopLossPips: ", MinStopLossPips); // Commented to reduce log spam
   }
   
   // Also check if the calculated SL is too close to current price (broker's MODE_STOPLEVEL)
   // This is crucial to avoid error 130 (invalid stops)
   double min_broker_sl_points = MarketInfo(Symbol(), MODE_STOPLEVEL);
   if (calculated_stop_loss_points < min_broker_sl_points) {
       Print("WARNING: Calculated SL (", calculated_stop_loss_points, " points) is less than broker's minimum (", min_broker_sl_points, " points). Adjusting to broker minimum.");
       calculated_stop_loss_points = min_broker_sl_points;
   }
   
   //--- 6. Check for open positions to decide whether to open new trades or manage existing ones
   if (OrdersTotal() == 0) // No open trades, look for new signals
   {
      //--- BUY Signal Logic:
      if (macd1_curr > 0 && macd1_prev <= 0 &&     // Fastest timeframe MACD just turned bullish
          macd2_curr > 0 &&                       // Second timeframe MACD is bullish
          macd3_curr > 0 &&                       // Third timeframe MACD is bullish
          macd4_curr > 0 &&                       // Slowest timeframe MACD is bullish (strong trend confirmation)
          adx_main_4H > ADX_Strength_Threshold && // Strong trend detected by ADX
          adx_plusdi_4H > adx_minusdi_4H)         // Bullish trend direction confirmed by ADX
      {
         double sl_price_buy = NormalizeDouble(AskPrice - calculated_stop_loss_points * _Point, _Digits);
         double tp_price_buy = NormalizeDouble(AskPrice + TakeProfitPips * _Point, _Digits); // TP still fixed for now

         if (OrderSend(Symbol(), OP_BUY, LotSize, AskPrice, Slippage, sl_price_buy, tp_price_buy, "Buy MTF MACD+ADX+ATRSL", MagicNumber, 0, Green) != -1)
         {
            Print("BUY order placed successfully! SL: ", sl_price_buy, " (", calculated_stop_loss_points, " points), TP: ", tp_price_buy);
         }
         else
         {
            Print("ERROR placing BUY order: ", GetLastError());
         }
      }
      //--- SELL Signal Logic:
      else if (macd1_curr < 0 && macd1_prev >= 0 && // Fastest timeframe MACD just turned bearish
               macd2_curr < 0 &&                    // Second timeframe MACD is bearish
               macd3_curr < 0 &&                    // Third timeframe MACD is bearish
               macd4_curr < 0 &&                    // Slowest timeframe MACD is bearish (strong trend confirmation)
               adx_main_4H > ADX_Strength_Threshold && // Strong trend detected by ADX
               adx_minusdi_4H > adx_plusdi_4H)         // Bearish trend direction confirmed by ADX
      {
         double sl_price_sell = NormalizeDouble(BidPrice + calculated_stop_loss_points * _Point, _Digits);
         double tp_price_sell = NormalizeDouble(BidPrice - TakeProfitPips * _Point, _Digits); // TP still fixed for now

         if (OrderSend(Symbol(), OP_SELL, LotSize, BidPrice, Slippage, sl_price_sell, tp_price_sell, "Sell MTF MACD+ADX+ATRSL", MagicNumber, 0, Red) != -1)
         {
            Print("SELL order placed successfully! SL: ", sl_price_sell, " (", calculated_stop_loss_points, " points), TP: ", tp_price_sell);
         }
         else
         {
            Print("ERROR placing SELL order: ", GetLastError());
         }
      }
   }
   else // There are open trades, manage them (exit logic remains the same for simplicity for now)
   {
      // We will add trailing stop and partial close here in the next iteration
      for (int i = 0; i < OrdersTotal(); i++)
      {
         if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
               // --- Current exit logic: Close on opposite signal on the fastest timeframe
               if (OrderType() == OP_BUY)
               {
                  if (macd1_curr < 0 && macd1_prev >= 0) // Fastest TF MACD just turned bearish
                  {
                     if (OrderClose(OrderTicket(), OrderLots(), BidPrice, Slippage, Red))
                     {
                        Print("BUY order #", OrderTicket(), " closed on fastest MACD sell signal.");
                     }
                     else
                     {
                        Print("ERROR closing BUY order #", OrderTicket(), ": ", GetLastError());
                     }
                  }
               }
               else if (OrderType() == OP_SELL)
               {
                  if (macd1_curr > 0 && macd1_prev <= 0) // Fastest TF MACD just turned bullish
                  {
                     if (OrderClose(OrderTicket(), OrderLots(), AskPrice, Slippage, Green))
                     {
                        Print("SELL order #", OrderTicket(), " closed on fastest MACD buy signal.");
                     }
                     else
                     {
                        Print("ERROR closing SELL order #", OrderTicket(), ": ", GetLastError());
                     }
                  }
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+

