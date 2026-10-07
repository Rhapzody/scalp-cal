#property copyright "MT5 Trading Tools"
#property version "1.10"
#property description "M5 histogram swings, qualified breakouts, demand/supply retests and M1 LH/HL close breaks."
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots 8
#property strict
#include "PullbackCore.mqh"

input group "MACD Histogram color only - same settings on M5 and M1"
input int InpFastEMA=12;
input int InpSlowEMA=26;
input int InpSignalEMA=9;
input int InpWarmupBars=0;
input group "M5 zones - full wick range of the source candle"
input ENUM_RP_ZONE_MODE InpZoneMode=RP_BOTH;
input int InpHistoryM5Bars=1500; // 100..5000; replay window, including MACD warmup
input int InpZoneLifeBars=144; // Expire after this many M5 bars
input group "Breakout strength - initial research settings, not optimized"
input ENUM_RP_STRENGTH InpStrength=RP_FVG_OR_DISPLACEMENT;
input int InpATRLength=14;
input int InpMaxLegBars=30;
input double InpMinLegATR=1.0;
input double InpMinFVGATR=0.10;
input double InpMinEfficiency=0.65;
input double InpMinBreakBodyRatio=0.50;
input group "M1 confirmation after zone touch"
input int InpConfirmationBars=30; // Require a later closed M1 candle; expire after 1..300 bars
input group "Display and notifications"
input int InpVisibleZones=30; // 0..100, active zones only
input int InpVisibleSignals=100; // 0..500
input bool InpFillZones=false;
input color InpDemandColor=clrSeaGreen;
input color InpSupplyColor=clrIndianRed;
input color InpBuyColor=clrLimeGreen;
input color InpSellColor=clrTomato;
input bool InpPopupAlert=false; // New closed M1 signals only; no historical alerts on attach
// Append new inputs to preserve existing positional iCustom arguments.
input group "Signal tuning - keep identical in EA and indicator"
input ENUM_RP_SIDE InpTradeSide=RP_ALL_SIDES;
input double InpM5BreakBufferPoints=0; // Closed M5 price must exceed swing wick + this distance
input double InpM1BreakBufferPoints=0; // Closed M1 price must exceed LH/HL + this distance
input ENUM_RP_TOUCH InpTouchMode=RP_TOUCH_WICK;
input ENUM_RP_INVALIDATE InpInvalidationMode=RP_INVALIDATE_CLOSE;
input double InpMaxCloseTailRatio=0.25; // 0..1, distance from breakout close to directional tip / range
input group "Additional display settings"
input int InpZoneExtendM1Bars=10; // Extend visible zones by 1..500 minutes
input int InpSignalArrowWidth=2; // 1..5

double BuyBuffer[],SellBuffer[],SignalTime[],TriggerPrice[],ZoneLower[],ZoneUpper[],SRPrice[],Quality[];
RPConfig g_config;
RPState g_state;
RPEntry g_entries[];
string g_prefix="";
long g_last_m1=0,g_first_chart=0,g_alert_time=0;
bool g_ready=false;

void ClearOutput()
{
   ArrayInitialize(BuyBuffer,EMPTY_VALUE); ArrayInitialize(SellBuffer,EMPTY_VALUE);
   ArrayInitialize(SignalTime,EMPTY_VALUE); ArrayInitialize(TriggerPrice,EMPTY_VALUE);
   ArrayInitialize(ZoneLower,EMPTY_VALUE); ArrayInitialize(ZoneUpper,EMPTY_VALUE);
   ArrayInitialize(SRPrice,EMPTY_VALUE); ArrayInitialize(Quality,EMPTY_VALUE);
}

void Status(const string text)
{
   ObjectSetString(0,g_prefix+"owner",OBJPROP_TEXT,"MACD Zone Pullback | "+text);
}

int OnInit()
{
   if(_Period!=PERIOD_M1 && _Period!=PERIOD_M5)
   { Print("MACDZonePullback: attach to an M1 or M5 chart."); return INIT_PARAMETERS_INCORRECT; }
   g_config.macd.fast=InpFastEMA; g_config.macd.slow=InpSlowEMA;
   g_config.macd.signal=InpSignalEMA; g_config.macd.warmup=InpWarmupBars;
   g_config.macd.atr_length=InpATRLength; g_config.macd.threshold_mode=MS_PRICE;
   g_config.macd.threshold=0; g_config.macd.point=_Point;
   g_config.macd.swing_mode=MS_HISTOGRAM_COLOR;
   g_config.zones=InpZoneMode; g_config.strength=InpStrength;
   g_config.min_leg_atr=InpMinLegATR; g_config.min_fvg_atr=InpMinFVGATR;
   g_config.min_efficiency=InpMinEfficiency; g_config.min_body_ratio=InpMinBreakBodyRatio;
   g_config.max_leg_bars=InpMaxLegBars; g_config.zone_life_bars=InpZoneLifeBars;
   g_config.confirmation_bars=InpConfirmationBars;
   g_config.side=InpTradeSide; g_config.touch_mode=InpTouchMode; g_config.invalidate_mode=InpInvalidationMode;
   g_config.m5_break_buffer_points=InpM5BreakBufferPoints; g_config.m1_break_buffer_points=InpM1BreakBufferPoints;
   g_config.max_close_tail_ratio=InpMaxCloseTailRatio;
   if(!RPConfigValid(g_config) || InpHistoryM5Bars<100 || InpHistoryM5Bars>5000 ||
      InpVisibleZones<0 || InpVisibleZones>100 || InpVisibleSignals<0 || InpVisibleSignals>500 ||
      InpZoneExtendM1Bars<1 || InpZoneExtendM1Bars>500 || InpSignalArrowWidth<1 || InpSignalArrowWidth>5)
   { Print("MACDZonePullback: invalid Inputs. See manual."); return INIT_PARAMETERS_INCORRECT; }
   SetIndexBuffer(0,BuyBuffer,INDICATOR_DATA); SetIndexBuffer(1,SellBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,SignalTime,INDICATOR_DATA); SetIndexBuffer(3,TriggerPrice,INDICATOR_DATA);
   SetIndexBuffer(4,ZoneLower,INDICATOR_DATA); SetIndexBuffer(5,ZoneUpper,INDICATOR_DATA);
   SetIndexBuffer(6,SRPrice,INDICATOR_DATA); SetIndexBuffer(7,Quality,INDICATOR_DATA);
   ArraySetAsSeries(BuyBuffer,false); ArraySetAsSeries(SellBuffer,false);
   ArraySetAsSeries(SignalTime,false); ArraySetAsSeries(TriggerPrice,false);
   ArraySetAsSeries(ZoneLower,false); ArraySetAsSeries(ZoneUpper,false);
   ArraySetAsSeries(SRPrice,false); ArraySetAsSeries(Quality,false);
   string names[8]={"Buy close","Sell close","M1 signal open time","M1 LH/HL trigger",
                    "Zone lower","Zone upper","M5 swing wick SR","Strength: 2 FVG / 1 displacement"};
   for(int i=0;i<8;i++)
   {
      PlotIndexSetInteger(i,PLOT_DRAW_TYPE,DRAW_NONE);
      PlotIndexSetString(i,PLOT_LABEL,names[i]);
      PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   }
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"MACD Zone Pullback M5 > M1");
   string base="MZP_"+(string)ChartID()+"_"+(string)GetMicrosecondCount()+"_";
   int suffix=0;
   do { g_prefix=base+IntegerToString(suffix++)+"_"; } while(ObjectFind(0,g_prefix+"owner")>=0);
   if(!ObjectCreate(0,g_prefix+"owner",OBJ_LABEL,0,0,0)) { g_prefix=""; return INIT_FAILED; }
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_YDISTANCE,16);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,g_prefix+"owner",OBJPROP_HIDDEN,true);
   g_last_m1=0; g_first_chart=0; g_alert_time=0; g_ready=false;
   Status("Loading M5 / M1 history");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_prefix!="") ObjectsDeleteAll(0,g_prefix);
   ChartRedraw(0);
}

void SetObjectStyle(const string name,const color value)
{
   ObjectSetInteger(0,name,OBJPROP_COLOR,value);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

string KindText(const int kind) { return kind==RP_SWING_ZONE ? "Swing flip" : "Impulse origin"; }
string StrengthText(const int quality) { return quality==2 ? "FVG" : "Displacement"; }

bool Render(const long current)
{
   ObjectsDeleteAll(0,g_prefix+"view_");
   int displayed=0,touched=0;
   bool selected[RP_MAX_ZONES];
   ArrayInitialize(selected,false);
   for(int v=0;v<InpVisibleZones;v++)
   {
      int best=-1;
      for(int k=0;k<RP_MAX_ZONES;k++)
         if(!selected[k] && g_state.zones[k].serial>0 && g_state.zones[k].status<=RP_TOUCHED &&
            (best<0 || g_state.zones[k].serial>g_state.zones[best].serial)) best=k;
      if(best<0) break;
      selected[best]=true;
      RPZone z=g_state.zones[best];
      string name=g_prefix+"view_zone_"+(string)z.serial;
      // Start at confirmation, never imply that the zone was known at its source candle.
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,(datetime)z.born_time,z.lower,
                       (datetime)(current+60*InpZoneExtendM1Bars),z.upper)) return false;
      SetObjectStyle(name,z.direction==1 ? InpDemandColor : InpSupplyColor);
      ObjectSetInteger(0,name,OBJPROP_FILL,InpFillZones);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,z.status==RP_TOUCHED ? 2 : 1);
      ObjectSetInteger(0,name,OBJPROP_STYLE,z.kind==RP_SWING_ZONE ? STYLE_SOLID : STYLE_DASH);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,(z.direction==1 ? "Demand | " : "Supply | ")+
                      KindText(z.kind)+" | "+StrengthText(z.quality)+
                      (z.status==RP_TOUCHED ? " | Waiting M1 break" : " | Waiting retest")+
                      "\n"+DoubleToString(z.lower,_Digits)+" - "+DoubleToString(z.upper,_Digits)+
                      "\nSource: "+TimeToString((datetime)z.source_time)+
                      "\nKnown: "+TimeToString((datetime)z.born_time));
      string level=name+"_sr";
      if(!ObjectCreate(0,level,OBJ_TREND,0,(datetime)z.born_time,z.sr,(datetime)(current+60*InpZoneExtendM1Bars),z.sr)) return false;
      SetObjectStyle(level,z.direction==1 ? InpDemandColor : InpSupplyColor);
      ObjectSetInteger(0,level,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,level,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetString(0,level,OBJPROP_TOOLTIP,"Broken M5 swing wick SR: "+DoubleToString(z.sr,_Digits));
      displayed++;
      if(z.status==RP_TOUCHED) touched++;
   }
   int total=ArraySize(g_entries),first=(int)MathMax(0,total-InpVisibleSignals);
   for(int i=first;i<total;i++)
   {
      RPEntry e=g_entries[i];
      string name=g_prefix+"view_signal_"+(string)i;
      if(!ObjectCreate(0,name,OBJ_ARROW,0,(datetime)e.time,e.price)) return false;
      SetObjectStyle(name,e.direction==1 ? InpBuyColor : InpSellColor);
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,e.direction==1 ? 233 : 234);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,e.direction==1 ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,InpSignalArrowWidth);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,(e.direction==1 ? "BUY" : "SELL")+" | "+KindText(e.kind)+
                      " | "+StrengthText(e.quality)+"\nConfirmed: "+TimeToString((datetime)(e.time+60))+
                      "\nClose: "+DoubleToString(e.price,_Digits)+" | Swing: "+DoubleToString(e.trigger,_Digits)+
                      " | Break level: "+DoubleToString(e.trigger+e.direction*InpM1BreakBufferPoints*_Point,_Digits)+
                      "\nZone: "+DoubleToString(e.lower,_Digits)+" - "+DoubleToString(e.upper,_Digits));
   }
   Status("M5 zones "+(string)displayed+" | Retested "+(string)touched+" | M1 signals "+(string)total);
   ChartRedraw(0);
   return true;
}

int ChartBar(const long timestamp,const datetime &time[],const int count)
{
   int left=0,right=count-1,found=-1;
   while(left<=right)
   {
      int middle=(left+right)/2;
      if((long)time[middle]<=timestamp) { found=middle; left=middle+1; }
      else right=middle-1;
   }
   if(found>=0 && timestamp>=(long)time[found]+PeriodSeconds(_Period)) return -1;
   return found;
}

bool LoadAndReplay(const long current1)
{
   MqlRates m5[],m1[];
   ArraySetAsSeries(m5,false); ArraySetAsSeries(m1,false);
   int n5=CopyRates(_Symbol,PERIOD_M5,0,InpHistoryM5Bars+1,m5);
   if(n5<2 || !SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED)) return false;
   int n1=CopyRates(_Symbol,PERIOD_M1,m5[0].time,(datetime)current1,m1);
   if(n1<2 || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED) ||
      (long)m1[n1-1].time!=current1 || (long)m5[n5-1].time>current1 ||
      current1>=(long)m5[n5-1].time+300) return false;
   MSBar one[],five[];
   if(ArrayResize(one,n1)!=n1 || ArrayResize(five,n5)!=n5) return false;
   for(int i=0;i<n1;i++)
   { one[i].time=(long)m1[i].time; one[i].open=m1[i].open; one[i].high=m1[i].high; one[i].low=m1[i].low; one[i].close=m1[i].close; }
   for(int i=0;i<n5;i++)
   { five[i].time=(long)m5[i].time; five[i].open=m5[i].open; five[i].high=m5[i].high; five[i].low=m5[i].low; five[i].close=m5[i].close; }
   return RPReplay(g_state,g_config,one,n1,five,n5,current1,g_entries);
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(time,false);
   long current=(long)iTime(_Symbol,PERIOD_M1,0);
   if(current<=0) { Status("Waiting for M1 history"); return 0; }
   if(g_ready && prev_calculated>0 && prev_calculated==rates_total &&
      current==g_last_m1 && g_first_chart==(long)time[0]) return rates_total;
   if(!LoadAndReplay(current))
   {
      ClearOutput(); ObjectsDeleteAll(0,g_prefix+"view_");
      Status("History loading / calculation unavailable; retrying");
      return 0;
   }
   ClearOutput();
   int count=ArraySize(g_entries);
   for(int i=0;i<count;i++)
   {
      RPEntry e=g_entries[i];
      int bar=ChartBar(e.time,time,rates_total);
      if(bar<0) continue;
      // M5 buffers show only the latest M1 event within that chart candle.
      BuyBuffer[bar]=e.direction==1 ? e.price : EMPTY_VALUE;
      SellBuffer[bar]=e.direction==-1 ? e.price : EMPTY_VALUE;
      SignalTime[bar]=(double)e.time; TriggerPrice[bar]=e.trigger;
      ZoneLower[bar]=e.lower; ZoneUpper[bar]=e.upper; SRPrice[bar]=e.sr; Quality[bar]=e.quality;
   }
   if(!Render(current)) { Status("Chart object error; retrying"); return 0; }
   if(InpPopupAlert && g_ready && current>g_last_m1)
      for(int i=0;i<count;i++)
         if(g_entries[i].time==current-60 && g_entries[i].time>g_alert_time)
            Alert(_Symbol," MACD Zone Pullback ",g_entries[i].direction==1 ? "BUY" : "SELL",
                  " | ",KindText(g_entries[i].kind)," | M1 closed ",TimeToString((datetime)current));
   g_alert_time=current-60;
   g_last_m1=current; g_first_chart=(long)time[0]; g_ready=true;
   return rates_total;
}
