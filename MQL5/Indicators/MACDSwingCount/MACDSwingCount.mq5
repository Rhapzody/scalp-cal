#property copyright "MT5 Trading Tools"
#property version "1.20"
#property description "MACD cross or histogram-color swings with closed-bar confirmation and market structure."
#property indicator_chart_window
#property indicator_buffers 12
#property indicator_plots 12
#property strict
#include "SwingCore.mqh"

input group "MACD - EMA / EMA, Close source"
input int InpFastEMA=12;
input int InpSlowEMA=26;
input int InpSignalEMA=9;
input int InpWarmupBars=0; // 0=automatic; otherwise number of consecutive valid closed bars
input group "MACD cross filter only - not used in Histogram color mode"
input ENUM_MS_THRESHOLD InpThresholdMode=MS_PRICE;
input double InpMinHistogram=0.0;
input int InpATRLength=14;
input group "Swing labels"
input int InpVisibleSwings=10; // 0 hides labels and connecting lines, buffers remain available
input ENUM_MS_LABEL InpLabelMode=MS_NUMBER_STRUCTURE;
input int InpFontSize=10;
input double InpOffsetPoints=80;
input color InpHighColor=clrTomato;
input color InpLowColor=clrDeepSkyBlue;
input bool InpShowLines=false;
input color InpLineColor=clrSilver;
input group "Confirmation candle markers"
input bool InpShowConfirmation=true;
input int InpArrowWidth=1;
input int InpArrowGapPixels=12;
input group "Notifications"
input bool InpPopupAlert=false; // New confirmed swing only; no history alerts on attach/reload
input bool InpDebug=false;
// Append to preserve all existing positional iCustom input arguments.
input group "Swing detection mode"
input ENUM_MS_SWING_MODE InpSwingMode=MS_MACD_CROSS;
input group "Swing support / resistance rays"
input bool InpShowSR=true;
input int InpSRCount=10; // Latest confirmed swings in total, independent of label count
input ENUM_MS_SR_ANCHOR InpSRAnchor=MS_SR_WICK;
input color InpResistanceColor=clrTomato;
input color InpSupportColor=clrDeepSkyBlue;
input int InpSRWidth=1; // 1..5

double SwingHigh[],SwingLow[],EventType[],EventPrice[],EventSwingTime[],EventClass[];
double HighConfirmation[],LowConfirmation[],MACDValues[],SignalValues[],HistogramValues[],ThresholdValues[];
MSConfig g_config;
MSEngine g_engine;
MSEvent g_events[];
int g_event_count=0,g_processed=0,g_rates=0;
long g_first_time=0,g_processed_time=0;
string g_prefix="";

void ClearBuffers()
{
   ArrayInitialize(SwingHigh,EMPTY_VALUE); ArrayInitialize(SwingLow,EMPTY_VALUE);
   ArrayInitialize(EventType,EMPTY_VALUE); ArrayInitialize(EventPrice,EMPTY_VALUE);
   ArrayInitialize(EventSwingTime,EMPTY_VALUE); ArrayInitialize(EventClass,EMPTY_VALUE);
   ArrayInitialize(HighConfirmation,EMPTY_VALUE); ArrayInitialize(LowConfirmation,EMPTY_VALUE);
   ArrayInitialize(MACDValues,EMPTY_VALUE); ArrayInitialize(SignalValues,EMPTY_VALUE);
   ArrayInitialize(HistogramValues,EMPTY_VALUE); ArrayInitialize(ThresholdValues,EMPTY_VALUE);
}

void ClearBar(const int i)
{
   SwingHigh[i]=EMPTY_VALUE; SwingLow[i]=EMPTY_VALUE;
   EventType[i]=EMPTY_VALUE; EventPrice[i]=EMPTY_VALUE;
   EventSwingTime[i]=EMPTY_VALUE; EventClass[i]=EMPTY_VALUE;
   HighConfirmation[i]=EMPTY_VALUE; LowConfirmation[i]=EMPTY_VALUE;
   MACDValues[i]=EMPTY_VALUE; SignalValues[i]=EMPTY_VALUE;
   HistogramValues[i]=EMPTY_VALUE; ThresholdValues[i]=EMPTY_VALUE;
}

string ClassText(const int value)
{
   switch(value)
   {
      case MS_HH: return "HH"; case MS_LH: return "LH"; case MS_EH: return "EH";
      case MS_HL: return "HL"; case MS_LL: return "LL"; case MS_EL: return "EL";
      case MS_FIRST_HIGH: return "H"; case MS_FIRST_LOW: return "L";
   }
   return "?";
}

int OnInit()
{
   g_config.fast=InpFastEMA; g_config.slow=InpSlowEMA; g_config.signal=InpSignalEMA;
   g_config.warmup=InpWarmupBars; g_config.atr_length=InpATRLength;
   g_config.threshold_mode=InpThresholdMode; g_config.threshold=InpMinHistogram; g_config.point=_Point;
   g_config.swing_mode=InpSwingMode;
   if(!MSConfigValid(g_config) || InpVisibleSwings<0 || InpVisibleSwings>1000 ||
      InpFontSize<6 || InpFontSize>72 || !MathIsValidNumber(InpOffsetPoints) || InpOffsetPoints<0 ||
      InpArrowWidth<1 || InpArrowWidth>5 || InpArrowGapPixels<0 || InpArrowGapPixels>1000 ||
      InpSRCount<0 || InpSRCount>1000 || InpSRWidth<1 || InpSRWidth>5 ||
      InpSRAnchor<MS_SR_WICK || InpSRAnchor>MS_SR_BODY ||
      InpLabelMode<MS_NUMBER || InpLabelMode>MS_NUMBER_STRUCTURE)
   { Print("MACDSwingCount: invalid Inputs. See the indicator manual for allowed ranges."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,SwingHigh,INDICATOR_DATA); SetIndexBuffer(1,SwingLow,INDICATOR_DATA);
   SetIndexBuffer(2,EventType,INDICATOR_DATA); SetIndexBuffer(3,EventPrice,INDICATOR_DATA);
   SetIndexBuffer(4,EventSwingTime,INDICATOR_DATA); SetIndexBuffer(5,EventClass,INDICATOR_DATA);
   SetIndexBuffer(6,HighConfirmation,INDICATOR_DATA); SetIndexBuffer(7,LowConfirmation,INDICATOR_DATA);
   SetIndexBuffer(8,MACDValues,INDICATOR_DATA); SetIndexBuffer(9,SignalValues,INDICATOR_DATA);
   SetIndexBuffer(10,HistogramValues,INDICATOR_DATA); SetIndexBuffer(11,ThresholdValues,INDICATOR_DATA);
   ArraySetAsSeries(SwingHigh,false); ArraySetAsSeries(SwingLow,false);
   ArraySetAsSeries(EventType,false); ArraySetAsSeries(EventPrice,false);
   ArraySetAsSeries(EventSwingTime,false); ArraySetAsSeries(EventClass,false);
   ArraySetAsSeries(HighConfirmation,false); ArraySetAsSeries(LowConfirmation,false);
   ArraySetAsSeries(MACDValues,false); ArraySetAsSeries(SignalValues,false);
   ArraySetAsSeries(HistogramValues,false); ArraySetAsSeries(ThresholdValues,false);
   string names[12]={"Swing High (backdated)","Swing Low (backdated)","Confirmed type H=1 L=-1",
                     "Confirmed pivot price","Pivot time (Unix)","Structure code",
                     "High confirmed","Low confirmed","MACD (closed)","Signal (closed)",
                     "Histogram (closed)","Threshold (price)"};
   for(int p=0;p<12;p++)
   {
      PlotIndexSetString(p,PLOT_LABEL,names[p]);
      PlotIndexSetInteger(p,PLOT_DRAW_TYPE,(p==6 || p==7) && InpShowConfirmation ? DRAW_ARROW : DRAW_NONE);
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   }
   PlotIndexSetInteger(6,PLOT_ARROW,234); PlotIndexSetInteger(7,PLOT_ARROW,233);
   PlotIndexSetInteger(6,PLOT_ARROW_SHIFT,-InpArrowGapPixels); PlotIndexSetInteger(7,PLOT_ARROW_SHIFT,InpArrowGapPixels);
   PlotIndexSetInteger(6,PLOT_LINE_COLOR,InpHighColor); PlotIndexSetInteger(7,PLOT_LINE_COLOR,InpLowColor);
   PlotIndexSetInteger(6,PLOT_LINE_WIDTH,InpArrowWidth); PlotIndexSetInteger(7,PLOT_LINE_WIDTH,InpArrowWidth);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"MACD Swing Count "+
                      (InpSwingMode==MS_HISTOGRAM_COLOR ? "Histogram" : "Cross")+" ("+IntegerToString(InpFastEMA)+","+
                      IntegerToString(InpSlowEMA)+","+IntegerToString(InpSignalEMA)+")");
   // Reserve an owner object. No instance deletes another instance's labels.
   string base="MSC_"+(string)ChartID()+"_"+(string)GetMicrosecondCount()+"_";
   int suffix=0;
   do { g_prefix=base+IntegerToString(suffix++)+"_"; } while(ObjectFind(0,g_prefix+"owner")>=0);
   if(!ObjectCreate(0,g_prefix+"owner",OBJ_LABEL,0,0,0)) { g_prefix=""; return INIT_FAILED; }
   ObjectSetString(0,g_prefix+"owner",OBJPROP_TEXT,"");
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_HIDDEN,true);
   MSReset(g_engine); g_event_count=0; g_processed=0; g_rates=0;
   g_first_time=0; g_processed_time=0; ArrayResize(g_events,0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
}

void RenderSRLevels()
{
   if(g_prefix=="") return;
   ObjectsDeleteAll(0,g_prefix+"sr_");
   if(!InpShowSR || InpSRCount<=0) return;
   int first=(int)MathMax(0,g_event_count-InpSRCount);
   long seconds=(long)MathMax(1,PeriodSeconds((ENUM_TIMEFRAMES)_Period));
   for(int j=g_event_count-1;j>=first;j--)
   {
      MSEvent e=g_events[j];
      string name=g_prefix+"sr_"+IntegerToString(g_event_count-j);
      double price=MSSRPrice(e,InpSRAnchor);
      // Equal-price anchors form a horizontal ray from the pivot candle to the right.
      ObjectCreate(0,name,OBJ_TREND,0,(datetime)e.pivot_time,price,(datetime)(e.pivot_time+seconds),price);
      ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
      ObjectSetInteger(0,name,OBJPROP_COLOR,e.type==1 ? InpResistanceColor : InpSupportColor);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,InpSRWidth);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      string kind=e.type==1 ? "Resistance" : "Support";
      ObjectSetString(0,name,OBJPROP_TOOLTIP,kind+
                      (InpSRAnchor==MS_SR_BODY ? " (swing body) " : " (swing wick) ")+DoubleToString(price,_Digits));
   }
}

void RenderSwings()
{
   RenderSRLevels();
   // Rebuild only this instance's small visible object set when its swings change.
   ObjectsDeleteAll(0,g_prefix+"view_");
   int first=(int)MathMax(0,g_event_count-InpVisibleSwings);
   for(int j=g_event_count-1;j>=first;j--)
   {
      MSEvent e=g_events[j];
      int number=g_event_count-j;
      string label=InpLabelMode==MS_NUMBER ? IntegerToString(number) :
                   (InpLabelMode==MS_STRUCTURE ? ClassText(e.classification) :
                    IntegerToString(number)+" "+ClassText(e.classification));
      string name=g_prefix+"view_label_"+IntegerToString(number);
      double price=e.price+(e.type==1 ? 1 : -1)*InpOffsetPoints*_Point;
      ObjectCreate(0,name,OBJ_TEXT,0,(datetime)e.pivot_time,price);
      ObjectSetString(0,name,OBJPROP_TEXT,label);
      ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,InpFontSize);
      ObjectSetInteger(0,name,OBJPROP_COLOR,e.type==1 ? InpHighColor : InpLowColor);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,e.type==1 ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,(e.type==1 ? "High " : "Low ")+DoubleToString(e.price,_Digits)+
                      " | pivot "+TimeToString((datetime)e.pivot_time)+
                      " | confirmation candle "+TimeToString((datetime)e.confirm_time)+" (known after close)");
      if(InpShowLines && j>first)
      {
         MSEvent older=g_events[j-1];
         string line=g_prefix+"view_line_"+IntegerToString(number);
         ObjectCreate(0,line,OBJ_TREND,0,(datetime)older.pivot_time,older.price,(datetime)e.pivot_time,e.price);
         ObjectSetInteger(0,line,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,line,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,line,OBJPROP_COLOR,InpLineColor); ObjectSetInteger(0,line,OBJPROP_BACK,true);
         ObjectSetInteger(0,line,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,line,OBJPROP_HIDDEN,true);
      }
   }
   ChartRedraw();
}

void ReportLatest(const bool reset,const int last_closed)
{
   if(g_event_count==0) return;
   MSEvent e=g_events[g_event_count-1];
   if(InpDebug) PrintFormat("MACDSwingCount: %d swings; latest %s price=%s pivot=%s confirmation candle=%s reset=%s",
                           g_event_count,ClassText(e.classification),DoubleToString(e.price,_Digits),
                           TimeToString((datetime)e.pivot_time),TimeToString((datetime)e.confirm_time),reset ? "true" : "false");
   if(InpPopupAlert && !reset && e.confirm_index==last_closed)
      Alert(_Symbol," ",EnumToString((ENUM_TIMEFRAMES)_Period),
            InpSwingMode==MS_HISTOGRAM_COLOR ? " Histogram " : " Cross ",ClassText(e.classification),
            " confirmed: ",DoubleToString(e.price,_Digits)," | pivot ",TimeToString((datetime)e.pivot_time));
}

bool CalculateClosedBar(const int i,const long timestamp,const double o,const double h,const double l,const double c)
{
   ClearBar(i);
   MSBar bar={timestamp,o,h,l,c};
   MSEvent event;
   if(!MSProcess(g_config,bar,i,g_engine,event)) return true; // Invalid OHLC resets core, no signal.
   MACDValues[i]=g_engine.fast-g_engine.slow; SignalValues[i]=g_engine.signal;
   HistogramValues[i]=g_engine.histogram; ThresholdValues[i]=g_engine.threshold;
   if(event.type==0) return true;
   if(g_event_count>=ArraySize(g_events) && ArrayResize(g_events,g_event_count+256)<g_event_count+1)
      return false;
   g_events[g_event_count++]=event;
   if(event.type==1) { SwingHigh[event.pivot_index]=event.price; HighConfirmation[i]=h; }
   else { SwingLow[event.pivot_index]=event.price; LowConfirmation[i]=l; }
   EventType[i]=event.type; EventPrice[i]=event.price;
   EventSwingTime[i]=(double)event.pivot_time; EventClass[i]=event.classification;
   return true;
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false); ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false); ArraySetAsSeries(close,false);
   int closed=rates_total-1;
   bool reset=prev_calculated==0 || prev_calculated!=g_rates || rates_total<g_rates ||
              g_processed>closed || g_first_time!=(long)time[0];
   if(!reset && g_processed>0 && g_processed_time!=(long)time[g_processed-1]) reset=true;
   if(reset)
   {
      ClearBuffers(); MSReset(g_engine); g_event_count=0; g_processed=0;
      g_processed_time=0; g_first_time=(long)time[0];
   }
   int old_events=g_event_count;
   for(int i=g_processed;i<closed;i++)
   {
      if(IsStopped() || !CalculateClosedBar(i,(long)time[i],open[i],high[i],low[i],close[i])) return 0;
      g_processed=i+1; g_processed_time=(long)time[i];
   }
   ClearBar(closed); // Shift 0 is always EMPTY_VALUE, including MACD debug buffers.
   g_rates=rates_total;
   if(reset || old_events!=g_event_count)
   {
      RenderSwings();
      ReportLatest(reset,closed-1);
   }
   return rates_total;
}
