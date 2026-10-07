#property copyright "MT5 Trading Tools"
#property version "1.11"
#property description "FVG and configurable single/multi-candle displacement zones; closed candles only."
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots 7
#property indicator_type1 DRAW_NONE
#property indicator_label1 "FVG direction (+1 bull / -1 bear)"
#property indicator_type2 DRAW_NONE
#property indicator_label2 "FVG lower"
#property indicator_type3 DRAW_NONE
#property indicator_label3 "FVG upper"
#property indicator_type4 DRAW_NONE
#property indicator_label4 "Displacement direction"
#property indicator_type5 DRAW_NONE
#property indicator_label5 "Displacement lower"
#property indicator_type6 DRAW_NONE
#property indicator_label6 "Displacement upper"
#property indicator_type7 DRAW_NONE
#property indicator_label7 "Displacement kind (1 single / 2 leg)"
#property strict
#include "DisplacementCore.mqh"

input group "FVG detection - current chart timeframe, closed candles only"
input int InpLookbackBars=500; // Last 3..5000 CLOSED candles; all three must be in this window
input double InpMinGapPoints=0; // Minimum gap in symbol points (not pips)
input bool InpRequireMiddleDirection=false; // Middle candle must agree with gap direction
input group "Zone lifecycle - evaluated on closed candles"
input ENUM_FVG_FILL InpFillMode=FVG_FILL_FULL;
input bool InpShowFilled=false; // Keep filled zones in gray, ending on their first fill candle
input group "Display"
input bool InpShowBullish=true;
input bool InpShowBearish=true;
input int InpMaxZones=50; // Newest eligible zones, 1..500
input int InpExtendBars=10; // Active zone extension beyond current bar, 0..500
input bool InpFillRectangles=true;
input color InpBullishColor=clrDarkGreen;
input color InpBearishColor=clrMaroon;
input color InpFilledColor=clrDimGray;

// New inputs appended to retain the original FVG iCustom argument order.
input group "Detection mode"
input ENUM_FVG_DETECTION InpDetectionMode=FVG_AND_DISPLACEMENT;
input ENUM_DP_METHOD InpDisplacementMethod=DP_SINGLE_OR_LEG;
input int InpATRLength=14; // SMA true range BEFORE impulse, 1..200
input bool InpRejectTimeGaps=true; // Displacement: require continuous reference/impulse bars
input group "Single candle displacement"
input double InpMinBodyATR=0.80;
input double InpMinBodyRatio=0.70; // Body / full candle range, (0,1]
input double InpMaxTailRatio=0.15; // BUY upper tail / SELL lower tail, [0,1]
input double InpMinRelativeBody=0; // 0 disables; otherwise body / median previous bodies
input int InpRelativeBodyBars=20; // 1..200; excludes the signal candle
input group "Multi candle displacement"
input int InpMinLegBars=2;
input int InpMaxLegBars=4; // 2..10
input double InpMinLegATR=1.50;
input double InpMinEfficiency=0.75; // Net close movement / sum absolute close changes
input double InpMinDirectionRatio=0.66; // Same-direction bodies / leg length; 0.66 accepts 2/3
input double InpMaxLegTailRatio=0.20; // Directional tail of final candle / its range
input group "Displacement breakout and zone"
input bool InpRequireBreakout=true;
input int InpBreakoutBars=5; // High/Low window BEFORE impulse; 1..200
input double InpBreakoutBufferATR=0.10;
input ENUM_DP_ZONE InpDisplacementZone=DP_BASE_WICK;
input int InpBaseSearchBars=5; // Last opposing/doji before impulse, 1..20
input color InpBullishDisplacementColor=clrTeal;
input color InpBearishDisplacementColor=clrDarkOrange;
input ENUM_FVG_FILL InpDisplacementFillMode=FVG_FILL_FULL;

double DirectionBuffer[],LowerBuffer[],UpperBuffer[];
double DPDirectionBuffer[],DPLowerBuffer[],DPUpperBuffer[],DPKindBuffer[];
DPConfig g_dp;
string g_prefix="";
datetime g_first_bar=0,g_current_bar=0;

void LoadDPConfig()
{
   g_dp.method=InpDisplacementMethod; g_dp.zone_mode=InpDisplacementZone;
   g_dp.atr_length=InpATRLength; g_dp.relative_bars=InpRelativeBodyBars;
   g_dp.min_leg_bars=InpMinLegBars; g_dp.max_leg_bars=InpMaxLegBars;
   g_dp.breakout_bars=InpBreakoutBars; g_dp.base_search_bars=InpBaseSearchBars;
   g_dp.min_body_atr=InpMinBodyATR; g_dp.min_body_ratio=InpMinBodyRatio;
   g_dp.max_tail_ratio=InpMaxTailRatio; g_dp.min_relative_body=InpMinRelativeBody;
   g_dp.min_leg_atr=InpMinLegATR; g_dp.min_efficiency=InpMinEfficiency;
   g_dp.min_direction_ratio=InpMinDirectionRatio; g_dp.max_leg_tail_ratio=InpMaxLegTailRatio;
   g_dp.require_breakout=InpRequireBreakout; g_dp.breakout_atr=InpBreakoutBufferATR;
   g_dp.reject_time_gaps=InpRejectTimeGaps;
}

int OnInit()
{
   LoadDPConfig();
   if(!DPConfigValid(g_dp) || InpDetectionMode<FVG_ONLY || InpDetectionMode>FVG_AND_DISPLACEMENT ||
      (InpDisplacementFillMode!=FVG_FILL_FULL && InpDisplacementFillMode!=FVG_FILL_TOUCH) ||
      InpLookbackBars<3 || InpLookbackBars>5000 ||
      !MathIsValidNumber(InpMinGapPoints) || InpMinGapPoints<0 ||
      !MathIsValidNumber(InpMinGapPoints*_Point) || _Point<=0 ||
      InpMaxZones<1 || InpMaxZones>500 || InpExtendBars<0 || InpExtendBars>500 ||
      (InpFillMode!=FVG_FILL_FULL && InpFillMode!=FVG_FILL_TOUCH))
   { Print("ImbalanceFlow: invalid Inputs. See the indicator manual for allowed ranges."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,DirectionBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,LowerBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,UpperBuffer,INDICATOR_DATA);
   ArraySetAsSeries(DirectionBuffer,false);
   ArraySetAsSeries(LowerBuffer,false);
   ArraySetAsSeries(UpperBuffer,false);
   SetIndexBuffer(3,DPDirectionBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,DPLowerBuffer,INDICATOR_DATA);
   SetIndexBuffer(5,DPUpperBuffer,INDICATOR_DATA);
   SetIndexBuffer(6,DPKindBuffer,INDICATOR_DATA);
   ArraySetAsSeries(DPDirectionBuffer,false); ArraySetAsSeries(DPLowerBuffer,false);
   ArraySetAsSeries(DPUpperBuffer,false); ArraySetAsSeries(DPKindBuffer,false);
   for(int p=0;p<7;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"ImbalanceFlow / "+EnumToString(InpDetectionMode));
   string base="FVG_"+(string)ChartID()+"_"+(string)GetMicrosecondCount()+"_";
   int suffix=0;
   do { g_prefix=base+IntegerToString(suffix++)+"_"; } while(ObjectFind(0,g_prefix+"owner")>=0);
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

bool DrawFVGZone(const FVGZone &zone,const datetime start,const datetime confirmed,
                 const datetime end,const bool filled,const int kind=0)
{
   string name=g_prefix+"zone_"+(string)confirmed+"_"+IntegerToString(kind);
   if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,start,zone.lower,end,zone.upper))
   { Print("ImbalanceFlow: cannot create zone, error ",GetLastError()); return false; }
   color active=kind==0 ? (zone.direction==1 ? InpBullishColor : InpBearishColor) :
                            (zone.direction==1 ? InpBullishDisplacementColor : InpBearishDisplacementColor);
   ObjectSetInteger(0,name,OBJPROP_COLOR,filled ? InpFilledColor : active);
   ObjectSetInteger(0,name,OBJPROP_FILL,InpFillRectangles);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,kind==0 ? 1 : 2);
   string label=kind==0 ? "FVG" : (kind==1 ? "Displacement single" : "Displacement leg");
   string text=(zone.direction==1 ? "Bullish " : "Bearish ")+label+
               (filled ? " (filled)" : " (active)")+"\n"+
               DoubleToString(zone.lower,_Digits)+" - "+DoubleToString(zone.upper,_Digits)+
               "\nSignal candle (known after close): "+TimeToString(confirmed,TIME_DATE|TIME_MINUTES);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
   return true;
}

bool RebuildFVG(const int rates_total,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[])
{
   ArrayInitialize(DirectionBuffer,EMPTY_VALUE);
   ArrayInitialize(LowerBuffer,EMPTY_VALUE); ArrayInitialize(UpperBuffer,EMPTY_VALUE);
   ArrayInitialize(DPDirectionBuffer,EMPTY_VALUE); ArrayInitialize(DPLowerBuffer,EMPTY_VALUE);
   ArrayInitialize(DPUpperBuffer,EMPTY_VALUE); ArrayInitialize(DPKindBuffer,EMPTY_VALUE);
   ObjectsDeleteAll(0,g_prefix+"zone_");
   int last=rates_total-2;
   int first=(int)MathMax(0,last-InpLookbackBars+1);
   int shown=0;
   long seconds=(long)MathMax(1,PeriodSeconds(_Period));
   datetime active_end=(datetime)((long)time[rates_total-1]+seconds*InpExtendBars);
   FVGBar bars[]; long times[]; FVGZone displaced[]; int sources[],kinds[],used[];
   if(ArrayResize(bars,rates_total)!=rates_total || ArrayResize(times,rates_total)!=rates_total ||
      ArrayResize(displaced,rates_total)!=rates_total || ArrayResize(sources,rates_total)!=rates_total ||
      ArrayResize(kinds,rates_total)!=rates_total || ArrayResize(used,rates_total)!=rates_total) return false;
   ArrayInitialize(kinds,0); ArrayInitialize(used,0);
   for(int i=0;i<rates_total;i++)
   { bars[i].open=open[i]; bars[i].high=high[i]; bars[i].low=low[i]; bars[i].close=close[i]; times[i]=(long)time[i]; }
   if(InpDetectionMode!=FVG_ONLY)
      for(int i=first;i<=last;i++)
      {
         if(IsStopped()) return false;
         FVGZone zone; int source,kind;
         if(!DPDetect(g_dp,bars,times,rates_total,first,i,seconds,zone,source,kind)) continue;
         int bit=zone.direction==1 ? 1 : 2;
         if((used[source]&bit)!=0) continue; // One displacement per source/direction in this lookback.
         used[source]|=bit;
         displaced[i]=zone; sources[i]=source; kinds[i]=kind;
      }
   // Shared newest-first visible budget; FVG gets priority if both occur on the same candle.
   for(int i=last;i>=first;i--)
   {
      if(IsStopped()) return false;
      for(int pass=0;pass<2;pass++)
      {
         FVGZone zone; int source=i-2,kind=0;
         if(pass==0)
         {
            if(InpDetectionMode==DISPLACEMENT_ONLY || i<first+2 ||
               !FVGDetect(bars[i-2],bars[i-1],bars[i],InpMinGapPoints,_Point,InpRequireMiddleDirection,zone)) continue;
            DirectionBuffer[i]=zone.direction; LowerBuffer[i]=zone.lower; UpperBuffer[i]=zone.upper;
         }
         else
         {
            if(kinds[i]==0) continue;
            zone=displaced[i]; source=sources[i]; kind=kinds[i];
            DPDirectionBuffer[i]=zone.direction; DPLowerBuffer[i]=zone.lower;
            DPUpperBuffer[i]=zone.upper; DPKindBuffer[i]=kind;
         }
         if(shown>=InpMaxZones || (zone.direction==1 && !InpShowBullish) ||
            (zone.direction==-1 && !InpShowBearish)) continue;
         int fill_bar=-1;
         ENUM_FVG_FILL fill_mode=kind==0 ? InpFillMode : InpDisplacementFillMode;
         // Only candles after confirmation may fill either kind of zone.
         for(int j=i+1;j<=last;j++)
         {
            if(IsStopped()) return false;
            if(FVGIsFilled(zone,bars[j],fill_mode)) { fill_bar=j; break; }
         }
         if(fill_bar>=0 && !InpShowFilled) continue;
         datetime end=fill_bar>=0 ? time[fill_bar+1] : active_end;
         if(!DrawFVGZone(zone,time[source],time[i],end,fill_bar>=0,kind)) return false;
         shown++;
      }
   }
   ChartRedraw(0);
   return true;
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(time,false); ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false); ArraySetAsSeries(low,false); ArraySetAsSeries(close,false);
   bool rebuild=prev_calculated<=0 || prev_calculated!=rates_total ||
                g_first_bar!=time[0] || g_current_bar!=time[rates_total-1];
   if(!rebuild) return rates_total;
   if(!RebuildFVG(rates_total,time,open,high,low,close)) return 0;
   g_first_bar=time[0]; g_current_bar=time[rates_total-1];
   return rates_total;
}
