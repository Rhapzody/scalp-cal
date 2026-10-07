// Generated from WickHuntAnchor 1.12. Regenerate with scripts/sync-wick-hunt-anchor-runtime.py
// Source SHA256: 59157df533f2fc43b0a05e2b8014b71198a8c03616c3729f488e0e2859d1abaf
#ifndef WHA_ALERT_RUNTIME
#define WHA_ALERT_RUNTIME
#include "../../Indicators/WickHuntAnchor/WickHuntAnchorCore.mqh"
#include "../../Indicators/WickHuntAnchor/WickHuntQuoteSessions.mqh"
input group "Main timeframe - wick hunt and anchor"
input ENUM_TIMEFRAMES InpHuntTF=PERIOD_H1; // InpHuntTF | TF หลักสำหรับ hunt และ anchor
input int InpHuntBars=1; // InpHuntBars | จำนวนหางก่อนหน้าที่ต้องกวาด
input double InpMinHuntPoints=0; // InpMinHuntPoints | ระยะกวาดเกินหางเดิม (points)
input ENUM_WHA_OBSERVATION InpObservationMode=WHA_LOWER_TF_CLOSE; // InpObservationMode | วิธีตรวจ (tick/แท่งหลักปิด/TF ย่อยปิด)
input int InpHistoryBars=0; // InpHistoryBars | ประวัติ TF หลัก (0=ทั้งหมด)
input group "First candle touched by the wick tip"
input int InpSearchBars=36; // InpSearchBars | ระยะ anchor สูงสุด แท่ง TF หลัก (0=ไม่จำกัด)
input ENUM_WHA_ANCHOR_RULE InpAnchorRule=WHA_FVG_OR_STRONG; // InpAnchorRule | กฎ anchor (FVG/Strong/OR/AND)
input double InpStrongHeadWickPercent=30; // InpStrongHeadWickPercent | หางหัว Strong ต้องน้อยกว่า (%)
input bool InpRequireAnchorColor=false; // InpRequireAnchorColor | บังคับสีทั้งสองฝั่ง Buy เขียว/Sell แดง
input bool InpRequireBodyTouch=false; // InpRequireBodyTouch | ปลายหางต้องแตะเนื้อแท่ง anchor
input double InpMinFVGGapPoints=0; // InpMinFVGGapPoints | ช่องว่าง FVG ขั้นต่ำ (points)
input bool InpRequireFVGMiddleDirection=false; // InpRequireFVGMiddleDirection | สีแท่งกลางต้องตรงทิศ FVG
input bool InpRequireFVGDirection=false; // InpRequireFVGDirection | ทิศ FVG ต้องตรงฝั่ง Buy/Sell
input group "Display and alerts"
input bool InpEnableBuy=true; // InpEnableBuy | เปิดตรวจสัญญาณ Buy
input bool InpEnableSell=true; // InpEnableSell | เปิดตรวจสัญญาณ Sell
input int InpVisibleSignals=100; // InpVisibleSignals | จำนวนลูกศรล่าสุดที่แสดง (0=ซ่อน)
input bool InpShowAnchorLinks=true; // InpShowAnchorLinks | แสดงเส้นปลายหางไปยัง anchor
input color InpBuyColor=clrLimeGreen; // InpBuyColor | สีลูกศร Buy
input color InpSellColor=clrTomato; // InpSellColor | สีลูกศร Sell
input color InpAnchorColor=clrSilver; // InpAnchorColor | สีเส้นเชื่อม anchor
input int InpArrowWidth=1; // InpArrowWidth | ขนาดลูกศร (1-5)
input int InpArrowGapPoints=200; // InpArrowGapPoints | ระยะลูกศรห่างแท่งเทียน (points)
input bool InpPopupAlert=false; // InpPopupAlert | แจ้งสัญญาณใหม่ด้วย Popup
input group "Lower timeframe - check only at candle close"
input ENUM_TIMEFRAMES InpCheckTF=PERIOD_M5; // InpCheckTF | TF ย่อยที่รอปิดก่อนตรวจ
input int InpCheckHistoryBars=0; // InpCheckHistoryBars | ประวัติ TF ย่อย (0=ทั้งหมด)
input group "Anchor colors - additional filters"
input bool InpRequireBuyAnchorGreen=true; // InpRequireBuyAnchorGreen | Buy ต้องชน anchor เขียว
input bool InpRequireSellAnchorRed=true; // InpRequireSellAnchorRed | Sell ต้องชน anchor แดง
input group "Swept candle wick - single-tail hunts only"
input double InpMinSweptWickBodyPercent=10; // InpMinSweptWickBodyPercent | หางเดิม/เนื้อขั้นต่ำ % (N=1)

struct WHAEvent
{
   long time,setup_time,anchor_time;
   double price,tip,signal_tip,head_wick_percent; // signal_tip is immutable; tip drives revalidation
   int direction,pattern,fvg_direction,observation;
   bool closed;
};

WHABar g_bars[];
WHAEvent g_events[];
ENUM_TIMEFRAMES g_hunt_tf;
int g_hunt_seconds=0,g_chart_total=0,g_loaded_available=-1;
long g_loaded_open=0,g_live_setup=0,g_last_closed=0;
long g_chart_first=0,g_chart_last=0;
double g_chart_high=0,g_chart_low=0;
bool g_force_history=true,g_history_dirty=true,g_display_dirty=true,g_buffers_dirty=true;
bool g_buy_sent=false,g_sell_sent=false,g_live_observed=false,g_closed_ready=false;
int g_check_seconds=0,g_check_available=-1;
long g_check_open=0,g_check_last_closed=0,g_check_first=0;
bool g_check_ready=false;
string g_prefix="";

void Status(const string text)
{
   if(g_prefix!="") ObjectSetString(0,g_prefix+"status",OBJPROP_TEXT,"WickHuntAnchor EA | "+text);
}

string PatternText(const int pattern)
{
   return pattern==3 ? "FVG + Strong" : (pattern==1 ? "FVG" : "Strong");
}

string RuleText()
{
   if(InpAnchorRule==WHA_FVG_ONLY) return "FVG only";
   string strong="Strong (head <"+DoubleToString(InpStrongHeadWickPercent,1)+"%)";
   if(InpAnchorRule==WHA_STRONG_ONLY) return strong+" only";
   return (InpAnchorRule==WHA_FVG_OR_STRONG ? "FVG OR " : "FVG AND ")+strong;
}

bool LoadHistory()
{
   long opened=(long)iTime(_Symbol,g_hunt_tf,0);
   int available=iBars(_Symbol,g_hunt_tf);
   if(opened<=0 || !SeriesInfoInteger(_Symbol,g_hunt_tf,SERIES_SYNCHRONIZED)) return false;
   if(!g_force_history && opened==g_loaded_open && available==g_loaded_available) return true;
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int requested=InpHistoryBars==0 ? available : InpHistoryBars+1;
   int n=CopyRates(_Symbol,g_hunt_tf,0,requested,rates);
   if(n<InpHuntBars+1 || (long)rates[n-1].time!=opened ||
      !SeriesInfoInteger(_Symbol,g_hunt_tf,SERIES_SYNCHRONIZED)) return false;
   if(ArrayResize(g_bars,n)!=n) return false;
   for(int i=0;i<n;i++)
   {
      if(IsStopped() || (i>0 && rates[i].time<=rates[i-1].time)) return false;
      WHABar b={(long)rates[i].time,rates[i].open,rates[i].high,rates[i].low,rates[i].close};
      g_bars[i]=b;
   }
   g_loaded_open=opened; g_loaded_available=available;
   g_force_history=false; g_history_dirty=true;
   return true;
}

bool RequireAnchorColor(const int direction)
{
   return InpRequireAnchorColor || (direction==1 && InpRequireBuyAnchorGreen) ||
          (direction==-1 && InpRequireSellAnchorRed);
}

// Recheck an existing event when the observed hunt tip extends. A color-
// filtered signal cannot keep referring to an obsolete first collision.
// If the anchor changes, discard the old event; AddEvent must confirm a
// fresh return to Open for the new anchor. No creation happens here.
bool RefreshEventAnchor(const WHABar &bar,const int prior_count,
                        const int direction,bool &sent)
{
   if(!RequireAnchorColor(direction)) return true;
   double tip=direction==1 ? bar.low : bar.high;
   for(int i=ArraySize(g_events)-1;i>=0;i--)
   {
      if(g_events[i].setup_time<bar.time) break;
      if(g_events[i].setup_time!=bar.time || g_events[i].direction!=direction) continue;
      if(g_events[i].tip==tip) return true;
      WHAAnchor anchor;
      bool valid=WHAFindAnchor(g_bars,prior_count,tip,direction,InpSearchBars,InpAnchorRule,
                               InpStrongHeadWickPercent,true,InpRequireBodyTouch,
                               InpMinFVGGapPoints,_Point,InpRequireFVGMiddleDirection,
                               InpRequireFVGDirection,anchor);
      if(valid && anchor.time==g_events[i].anchor_time)
      {
         // Same valid colored candle, updated tip and descriptive metadata.
         g_events[i].tip=tip;
         g_events[i].head_wick_percent=anchor.head_wick_percent;
         g_events[i].pattern=anchor.pattern;
         g_events[i].fvg_direction=anchor.fvg_direction;
      }
      else
      {
         int total=ArraySize(g_events);
         for(int j=i;j<total-1;j++) g_events[j]=g_events[j+1];
         if(ArrayResize(g_events,total-1)!=total-1) return false;
         sent=false;
      }
      g_display_dirty=true; g_buffers_dirty=true;
      return true;
   }
   return true;
}

bool AddEvent(const WHABar &bar,const int prior_count,const long now,
              const double price,const int direction,const bool closed,bool &emitted)
{
   emitted=false;
   if(!WHAValid(bar) || price<bar.low || price>bar.high ||
      (direction==1 ? price<bar.open : price>bar.open) ||
      !WHASwept(g_bars,prior_count,InpHuntBars,bar.open,bar.high,bar.low,direction,InpMinHuntPoints*_Point) ||
      !WHASweptWickBodyAllowed(g_bars,prior_count,InpHuntBars,direction,InpMinSweptWickBodyPercent)) return true;
   WHAAnchor anchor; double tip=direction==1 ? bar.low : bar.high;
   bool require_color=RequireAnchorColor(direction);
   if(!WHAFindAnchor(g_bars,prior_count,tip,direction,InpSearchBars,InpAnchorRule,
                     InpStrongHeadWickPercent,require_color,InpRequireBodyTouch,
                     InpMinFVGGapPoints,_Point,InpRequireFVGMiddleDirection,InpRequireFVGDirection,anchor)) return true;
   int count=ArraySize(g_events);
   if(ArrayResize(g_events,count+1)!=count+1) return false;
   WHAEvent e;
   e.time=now; e.setup_time=bar.time; e.anchor_time=anchor.time;
   e.price=price; e.tip=tip; e.signal_tip=tip; e.head_wick_percent=anchor.head_wick_percent;
   e.direction=direction; e.pattern=anchor.pattern; e.fvg_direction=anchor.fvg_direction; e.closed=closed;
   e.observation=closed ? (int)InpObservationMode : (int)WHA_LIVE_TICK;
   g_events[count]=e; emitted=true;
   g_display_dirty=true; g_buffers_dirty=true;
   return true;
}

bool ReplayClosed()
{
   if(!g_history_dirty) return true;
   int n=ArraySize(g_bars);
   long previous=g_last_closed;
   bool ready=g_closed_ready;
   ArrayResize(g_events,0);
   for(int i=InpHuntBars;i<n-1;i++)
   {
      if(IsStopped()) return false;
      bool emitted;
      WHABar bar=g_bars[i];
      if(bar.time+g_hunt_seconds>g_loaded_open) return false;
      if(InpEnableBuy && !AddEvent(bar,i,bar.time+g_hunt_seconds,bar.close,1,true,emitted)) return false;
      if(InpEnableSell && !AddEvent(bar,i,bar.time+g_hunt_seconds,bar.close,-1,true,emitted)) return false;
   }
   long latest=g_bars[n-2].time+g_hunt_seconds;
   if(InpPopupAlert && ready)
      for(int i=0;i<ArraySize(g_events);i++)
      {
         WHAEvent e=g_events[i];
         if(e.time>previous && e.time==latest)
            Alert(_Symbol," WickHuntAnchor ",e.direction==1 ? "BUY" : "SELL",
                  " | closed ",EnumToString(g_hunt_tf)," | ",PatternText(e.pattern));
      }
   g_last_closed=latest; g_closed_ready=true; g_history_dirty=false;
   g_display_dirty=true; g_buffers_dirty=true;
   return true;
}

bool ReplayLowerClosed()
{
   if(WHARefreshQuoteSessions(_Symbol)) g_history_dirty=true;
   long opened=(long)iTime(_Symbol,InpCheckTF,0);
   int available=iBars(_Symbol,InpCheckTF);
   if(opened<=0 || !SeriesInfoInteger(_Symbol,InpCheckTF,SERIES_SYNCHRONIZED)) return false;
   if(g_check_ready && !g_history_dirty && opened==g_check_open && available==g_check_available) return true;
   MqlRates lower[]; ArraySetAsSeries(lower,false);
   int requested=InpCheckHistoryBars==0 ? available : InpCheckHistoryBars+1;
   int n=CopyRates(_Symbol,InpCheckTF,0,requested,lower);
   if(n<2 || (long)lower[n-1].time!=opened ||
      !SeriesInfoInteger(_Symbol,InpCheckTF,SERIES_SYNCHRONIZED)) return false;
   int main_count=ArraySize(g_bars),main=0,active=-1;
   bool complete=false,buy_sent=false,sell_sent=false;
   long previous_end=0,prior_checked=g_check_last_closed;
   double running_high=0,running_low=0;
   bool was_ready=g_check_ready;
   // Keep a failed/interrupted replay dirty until it completes successfully.
   g_history_dirty=true;
   ArrayResize(g_events,0);
   for(int i=0;i<n-1;i++)
   {
      if(IsStopped() || (i>0 && lower[i].time<=lower[i-1].time)) return false;
      WHABar small={(long)lower[i].time,lower[i].open,lower[i].high,lower[i].low,lower[i].close};
      long closed_at=small.time+g_check_seconds;
      if(closed_at>opened) return false;
      while(main+1<main_count && g_bars[main+1].time<=small.time) main++;
      int window=-1;
      if(small.time>=g_bars[main].time && closed_at<=g_bars[main].time+g_hunt_seconds) window=main;
      if(window!=active)
      {
         active=window; buy_sent=false; sell_sent=false;
         complete=window>=0 && WHAClosedQuoteGap(g_bars[window].time,small.time);
         running_high=window>=0 ? g_bars[window].open : 0;
         running_low=running_high;
      }
      else if(small.time!=previous_end && !WHAClosedQuoteGap(previous_end,small.time)) complete=false;
      if(!WHAValid(small)) complete=false;
      if(window>=0 && WHAValid(small))
      {
         // Scheduled quote closures may separate these bars; open-session
         // data gaps still invalidate this window. Never synthesize a candle.
         // Only lower candles already closed contribute the current main
         // wick. Never import its final high/low from future primary OHLC.
         running_high=MathMax(running_high,small.high);
         running_low=MathMin(running_low,small.low);
      }
      if(complete && window>=InpHuntBars)
      {
         WHABar snapshot={g_bars[window].time,g_bars[window].open,running_high,running_low,small.close};
         if(buy_sent && !RefreshEventAnchor(snapshot,window,1,buy_sent)) return false;
         if(sell_sent && !RefreshEventAnchor(snapshot,window,-1,sell_sent)) return false;
         bool emitted=false;
         // The anchor scan receives only main candles BEFORE this window.
         if(InpEnableBuy && !buy_sent)
         {
            if(!AddEvent(snapshot,window,closed_at,small.close,1,true,emitted)) return false;
            if(emitted) buy_sent=true;
         }
         if(InpEnableSell && !sell_sent)
         {
            if(!AddEvent(snapshot,window,closed_at,small.close,-1,true,emitted)) return false;
            if(emitted) sell_sent=true;
         }
      }
      previous_end=closed_at;
   }
   if(InpPopupAlert && was_ready)
      for(int i=0;i<ArraySize(g_events);i++)
      {
         WHAEvent e=g_events[i];
         if(e.time>prior_checked && e.time==previous_end)
            Alert(_Symbol," WickHuntAnchor ",e.direction==1 ? "BUY" : "SELL",
                  " | ",EnumToString(g_hunt_tf)," hunt/open at ",EnumToString(InpCheckTF),
                  " close | ",PatternText(e.pattern));
      }
   g_check_open=opened; g_check_available=available;
   g_check_last_closed=previous_end; g_check_first=(long)lower[0].time;
   g_check_ready=true; g_history_dirty=false; g_display_dirty=true; g_buffers_dirty=true;
   return true;
}

bool RenderEvents()
{
   if(!g_display_dirty) return true;
   ObjectsDeleteAll(0,g_prefix+"event_");
   int total=ArraySize(g_events),first=(int)MathMax(0,total-InpVisibleSignals);
   ENUM_TIMEFRAMES chart_tf=(ENUM_TIMEFRAMES)_Period;
   for(int i=first;i<total;i++)
   {
      WHAEvent e=g_events[i]; long plotted=e.closed ? e.time-1 : e.time;
      int shift=iBarShift(_Symbol,chart_tf,(datetime)plotted,false);
      if(shift<0) continue;
      long opened=(long)iTime(_Symbol,chart_tf,shift);
      if(opened<=0 || plotted<opened || plotted>=opened+PeriodSeconds(chart_tf)) continue;
      double high=iHigh(_Symbol,chart_tf,shift),low=iLow(_Symbol,chart_tf,shift);
      if(!MathIsValidNumber(high) || !MathIsValidNumber(low) || high<low || low<=0) continue;
      double marker=e.direction==1 ? low-InpArrowGapPoints*_Point : high+InpArrowGapPoints*_Point;
      string name=g_prefix+"event_"+IntegerToString(i);
      if(!ObjectCreate(0,name,OBJ_ARROW,0,(datetime)opened,marker)) return false;
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,e.direction==1 ? 233 : 234);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,e.direction==1 ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0,name,OBJPROP_COLOR,e.direction==1 ? InpBuyColor : InpSellColor);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,InpArrowWidth);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,0);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      string tooltip=(e.direction==1 ? "BUY" : "SELL")+" | "+PatternText(e.pattern)+
                     (e.observation==WHA_LOWER_TF_CLOSE ? " | confirmed "+EnumToString(InpCheckTF)+" close " :
                      (e.closed ? " | confirmed main close " : " | observed tick "))+
                     TimeToString((datetime)e.time,TIME_DATE|TIME_SECONDS)+
                     " | hunt "+EnumToString(g_hunt_tf)+" "+TimeToString((datetime)e.setup_time)+
                     " | signal tip "+DoubleToString(e.signal_tip,_Digits)+
                     " | latest tip "+DoubleToString(e.tip,_Digits)+
                     " | first anchor "+TimeToString((datetime)e.anchor_time,TIME_DATE|TIME_MINUTES)+
                     " | head wick "+DoubleToString(e.head_wick_percent,2)+"% of High-Low";
      ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip);
      if(InpShowAnchorLinks)
      {
         string link=name+"_link";
         if(!ObjectCreate(0,link,OBJ_TREND,0,(datetime)e.anchor_time,e.signal_tip,(datetime)e.time,e.signal_tip)) return false;
         ObjectSetInteger(0,link,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,link,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,link,OBJPROP_COLOR,InpAnchorColor); ObjectSetInteger(0,link,OBJPROP_STYLE,STYLE_DOT);
         ObjectSetInteger(0,link,OBJPROP_BACK,true); ObjectSetInteger(0,link,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,link,OBJPROP_HIDDEN,true); ObjectSetString(0,link,OBJPROP_TOOLTIP,tooltip);
      }
   }
   g_display_dirty=false;
   return true;
}

bool UpdateEngine()
{
   if(g_prefix=="" || g_chart_total<1) return false;
   if(!LoadHistory()) { Status("History loading / waiting for main timeframe"); return false; }
   if(InpObservationMode==WHA_LOWER_TF_CLOSE)
   {
      if(!ReplayLowerClosed()) { Status("History loading / waiting for lower timeframe"); return false; }
   }
   else if(InpObservationMode==WHA_CLOSED_CANDLE)
   {
      if(!ReplayClosed()) { Status("History replay failed; retrying"); return false; }
   }
   else
   {
      MqlTick tick;
      if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !SymbolInfoTick(_Symbol,tick) || tick.time<=0)
      { Status("Disconnected / waiting for quote"); return false; }
      MqlRates current[];
      if(CopyRates(_Symbol,g_hunt_tf,0,1,current)!=1 || (long)current[0].time!=g_loaded_open)
      { g_force_history=true; Status("Waiting for current main candle"); return false; }
      long now=(long)tick.time;
      if(now<g_loaded_open || now>=g_loaded_open+g_hunt_seconds)
      { Status("Live tick / waiting for current quote"); return false; }
      double price=SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE)==SYMBOL_CHART_MODE_LAST ? tick.last : tick.bid;
      if(!MathIsValidNumber(price) || price<=0 || price<current[0].low || price>current[0].high) return false;
      if(g_live_setup!=g_loaded_open)
      {
         // Finalize the previously observed candle against its now-closed
         // tip before resetting this instance's emission flags.
         int previous=ArraySize(g_bars)-2;
         if(previous>=0 && g_bars[previous].time==g_live_setup &&
            ((!RefreshEventAnchor(g_bars[previous],previous,1,g_buy_sent)) ||
             (!RefreshEventAnchor(g_bars[previous],previous,-1,g_sell_sent))))
         { Status("Anchor refresh failed; retrying"); return false; }
         g_live_setup=g_loaded_open; g_buy_sent=false; g_sell_sent=false;
      }
      WHABar bar={(long)current[0].time,current[0].open,current[0].high,current[0].low,current[0].close};
      if(!RefreshEventAnchor(bar,ArraySize(g_bars)-1,1,g_buy_sent) ||
         !RefreshEventAnchor(bar,ArraySize(g_bars)-1,-1,g_sell_sent))
      { Status("Anchor refresh failed; retrying"); return false; }
      for(int direction=1;direction>=-1;direction-=2)
      {
         if(direction==1 ? !InpEnableBuy || g_buy_sent : !InpEnableSell || g_sell_sent) continue;
         bool emitted;
         if(!AddEvent(bar,ArraySize(g_bars)-1,now,price,direction,false,emitted))
         { Status("Signal allocation failed; retrying"); return false; }
         if(!emitted) continue;
         if(direction==1) g_buy_sent=true; else g_sell_sent=true;
         WHAEvent e=g_events[ArraySize(g_events)-1];
         if(InpPopupAlert && g_live_observed)
            Alert(_Symbol," WickHuntAnchor ",direction==1 ? "BUY" : "SELL",
                  " | ",EnumToString(g_hunt_tf)," hunt/open | ",PatternText(e.pattern));
      }
      g_live_observed=true;
   }
   return true;
}
#endif
