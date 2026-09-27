#property copyright "Copilot"
#property version   "1.00"
#property strict

input group "General"
input int    InpMagicNumber       = 202406;
input bool   InpUseBuy            = true;
input bool   InpUseSell           = true;
input bool   InpUseRiskLot        = true;
input double InpRiskPercent       = 0.5;
input double InpFixedLot          = 0.01;
input int    InpMaxPositions      = 1;
input int    InpSlippage          = 3;

input group "Trend filter"
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;
input int    InpFastEMA           = 20;
input int    InpSlowEMA           = 200;

input group "Levels"
input bool   InpUsePDH            = true;
input bool   InpUsePDL            = true;
input bool   InpUseAsiaLevels     = true;
input bool   InpUseLondonLevels   = true;
input bool   InpUseNYLevels       = true;
input bool   InpUseSwingLevels    = true;

input group "Risk / Reward"
input int    InpStopLossPoints    = 30;
input int    InpTakeProfitPoints  = 60;
input int    InpTrailStartPoints  = 25;
input int    InpTrailStepPoints   = 10;

struct LevelInfo
{
   double price;
   bool   upper;
};

LevelInfo gUpperLevels[];
LevelInfo gLowerLevels[];

int OnInit()
{
   ArrayResize(gUpperLevels, 0);
   ArrayResize(gLowerLevels, 0);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ArrayResize(gUpperLevels, 0);
   ArrayResize(gLowerLevels, 0);
}

void OnTick()
{
   if(!IsNewBar())
      return;

   if(GetOpenPositions() >= InpMaxPositions)
      return;

   BuildLevels();

   if(InpUseBuy && IsBuySignal())
      OpenTrade(ORDER_TYPE_BUY);

   if(InpUseSell && IsSellSignal())
      OpenTrade(ORDER_TYPE_SELL);

   ManageTrailingStops();
}

bool IsNewBar()
{
   static datetime lastTime = 0;
   datetime currentTime = iTime(_Symbol, _Period, 0);

   if(lastTime == currentTime)
      return false;

   lastTime = currentTime;
   return true;
}

void BuildLevels()
{
   ArrayResize(gUpperLevels, 0);
   ArrayResize(gLowerLevels, 0);

   if(InpUsePDH)
      AddUpper(iHigh(_Symbol, PERIOD_D1, 1));
   if(InpUsePDL)
      AddLower(iLow(_Symbol, PERIOD_D1, 1));

   if(InpUseAsiaLevels)
   {
      double high = GetSessionHigh(0, 6);
      double low  = GetSessionLow(0, 6);
      if(high > 0) AddUpper(high);
      if(low > 0)  AddLower(low);
   }

   if(InpUseLondonLevels)
   {
      double high = GetSessionHigh(7, 10);
      double low  = GetSessionLow(7, 10);
      if(high > 0) AddUpper(high);
      if(low > 0)  AddLower(low);
   }

   if(InpUseNYLevels)
   {
      double high = GetSessionHigh(13, 17);
      double low  = GetSessionLow(13, 17);
      if(high > 0) AddUpper(high);
      if(low > 0)  AddLower(low);
   }

   if(InpUseSwingLevels)
   {
      int highestIndex = iHighest(_Symbol, InpTrendTF, MODE_HIGH, 50, 0);
      int lowestIndex  = iLowest(_Symbol, InpTrendTF, MODE_LOW, 50, 0);

      if(highestIndex >= 0)
         AddUpper(iHigh(_Symbol, InpTrendTF, highestIndex));

      if(lowestIndex >= 0)
         AddLower(iLow(_Symbol, InpTrendTF, lowestIndex));
   }
}

void AddUpper(double price)
{
   if(price <= 0)
      return;

   int n = ArraySize(gUpperLevels);
   ArrayResize(gUpperLevels, n + 1);
   gUpperLevels[n].price = price;
   gUpperLevels[n].upper = true;
}

void AddLower(double price)
{
   if(price <= 0)
      return;

   int n = ArraySize(gLowerLevels);
   ArrayResize(gLowerLevels, n + 1);
   gLowerLevels[n].price = price;
   gLowerLevels[n].upper = false;
}

double GetSessionHigh(int startHour, int endHour)
{
   double res = 0.0;
   int totalBars = 200;

   for(int i = 0; i < totalBars; i++)
   {
      datetime t = iTime(_Symbol, PERIOD_H1, i);
      int hour = TimeHour(t);

      if(hour >= startHour && hour <= endHour)
      {
         double val = iHigh(_Symbol, PERIOD_H1, i);
         if(val > res)
            res = val;
      }
   }

   return res;
}

double GetSessionLow(int startHour, int endHour)
{
   double res = 0.0;
   bool init = false;
   int totalBars = 200;

   for(int i = 0; i < totalBars; i++)
   {
      datetime t = iTime(_Symbol, PERIOD_H1, i);
      int hour = TimeHour(t);

      if(hour >= startHour && hour <= endHour)
      {
         double val = iLow(_Symbol, PERIOD_H1, i);
         if(!init || val < res)
         {
            res = val;
            init = true;
         }
      }
   }

   return res;
}

bool IsBuySignal()
{
   double emaFast = iMA(_Symbol, InpTrendTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(_Symbol, InpTrendTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 0);

   if(emaFast < emaSlow)
      return false;

   double level = GetNearestLowerLiquidity();
   if(level <= 0)
      return false;

   bool sweep = (Low[1] < level && Close[1] > level);
   if(!sweep)
      return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= emaSlow)
      return false;

   return true;
}

bool IsSellSignal()
{
   double emaFast = iMA(_Symbol, InpTrendTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(_Symbol, InpTrendTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 0);

   if(emaFast > emaSlow)
      return false;

   double level = GetNearestUpperLiquidity();
   if(level <= 0)
      return false;

   bool sweep = (High[1] > level && Close[1] < level);
   if(!sweep)
      return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask >= emaSlow)
      return false;

   return true;
}

double GetNearestLowerLiquidity()
{
   double best = 0.0;

   for(int i = 0; i < ArraySize(gLowerLevels); i++)
   {
      double price = gLowerLevels[i].price;
      if(price <= 0)
         continue;

      if(best == 0 || price > best)
         best = price;
   }

   return best;
}

double GetNearestUpperLiquidity()
{
   double best = 0.0;

   for(int i = 0; i < ArraySize(gUpperLevels); i++)
   {
      double price = gUpperLevels[i].price;
      if(price <= 0)
         continue;

      if(best == 0 || price < best)
         best = price;
   }

   return best;
}

void OpenTrade(int type)
{
   double lot = GetLot();
   if(lot <= 0)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (type == ORDER_TYPE_BUY) ? ask : bid;

   double sl = 0.0;
   double tp = 0.0;

   if(type == ORDER_TYPE_BUY)
   {
      double level = GetNearestLowerLiquidity();
      sl = (level > 0) ? level - InpStopLossPoints * _Point : price - InpStopLossPoints * _Point;
      tp = price + InpTakeProfitPoints * _Point;
   }
   else
   {
      double level = GetNearestUpperLiquidity();
      sl = (level > 0) ? level + InpStopLossPoints * _Point : price + InpStopLossPoints * _Point;
      tp = price - InpTakeProfitPoints * _Point;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = type;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.magic = InpMagicNumber;
   request.comment = "LiquiditySweepEA";
   request.deviation = InpSlippage;

   if(OrderSend(request, result))
   {
      // успішно
   }
}

double GetLot()
{
   if(InpUseRiskLot)
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

void ManageTrailingStops()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double distance = bid - openPrice;

         if(distance > InpTrailStartPoints * _Point)
         {
            double newSL = bid - InpTrailStartPoints * _Point;

            if(currentSL == 0.0 || newSL > currentSL + InpTrailStepPoints * _Point)
            {
               MqlTradeRequest request;
               MqlTradeResult result;

               ZeroMemory(request);
               ZeroMemory(result);

               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.sl = newSL;
               request.tp = currentTP;

               if(OrderSend(request, result))
               {
                  // успішно
               }
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double distance = openPrice - ask;

         if(distance > InpTrailStartPoints * _Point)
         {
            double newSL = ask + InpTrailStartPoints * _Point;

            if(currentSL == 0.0 || newSL < currentSL - InpTrailStepPoints * _Point)
            {
               MqlTradeRequest request;
               MqlTradeResult result;

               ZeroMemory(request);
               ZeroMemory(result);

               request.action = TRADE_ACTION_SLTP;
               request.position = ticket;
               request.sl = newSL;
               request.tp = currentTP;

               if(OrderSend(request, result))
               {
                  // успішно
               }
            }
         }
      }
   }
}

int GetOpenPositions()
{
   int total = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      total++;
   }

   return total;
}
