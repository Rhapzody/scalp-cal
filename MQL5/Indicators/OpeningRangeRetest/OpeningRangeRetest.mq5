#property copyright "MT5 Trading Tools"
#property version "1.00"
#property description "M5 opening range breakout, retest and reclaim with ATR risk geometry."
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots 8
#property strict
#include "OpeningInputs.mqh"
input group "Display"
input int InpVisiblePlans=20;
input int InpPlanLengthBars=6;
input color InpBuyColor=clrLimeGreen;
input color InpSellColor=clrTomato;
input color InpRangeColor=clrDarkSlateGray;
input bool InpPopupAlert=false;
double Buy[],Sell[],Stop[],Target[],RangeHigh[],RangeLow[],BreakLevel[],SignalATR[];
ORConfig g_config; ORBar g_bars[]; ORSignal g_signals[]; string g_prefix="";
long g_last=0,g_first=0,g_alert=0; bool g_ready=false;
int OnInit()
{
   ORConfigure(g_config);
   if(_Period!=PERIOD_M5 || !ORConfigValid(g_config) || InpHistoryBars<ORWarmup(g_config)+20 || InpHistoryBars>20000 ||
      InpVisiblePlans<0 || InpVisiblePlans>100 || InpPlanLengthBars<1 || InpPlanLengthBars>100)
   { Print("OpeningRangeRetest: use M5 and valid Inputs; see README."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,Buy,INDICATOR_DATA); SetIndexBuffer(1,Sell,INDICATOR_DATA); SetIndexBuffer(2,Stop,INDICATOR_DATA);
   SetIndexBuffer(3,Target,INDICATOR_DATA); SetIndexBuffer(4,RangeHigh,INDICATOR_DATA); SetIndexBuffer(5,RangeLow,INDICATOR_DATA);
   SetIndexBuffer(6,BreakLevel,INDICATOR_DATA); SetIndexBuffer(7,SignalATR,INDICATOR_DATA);
   ArraySetAsSeries(Buy,false);ArraySetAsSeries(Sell,false);ArraySetAsSeries(Stop,false);ArraySetAsSeries(Target,false);
   ArraySetAsSeries(RangeHigh,false);ArraySetAsSeries(RangeLow,false);ArraySetAsSeries(BreakLevel,false);ArraySetAsSeries(SignalATR,false);
   string labels[8]={"Buy close","Sell close","Planned SL","Planned TP","Opening range high","Opening range low","Breakout level","ATR"};
   for(int i=0;i<8;i++){PlotIndexSetInteger(i,PLOT_DRAW_TYPE,i<2?DRAW_ARROW:DRAW_NONE);PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);PlotIndexSetString(i,PLOT_LABEL,labels[i]);}
   PlotIndexSetInteger(0,PLOT_ARROW,233);PlotIndexSetInteger(1,PLOT_ARROW,234);PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpBuyColor);PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpSellColor);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits); IndicatorSetString(INDICATOR_SHORTNAME,"Opening Range Retest M5");
   g_prefix="ORR_"+(string)ChartID()+"_"+(string)GetMicrosecondCount()+"_";
   if(!ObjectCreate(0,g_prefix+"status",OBJ_LABEL,0,0,0))return INIT_FAILED;
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_CORNER,CORNER_LEFT_LOWER);ObjectSetInteger(0,g_prefix+"status",OBJPROP_XDISTANCE,12);ObjectSetInteger(0,g_prefix+"status",OBJPROP_YDISTANCE,18);ObjectSetInteger(0,g_prefix+"status",OBJPROP_COLOR,clrSilver);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){if(g_prefix!="")ObjectsDeleteAll(0,g_prefix);}
int ORChartIndex(const datetime &time[],const int total,const long wanted)
{int lo=0,hi=total-1;while(lo<=hi){int mid=(lo+hi)/2;if((long)time[mid]==wanted)return mid;if((long)time[mid]<wanted)lo=mid+1;else hi=mid-1;}return -1;}
void ORLine(const string name,const long start,const long end,const double price,const color ink)
{if(!ObjectCreate(0,name,OBJ_TREND,0,(datetime)start,price,(datetime)end,price))return;ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,name,OBJPROP_COLOR,ink);ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<2)return 0; ArraySetAsSeries(time,false); long current=(long)time[rates_total-1];
   if(g_ready&&prev_calculated>0&&current==g_last&&g_first==(long)time[0])return rates_total;
   ArrayInitialize(Buy,EMPTY_VALUE);ArrayInitialize(Sell,EMPTY_VALUE);ArrayInitialize(Stop,EMPTY_VALUE);ArrayInitialize(Target,EMPTY_VALUE);ArrayInitialize(RangeHigh,EMPTY_VALUE);ArrayInitialize(RangeLow,EMPTY_VALUE);ArrayInitialize(BreakLevel,EMPTY_VALUE);ArrayInitialize(SignalATR,EMPTY_VALUE);
   ObjectsDeleteAll(0,g_prefix+"plan_"); MqlRates rates[];ArraySetAsSeries(rates,false);int n=CopyRates(_Symbol,PERIOD_M5,0,InpHistoryBars+1,rates);
   if(n<ORWarmup(g_config)+2||!SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED)||(long)rates[n-1].time!=current){ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"Opening Range | Loading M5 history");return 0;}
   if(ArrayResize(g_bars,n)!=n)return 0;for(int i=0;i<n;i++){g_bars[i].time=(long)rates[i].time;g_bars[i].open=rates[i].open;g_bars[i].high=rates[i].high;g_bars[i].low=rates[i].low;g_bars[i].close=rates[i].close;}
   if(!ORReplay(g_config,g_bars,n,current,g_signals))return 0;int total=ArraySize(g_signals);
   for(int i=0;i<total;i++){ORSignal s=g_signals[i];int j=ORChartIndex(time,rates_total,s.time);if(j>=0&&j<rates_total-1){if(s.direction==1)Buy[j]=s.price;else Sell[j]=s.price;Stop[j]=s.stop;Target[j]=s.target;RangeHigh[j]=s.range_high;RangeLow[j]=s.range_low;BreakLevel[j]=s.trigger;SignalATR[j]=s.atr;}if(i>=total-InpVisiblePlans){ORLine(g_prefix+"plan_"+(string)s.time+"_sl",s.time+300,s.time+300+InpPlanLengthBars*300,s.stop,clrIndianRed);ORLine(g_prefix+"plan_"+(string)s.time+"_tp",s.time+300,s.time+300+InpPlanLengthBars*300,s.target,clrSeaGreen);}}
   if(InpPopupAlert&&g_ready&&current>g_last&&total>0&&g_signals[total-1].time==current-300&&g_signals[total-1].time>g_alert){Alert("Opening Range Retest ",_Symbol,g_signals[total-1].direction==1?" BUY":" SELL");g_alert=g_signals[total-1].time;}
   ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"Opening Range | "+(string)total+" closed signals | plan before costs");g_last=current;g_first=(long)time[0];g_ready=true;return rates_total;
}
