#ifndef PA_REVERSAL_TRADER_CORE
#define PA_REVERSAL_TRADER_CORE

#include "../../Indicators/PAReversal/PAReversalCore.mqh"
#include "../ScalpCalculator/ScalpCore.mqh"

struct PAConfirmedSwing
{
   int type; // +1 high, -1 low
   long time;
   double price;
};

struct PASetup
{
   int direction;
   int signal_index;
   long signal_time;
   double signal_price;
   double ema20,atr;
   double pattern_low,pattern_high;
   double sl,tp;
   double rr_entry;
   double rr_threshold;
   bool followup_allowed;
};

struct PATradeConfig
{
   int min_bars,ema_period,atr_length;
   double max_sl_ema_atr,max_retrace_ema_atr,max_ema_penetration_atr;
   double sl_buffer_points,min_rr,point,tick;
};

bool PATradeConfigValid(const PATradeConfig &c)
{
   return c.min_bars>=2 && c.min_bars<=1000 && c.ema_period>=1 && c.ema_period<=1000 &&
          c.atr_length>=1 && c.atr_length<=1000 && MathIsValidNumber(c.max_sl_ema_atr) && c.max_sl_ema_atr>0 &&
          MathIsValidNumber(c.max_retrace_ema_atr) && c.max_retrace_ema_atr>0 &&
          MathIsValidNumber(c.max_ema_penetration_atr) && c.max_ema_penetration_atr>0 &&
          MathIsValidNumber(c.sl_buffer_points) && c.sl_buffer_points>=0 &&
          MathIsValidNumber(c.min_rr) && c.min_rr>=1 && MathIsValidNumber(c.point) && c.point>0 &&
          MathIsValidNumber(c.tick) && c.tick>0;
}

double PAEmaNext(const double value,const double previous,const int period)
{
   return previous+(2.0/(period+1.0))*(value-previous);
}

double PAWilderAtrNext(const PABar &bar,const double previous_close,const double previous_atr,
                       const int period,const bool first)
{
   double tr=first ? bar.high-bar.low : MathMax(bar.high-bar.low,
                    MathMax(MathAbs(bar.high-previous_close),MathAbs(bar.low-previous_close)));
   return first ? tr : previous_atr+(tr-previous_atr)/period;
}

double PAOutwardStop(const bool buy,const double pattern_low,const double pattern_high,
                     const double buffer_points,const double point,const double tick,const int digits)
{
   if(!MathIsValidNumber(buffer_points) || buffer_points<0 || point<=0 || tick<=0) return 0;
   double distance=MathMax(tick,buffer_points*point);
   double raw=buy ? pattern_low-distance : pattern_high+distance;
   double stop=ScalpSnap(raw,tick,digits);
   if(buy && stop>raw+tick*1e-7) stop=ScalpSnap(stop-tick,tick,digits);
   if(!buy && stop<raw-tick*1e-7) stop=ScalpSnap(stop+tick,tick,digits);
   return stop;
}

double PARRThreshold(const bool buy,const double sl,const double tp)
{
   // Entry at or better than this midpoint gives reward >= risk.
   if(buy) { /* midpoint is symmetric; keep the side explicit for readability */ }
   return (sl+tp)/2.0;
}

double PATargetPrice(const bool buy,const double target,const double buffer_points,
                     const double point,const double tick,const int digits)
{
   if(!MathIsValidNumber(target) || target<=0 || !MathIsValidNumber(buffer_points) || buffer_points<0 ||
      point<=0 || tick<=0) return 0;
   double raw=target+(buy ? -1 : 1)*buffer_points*point;
   double price=ScalpSnap(raw,tick,digits);
   if(buffer_points>0 && buy && price>raw+tick*1e-7) price=ScalpSnap(price-tick,tick,digits);
   if(buffer_points>0 && !buy && price<raw-tick*1e-7) price=ScalpSnap(price+tick,tick,digits);
   return price;
}

// Keep the nearest swing as the structural target, but never place a target
// beyond one initial risk unit. If the swing is closer than 1R it is kept so
// the one-bar recovery logic can wait for a better entry.
double PACapTPAtOneR(const bool buy,const double entry,const double sl,const double swing_tp)
{
   if(!ScalpGeometry(buy,entry,sl,swing_tp)) return 0;
   double one_r=buy ? entry+(entry-sl) : entry-(sl-entry);
   return buy ? MathMin(swing_tp,one_r) : MathMax(swing_tp,one_r);
}

bool PARRValid(const bool buy,const double entry,const double sl,const double tp,const double minimum)
{
   return MathIsValidNumber(entry) && MathIsValidNumber(sl) && MathIsValidNumber(tp) && minimum>=1 &&
          ScalpGeometry(buy,entry,sl,tp) && ScalpRR(entry,sl,tp)+1e-12>=minimum;
}

bool PASLFromEMAValid(const double ema,const double sl,const double atr,const double max_atr)
{
   return MathIsValidNumber(ema) && MathIsValidNumber(sl) && MathIsValidNumber(atr) && atr>0 &&
          MathAbs(ema-sl)<=max_atr*atr+1e-9;
}

// The old SL-to-EMA envelope is a safety guard. This separate filter makes
// the signal candle actually interact with EMA20: its wick must come close to
// the line, or pierce it by no more than the configured ATR allowance and then
// close back on the trend side. PAStep already guarantees the PA reversal /
// engulf condition (close outside the previous candle's wick).
bool PAEMAReversalValid(const bool buy,const PABar &bar,const PABar &previous,
                        const double ema,const double previous_ema,const double atr,
                        const double max_retrace_atr,const double max_penetration_atr)
{
   if(!PAValid(bar) || !PAValid(previous) || !MathIsValidNumber(ema) ||
      !MathIsValidNumber(previous_ema) || !MathIsValidNumber(atr) || atr<=0 ||
      !MathIsValidNumber(max_retrace_atr) || max_retrace_atr<=0 ||
      !MathIsValidNumber(max_penetration_atr) || max_penetration_atr<=0) return false;
   double near_distance=max_retrace_atr*atr;
   double penetration=max_penetration_atr*atr;
   if(buy)
   {
      if(bar.close<=ema) return false;
      bool near_line=bar.low<=ema+near_distance && bar.low>=ema-penetration;
      bool pierced=bar.low<=ema || previous.low<=previous_ema || previous.close<=previous_ema;
      bool reclaimed=pierced && bar.low<=ema+near_distance && bar.low>=ema-penetration;
      return near_line || reclaimed;
   }
   if(bar.close>=ema) return false;
   bool near_line=bar.high>=ema-near_distance && bar.high<=ema+penetration;
   bool pierced=bar.high>=ema || previous.high>=previous_ema || previous.close>=previous_ema;
   bool reclaimed=pierced && bar.high>=ema-near_distance && bar.high<=ema+penetration;
   return near_line || reclaimed;
}

// For a bearish reversal, the prior upward retrace's preceding candles must
// remain below EMA20; for a bullish reversal they must remain above it. The
// latest retrace candle is deliberately excluded because it may cross EMA20
// before the engulf candle confirms the reversal.
bool PALegEMASequenceValid(const bool bullish_reversal,const PABar &bars[],
                           const double &ema_values[],const int signal_index,
                           const int minimum)
{
   if(signal_index<minimum || minimum<2 || ArraySize(bars)<=signal_index ||
      ArraySize(ema_values)<=signal_index) return false;
   for(int offset=2;offset<=minimum;offset++)
   {
      int index=signal_index-offset;
      if(index<0 || !MathIsValidNumber(ema_values[index])) return false;
      if(bullish_reversal)
      {
         if(bars[index].close<=ema_values[index]) return false;
      }
      else
      {
         if(bars[index].close>=ema_values[index]) return false;
      }
   }
   return true;
}

int PANearestTarget(const bool buy,const double entry,const PAConfirmedSwing &swings[])
{
   int best=-1;
   for(int i=0;i<ArraySize(swings);i++)
   {
      PAConfirmedSwing s=swings[i];
      if(s.type!=(buy ? 1 : -1) || !MathIsValidNumber(s.price) || s.price<=0 ||
         (buy ? s.price<=entry : s.price>=entry)) continue;
      if(best<0 || (buy ? s.price<swings[best].price : s.price>swings[best].price) ||
         (s.price==swings[best].price && s.time>swings[best].time)) best=i;
   }
   return best;
}

// Rebuild only closed candles. signal_index is the PA candle that just closed;
// the caller supplies a history window ending at that candle.
bool PABuildLatest(const PATradeConfig &c,const PABar &bars[],const int n,const int signal_index,
                   const int digits,PASetup &setup,string &reason)
{
   ZeroMemory(setup); reason="No PA reversal";
   if(!PATradeConfigValid(c) || n<2 || signal_index<1 || signal_index>=n) { reason="Invalid PA history"; return false; }
   PAState state{}; double ema=0,atr=0,previous_close=0; bool seeded=false;
   double ema_values[]; ArrayResize(ema_values,n);
   double leg_high=0,leg_low=0; PAConfirmedSwing swings[]; ArrayResize(swings,0);
   int signal=0; PABar previous{};
   for(int i=0;i<=signal_index;i++)
   {
      if(!PAValid(bars[i])) { PASeed(bars[i],state); seeded=false; ArrayResize(swings,0); continue; }
      double ema_before=ema;
      bool was_seeded=seeded;
      ema=(!seeded) ? bars[i].close : PAEmaNext(bars[i].close,ema,c.ema_period);
      ema_values[i]=ema;
      atr=PAWilderAtrNext(bars[i],previous_close,atr,c.atr_length,!seeded);
      previous_close=bars[i].close; seeded=true;
      PAState after{}; signal=0;
      if(i==0) PASeed(bars[i],after);
      else signal=PAStep(bars[i],previous,state,c.min_bars,after);
      if(i==0 || state.direction==0)
      {
         if(after.direction==1) { leg_high=bars[i].high; leg_low=bars[i].low; }
         if(after.direction==-1) { leg_high=bars[i].high; leg_low=bars[i].low; }
      }
      bool is_latest_signal=signal!=0 && i==signal_index;
      // The prior leg's extreme becomes a confirmed swing on reversal. Do not
      // add the current swing before selecting the profit target.
      if(signal!=0)
      {
         if(signal==1)
         {
            int target=PANearestTarget(true,bars[i].close,swings);
            PAConfirmedSwing low={-1,0,leg_low};
            if(is_latest_signal && target>=0 && bars[i].close>ema &&
               PALegEMASequenceValid(true,bars,ema_values,i,c.min_bars) &&
               PAEMAReversalValid(true,bars[i],bars[i-1],ema,was_seeded ? ema_before : ema,atr,
                                  c.max_retrace_ema_atr,c.max_ema_penetration_atr))
            {
               double sl=PAOutwardStop(true,MathMin(bars[i].low,bars[i-1].low),MathMax(bars[i].high,bars[i-1].high),
                                       c.sl_buffer_points,c.point,c.tick,digits);
               double tp=ScalpSnap(swings[target].price,c.tick,digits);
               if(PASLFromEMAValid(ema,sl,atr,c.max_sl_ema_atr))
               {
                  setup.direction=1; setup.signal_index=i; setup.signal_time=0; setup.signal_price=bars[i].close;
                  setup.ema20=ema; setup.atr=atr; setup.pattern_low=MathMin(bars[i].low,bars[i-1].low);
                  setup.pattern_high=MathMax(bars[i].high,bars[i-1].high); setup.sl=sl; setup.tp=tp;
                  setup.rr_threshold=PARRThreshold(true,sl,tp); setup.rr_entry=ScalpRR(bars[i].close,sl,tp);
                  setup.followup_allowed=setup.rr_entry+1e-12<c.min_rr; reason="Signal ready";
               }
            }
            int count=ArraySize(swings); ArrayResize(swings,count+1); swings[count]=low;
         }
         else
         {
            int target=PANearestTarget(false,bars[i].close,swings);
            PAConfirmedSwing high={1,0,leg_high};
            if(is_latest_signal && target>=0 && bars[i].close<ema &&
               PALegEMASequenceValid(false,bars,ema_values,i,c.min_bars) &&
               PAEMAReversalValid(false,bars[i],bars[i-1],ema,was_seeded ? ema_before : ema,atr,
                                  c.max_retrace_ema_atr,c.max_ema_penetration_atr))
            {
               double sl=PAOutwardStop(false,MathMin(bars[i].low,bars[i-1].low),MathMax(bars[i].high,bars[i-1].high),
                                       c.sl_buffer_points,c.point,c.tick,digits);
               double tp=ScalpSnap(swings[target].price,c.tick,digits);
               if(PASLFromEMAValid(ema,sl,atr,c.max_sl_ema_atr))
               {
                  setup.direction=-1; setup.signal_index=i; setup.signal_time=0; setup.signal_price=bars[i].close;
                  setup.ema20=ema; setup.atr=atr; setup.pattern_low=MathMin(bars[i].low,bars[i-1].low);
                  setup.pattern_high=MathMax(bars[i].high,bars[i-1].high); setup.sl=sl; setup.tp=tp;
                  setup.rr_threshold=PARRThreshold(false,sl,tp); setup.rr_entry=ScalpRR(bars[i].close,sl,tp);
                  setup.followup_allowed=setup.rr_entry+1e-12<c.min_rr; reason="Signal ready";
               }
            }
            int count=ArraySize(swings); ArrayResize(swings,count+1); swings[count]=high;
         }
         leg_high=bars[i].high; leg_low=bars[i].low;
      }
      else if(after.direction==1) { leg_high=MathMax(leg_high,bars[i].high); leg_low=MathMin(leg_low,bars[i].low); }
      else if(after.direction==-1) { leg_high=MathMax(leg_high,bars[i].high); leg_low=MathMin(leg_low,bars[i].low); }
      previous=bars[i]; state=after;
   }
   return setup.direction!=0;
}
#endif
