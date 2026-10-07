#property copyright "MT5 Trading Tools"
#property version "1.00"
#property description "M5 trend-filtered sweep and reclaim; closed bars, prior levels, planned 2R and room filter."
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots 7
#property strict
#include "SweepInputs.mqh"
input group "Display"
input int InpVisiblePlans=20;
input int InpPlanLengthBars=6;
input color InpBuyColor=clrLimeGreen;
input color InpSellColor=clrTomato;
input bool InpPopupAlert=false;
double Buy[],Sell[],Stop[],Target[],Level[],Obstacle[],SignalATR[];
TSConfig g_config;
TSBar g_bars[];
TSSignal g_signals[];
string g_prefix="";
long g_last=0,g_first=0,g_alert=0;
bool g_ready=false;
int OnInit()
{
   TSConfigure(g_config);
   if(_Period!=PERIOD_M5 || !TSValid(g_config) || InpHistoryBars<TSWarmup(g_config)+g_config.room_bars+1 ||
      InpHistoryBars>20000 || InpVisiblePlans<0 || InpVisiblePlans>100 || InpPlanLengthBars<1 || InpPlanLengthBars>100)
   { Print("TrendSweepReclaim: use M5 and valid Inputs; see README."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,Buy,INDICATOR_DATA); SetIndexBuffer(1,Sell,INDICATOR_DATA);
   SetIndexBuffer(2,Stop,INDICATOR_DATA); SetIndexBuffer(3,Target,INDICATOR_DATA);
   SetIndexBuffer(4,Level,INDICATOR_DATA); SetIndexBuffer(5,Obstacle,INDICATOR_DATA);
   SetIndexBuffer(6,SignalATR,INDICATOR_DATA);
   ArraySetAsSeries(Buy,false); ArraySetAsSeries(Sell,false); ArraySetAsSeries(Stop,false);
   ArraySetAsSeries(Target,false); ArraySetAsSeries(Level,false); ArraySetAsSeries(Obstacle,false); ArraySetAsSeries(SignalATR,false);
   string labels[7]={"Buy close","Sell close","Planned SL","Planned TP","Swept level","Room limit","Prior ATR"};
   for(int k=0;k<7;k++)
   {
      PlotIndexSetInteger(k,PLOT_DRAW_TYPE,k<2 ? DRAW_ARROW : DRAW_NONE);
      PlotIndexSetDouble(k,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetString(k,PLOT_LABEL,labels[k]);
   }
   PlotIndexSetInteger(0,PLOT_ARROW,233); PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpBuyColor); PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpSellColor);
   PlotIndexSetInteger(0,PLOT_LINE_WIDTH,2); PlotIndexSetInteger(1,PLOT_LINE_WIDTH,2);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"Trend Sweep Reclaim M5");
   g_prefix="TSR_"+(string)ChartID()+"_"+(string)GetMicrosecondCount()+"_";
   if(!ObjectCreate(0,g_prefix+"status",OBJ_LABEL,0,0,0)) return INIT_FAILED;
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_YDISTANCE,18);
   ObjectSetInteger(0,g_prefix+"status",OBJPROP_COLOR,clrSilver);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { if(g_prefix!="") ObjectsDeleteAll(0,g_prefix); }
int TSChartIndex(const datetime &time[],const int total,const long wanted)
{
   int lo=0,hi=total-1;
   while(lo<=hi) { int mid=(lo+hi)/2; if((long)time[mid]==wanted) return mid;
      if((long)time[mid]<wanted) lo=mid+1; else hi=mid-1; }
   return -1;
}
void TSLine(const string name,const long known,const double price,const color ink)
{
   if(!ObjectCreate(0,name,OBJ_TREND,0,(datetime)known,price,(datetime)(known+300*InpPlanLengthBars),price)) return;
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"Signal-close plan; actual EA prices depend on spread/entry | "+DoubleToString(price,_Digits));
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<2) return 0;
   ArraySetAsSeries(time,false);
   long current=(long)time[rates_total-1];
   if(g_ready && prev_calculated>0 && current==g_last && g_first==(long)time[0]) return rates_total;
   ArrayInitialize(Buy,EMPTY_VALUE); ArrayInitialize(Sell,EMPTY_VALUE); ArrayInitialize(Stop,EMPTY_VALUE);
   ArrayInitialize(Target,EMPTY_VALUE); ArrayInitialize(Level,EMPTY_VALUE); ArrayInitialize(Obstacle,EMPTY_VALUE); ArrayInitialize(SignalATR,EMPTY_VALUE);
   ObjectsDeleteAll(0,g_prefix+"plan_");
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int n=CopyRates(_Symbol,PERIOD_M5,0,InpHistoryBars+1,rates);
   if(n<TSWarmup(g_config)+2 || !SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED) || (long)rates[n-1].time!=current)
   { ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"Trend Sweep | Loading M5 history"); return 0; }
   if(ArrayResize(g_bars,n)!=n) return 0;
   for(int i=0;i<n;i++)
   { g_bars[i].time=(long)rates[i].time; g_bars[i].open=rates[i].open; g_bars[i].high=rates[i].high; g_bars[i].low=rates[i].low; g_bars[i].close=rates[i].close; }
   if(!TSReplay(g_config,g_bars,n,current,g_signals)) return 0;
   int total=ArraySize(g_signals);
   for(int i=0;i<total;i++)
   {
      TSSignal s=g_signals[i]; int j=TSChartIndex(time,rates_total,s.time);
      if(j>=0 && j<rates_total-1)
      {
         if(s.direction==1) Buy[j]=s.price; else Sell[j]=s.price;
         Stop[j]=s.stop; Target[j]=s.target; Level[j]=s.trigger; Obstacle[j]=s.obstacle; SignalATR[j]=s.atr;
      }
      if(i>=total-InpVisiblePlans)
      {
         string base=g_prefix+"plan_"+(string)s.time;
         TSLine(base+"_SL",s.time+300,s.stop,clrIndianRed);
         TSLine(base+"_TP",s.time+300,s.target,clrSeaGreen);
      }
   }
   if(InpPopupAlert && g_ready && current>g_last && total>0)
   {
      TSSignal s=g_signals[total-1];
      if(s.time==current-300 && s.time>g_alert)
      { Alert("Trend Sweep Reclaim ",_Symbol,s.direction==1 ? " BUY" : " SELL"," | M5 closed"); g_alert=s.time; }
   }
   ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"Trend Sweep M5 | "+(string)total+" historical signals | plans before costs");
   g_last=current; g_first=(long)time[0]; g_ready=true;
   return rates_total;
}
