#property copyright "TV Style MACD - independent MT5 implementation"
#property version "1.00"
#property description "TradingView-style MACD: separate MACD/Signal lines and four-color histogram."
#property description "Not affiliated with TradingView. Different price feeds/history can produce different values."
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots 3
#property indicator_label1 "Histogram"
#property indicator_type1 DRAW_COLOR_HISTOGRAM
#property indicator_color1 C'38,166,154',C'178,223,219',C'255,205,210',C'255,82,82'
#property indicator_width1 3
#property indicator_label2 "MACD"
#property indicator_type2 DRAW_LINE
#property indicator_color2 C'41,98,255'
#property indicator_width2 1
#property indicator_label3 "Signal"
#property indicator_type3 DRAW_LINE
#property indicator_color3 C'255,109,0'
#property indicator_width3 1
#property strict
#include "MACDCore.mqh"

input group "Calculation - TradingView defaults"
input int InpFastLength=12;
input int InpSlowLength=26;
input int InpSignalLength=9;
input ENUM_TV_SOURCE InpSource=TV_CLOSE;
input ENUM_TV_MA InpOscillatorMA=TV_EMA;
input ENUM_TV_MA InpSignalMA=TV_EMA;
input ENUM_TIMEFRAMES InpTimeframe=PERIOD_CURRENT;
input bool InpWaitForTimeframeClose=true; // MTF gaps; current chart timeframe remains live

input group "Show / hide components"
input bool InpShowMACD=true;
input bool InpShowSignal=true;
input bool InpShowHistogram=true;
input bool InpShowZeroLine=true;
input bool InpShowDataWindow=true;
input bool InpShowToggleButtons=false; // Optional buttons in this indicator pane

input group "MACD and Signal appearance"
input color InpMACDColor=C'41,98,255';
input color InpSignalColor=C'255,109,0';
input int InpMACDWidth=1;
input int InpSignalWidth=1;
input ENUM_LINE_STYLE InpMACDStyle=STYLE_SOLID;
input ENUM_LINE_STYLE InpSignalStyle=STYLE_SOLID;

input group "Histogram appearance"
input bool InpFourColorHistogram=true;
input color InpPositiveRising=C'38,166,154';
input color InpPositiveFalling=C'178,223,219';
input color InpNegativeRising=C'255,205,210';
input color InpNegativeFalling=C'255,82,82';
input int InpHistogramWidth=3; // MT5 native histogram width, 1..5 pixels

input group "Zero line and precision"
input color InpZeroColor=C'120,123,134';
input ENUM_LINE_STYLE InpZeroStyle=STYLE_SOLID;
input int InpZeroWidth=1;
input int InpDisplayDigits=4;

input group "Alerts - histogram crossing zero, closed bars only"
input bool InpAlertPositiveCross=false;
input bool InpAlertNegativeCross=false;
input bool InpPopupAlert=true;
input bool InpSoundAlert=false;
input string InpSoundFile="alert.wav";

double PlotHistogram[],PlotColors[],PlotMACD[],PlotSignal[];
int MappedIndices[];
double Src[],Fast[],Slow[],MACD[],Signal[],Histogram[],Palette[],FastSum[],SlowSum[],SignalSum[];
MqlRates SourceRates[];
ENUM_TIMEFRAMES g_tf;
bool g_show_macd,g_show_signal,g_show_hist,g_show_zero;
string g_name,g_prefix;
datetime g_first=0,g_last=0,g_last_alert_bar=0;
int g_count=0;
bool g_alert_primed=false;

void ResizeWorking(const int n)
{
   ArrayResize(Src,n); ArrayResize(Fast,n); ArrayResize(Slow,n);
   ArrayResize(MACD,n); ArrayResize(Signal,n); ArrayResize(Histogram,n);
   ArrayResize(Palette,n); ArrayResize(FastSum,n); ArrayResize(SlowSum,n); ArrayResize(SignalSum,n);
}

void CalculateBar(const int i,const double source)
{
   Src[i]=source;
   Fast[i]=TVMovingAverage(InpOscillatorMA,InpFastLength,i+1,source,i>0 ? Fast[i-1] : EMPTY_VALUE,
                           i>0 ? FastSum[i-1] : 0,i>=InpFastLength ? Src[i-InpFastLength] : 0,FastSum[i]);
   Slow[i]=TVMovingAverage(InpOscillatorMA,InpSlowLength,i+1,source,i>0 ? Slow[i-1] : EMPTY_VALUE,
                           i>0 ? SlowSum[i-1] : 0,i>=InpSlowLength ? Src[i-InpSlowLength] : 0,SlowSum[i]);
   MACD[i]=EMPTY_VALUE; Signal[i]=EMPTY_VALUE; Histogram[i]=EMPTY_VALUE; SignalSum[i]=0; Palette[i]=0;
   if(Fast[i]==EMPTY_VALUE || Slow[i]==EMPTY_VALUE) return;
   MACD[i]=Fast[i]-Slow[i];
   int first=InpOscillatorMA==TV_SMA ? (int)MathMax(InpFastLength,InpSlowLength)-1 : 0;
   int valid=i-first+1;
   Signal[i]=TVMovingAverage(InpSignalMA,InpSignalLength,valid,MACD[i],i>0 ? Signal[i-1] : EMPTY_VALUE,
                             i>0 ? SignalSum[i-1] : 0,valid>InpSignalLength ? MACD[i-InpSignalLength] : 0,SignalSum[i]);
   if(Signal[i]==EMPTY_VALUE) return;
   Histogram[i]=MACD[i]-Signal[i];
   Palette[i]=TVHistogramColor(Histogram[i],i>0 ? Histogram[i-1] : EMPTY_VALUE,InpFourColorHistogram);
}

datetime BarEnd(const datetime opened,const ENUM_TIMEFRAMES tf)
{
   if(tf!=PERIOD_MN1) return opened+PeriodSeconds(tf);
   MqlDateTime dt; TimeToStruct(opened,dt);
   dt.mon++; if(dt.mon>12) { dt.mon=1; dt.year++; }
   return StructToTime(dt);
}

void PutPlot(const int chart_index,const int source_index)
{
   MappedIndices[chart_index]=source_index;
   if(source_index<0 || source_index>=g_count)
   {
      PlotHistogram[chart_index]=EMPTY_VALUE; PlotColors[chart_index]=0;
      PlotMACD[chart_index]=EMPTY_VALUE; PlotSignal[chart_index]=EMPTY_VALUE;
      return;
   }
   PlotHistogram[chart_index]=g_show_hist ? Histogram[source_index] : EMPTY_VALUE;
   PlotColors[chart_index]=Palette[source_index];
   PlotMACD[chart_index]=g_show_macd ? MACD[source_index] : EMPTY_VALUE;
   PlotSignal[chart_index]=g_show_signal ? Signal[source_index] : EMPTY_VALUE;
}

void ApplyAppearance()
{
   // Keep the two-buffer histogram binding intact; hidden plots use EMPTY_VALUE
   // so they also stop affecting autoscale. Working calculation is unaffected.
   color cols[4]={InpPositiveRising,InpPositiveFalling,InpNegativeRising,InpNegativeFalling};
   for(int i=0;i<4;i++) PlotIndexSetInteger(0,PLOT_LINE_COLOR,i,g_show_hist ? cols[i] : clrNONE);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,g_show_macd ? InpMACDColor : clrNONE);
   PlotIndexSetInteger(2,PLOT_LINE_COLOR,g_show_signal ? InpSignalColor : clrNONE);
   PlotIndexSetInteger(0,PLOT_LINE_WIDTH,InpHistogramWidth);
   PlotIndexSetInteger(1,PLOT_LINE_WIDTH,InpMACDWidth);
   PlotIndexSetInteger(2,PLOT_LINE_WIDTH,InpSignalWidth);
   PlotIndexSetInteger(1,PLOT_LINE_STYLE,InpMACDStyle);
   PlotIndexSetInteger(2,PLOT_LINE_STYLE,InpSignalStyle);
   int line_type=g_tf!=(ENUM_TIMEFRAMES)_Period && InpWaitForTimeframeClose ? DRAW_SECTION : DRAW_LINE;
   PlotIndexSetInteger(1,PLOT_DRAW_TYPE,line_type);
   PlotIndexSetInteger(2,PLOT_DRAW_TYPE,line_type);
   for(int i=0;i<3;i++)
   {
      PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      bool visible=i==0 ? g_show_hist : (i==1 ? g_show_macd : g_show_signal);
      PlotIndexSetInteger(i,PLOT_SHOW_DATA,InpShowDataWindow && visible);
   }
   IndicatorSetInteger(INDICATOR_LEVELS,g_show_zero ? 1 : 0);
   if(g_show_zero)
   {
      IndicatorSetDouble(INDICATOR_LEVELVALUE,0,0.0);
      IndicatorSetInteger(INDICATOR_LEVELCOLOR,0,InpZeroColor);
      IndicatorSetInteger(INDICATOR_LEVELSTYLE,0,InpZeroStyle);
      IndicatorSetInteger(INDICATOR_LEVELWIDTH,0,InpZeroWidth);
      IndicatorSetString(INDICATOR_LEVELTEXT,0,"Zero");
   }
}

void Buttons()
{
   if(!InpShowToggleButtons) return;
   int pane=ChartWindowFind(); if(pane<1) return;
   string keys[4]={"MACD","SIGNAL","HIST","ZERO"};
   bool states[4]={g_show_macd,g_show_signal,g_show_hist,g_show_zero};
   for(int i=0;i<4;i++)
   {
      string name=g_prefix+keys[i];
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,pane,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12+(4-i)*76);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,22);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,72); ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,states[i] ? C'41,98,255' : C'54,58,69');
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'54,58,69');
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,name,OBJPROP_TEXT,keys[i]+(states[i] ? " ON" : " OFF"));
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
   }
}

void CheckAlerts(const int latest_closed,const datetime stamp)
{
   if(latest_closed<1 || latest_closed>=g_count) return;
   // Never fire historical alerts when attaching/reloading the indicator.
   if(!g_alert_primed) { g_alert_primed=true; g_last_alert_bar=stamp; return; }
   if(stamp<=g_last_alert_bar) return;
   g_last_alert_bar=stamp;
   int cross=TVHistogramCross(Histogram[latest_closed-1],Histogram[latest_closed]);
   if((cross>0 && !InpAlertPositiveCross) || (cross<0 && !InpAlertNegativeCross) || cross==0) return;
   string tf=EnumToString(g_tf); StringReplace(tf,"PERIOD_","");
   string message="TV Style MACD | "+_Symbol+" "+tf+" | Histogram "+(cross>0 ? "crossed above zero" : "crossed below zero")+" | "+TimeToString(stamp);
   Print(message);
   if(InpPopupAlert) Alert(message);
   if(InpSoundAlert) PlaySound(InpSoundFile);
}

int OnInit()
{
   if(InpFastLength<1 || InpSlowLength<1 || InpSignalLength<1 ||
      InpFastLength>10000 || InpSlowLength>10000 || InpSignalLength>10000 ||
      InpMACDWidth<1 || InpMACDWidth>5 || InpSignalWidth<1 || InpSignalWidth>5 ||
      InpHistogramWidth<1 || InpHistogramWidth>5 || InpZeroWidth<1 || InpZeroWidth>5 ||
      InpDisplayDigits<0 || InpDisplayDigits>8)
   { Print("TV Style MACD: lengths must be 1..10000, widths 1..5, digits 0..8"); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,PlotHistogram,INDICATOR_DATA);
   SetIndexBuffer(1,PlotColors,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,PlotMACD,INDICATOR_DATA);
   SetIndexBuffer(3,PlotSignal,INDICATOR_DATA);
   ArraySetAsSeries(PlotHistogram,false); ArraySetAsSeries(PlotColors,false);
   ArraySetAsSeries(PlotMACD,false); ArraySetAsSeries(PlotSignal,false);
   ArraySetAsSeries(SourceRates,false);
   g_tf=InpTimeframe==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpTimeframe;
   g_show_macd=InpShowMACD; g_show_signal=InpShowSignal; g_show_hist=InpShowHistogram; g_show_zero=InpShowZeroLine;
   g_name=StringFormat("TV MACD (%d,%d,%d)",InpFastLength,InpSlowLength,InpSignalLength);
   if(g_tf!=(ENUM_TIMEFRAMES)_Period) { string tf=EnumToString(g_tf); StringReplace(tf,"PERIOD_",""); g_name+=" "+tf; }
   IndicatorSetString(INDICATOR_SHORTNAME,g_name);
   IndicatorSetInteger(INDICATOR_DIGITS,InpDisplayDigits);
   g_prefix="TVMACD."+IntegerToString(ChartID())+"."+IntegerToString((long)GetMicrosecondCount())+".";
   ApplyAppearance();
   if(InpShowToggleButtons) EventSetTimer(1);
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArrayResize(MappedIndices,rates_total);
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false); ArraySetAsSeries(close,false);
   if(prev_calculated==0)
   {
      ArrayInitialize(MappedIndices,-1);
      ArrayInitialize(PlotHistogram,EMPTY_VALUE); ArrayInitialize(PlotColors,0);
      ArrayInitialize(PlotMACD,EMPTY_VALUE); ArrayInitialize(PlotSignal,EMPTY_VALUE);
      g_alert_primed=false;
   }
   if(g_tf==(ENUM_TIMEFRAMES)_Period)
   {
      bool reset=prev_calculated==0 || g_count>rates_total || g_first!=time[0] || g_count==0;
      int start=reset ? 0 : (int)MathMax(0,prev_calculated-1);
      ResizeWorking(rates_total); g_count=rates_total;
      for(int i=start;i<rates_total;i++)
      {
         CalculateBar(i,TVPrice(InpSource,open[i],high[i],low[i],close[i])); PutPlot(i,i);
      }
      g_first=time[0]; g_last=time[rates_total-1];
      if(rates_total>1) CheckAlerts(rates_total-2,time[rates_total-2]);
   }
   else
   {
      int available=Bars(_Symbol,g_tf);
      if(available<1) return 0;
      int copied=CopyRates(_Symbol,g_tf,0,available,SourceRates);
      if(copied<1 || !SeriesInfoInteger(_Symbol,g_tf,SERIES_SYNCHRONIZED)) return 0;
      bool reset=prev_calculated==0 || copied<g_count || g_count==0 || g_first!=SourceRates[0].time;
      if(!reset && (g_count>copied || SourceRates[g_count-1].time!=g_last)) reset=true;
      int start=reset ? 0 : (int)MathMax(0,g_count-1);
      ResizeWorking(copied); g_count=copied;
      for(int i=start;i<copied;i++)
         CalculateBar(i,TVPrice(InpSource,SourceRates[i].open,SourceRates[i].high,SourceRates[i].low,SourceRates[i].close));
      g_first=SourceRates[0].time; g_last=SourceRates[copied-1].time;
      // Full mapping rebuild is intentional: closing a source candle changes
      // which chart bar owns its confirmed value. No final HTF value leaks back.
      int confirmed=-1,developing=-1;
      datetime now=TimeCurrent();
      for(int i=0;i<rates_total;i++)
      {
         bool live=i==rates_total-1;
         datetime cutoff=BarEnd(time[i],(ENUM_TIMEFRAMES)_Period);
         if(live && now<cutoff) cutoff=now;
         while(confirmed+1<copied && BarEnd(SourceRates[confirmed+1].time,g_tf)<=cutoff) confirmed++;
         while(developing+1<copied && SourceRates[developing+1].time<=cutoff) developing++;
         bool completed_here=confirmed>=0 && BarEnd(SourceRates[confirmed].time,g_tf)>time[i];
         int mapped=TVMappedIndex(confirmed,developing,live,InpWaitForTimeframeClose,completed_here);
         PutPlot(i,mapped);
      }
      // Alert only completed source bars, independently of chart aggregation.
      int last_closed=copied-1;
      if(BarEnd(SourceRates[last_closed].time,g_tf)>now) last_closed--;
      if(last_closed>=1) CheckAlerts(last_closed,SourceRates[last_closed].time);
   }
   Buttons();
   return rates_total;
}

void OnTimer() { Buttons(); }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE) { Buttons(); return; }
   if(id!=CHARTEVENT_OBJECT_CLICK || StringFind(sparam,g_prefix)!=0) return;
   string key=StringSubstr(sparam,StringLen(g_prefix));
   if(key=="MACD") g_show_macd=!g_show_macd;
   if(key=="SIGNAL") g_show_signal=!g_show_signal;
   if(key=="HIST") g_show_hist=!g_show_hist;
   if(key=="ZERO") g_show_zero=!g_show_zero;
   ApplyAppearance();
   for(int i=0;i<ArraySize(MappedIndices);i++) PutPlot(i,MappedIndices[i]);
   Buttons(); ChartRedraw();
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
}
