#property copyright "Copilot"
#property link      "https://github.com/Masdqqw/MT5_Liquidity_EA"
#property version   "1.00"
#property strict

input group "General"
input int    InpMagicNumber          = 123456;
input bool   InpUseBuy               = true;
input bool   InpUseSell              = true;
input bool   InpUseRiskBasedLot      = true;
input double InpRiskPercent          = 0.5;
input double InpFixedLot             = 0.01;
input int    InpMaxPositions         = 1;
input int    InpSlippage             = 3;
input int    InpTrailStartPoints     = 20;
input int    InpTrailStepPoints      = 10;

input group "Filters"
input ENUM_TIMEFRAMES InpTrendTF     = PERIOD_H1;
input int    InpTrendMaFast          = 20;
input int    InpTrendMaSlow          = 200;
input int    InpLookbackBars         = 200;
input double InpLevelTolerancePoints = 25.0;
input int    InpSwingPeriod          = 50;
input bool   InpUseDailyLevels      = true;
input bool   InpUseSessionLevels     = true;
input bool   InpUseSwingLevels       = true;
input bool   InpUseEqualLevels       = true;

input group "Risk / Reward"
input int    InpStopLossPoints       = 30;
input int    InpTakeProfitPoints     = 60;
input double InpMinRiskReward        = 1.5;

// ================================================================
// Liquidity Sweep EA for MT5
// ---------------------------------------------------------------
// Trading concept:
//  - identifies key liquidity levels from previous day, sessions,
//    swings, and equal highs/lows;
//  - waits for a sweep of that level and a continuation signal;
//  - enters only in the direction of the higher timeframe trend.
// ================================================================

struct LevelInfo
{
   double price;
   bool   isUpper;     // true = resistance / upper liquidity
   bool   active;      // still not swept
   bool   swept;
   datetime time;
};

LevelInfo g_upperLevels[];
LevelInfo g_lowerLevels[];

int OnInit()
{
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ArrayResize(g_upperLevels, 0);
   ArrayResize(g_lowerLevels, 0);
}

void OnTick()
{
   if(!IsTradingAllowed())
      return;

   RefreshLevels();

   if(GetOpenOrdersTotal() >= InpMaxPositions)
      return;

   CheckAndManageTrades();

   if(!IsNewBar())
      return;

   if(InpUseBuy && IsBuySetup())
      OpenTrade(OP_BUY);

   if(InpUseSell && IsSellSetup())
      OpenTrade(OP_SELL);
}

bool IsTradingAllowed()
{
   datetime now = TimeCurrent();
   int hour = TimeHour(now);
   // 24/7 trading is allowed by default; allow simple hour filter if someone wants to use it
   return true;
}

bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(lastBarTime == currentBarTime)
      return false;

   lastBarTime = currentBarTime;
   return true;
}

void RefreshLevels()
{
   ArrayResize(g_upperLevels, 0);
   ArrayResize(g_lowerLevels, 0);

   if(InpUseDailyLevels)
   {
      AddLevel(iHigh(_Symbol, PERIOD_D1, 1), true, Time[1]);
      AddLevel(iLow(_Symbol, PERIOD_D1, 1), false, Time[1]);
   }

   if(InpUseSessionLevels)
   {
      double asiaHigh = GetSessionHigh(0);
      double asiaLow  = GetSessionLow(0);
      if(asiaHigh > 0) AddLevel(asiaHigh, true, Time[0]);
      if(asiaLow > 0)  AddLevel(asiaLow, false, Time[0]);

      double londonHigh = GetSessionHigh(1);
      double londonLow  = GetSessionLow(1);
      if(londonHigh > 0) AddLevel(londonHigh, true, Time[0]);
      if(londonLow > 0)  AddLevel(londonLow, false, Time[0]);

      double nyHigh = GetSessionHigh(2);
      double nyLow  = GetSessionLow(2);
      if(nyHigh > 0) AddLevel(nyHigh, true, Time[0]);
      if(nyLow > 0)  AddLevel(nyLow, false, Time[0]);
   }

   if(InpUseSwingLevels)
   {
      double swingHigh = iHigh(_Symbol, InpTrendTF, iHighest(_Symbol, InpTrendTF, MODE_HIGH, InpSwingPeriod, 0));
      double swingLow  = iLow(_Symbol, InpTrendTF, iLowest(_Symbol, InpTrendTF, MODE_LOW, InpSwingPeriod, 0));
      AddLevel(swingHigh, true, iTime(_Symbol, InpTrendTF, 0));
      AddLevel(swingLow, false, iTime(_Symbol, InpTrendTF, 0));
   }

   if(InpUseEqualLevels)
   {
      AddEqualLevels();
   }
}

void AddLevel(double price, bool isUpper, datetime time)
{
   if(price <= 0)
      return;

   LevelInfo info;
   info.price = price;
   info.isUpper = isUpper;
   info.active = true;
   info.swept = false;
   info.time = time;

   if(isUpper)
      g_upperLevels[ArraySize(g_upperLevels)] = info;
   else
      g_lowerLevels[ArraySize(g_lowerLevels)] = info;
}

bool IsDuplicateLevel(double price, bool isUpper, double tolerance)
{
   if(isUpper)
   {
      for(int i = 0; i < ArraySize(g_upperLevels); i++)
      {
         if(MathAbs(g_upperLevels[i].price - price) <= tolerance)
            return true;
      }
   }
   else
   {
      for(int i = 0; i < ArraySize(g_lowerLevels); i++)
      {
         if(MathAbs(g_lowerLevels[i].price - price) <= tolerance)
            return true;
      }
   }
   return false;
}

void AddEqualLevels()
{
   int bars = MathMin(InpLookbackBars, iBarShift(_Symbol, _Period, TimeCurrent()) + 50);
   double tolerance = InpLevelTolerancePoints * _Point;

   for(int i = 1; i < bars - 2; i++)
   {
      double hi = iHigh(_Symbol, _Period, i);
      double lo = iLow(_Symbol, _Period, i);

      for(int j = i + 1; j < bars; j++)
      {
         double diffHigh = MathAbs(hi - iHigh(_Symbol, _Period, j));
         double diffLow  = MathAbs(lo - iLow(_Symbol, _Period, j));

         if(diffHigh <= tolerance && !IsDuplicateLevel(hi, true, tolerance))
            AddLevel(hi, true, iTime(_Symbol, _Period, i));

         if(diffLow <= tolerance && !IsDuplicateLevel(lo, false, tolerance))
            AddLevel(lo, false, iTime(_Symbol, _Period, i));
      }
   }
}

double GetSessionHigh(int session)
{
   int startHour = 0;
   int endHour = 0;

   if(session == 0) { startHour = 0; endHour = 6; }
   if(session == 1) { startHour = 7; endHour = 10; }
   if(session == 2) { startHour = 13; endHour = 17; }

   double result = 0;
   for(int i = 0; i < 200; i++)
   {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      int hour = TimeHour(barTime);
      if(hour >= startHour && hour <= endHour)
      {
         double val = iHigh(_Symbol, PERIOD_H1, i);
         if(val > result)
            result = val;
      }
   }
   return result;
}

double GetSessionLow(int session)
{
   int startHour = 0;
   int endHour = 0;

   if(session == 0) { startHour = 0; endHour = 6; }
   if(session == 1) { startHour = 7; endHour = 10; }
   if(session == 2) { startHour = 13; endHour = 17; }

   double result = 0;
   bool initialized = false;
   for(int i = 0; i < 200; i++)
   {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      int hour = TimeHour(barTime);
      if(hour >= startHour && hour <= endHour)
      {
         double val = iLow(_Symbol, PERIOD_H1, i);
         if(!initialized || val < result)
         {
            result = val;
            initialized = true;
         }
      }
   }
   return result;
}

void CheckAndManageTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderMagicNumber() != InpMagicNumber)
         continue;

      if(OrderType() == OP_BUY)
      {
         double trailingStart = InpTrailStartPoints * _Point;
         double trailStep = InpTrailStepPoints * _Point;
         if(Bid - OrderOpenPrice() > trailingStart)
         {
            double newStop = Bid - trailingStart;
            if(OrderStopLoss() < OrderOpenPrice() || OrderStopLoss() == 0)
               newStop = OrderOpenPrice();
            if(newStop > OrderStopLoss() + trailStep)
               OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrNONE);
         }
      }
      else if(OrderType() == OP_SELL)
      {
         double trailingStart = InpTrailStartPoints * _Point;
         double trailStep = InpTrailStepPoints * _Point;
         if(OrderOpenPrice() - Ask > trailingStart)
         {
            double newStop = Ask + trailingStart;
            if(OrderStopLoss() > OrderOpenPrice() || OrderStopLoss() == 0)
               newStop = OrderOpenPrice();
            if(newStop < OrderStopLoss() - trailStep)
               OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrNONE);
         }
      }
   }
}

bool IsBuySetup()
{
   double emaFast = iMA(_Symbol, InpTrendTF, InpTrendMaFast, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(_Symbol, InpTrendTF, InpTrendMaSlow, 0, MODE_EMA, PRICE_CLOSE, 0);
   if(emaFast < emaSlow)
      return false;

   double buyLevel = FindBestLowerLevel();
   if(buyLevel <= 0)
      return false;

   bool sweep = (Low[1] < buyLevel && Close[1] > buyLevel);
   if(!sweep)
      return false;

   return (Bid > emaSlow);
}

bool IsSellSetup()
{
   double emaFast = iMA(_Symbol, InpTrendTF, InpTrendMaFast, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(_Symbol, InpTrendTF, InpTrendMaSlow, 0, MODE_EMA, PRICE_CLOSE, 0);
   if(emaFast > emaSlow)
      return false;

   double sellLevel = FindBestUpperLevel();
   if(sellLevel <= 0)
      return false;

   bool sweep = (High[1] > sellLevel && Close[1] < sellLevel);
   if(!sweep)
      return false;

   return (Ask < emaSlow);
}

double FindBestLowerLevel()
{
   double best = 0.0;
   for(int i = 0; i < ArraySize(g_lowerLevels); i++)
   {
      double level = g_lowerLevels[i].price;
      if(level <= 0)
         continue;
      if(g_lowerLevels[i].swept)
         continue;
      if(best == 0 || level > best)
         best = level;
   }
   return best;
}

double FindBestUpperLevel()
{
   double best = 0.0;
   for(int i = 0; i < ArraySize(g_upperLevels); i++)
   {
      double level = g_upperLevels[i].price;
      if(level <= 0)
         continue;
      if(g_upperLevels[i].swept)
         continue;
      if(best == 0 || level < best)
         best = level;
   }
   return best;
}

int GetOpenOrdersTotal()
{
   int total = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderMagicNumber() == InpMagicNumber)
         total++;
   }
   return total;
}

void OpenTrade(int orderType)
{
   double price = (orderType == OP_BUY) ? Ask : Bid;
   double stopLoss = 0.0;
   double takeProfit = 0.0;

   if(orderType == OP_BUY)
   {
      double level = FindBestLowerLevel();
      stopLoss = level - InpStopLossPoints * _Point;
      takeProfit = price + InpTakeProfitPoints * _Point;
      if(stopLoss <= 0)
         stopLoss = price - InpStopLossPoints * _Point;
      if(takeProfit <= 0)
         takeProfit = price + InpTakeProfitPoints * _Point;
   }
   else
   {
      double level = FindBestUpperLevel();
      stopLoss = level + InpStopLossPoints * _Point;
      takeProfit = price - InpTakeProfitPoints * _Point;
      if(stopLoss <= 0)
         stopLoss = price + InpStopLossPoints * _Point;
      if(takeProfit <= 0)
         takeProfit = price - InpTakeProfitPoints * _Point;
   }

   double lot = GetLotSize();
   if(lot <= 0)
      return;

   int ticket = OrderSend(_Symbol, orderType, lot, price, InpSlippage, stopLoss, takeProfit, "LiquiditySweepEA", InpMagicNumber, 0, clrNONE);
   if(ticket < 0)
      Print("OrderSend failed: ", GetLastError());
}

double GetLotSize()
{
   if(InpUseRiskBasedLot)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * InpRiskPercent / 100.0;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double lot = riskMoney / (InpStopLossPoints * tickValue * 10.0);
      if(lot <= 0)
         lot = InpFixedLot;
      return MathMax(lot, 0.01);
   }

   return InpFixedLot;
}

// ================================================================
// End of EA
// ================================================================
