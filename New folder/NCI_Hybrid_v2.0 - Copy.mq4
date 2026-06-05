//+------------------------------------------------------------------+
//| NCI GodMode v2.0 — Hybrid Confluence Trading EA                  |
//| MetaTrader 4 Expert Advisor                                       |
//| Writes JSON output to MT4 terminal folder for dashboard           |
//+------------------------------------------------------------------+

#property strict
#include <stdlib.mqh>

//--- Input Parameters
input double   RiskPerTrade = 1.0;           // Risk per trade (%)
input int      MaxOpenTrades = 5;            // Maximum concurrent trades
input int      MaxDailyTrades = 15;          // Maximum trades per day
input double   RiskRewardRatio = 2.5;        // Target risk:reward
input int      StopLossPips = 20;            // Default SL (pips)
input bool     EnableLogging = true;         // Write JSON files

//--- Global Variables
int            TotalTradesToday = 0;
int            ConsecutiveLosses = 0;
datetime       DayStart = 0;
double         StartingBalance = 0;

//--- Constants
#define BUFFER_SIZE 2048
#define JSON_UPDATE_INTERVAL 1  // Update every N ticks

int tick_counter = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    if (EnableLogging) {
        Print("[OK] NCI GodMode v2.0 EA initialized");
    }

    StartingBalance = AccountBalance();
    DayStart = TimeDayStart(TimeCurrent());
    TotalTradesToday = 0;
    ConsecutiveLosses = 0;

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (EnableLogging) {
        Print("[OK] NCI GodMode v2.0 EA shutdown");
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    tick_counter++;

    // Update every N ticks
    if (tick_counter % JSON_UPDATE_INTERVAL == 0) {
        // Reset daily counter if new day
        if (TimeDayStart(TimeCurrent()) > DayStart) {
            DayStart = TimeDayStart(TimeCurrent());
            TotalTradesToday = 0;
            ConsecutiveLosses = 0;
        }

        // Write live account data
        WriteLiveData();

        // Check for signal opportunities
        CheckSignals();

        tick_counter = 0;
    }
}

//+------------------------------------------------------------------+
//| Write live account data to JSON                                  |
//+------------------------------------------------------------------+
void WriteLiveData() {
    string json = "";
    int handle;

    // Calculate account metrics
    double balance = AccountBalance();
    double equity = AccountEquity();
    double margin_used = AccountMargin();
    double drawdown = 0.0;

    if (StartingBalance > 0) {
        drawdown = (balance - StartingBalance) / StartingBalance;
    }

    // Build JSON
    json = "{";
    json += "\"balance\": " + DoubleToString(balance, 2) + ", ";
    json += "\"equity\": " + DoubleToString(equity, 2) + ", ";
    json += "\"margin\": " + DoubleToString(margin_used, 2) + ", ";
    json += "\"drawdown\": " + DoubleToString(drawdown, 4) + ", ";
    json += "\"trades_daily\": " + IntegerToString(TotalTradesToday) + ", ";
    json += "\"consec_losses\": " + IntegerToString(ConsecutiveLosses) + ", ";
    json += "\"phase\": \"ABC Complete\", ";
    json += "\"atr\": " + DoubleToString(CalculateATR(), 6) + ", ";
    json += "\"timestamp\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\"";
    json += "}";

    // Write to file in terminal folder
    handle = FileOpen("NCI_LiveData.json", FILE_WRITE|FILE_TXT|FILE_ANSI);
    if (handle != INVALID_HANDLE) {
        FileWriteString(handle, json);
        FileClose(handle);
    }
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckSignals() {
    // Signal generation logic
    // This is where the GodMode confluence scoring would happen

    string signal_json = "";
    int handle;

    // Example signal (replace with actual confluence logic)
    string symbol = Symbol();
    string action = "BUY";
    string mode = "SCALP";
    double score = 8.5;
    int sl_pips = 18;
    int tp_pips = 42;
    double rr = (double)tp_pips / (double)sl_pips;

    // Build signal JSON
    signal_json = "{";
    signal_json += "\"symbol\": \"" + symbol + "\", ";
    signal_json += "\"action\": \"" + action + "\", ";
    signal_json += "\"mode\": \"" + mode + "\", ";
    signal_json += "\"godmode_score\": " + DoubleToString(score, 2) + ", ";
    signal_json += "\"sl_pips\": " + IntegerToString(sl_pips) + ", ";
    signal_json += "\"tp_pips\": " + IntegerToString(tp_pips) + ", ";
    signal_json += "\"risk_reward\": " + DoubleToString(rr, 2) + ", ";
    signal_json += "\"timestamp\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\", ";
    signal_json += "\"approved\": false";
    signal_json += "}";

    // Write to file
    handle = FileOpen("signal_proposal.json", FILE_WRITE|FILE_TXT|FILE_ANSI);
    if (handle != INVALID_HANDLE) {
        FileWriteString(handle, signal_json);
        FileClose(handle);
    }
}

//+------------------------------------------------------------------+
//| Calculate ATR (Average True Range)                               |
//+------------------------------------------------------------------+
double CalculateATR() {
    // Simplified ATR calculation
    // For demo, use iATR from built-in functions
    double atr = 0.0;

    // Use the standard ATR calculation (14 period)
    // Note: MQL4 doesn't have iATR like newer versions
    // So we calculate manually or use a fixed value for demo
    atr = (High[0] - Low[0]) / Point;

    return atr * Point;
}

//+------------------------------------------------------------------+
//| Helper: Time to Day Start                                        |
//+------------------------------------------------------------------+
datetime TimeDayStart(datetime time_val) {
    return time_val - (time_val % 86400);
}

//+------------------------------------------------------------------+
// END OF EA
//+------------------------------------------------------------------+
