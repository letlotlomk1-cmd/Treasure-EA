#property strict
#property version "8.10"

#include <Trade/Trade.mqh>

CTrade trade;

input double LotSize=0.01;
input ulong MagicNumber=123456;
input int MaxSpreadPoints=30;
input bool AllowBuy=true;
input bool AllowSell=true;

input bool CloseTradesOnTrendChange=true;
input ENUM_TIMEFRAMES TrendH1=PERIOD_H1;
input ENUM_TIMEFRAMES TrendM30=PERIOD_M30;
input ENUM_TIMEFRAMES TrendM15=PERIOD_M15;
input int TrendFastEMA=20;
input int TrendSlowEMA=50;

input ENUM_TIMEFRAMES EntryM5=PERIOD_M5;
input ENUM_TIMEFRAMES EntryM1=PERIOD_M1;

input bool EnableM1Monitoring=true;
input int M1FastEMA=9;
input int M1SlowEMA=21;
input double M1MomentumThreshold=0.60;
input int M1StructureLookback=50;
input int M1SwingStrength=2;

input int SwingStrength=3;
input int StructureLookback=100;
input int LiquidityTolerancePoints=20;
input int SRTolerancePoints=30;

input bool EnableSMT=true;
input string SMT_Symbol="GBPUSD";
input int SMTLookback=100;
input int SMTStrength=3;
input int SMTTolerancePoints=20;

input bool EnableTickAnalysis=true;
input int TickLookbackSeconds=60;
input int TickAverageBars=20;
input double TickVolumeMultiplier=1.20;

input bool EnableNewsFilter=true;
input bool BlockHighImpactNews=true;
input bool BlockMediumImpactNews=false;
input int NewsBeforeMinutes=30;
input int NewsAfterMinutes=30;
input bool AnalyzeNewsData=true;
input int NewsRefreshSeconds=30;

input int ATRPeriod=14;
input double SL_ATR_Multiplier=1.0;
input double RiskRewardRatio=2.0;

int atrHandle=INVALID_HANDLE;
datetime lastM1Bar=0;
datetime lastNewsCheck=0;
bool cachedNewsBlocked=false;

double lastSwingHigh=0,lastSwingLow=0;
double previousSwingHigh=0,previousSwingLow=0;
bool bullishStructure=false,bearishStructure=false;
bool bullishLiquiditySweep=false,bearishLiquiditySweep=false;

enum MarketStructureState
{
   STRUCTURE_NEUTRAL=0,
   STRUCTURE_BULLISH=1,
   STRUCTURE_BEARISH=-1
};

struct NewsAnalysis
{
   bool eventFound;
   bool highImpact;
   bool mediumImpact;
   string eventName;
   string currency;
   datetime eventTime;
   double actual;
   double forecast;
   double previous;
   bool hasActual;
   bool hasForecast;
   bool hasPrevious;
};

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   atrHandle=iATR(_Symbol,EntryM5,ATRPeriod);
   if(atrHandle==INVALID_HANDLE)
      return INIT_FAILED;

   if(EnableSMT)
      SymbolSelect(SMT_Symbol,true);

   EventSetTimer(MathMax(1,NewsRefreshSeconds));

   Print("Advanced SMC/ICT/SMT/News EA started.");
   return INIT_SUCCEEDED;
}

void OnTimer()
{
   if(EnableNewsFilter)
      UpdateNewsCache();
}

void OnTick()
{
   CheckTrendChangeExit();

   if(EnableNewsFilter && lastNewsCheck==0)
      UpdateNewsCache();

   int m1Movement=MonitorM1Movement();
   int m1Analysis=AnalyzeM1Market();

   bool m1Bullish=m1Analysis==STRUCTURE_BULLISH;
   bool m1Bearish=m1Analysis==STRUCTURE_BEARISH;

   if(cachedNewsBlocked)
      return;

   datetime currentM1=iTime(_Symbol,EntryM1,0);
   if(currentM1==lastM1Bar)
      return;

   lastM1Bar=currentM1;

   if(!SpreadAllowed())
      return;

   bool h1Bull=GetBullishTrend(_Symbol,TrendH1);
   bool m30Bull=GetBullishTrend(_Symbol,TrendM30);
   bool m15Bull=GetBullishTrend(_Symbol,TrendM15);

   bool h1Bear=GetBearishTrend(_Symbol,TrendH1);
   bool m30Bear=GetBearishTrend(_Symbol,TrendM30);
   bool m15Bear=GetBearishTrend(_Symbol,TrendM15);

   bool bullishTrend=h1Bull&&m30Bull&&m15Bull;
   bool bearishTrend=h1Bear&&m30Bear&&m15Bear;

   DetectMarketStructure(EntryM5);
   DetectLiquiditySweeps(EntryM5);

   bool nearSupport=IsNearSupport(EntryM5);
   bool nearResistance=IsNearResistance(EntryM5);

   bool m5Bull=EntryBullish(EntryM5);
   bool m5Bear=EntryBearish(EntryM5);
   bool m1Bull=EntryBullish(EntryM1);
   bool m1Bear=EntryBearish(EntryM1);

   bool m1MovementBullish=m1Movement==1;
   bool m1MovementBearish=m1Movement==-1;

   bool bullishSMT=BullishSMT();
   bool bearishSMT=BearishSMT();

   if(PositionSelect(_Symbol))
      return;

   bool buySetup=bullishTrend&&m5Bull&&m1Bull&&m1Bullish&&m1MovementBullish&&
                 bullishLiquiditySweep&&bullishStructure&&nearSupport&&bullishSMT;

   bool sellSetup=bearishTrend&&m5Bear&&m1Bear&&m1Bearish&&m1MovementBearish&&
                  bearishLiquiditySweep&&bearishStructure&&nearResistance&&bearishSMT;

   if(AllowBuy&&buySetup)
   {
      OpenBuy();
      return;
   }

   if(AllowSell&&sellSetup)
   {
      OpenSell();
      return;
   }
}

void UpdateNewsCache()
{
   if(!EnableNewsFilter)
   {
      cachedNewsBlocked=false;
      lastNewsCheck=TimeTradeServer();
      return;
   }

   NewsAnalysis news=AnalyzeEconomicNews();

   cachedNewsBlocked=news.eventFound;
   lastNewsCheck=TimeTradeServer();

   if(news.eventFound)
   {
      Print("NEWS BLOCK: ",news.eventName,
            " | ",news.currency,
            " | ",TimeToString(news.eventTime,TIME_DATE|TIME_MINUTES));

      if(AnalyzeNewsData&&news.hasActual&&news.hasForecast)
      {
         double surprise=CalculateNewsSurprise(news);
         Print("News surprise: ",
               DoubleToString(surprise*100.0,2),"%");
      }
   }
}

int MonitorM1Movement()
{
   if(!EnableM1Monitoring)
      return 0;

   int fh=iMA(_Symbol,PERIOD_M1,M1FastEMA,0,MODE_EMA,PRICE_CLOSE);
   int sh=iMA(_Symbol,PERIOD_M1,M1SlowEMA,0,MODE_EMA,PRICE_CLOSE);

   if(fh==INVALID_HANDLE||sh==INVALID_HANDLE)
      return 0;

   double fast[];
   double slow[];

   ArrayResize(fast,3);
   ArrayResize(slow,3);

   ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true);

   bool fastOK=CopyBuffer(fh,0,0,3,fast)>=3;
   bool slowOK=CopyBuffer(sh,0,0,3,slow)>=3;

   IndicatorRelease(fh);
   IndicatorRelease(sh);

   if(!fastOK||!slowOK)
      return 0;

   double c1=iClose(_Symbol,PERIOD_M1,1);
   double c2=iClose(_Symbol,PERIOD_M1,2);
   double c3=iClose(_Symbol,PERIOD_M1,3);

   if(c1<=0||c2<=0||c3<=0)
      return 0;

   double bullishScore=0.0;
   double bearishScore=0.0;

   double m1=c1-c2;
   double m2=c2-c3;

   if(fast[1]>slow[1]) bullishScore+=0.35;
   if(fast[1]<slow[1]) bearishScore+=0.35;
   if(fast[1]>fast[2]) bullishScore+=0.15;
   if(fast[1]<fast[2]) bearishScore+=0.15;
   if(m1>0) bullishScore+=0.20;
   if(m1<0) bearishScore+=0.20;
   if(m1>0&&m2>0) bullishScore+=0.15;
   if(m1<0&&m2<0) bearishScore+=0.15;

   double open=iOpen(_Symbol,PERIOD_M1,1);
   double high=iHigh(_Symbol,PERIOD_M1,1);
   double low=iLow(_Symbol,PERIOD_M1,1);
   double range=high-low;

   if(range>0)
   {
      double bodyRatio=MathAbs(c1-open)/range;

      if(bodyRatio>=0.60)
      {
         if(c1>open) bullishScore+=0.15;
         if(c1<open) bearishScore+=0.15;
      }
   }

   if(bullishScore>=M1MomentumThreshold&&bullishScore>bearishScore)
      return 1;

   if(bearishScore>=M1MomentumThreshold&&bearishScore>bullishScore)
      return -1;

   return 0;
}

int AnalyzeM1Market()
{
   int bull=0;
   int bear=0;

   int structure=AnalyzeM1MarketStructure();
   int bos=AnalyzeM1BreakOfStructure();
   int ticks=AnalyzeTickActivity();
   int displacement=AnalyzeM1Displacement();

   if(structure==STRUCTURE_BULLISH) bull+=2;
   if(structure==STRUCTURE_BEARISH) bear+=2;

   if(bos==STRUCTURE_BULLISH) bull+=2;
   if(bos==STRUCTURE_BEARISH) bear+=2;

   if(ticks==STRUCTURE_BULLISH) bull++;
   if(ticks==STRUCTURE_BEARISH) bear++;

   if(TickVolumeExpansion())
   {
      if(structure==STRUCTURE_BULLISH) bull++;
      if(structure==STRUCTURE_BEARISH) bear++;
   }

   if(displacement==STRUCTURE_BULLISH) bull++;
   if(displacement==STRUCTURE_BEARISH) bear++;

   if(bull>=4&&bull>bear) return STRUCTURE_BULLISH;
   if(bear>=4&&bear>bull) return STRUCTURE_BEARISH;

   return STRUCTURE_NEUTRAL;
}

int AnalyzeM1MarketStructure()
{
   double recentHigh=0,previousHigh=0;
   double recentLow=0,previousLow=0;
   int highCount=0,lowCount=0;

   int bars=Bars(_Symbol,PERIOD_M1);
   int limit=MathMin(M1StructureLookback,bars);

   for(int i=M1SwingStrength+1;i<limit-M1SwingStrength;i++)
   {
      double h=iHigh(_Symbol,PERIOD_M1,i);
      bool ok=true;

      for(int j=1;j<=M1SwingStrength;j++)
      {
         if(h<=iHigh(_Symbol,PERIOD_M1,i-j)||
            h<=iHigh(_Symbol,PERIOD_M1,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
      {
         if(highCount==0) recentHigh=h;
         else if(highCount==1) previousHigh=h;

         highCount++;

         if(highCount>=2)
            break;
      }
   }

   for(int i=M1SwingStrength+1;i<limit-M1SwingStrength;i++)
   {
      double l=iLow(_Symbol,PERIOD_M1,i);
      bool ok=true;

      for(int j=1;j<=M1SwingStrength;j++)
      {
         if(l>=iLow(_Symbol,PERIOD_M1,i-j)||
            l>=iLow(_Symbol,PERIOD_M1,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
      {
         if(lowCount==0) recentLow=l;
         else if(lowCount==1) previousLow=l;

         lowCount++;

         if(lowCount>=2)
            break;
      }
   }

   if(recentHigh<=0||previousHigh<=0||
      recentLow<=0||previousLow<=0)
      return STRUCTURE_NEUTRAL;

   if(recentHigh>previousHigh&&recentLow>previousLow)
      return STRUCTURE_BULLISH;

   if(recentHigh<previousHigh&&recentLow<previousLow)
      return STRUCTURE_BEARISH;

   return STRUCTURE_NEUTRAL;
}

int AnalyzeM1BreakOfStructure()
{
   double h=FindM1SwingHigh();
   double l=FindM1SwingLow();

   if(h<=0||l<=0)
      return STRUCTURE_NEUTRAL;

   double c=iClose(_Symbol,PERIOD_M1,1);

   if(c>h) return STRUCTURE_BULLISH;
   if(c<l) return STRUCTURE_BEARISH;

   return STRUCTURE_NEUTRAL;
}

int AnalyzeTickActivity()
{
   if(!EnableTickAnalysis)
      return STRUCTURE_NEUTRAL;

   MqlTick ticks[];

   datetime from=TimeTradeServer()-TickLookbackSeconds;
   datetime to=TimeTradeServer();

   ulong fromMsc=(ulong)from*1000;
   ulong toMsc=(ulong)to*1000;

   int n=CopyTicksRange(
      _Symbol,
      ticks,
      COPY_TICKS_ALL,
      fromMsc,
      toMsc
   );

   if(n<10)
      return STRUCTURE_NEUTRAL;

   double first=ticks[0].bid;
   double last=ticks[n-1].bid;

   if(first<=0||last<=0)
      return STRUCTURE_NEUTRAL;

   if(last>first) return STRUCTURE_BULLISH;
   if(last<first) return STRUCTURE_BEARISH;

   return STRUCTURE_NEUTRAL;
}

bool TickVolumeExpansion()
{
   if(!EnableTickAnalysis)
      return false;

   MqlRates rates[];

   int copied=CopyRates(
      _Symbol,
      PERIOD_M1,
      1,
      TickAverageBars,
      rates
   );

   if(copied<TickAverageBars)
      return false;

   long totalVolume=0;

   for(int i=0;i<copied;i++)
      totalVolume+=rates[i].tick_volume;

   double averageVolume=
      (double)totalVolume/(double)copied;

   long currentVolume=
      iVolume(_Symbol,PERIOD_M1,1);

   if(averageVolume<=0.0)
      return false;

   double threshold=
      averageVolume*TickVolumeMultiplier;

   return (double)currentVolume>=threshold;
}

int AnalyzeM1Displacement()
{
   double o=iOpen(_Symbol,PERIOD_M1,1);
   double c=iClose(_Symbol,PERIOD_M1,1);
   double h=iHigh(_Symbol,PERIOD_M1,1);
   double l=iLow(_Symbol,PERIOD_M1,1);

   double range=h-l;

   if(range<=0)
      return STRUCTURE_NEUTRAL;

   if(MathAbs(c-o)/range<0.60)
      return STRUCTURE_NEUTRAL;

   if(c>o) return STRUCTURE_BULLISH;
   if(c<o) return STRUCTURE_BEARISH;

   return STRUCTURE_NEUTRAL;
}

double FindM1SwingHigh()
{
   int bars=Bars(_Symbol,PERIOD_M1);
   int limit=MathMin(M1StructureLookback,bars);

   for(int i=M1SwingStrength+1;
       i<limit-M1SwingStrength;
       i++)
   {
      double h=iHigh(_Symbol,PERIOD_M1,i);
      bool ok=true;

      for(int j=1;j<=M1SwingStrength;j++)
      {
         if(h<=iHigh(_Symbol,PERIOD_M1,i-j)||
            h<=iHigh(_Symbol,PERIOD_M1,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
         return h;
   }

   return 0;
}

double FindM1SwingLow()
{
   int bars=Bars(_Symbol,PERIOD_M1);
   int limit=MathMin(M1StructureLookback,bars);

   for(int i=M1SwingStrength+1;
       i<limit-M1SwingStrength;
       i++)
   {
      double l=iLow(_Symbol,PERIOD_M1,i);
      bool ok=true;

      for(int j=1;j<=M1SwingStrength;j++)
      {
         if(l>=iLow(_Symbol,PERIOD_M1,i-j)||
            l>=iLow(_Symbol,PERIOD_M1,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
         return l;
   }

   return 0;
}

bool GetBullishTrend(
   string symbol,
   ENUM_TIMEFRAMES tf
)
{
   int f=iMA(
      symbol,tf,TrendFastEMA,0,
      MODE_EMA,PRICE_CLOSE
   );

   int s=iMA(
      symbol,tf,TrendSlowEMA,0,
      MODE_EMA,PRICE_CLOSE
   );

   if(f==INVALID_HANDLE||s==INVALID_HANDLE)
      return false;

   double a[];
   double b[];

   ArrayResize(a,2);
   ArrayResize(b,2);

   ArraySetAsSeries(a,true);
   ArraySetAsSeries(b,true);

   bool ok=
      CopyBuffer(f,0,0,2,a)>=2&&
      CopyBuffer(s,0,0,2,b)>=2;

   IndicatorRelease(f);
   IndicatorRelease(s);

   if(!ok)
      return false;

   return a[1]>b[1];
}

bool GetBearishTrend(
   string symbol,
   ENUM_TIMEFRAMES tf
)
{
   int f=iMA(
      symbol,tf,TrendFastEMA,0,
      MODE_EMA,PRICE_CLOSE
   );

   int s=iMA(
      symbol,tf,TrendSlowEMA,0,
      MODE_EMA,PRICE_CLOSE
   );

   if(f==INVALID_HANDLE||s==INVALID_HANDLE)
      return false;

   double a[];
   double b[];

   ArrayResize(a,2);
   ArrayResize(b,2);

   ArraySetAsSeries(a,true);
   ArraySetAsSeries(b,true);

   bool ok=
      CopyBuffer(f,0,0,2,a)>=2&&
      CopyBuffer(s,0,0,2,b)>=2;

   IndicatorRelease(f);
   IndicatorRelease(s);

   if(!ok)
      return false;

   return a[1]<b[1];
}

void CheckTrendChangeExit()
{
   if(!CloseTradesOnTrendChange)
      return;

   if(!PositionSelect(_Symbol))
      return;

   bool bull=
      GetBullishTrend(_Symbol,TrendH1)&&
      GetBullishTrend(_Symbol,TrendM30)&&
      GetBullishTrend(_Symbol,TrendM15);

   bool bear=
      GetBearishTrend(_Symbol,TrendH1)&&
      GetBearishTrend(_Symbol,TrendM30)&&
      GetBearishTrend(_Symbol,TrendM15);

   long type=
      PositionGetInteger(POSITION_TYPE);

   if(type==POSITION_TYPE_BUY&&bear)
      trade.PositionClose(_Symbol);

   if(type==POSITION_TYPE_SELL&&bull)
      trade.PositionClose(_Symbol);
}

bool EntryBullish(ENUM_TIMEFRAMES tf)
{
   return iClose(_Symbol,tf,1)>
          iOpen(_Symbol,tf,1);
}

bool EntryBearish(ENUM_TIMEFRAMES tf)
{
   return iClose(_Symbol,tf,1)<
          iOpen(_Symbol,tf,1);
}

void DetectMarketStructure(ENUM_TIMEFRAMES tf)
{
   double h=FindRecentSwingHigh(tf);
   double l=FindRecentSwingLow(tf);

   if(h>0)
   {
      previousSwingHigh=lastSwingHigh;
      lastSwingHigh=h;
   }

   if(l>0)
   {
      previousSwingLow=lastSwingLow;
      lastSwingLow=l;
   }

   double c=iClose(_Symbol,tf,1);

   if(lastSwingHigh>0&&c>lastSwingHigh)
   {
      bullishStructure=true;
      bearishStructure=false;
   }

   if(lastSwingLow>0&&c<lastSwingLow)
   {
      bearishStructure=true;
      bullishStructure=false;
   }
}

double FindRecentSwingHigh(ENUM_TIMEFRAMES tf)
{
   int bars=Bars(_Symbol,tf);
   int limit=MathMin(StructureLookback,bars);

   for(int i=SwingStrength+1;
       i<limit-SwingStrength;
       i++)
   {
      double h=iHigh(_Symbol,tf,i);
      bool ok=true;

      for(int j=1;j<=SwingStrength;j++)
      {
         if(h<=iHigh(_Symbol,tf,i-j)||
            h<=iHigh(_Symbol,tf,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
         return h;
   }

   return 0;
}

double FindRecentSwingLow(ENUM_TIMEFRAMES tf)
{
   int bars=Bars(_Symbol,tf);
   int limit=MathMin(StructureLookback,bars);

   for(int i=SwingStrength+1;
       i<limit-SwingStrength;
       i++)
   {
      double l=iLow(_Symbol,tf,i);
      bool ok=true;

      for(int j=1;j<=SwingStrength;j++)
      {
         if(l>=iLow(_Symbol,tf,i-j)||
            l>=iLow(_Symbol,tf,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
         return l;
   }

   return 0;
}

void DetectLiquiditySweeps(ENUM_TIMEFRAMES tf)
{
   bullishLiquiditySweep=false;
   bearishLiquiditySweep=false;

   if(lastSwingLow<=0||lastSwingHigh<=0)
      return;

   double low=iLow(_Symbol,tf,1);
   double high=iHigh(_Symbol,tf,1);
   double close=iClose(_Symbol,tf,1);

   double tol=LiquidityTolerancePoints*_Point;

   if(low<lastSwingLow-tol&&close>lastSwingLow)
      bullishLiquiditySweep=true;

   if(high>lastSwingHigh+tol&&close<lastSwingHigh)
      bearishLiquiditySweep=true;
}

bool IsNearSupport(ENUM_TIMEFRAMES tf)
{
   if(lastSwingLow<=0)
      return false;

   return MathAbs(
      iClose(_Symbol,tf,1)-lastSwingLow
   )<=SRTolerancePoints*_Point;
}

bool IsNearResistance(ENUM_TIMEFRAMES tf)
{
   if(lastSwingHigh<=0)
      return false;

   return MathAbs(
      iClose(_Symbol,tf,1)-lastSwingHigh
   )<=SRTolerancePoints*_Point;
}

double FindSMTSwingLow(string symbol)
{
   int bars=Bars(symbol,EntryM5);
   int limit=MathMin(SMTLookback,bars);

   for(int i=SMTStrength+1;
       i<limit-SMTStrength;
       i++)
   {
      double l=iLow(symbol,EntryM5,i);
      bool ok=true;

      for(int j=1;j<=SMTStrength;j++)
      {
         if(l>=iLow(symbol,EntryM5,i-j)||
            l>=iLow(symbol,EntryM5,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
         return l;
   }

   return 0;
}

double FindSMTSwingHigh(string symbol)
{
   int bars=Bars(symbol,EntryM5);
   int limit=MathMin(SMTLookback,bars);

   for(int i=SMTStrength+1;
       i<limit-SMTStrength;
       i++)
   {
      double h=iHigh(symbol,EntryM5,i);
      bool ok=true;

      for(int j=1;j<=SMTStrength;j++)
      {
         if(h<=iHigh(symbol,EntryM5,i-j)||
            h<=iHigh(symbol,EntryM5,i+j))
         {
            ok=false;
            break;
         }
      }

      if(ok)
         return h;
   }

   return 0;
}

bool BullishSMT()
{
   if(!EnableSMT)
      return true;

   if(!SymbolSelect(SMT_Symbol,true))
      return false;

   double a=FindSMTSwingLow(_Symbol);
   double b=FindSMTSwingLow(SMT_Symbol);

   if(a<=0||b<=0)
      return false;

   double ca=iLow(_Symbol,EntryM5,1);
   double cb=iLow(SMT_Symbol,EntryM5,1);

   double t=SMTTolerancePoints*_Point;

   return
      (ca<a-t&&!(cb<b-t))||
      (cb<b-t&&!(ca<a-t));
}

bool BearishSMT()
{
   if(!EnableSMT)
      return true;

   if(!SymbolSelect(SMT_Symbol,true))
      return false;

   double a=FindSMTSwingHigh(_Symbol);
   double b=FindSMTSwingHigh(SMT_Symbol);

   if(a<=0||b<=0)
      return false;

   double ca=iHigh(_Symbol,EntryM5,1);
   double cb=iHigh(SMT_Symbol,EntryM5,1);

   double t=SMTTolerancePoints*_Point;

   return
      (ca>a+t&&!(cb>b+t))||
      (cb>b+t&&!(ca>a+t));
}

double GetATR()
{
   double a[];

   ArrayResize(a,1);
   ArraySetAsSeries(a,true);

   if(CopyBuffer(atrHandle,0,1,1,a)!=1)
      return 0;

   return a[0];
}

void OpenBuy()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double atr=GetATR();

   if(atr<=0)
      return;

   double sl=NormalizeDouble(
      ask-atr*SL_ATR_Multiplier,
      _Digits
   );

   double tp=NormalizeDouble(
      ask+
      atr*
      SL_ATR_Multiplier*
      RiskRewardRatio,
      _Digits
   );

   trade.Buy(
      LotSize,
      _Symbol,
      ask,
      sl,
      tp,
      "MTF SMC ICT SMT NEWS BUY"
   );
}

void OpenSell()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double atr=GetATR();

   if(atr<=0)
      return;

   double sl=NormalizeDouble(
      bid+atr*SL_ATR_Multiplier,
      _Digits
   );

   double tp=NormalizeDouble(
      bid-
      atr*
      SL_ATR_Multiplier*
      RiskRewardRatio,
      _Digits
   );

   trade.Sell(
      LotSize,
      _Symbol,
      bid,
      sl,
      tp,
      "MTF SMC ICT SMT NEWS SELL"
   );
}

bool SpreadAllowed()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   return
      ((ask-bid)/_Point)<=MaxSpreadPoints;
}

NewsAnalysis AnalyzeEconomicNews()
{
   NewsAnalysis r;

   r.eventFound=false;
   r.highImpact=false;
   r.mediumImpact=false;

   r.eventName="";
   r.currency="";
   r.eventTime=0;

   r.actual=0;
   r.forecast=0;
   r.previous=0;

   r.hasActual=false;
   r.hasForecast=false;
   r.hasPrevious=false;

   if(!EnableNewsFilter)
      return r;

   datetime now=TimeTradeServer();

   datetime from=
      now-NewsAfterMinutes*60;

   datetime to=
      now+NewsBeforeMinutes*60;

   string baseCurrency=
      SymbolInfoString(
         _Symbol,
         SYMBOL_CURRENCY_BASE
      );

   string profitCurrency=
      SymbolInfoString(
         _Symbol,
         SYMBOL_CURRENCY_PROFIT
      );

   MqlCalendarValue values[];

   int total=
      CalendarValueHistory(
         values,
         from,
         to,
         NULL,
         NULL
      );

   if(total<=0)
      return r;

   for(int i=0;i<total;i++)
   {
      MqlCalendarEvent event;

      if(!CalendarEventById(
            values[i].event_id,
            event))
         continue;

      MqlCalendarCountry country;

      if(!CalendarCountryById(
            event.country_id,
            country))
         continue;

      string currency=country.currency;

      bool relevant=
         currency==baseCurrency||
         currency==profitCurrency;

      if(!relevant)
         continue;

      bool highImpact=
         event.importance==
         CALENDAR_IMPORTANCE_HIGH;

      bool mediumImpact=
         event.importance==
         CALENDAR_IMPORTANCE_MODERATE;

      if(!highImpact&&!mediumImpact)
         continue;

      if(highImpact&&!BlockHighImpactNews)
         continue;

      if(mediumImpact&&!BlockMediumImpactNews)
         continue;

      r.eventFound=true;
      r.highImpact=highImpact;
      r.mediumImpact=mediumImpact;

      r.eventName=event.name;
      r.currency=currency;
      r.eventTime=values[i].time;

      if(values[i].HasActualValue())
      {
         r.actual=
            values[i].GetActualValue();

         r.hasActual=true;
      }

      if(values[i].HasForecastValue())
      {
         r.forecast=
            values[i].GetForecastValue();

         r.hasForecast=true;
      }

      if(values[i].HasPreviousValue())
      {
         r.previous=
            values[i].GetPreviousValue();

         r.hasPrevious=true;
      }

      return r;
   }

   return r;
}

double CalculateNewsSurprise(
   NewsAnalysis &n
)
{
   if(
      !n.hasActual||
      !n.hasForecast||
      n.forecast==0
   )
      return 0;

   return
      (n.actual-n.forecast)/
      MathAbs(n.forecast);
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(atrHandle!=INVALID_HANDLE)
      IndicatorRelease(atrHandle);

   Print("EA stopped.");
}
