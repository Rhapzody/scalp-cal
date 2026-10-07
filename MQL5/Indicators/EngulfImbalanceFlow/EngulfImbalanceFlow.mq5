#property copyright "EngulfImbalanceFlow"
#property version "1.08"
#property description "FVG only, no trend filter. Engulf head wick is at most 10% of body. A close extended over 30% beyond the engulfed wick must pull back within spread in the next two bars."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots 6
#property indicator_label1 "Combo buy"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrLimeGreen
#property indicator_width1 2
#property indicator_label2 "Combo sell"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrRed
#property indicator_width2 2
#property indicator_label3 "Pattern (1 A / 2 B / 3 both)"
#property indicator_type3 DRAW_NONE
#property indicator_label4 "Direction (+1 buy / -1 sell)"
#property indicator_type4 DRAW_NONE
#property indicator_label5 "Pattern A confirmation time"
#property indicator_type5 DRAW_NONE
#property indicator_label6 "Pattern B confirmation time"
#property indicator_type6 DRAW_NONE
#property strict
#include "EngulfImbalanceCore.mqh"
#include "FVGCore.mqh"

input group "Pattern"
input int InpLookbackBars=0; // Closed bars to scan; 0 = all loaded history
input int InpMaxGapBars=5; // Max candles between confirmation and pattern B; 1..5 is the default rule
input int InpMaxSignals=300; // Newest chart marks, 1..5000; buffers still keep every signal

input group "Arrows"
input color InpBuyColor=clrLimeGreen;
input color InpSellColor=clrRed;
input int InpArrowWidth=2; // 1..5
input int InpArrowGapPixels=12; // Distance from the engulf wick

input group "Marks"
input color InpBodyColor=clrDodgerBlue; // Outline of the confirmation candle body
input color InpWickLineColor=clrGold; // Pattern B wick-tip line back to that body
input color InpLabelColor=clrWhite;
input int InpLabelSize=9; // 6..16

input group "FVG detection - confirmation candle is candle 3"
input double InpMinGapPoints=0; // Minimum gap in symbol points (not pips)
input bool InpRequireMiddleDirection=false; // Middle candle must agree with gap direction

double BuyBuffer[],SellBuffer[],PatternBuffer[],DirectionBuffer[];
double AnchorATimeBuffer[],AnchorBTimeBuffer[];
string g_prefix="";
datetime g_first_bar=0,g_current_bar=0;

int OnInit()
{
   if(InpLookbackBars<0 || (InpLookbackBars>0 && InpLookbackBars<3) || InpLookbackBars>100000 ||
      InpMaxGapBars<0 || InpMaxGapBars>100000 || InpMaxSignals<1 || InpMaxSignals>5000 ||
      InpArrowWidth<1 || InpArrowWidth>5 || InpArrowGapPixels<0 ||
      InpLabelSize<6 || InpLabelSize>16 ||
      !MathIsValidNumber(InpMinGapPoints) || InpMinGapPoints<0 ||
      !MathIsValidNumber(InpMinGapPoints*_Point) || _Point<=0)
   {
      Print("EngulfImbalanceFlow: invalid Inputs. Lookback 0 scans all loaded bars; pattern B gap 0 is unlimited inside that window.");
      return INIT_PARAMETERS_INCORRECT;
   }
   SetIndexBuffer(0,BuyBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SellBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,PatternBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,DirectionBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,AnchorATimeBuffer,INDICATOR_DATA);
   SetIndexBuffer(5,AnchorBTimeBuffer,INDICATOR_DATA);
   ArraySetAsSeries(BuyBuffer,false); ArraySetAsSeries(SellBuffer,false);
   ArraySetAsSeries(PatternBuffer,false); ArraySetAsSeries(DirectionBuffer,false);
   ArraySetAsSeries(AnchorATimeBuffer,false); ArraySetAsSeries(AnchorBTimeBuffer,false);
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,InpArrowGapPixels);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,-InpArrowGapPixels);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpBuyColor);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpSellColor);
   for(int plot=0;plot<6;plot++)
   {
      if(plot<2) PlotIndexSetInteger(plot,PLOT_LINE_WIDTH,InpArrowWidth);
      PlotIndexSetInteger(plot,PLOT_DRAW_BEGIN,2);
      PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   }
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"EngulfImbalanceFlow (A or B, no trend filter)");
   string base="EI_"+IntegerToString((int)(ChartID()%100000))+"_"+
               IntegerToString((int)(GetMicrosecondCount()%1000000))+"_";
   int suffix=0;
   do { g_prefix=base+IntegerToString(suffix++)+"_"; }
   while(ObjectFind(0,g_prefix+"owner")>=0);
   if(!ObjectCreate(0,g_prefix+"owner",OBJ_LABEL,0,0,0)) { g_prefix=""; return INIT_FAILED; }
   ObjectSetString(0,g_prefix+"owner",OBJPROP_TEXT,"");
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_HIDDEN,true);
   g_first_bar=0; g_current_bar=0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
   ChartRedraw(0);
}

void EIClear()
{
   ArrayInitialize(BuyBuffer,EMPTY_VALUE);
   ArrayInitialize(SellBuffer,EMPTY_VALUE);
   ArrayInitialize(PatternBuffer,EMPTY_VALUE);
   ArrayInitialize(DirectionBuffer,EMPTY_VALUE);
   ArrayInitialize(AnchorATimeBuffer,EMPTY_VALUE);
   ArrayInitialize(AnchorBTimeBuffer,EMPTY_VALUE);
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix+"m");
}

bool EIObjectStyle(const string name,const color mark,const int width)
{
   ObjectSetInteger(0,name,OBJPROP_COLOR,mark);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   return true;
}

bool EIDrawBody(const string name,const datetime opened,const datetime closed,
                const WHBar &bar,const string tooltip)
{
   double lower=MathMin(bar.open,bar.close);
   double upper=MathMax(bar.open,bar.close);
   if(upper<=lower)
   {
      lower-=_Point;
      upper+=_Point;
   }
   if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,opened,upper,closed,lower))
   {
      Print("EngulfImbalanceFlow: cannot create body mark, error ",GetLastError());
      return false;
   }
   EIObjectStyle(name,InpBodyColor,2);
   ObjectSetInteger(0,name,OBJPROP_FILL,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
   return true;
}

bool EIDrawWickLine(const string name,const datetime from,const datetime to,const double price,
                    const string tooltip)
{
   if(!ObjectCreate(0,name,OBJ_TREND,0,from,price,to,price))
   {
      Print("EngulfImbalanceFlow: cannot create wick line, error ",GetLastError());
      return false;
   }
   EIObjectStyle(name,InpWickLineColor,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
   return true;
}

bool EIDrawLabel(const string name,const datetime opened,const double price,const string text)
{
   if(!ObjectCreate(0,name,OBJ_TEXT,0,opened,price))
   {
      Print("EngulfImbalanceFlow: cannot create label, error ",GetLastError());
      return false;
   }
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,InpLabelSize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,InpLabelColor);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
   return true;
}

string EIPatternText(const int pattern)
{
   if(pattern==1) return "A";
   if(pattern==2) return "B";
   if(pattern==3) return "A+B";
   return "";
}

bool EIDrawSignal(const int index,const EIResult &result,const WHBar &bars[],
                  const datetime &time[],const int rates_total)
{
   string stamp=IntegerToString((long)time[index]);
   int anchors[2];
   anchors[0]=result.anchorA;
   anchors[1]=result.anchorB;
   for(int pass=0;pass<2;pass++)
   {
      int anchor=anchors[pass];
      if(anchor<0 || anchor>=index || (pass==1 && anchor==result.anchorA)) continue;
      datetime closed=anchor+1<rates_total ? time[anchor+1] : time[anchor]+PeriodSeconds(_Period);
      string kind=pass==0 ? "Pattern A" : "Pattern B";
      string tooltip=kind+" confirmation body\n"+
                     DoubleToString(MathMin(bars[anchor].open,bars[anchor].close),_Digits)+" - "+
                     DoubleToString(MathMax(bars[anchor].open,bars[anchor].close),_Digits)+"\n"+
                     TimeToString(time[anchor],TIME_DATE|TIME_MINUTES);
      if(!EIDrawBody(g_prefix+"mbody"+IntegerToString(pass)+"_"+stamp,
                     time[anchor],closed,bars[anchor],tooltip)) return false;
   }
   if(result.anchorB>=0)
   {
      string tooltip="Wick tip "+DoubleToString(result.wickTip,_Digits)+
                     " touches confirmation body\n"+
                     TimeToString(time[result.anchorB],TIME_DATE|TIME_MINUTES)+" -> "+
                     TimeToString(time[result.engulfIndex],TIME_DATE|TIME_MINUTES);
      if(!EIDrawWickLine(g_prefix+"mline_"+stamp,time[result.anchorB],time[result.engulfIndex],
                         result.wickTip,tooltip)) return false;
   }
   double pad=MathMax(_Point*InpLabelSize,(bars[index].high-bars[index].low)*0.35);
   double labelPrice=result.direction==1 ? bars[index].low-pad : bars[index].high+pad;
   string label=EIPatternText(result.pattern);
   if(result.delayed) label+=" R"+IntegerToString(index-result.engulfIndex);
   return EIDrawLabel(g_prefix+"mlabel_"+stamp,time[index],labelPrice,label);
}

bool RebuildCombo(const int rates_total,const datetime &time[],const double &open[],
                  const double &high[],const double &low[],const double &close[],
                  const int &spread[])
{
   EIClear();
   int last=rates_total-2;
   if(last<2) return true;
   int first=InpLookbackBars==0 ? 0 : (int)MathMax(0,last-InpLookbackBars+1);
   WHBar bars[]; FVGBar zones[]; int imbalance[]; double spreadPrice[];
   if(ArrayResize(bars,rates_total)!=rates_total || ArrayResize(zones,rates_total)!=rates_total ||
      ArrayResize(imbalance,rates_total)!=rates_total || ArrayResize(spreadPrice,rates_total)!=rates_total)
      return false;
   ArrayInitialize(imbalance,0);
   for(int i=0;i<rates_total;i++)
   {
      bars[i].open=open[i]; bars[i].high=high[i]; bars[i].low=low[i]; bars[i].close=close[i];
      zones[i].open=open[i]; zones[i].high=high[i]; zones[i].low=low[i]; zones[i].close=close[i];
      spreadPrice[i]=MathMax(0,spread[i])*_Point;
   }
   for(int i=first;i<=last;i++)
   {
      if(IsStopped()) return false;
      FVGZone zone;
      if(i>=first+2 &&
         FVGDetect(zones[i-2],zones[i-1],zones[i],InpMinGapPoints,_Point,InpRequireMiddleDirection,zone))
         imbalance[i]|=EIDirectionBit(zone.direction);
   }
   int shown=0;
   for(int i=last;i>=MathMax(first,2);i--)
   {
      if(IsStopped()) return false;
      EIResult result;
      if(!EIFindEntry(i,bars,imbalance,spreadPrice,rates_total,first,InpMaxGapBars,result)) continue;
      BuyBuffer[i]=result.direction==1 ? bars[i].low : EMPTY_VALUE;
      SellBuffer[i]=result.direction==-1 ? bars[i].high : EMPTY_VALUE;
      PatternBuffer[i]=result.pattern;
      DirectionBuffer[i]=result.direction;
      if(result.anchorA>=0) AnchorATimeBuffer[i]=(double)time[result.anchorA];
      if(result.anchorB>=0) AnchorBTimeBuffer[i]=(double)time[result.anchorB];
      if(shown<InpMaxSignals && !EIDrawSignal(i,result,bars,time,rates_total)) return false;
      shown++;
   }
   ChartRedraw(0);
   return true;
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   if(rates_total<1 || g_prefix=="") return 0;
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false); ArraySetAsSeries(low,false); ArraySetAsSeries(close,false);
   ArraySetAsSeries(spread,false);
   bool rebuild=prev_calculated<=0 || prev_calculated!=rates_total ||
                g_first_bar!=time[0] || g_current_bar!=time[rates_total-1];
   if(!rebuild) return rates_total;
   if(!RebuildCombo(rates_total,time,open,high,low,close,spread)) return 0;
   g_first_bar=time[0]; g_current_bar=time[rates_total-1];
   return rates_total;
}
