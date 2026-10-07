#ifndef MACD_ZONE_PULLBACK_CORE
#define MACD_ZONE_PULLBACK_CORE
#include "SwingCore.mqh"
#include "FVGCore.mqh"

#define RP_MAX_ZONES 256
enum ENUM_RP_ZONE_MODE { RP_BOTH=0,RP_SWING_ZONE=1,RP_ORIGIN_ZONE=2 };
enum ENUM_RP_STRENGTH { RP_FVG_OR_DISPLACEMENT=0,RP_FVG_ONLY=1 };
enum ENUM_RP_STATUS { RP_WAITING=0,RP_TOUCHED=1,RP_INVALID=2,RP_EXPIRED=3,RP_SIGNALED=4 };
enum ENUM_RP_SIDE { RP_ALL_SIDES=0,RP_BUY_ONLY=1,RP_SELL_ONLY=2 };
enum ENUM_RP_TOUCH { RP_TOUCH_WICK=0,RP_TOUCH_CLOSE=1 };
enum ENUM_RP_INVALIDATE { RP_INVALIDATE_CLOSE=0,RP_INVALIDATE_WICK=1 };

struct RPConfig
{
   MSConfig macd;
   ENUM_RP_ZONE_MODE zones;
   ENUM_RP_STRENGTH strength;
   double min_leg_atr,min_fvg_atr,min_efficiency,min_body_ratio;
   int max_leg_bars,zone_life_bars,confirmation_bars;
   ENUM_RP_SIDE side;
   ENUM_RP_TOUCH touch_mode;
   ENUM_RP_INVALIDATE invalidate_mode;
   double m5_break_buffer_points,m1_break_buffer_points,max_close_tail_ratio;
};

struct RPZone
{
   int serial,direction,kind,quality,status,born_index,touch_index;
   long source_time,born_time,touch_time,end_time;
   double lower,upper,sr;
};

struct RPEntry
{
   int direction,kind,quality,zone_serial;
   long time; // M1 opening time; signal becomes known 60 seconds later.
   double price,trigger,lower,upper,sr;
};

struct RPState
{
   MSEngine m1,m5;
   MSEvent high1,low1,high5,low5;
   bool has_high1,has_low1,has_high5,has_low5;
   bool broken_high1,broken_low1,broken_high5,broken_low5;
   RPZone zones[RP_MAX_ZONES];
   int next_slot,serial;
};

bool RPConfigValid(const RPConfig &c)
{
   return MSConfigValid(c.macd) && c.macd.swing_mode==MS_HISTOGRAM_COLOR &&
          c.zones>=RP_BOTH && c.zones<=RP_ORIGIN_ZONE &&
          c.strength>=RP_FVG_OR_DISPLACEMENT && c.strength<=RP_FVG_ONLY &&
          MathIsValidNumber(c.min_leg_atr) && c.min_leg_atr>0 &&
          MathIsValidNumber(c.min_fvg_atr) && c.min_fvg_atr>=0 &&
          MathIsValidNumber(c.min_efficiency) && c.min_efficiency>0 && c.min_efficiency<=1 &&
          MathIsValidNumber(c.min_body_ratio) && c.min_body_ratio>0 && c.min_body_ratio<=1 &&
          c.side>=RP_ALL_SIDES && c.side<=RP_SELL_ONLY &&
          c.touch_mode>=RP_TOUCH_WICK && c.touch_mode<=RP_TOUCH_CLOSE &&
          c.invalidate_mode>=RP_INVALIDATE_CLOSE && c.invalidate_mode<=RP_INVALIDATE_WICK &&
          MathIsValidNumber(c.m5_break_buffer_points) && c.m5_break_buffer_points>=0 &&
          MathIsValidNumber(c.m5_break_buffer_points*c.macd.point) &&
          MathIsValidNumber(c.m1_break_buffer_points) && c.m1_break_buffer_points>=0 &&
          MathIsValidNumber(c.m1_break_buffer_points*c.macd.point) &&
          MathIsValidNumber(c.max_close_tail_ratio) && c.max_close_tail_ratio>=0 && c.max_close_tail_ratio<=1 &&
          c.max_leg_bars>=3 && c.max_leg_bars<=300 && c.zone_life_bars>=1 &&
          c.zone_life_bars<=1000 && c.confirmation_bars>=1 && c.confirmation_bars<=300;
}

bool RPDirectionAllowed(const RPConfig &c,const int direction)
{
   return (direction==1 && c.side!=RP_SELL_ONLY) || (direction==-1 && c.side!=RP_BUY_ONLY);
}

void RPReset(RPState &s)
{
   ZeroMemory(s);
   MSReset(s.m1); MSReset(s.m5);
   for(int i=0;i<RP_MAX_ZONES;i++) s.zones[i].status=RP_EXPIRED;
}

// ATR is the value BEFORE the breakout candle, avoiding a self-inflated denominator.
// Return 2 for FVG, 1 for directional displacement without qualifying FVG, 0 for rejection.
int RPQuality(const RPConfig &c,const MSBar &bars[],const int origin,const int end,
              const int direction,const double atr)
{
   if(origin<0 || end<=origin || end-origin+1>c.max_leg_bars ||
      !MathIsValidNumber(atr) || atr<=0) return 0;
   double travel=0;
   for(int i=origin;i<=end;i++)
   {
      if(!MSBarValid(bars[i])) return 0;
      // A session/data gap does not qualify as an uninterrupted impulse.
      if(i>origin && bars[i].time-bars[i-1].time!=300) return 0;
      if(i>origin) travel+=MathAbs(bars[i].close-bars[i-1].close);
   }
   double net=direction*(bars[end].close-bars[origin].close);
   if(net<c.min_leg_atr*atr || travel<=0) return 0;
   for(int i=origin+2;i<=end;i++)
   {
      FVGBar a={bars[i-2].open,bars[i-2].high,bars[i-2].low,bars[i-2].close};
      FVGBar b={bars[i-1].open,bars[i-1].high,bars[i-1].low,bars[i-1].close};
      FVGBar d={bars[i].open,bars[i].high,bars[i].low,bars[i].close};
      FVGZone gap;
      if(FVGDetect(a,b,d,0,c.macd.point,false,gap) && gap.direction==direction &&
         gap.upper-gap.lower>=c.min_fvg_atr*atr) return 2;
   }
   if(c.strength==RP_FVG_ONLY) return 0;
   MSBar b=bars[end];
   double range=b.high-b.low;
   double body=direction*(b.close-b.open);
   double remaining=direction==1 ? b.high-b.close : b.close-b.low;
   if(range<=0 || body/range<c.min_body_ratio || remaining/range>c.max_close_tail_ratio ||
      net/travel<c.min_efficiency) return 0;
   return 1;
}

bool RPAddZone(RPState &s,const RPConfig &c,const MSBar &base,const int kind,
               const int direction,const int quality,const double sr,
               const int index,const long known_time,const double breakout_close)
{
   if(!RPDirectionAllowed(c,direction) || !MSBarValid(base) || base.high<=base.low ||
      (direction==1 ? breakout_close<=base.high : breakout_close>=base.low)) return false;
   // Prefer an unused/terminal slot; only evict an active zone if all 256 are active.
   int slot=s.next_slot;
   for(int k=0;k<RP_MAX_ZONES;k++)
   {
      int p=(s.next_slot+k)%RP_MAX_ZONES;
      if(s.zones[p].serial==0 || s.zones[p].status>=RP_INVALID) { slot=p; break; }
   }
   RPZone z;
   ZeroMemory(z);
   z.serial=++s.serial; z.direction=direction; z.kind=kind; z.quality=quality;
   z.status=RP_WAITING; z.born_index=index; z.touch_index=-1;
   z.source_time=base.time; z.born_time=known_time;
   z.lower=base.low; z.upper=base.high; z.sr=sr;
   s.zones[slot]=z; s.next_slot=(slot+1)%RP_MAX_ZONES;
   return true;
}

void RPCreateSetup(RPState &s,const RPConfig &c,const MSBar &bars[],const int index,
                   const int direction,const MSEvent &target,const MSEvent &origin,
                   const bool has_origin,const double atr)
{
   if(!has_origin || origin.pivot_index<target.pivot_index || origin.pivot_index>=index ||
      target.pivot_index<0 || target.pivot_index>=index) return;
   int quality=RPQuality(c,bars,origin.pivot_index,index,direction,atr);
   if(quality==0) return;
   long known=bars[index].time+300;
   if(c.zones==RP_BOTH || c.zones==RP_SWING_ZONE)
      RPAddZone(s,c,bars[target.pivot_index],RP_SWING_ZONE,direction,quality,target.price,
                index,known,bars[index].close);
   if(c.zones==RP_BOTH || c.zones==RP_ORIGIN_ZONE)
   {
      // Last opposing candle/doji in the launch leg; fallback to its swing origin.
      int base=origin.pivot_index;
      for(int i=index-1;i>=origin.pivot_index;i--)
         if(direction*(bars[i].close-bars[i].open)<=0) { base=i; break; }
      // Identical zone in BOTH mode is represented once.
      if(c.zones==RP_BOTH && bars[base].low==bars[target.pivot_index].low &&
         bars[base].high==bars[target.pivot_index].high) return;
      RPAddZone(s,c,bars[base],RP_ORIGIN_ZONE,direction,quality,target.price,
                index,known,bars[index].close);
   }
}

void RPProcessM5(RPState &s,const RPConfig &c,const MSBar &bars[],const int index)
{
   MSBar b=bars[index];
   for(int k=0;k<RP_MAX_ZONES;k++)
      if(s.zones[k].serial>0 && s.zones[k].status<=RP_TOUCHED &&
         index-s.zones[k].born_index>=c.zone_life_bars)
      { s.zones[k].status=RP_EXPIRED; s.zones[k].end_time=b.time+300; }
   double atr=s.m5.atr;
   MSEvent event;
   if(!MSProcess(c.macd,b,index,s.m5,event))
   { s.has_high5=false; s.has_low5=false; return; }
   // A new opposite pivot confirmed on the breakout close may define its origin.
   MSEvent origin_low=s.low5,origin_high=s.high5;
   bool has_low=s.has_low5,has_high=s.has_high5;
   if(event.type==-1) { origin_low=event; has_low=true; }
   if(event.type==1) { origin_high=event; has_high=true; }
   double break_buffer=c.m5_break_buffer_points*c.macd.point;
   if(s.has_high5 && !s.broken_high5 && b.close>s.high5.price+break_buffer)
   {
      s.broken_high5=true; // First close break only, even if its quality is rejected.
      RPCreateSetup(s,c,bars,index,1,s.high5,origin_low,has_low,atr);
   }
   if(s.has_low5 && !s.broken_low5 && b.close<s.low5.price-break_buffer)
   {
      s.broken_low5=true;
      RPCreateSetup(s,c,bars,index,-1,s.low5,origin_high,has_high,atr);
   }
   if(event.type==1) { s.high5=event; s.has_high5=true; s.broken_high5=false; }
   if(event.type==-1) { s.low5=event; s.has_low5=true; s.broken_low5=false; }
}

void RPSetEntry(RPEntry &entry,const RPZone &z,const MSBar &b,const double trigger)
{
   entry.direction=z.direction; entry.kind=z.kind; entry.quality=z.quality;
   entry.zone_serial=z.serial; entry.time=b.time; entry.price=b.close;
   entry.trigger=trigger; entry.lower=z.lower; entry.upper=z.upper; entry.sr=z.sr;
}

void RPProcessM1(RPState &s,const RPConfig &c,const MSBar &b,const int index,
                  RPEntry &buy,RPEntry &sell)
{
   ZeroMemory(buy); ZeroMemory(sell);
   if(!MSBarValid(b))
   {
      MSReset(s.m1); s.has_high1=false; s.has_low1=false;
      return;
   }
   // Only levels confirmed BEFORE this candle can trigger. Never reuse an old break.
   double buffer=c.m1_break_buffer_points*c.macd.point;
   double buy_level=s.high1.price+buffer,sell_level=s.low1.price-buffer;
   bool up=RPDirectionAllowed(c,1) && s.has_high1 && !s.broken_high1 && s.high1.classification==MS_LH &&
           s.m1.count>0 && s.m1.previous_close<=buy_level && b.close>buy_level;
   bool down=RPDirectionAllowed(c,-1) && s.has_low1 && !s.broken_low1 && s.low1.classification==MS_HL &&
             s.m1.count>0 && s.m1.previous_close>=sell_level && b.close<sell_level;
   for(int k=0;k<RP_MAX_ZONES;k++)
   {
      RPZone z=s.zones[k];
      if(z.serial==0 || z.status>RP_TOUCHED || b.time<z.born_time) continue;
      double lower_check=c.invalidate_mode==RP_INVALIDATE_WICK ? b.low : b.close;
      double upper_check=c.invalidate_mode==RP_INVALIDATE_WICK ? b.high : b.close;
      if((z.direction==1 && lower_check<z.lower) || (z.direction==-1 && upper_check>z.upper))
      { s.zones[k].status=RP_INVALID; s.zones[k].end_time=b.time+60; continue; }
      if(z.status==RP_TOUCHED && index-z.touch_index>c.confirmation_bars)
      { s.zones[k].status=RP_EXPIRED; s.zones[k].end_time=b.time+60; continue; }
      bool touched=c.touch_mode==RP_TOUCH_WICK ? (b.low<=z.upper && b.high>=z.lower) :
                                                (b.close>=z.lower && b.close<=z.upper);
      if(z.status==RP_WAITING && touched)
      {
         s.zones[k].status=RP_TOUCHED; s.zones[k].touch_time=b.time+60;
         s.zones[k].touch_index=index;
         continue; // Intrabar order of touch vs break is unknown: require a later candle.
      }
      if(z.status!=RP_TOUCHED || index<=z.touch_index) continue;
      bool signal=z.direction==1 ? up : down;
      if(!signal) continue;
      // The two zone types from one breakout share one entry opportunity.
      if(z.direction==1 && (buy.direction==0 || z.serial>buy.zone_serial))
         RPSetEntry(buy,z,b,s.high1.price);
      if(z.direction==-1 && (sell.direction==0 || z.serial>sell.zone_serial))
         RPSetEntry(sell,z,b,s.low1.price);
      for(int j=0;j<RP_MAX_ZONES;j++)
         if(s.zones[j].serial>0 && s.zones[j].born_time==z.born_time &&
            s.zones[j].direction==z.direction && s.zones[j].status<=RP_TOUCHED)
         { s.zones[j].status=RP_SIGNALED; s.zones[j].end_time=b.time+60; }
   }
   if(s.has_high1 && b.close>buy_level) s.broken_high1=true;
   if(s.has_low1 && b.close<sell_level) s.broken_low1=true;
   MSEvent event;
   if(!MSProcess(c.macd,b,index,s.m1,event)) return;
   if(event.type==1) { s.high1=event; s.has_high1=true; s.broken_high1=false; }
   if(event.type==-1) { s.low1=event; s.has_low1=true; s.broken_low1=false; }
}

// Deterministic chronological replay. At equal close times M1 runs first, so a
// newly confirmed M5 breakout cannot be retested by a candle inside that breakout.
bool RPReplay(RPState &s,const RPConfig &c,const MSBar &one[],const int n1,
              const MSBar &five[],const int n5,const long horizon,RPEntry &entries[])
{
   RPReset(s);
   if(!RPConfigValid(c) || n1<1 || n5<1) return false;
   if(ArrayResize(entries,2*n1)!=2*n1) return false;
   int i=0,j=0,count=0;
   // No setups before the common history window: their intervening retests are unknown.
   while(j<n5 && five[j].time<one[0].time) j++;
   while(i<n1 || j<n5)
   {
      if(IsStopped()) return false;
      bool ready1=i<n1 && one[i].time+60<=horizon;
      bool ready5=j<n5 && five[j].time+300<=horizon;
      if(!ready1 && !ready5) break;
      if(ready1 && (!ready5 || one[i].time+60<=five[j].time+300))
      {
         RPEntry buy,sell;
         RPProcessM1(s,c,one[i],i,buy,sell);
         if(buy.direction!=0) entries[count++]=buy;
         if(sell.direction!=0) entries[count++]=sell;
         i++;
      }
      else { RPProcessM5(s,c,five,j); j++; }
   }
   return ArrayResize(entries,count)==count;
}
#endif
