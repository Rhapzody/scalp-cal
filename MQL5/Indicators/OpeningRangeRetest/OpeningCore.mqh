#ifndef OPENING_RANGE_RETEST_CORE
#define OPENING_RANGE_RETEST_CORE

enum ENUM_OR_SIDE { OR_BOTH=0, OR_BUY_ONLY=1, OR_SELL_ONLY=2 };
enum ENUM_OR_RETEST { OR_RETEST_WICK=0, OR_RETEST_CLOSE=1 };

struct ORBar { long time; double open,high,low,close; };
struct ORConfig
{
   int start_hour,start_minute,range_minutes,atr_length,max_retest_bars,cooldown_days;
   int min_range_points;
   ENUM_OR_SIDE side;
   ENUM_OR_RETEST retest_mode;
   double min_break_atr,max_break_atr,min_body_ratio,min_close_location;
   double stop_buffer_atr,stop_buffer_points,min_stop_atr,max_stop_atr,target_rr,point;
};
struct ORSignal
{
   int direction;
   long time,session_start,session_end,breakout_time,retest_time;
   double price,trigger,stop,target,range_high,range_low,atr,high,low;
};
struct ORState
{
   long day,session_start,session_end,breakout_time;
   int phase,direction,range_count,breakout_index,signal_index,last_signal_day;
   double range_high,range_low,atr,previous_close;
   long previous_time;
};

bool ORConfigValid(const ORConfig &c)
{
   return c.start_hour>=0 && c.start_hour<=23 && c.start_minute>=0 && c.start_minute<=59 &&
          c.range_minutes>=5 && c.range_minutes<=480 && c.range_minutes%5==0 &&
          c.atr_length>=2 && c.atr_length<=200 && c.max_retest_bars>=1 && c.max_retest_bars<=100 &&
          c.cooldown_days>=0 && c.cooldown_days<=30 && c.min_range_points>=0 &&
          c.side>=OR_BOTH && c.side<=OR_SELL_ONLY && c.retest_mode>=OR_RETEST_WICK && c.retest_mode<=OR_RETEST_CLOSE &&
          MathIsValidNumber(c.min_break_atr) && c.min_break_atr>=0 &&
          MathIsValidNumber(c.max_break_atr) && c.max_break_atr>c.min_break_atr &&
          MathIsValidNumber(c.min_body_ratio) && c.min_body_ratio>=0 && c.min_body_ratio<=1 &&
          MathIsValidNumber(c.min_close_location) && c.min_close_location>=0.5 && c.min_close_location<=1 &&
          MathIsValidNumber(c.stop_buffer_atr) && c.stop_buffer_atr>=0 &&
          MathIsValidNumber(c.stop_buffer_points) && c.stop_buffer_points>=0 &&
          MathIsValidNumber(c.stop_buffer_points*c.point) && MathIsValidNumber(c.point) && c.point>0 &&
          MathIsValidNumber(c.min_stop_atr) && c.min_stop_atr>0 &&
          MathIsValidNumber(c.max_stop_atr) && c.max_stop_atr>=c.min_stop_atr &&
          MathIsValidNumber(c.target_rr) && c.target_rr>=1 && c.target_rr<=10;
}
bool ORBarValid(const ORBar &b)
{
   return b.time>0 && MathIsValidNumber(b.open) && MathIsValidNumber(b.high) &&
          MathIsValidNumber(b.low) && MathIsValidNumber(b.close) && b.low>0 && b.high>=b.low &&
          b.open>=b.low && b.open<=b.high && b.close>=b.low && b.close<=b.high;
}
int ORWarmup(const ORConfig &c) { return (int)MathMax(3*c.atr_length,c.range_minutes/5+2); }
void ORReset(ORState &s) { ZeroMemory(s); s.day=-1; s.phase=0; s.last_signal_day=-1000000; }
long ORDay(const long t) { return t/86400; }
long ORSessionStart(const ORConfig &c,const long t)
{ return ORDay(t)*86400+c.start_hour*3600+c.start_minute*60; }
bool ORSideAllowed(const ORConfig &c,const int direction)
{ return (direction==1 && c.side!=OR_SELL_ONLY) || (direction==-1 && c.side!=OR_BUY_ONLY); }

bool ORProcess(ORState &s,const ORConfig &c,const ORBar &bars[],const int i,ORSignal &out)
{
   ZeroMemory(out);
   ORBar b=bars[i];
   if(!ORBarValid(b) || (s.previous_time>0 && b.time<=s.previous_time)) { ORReset(s); return false; }
   if(s.previous_time>0 && b.time-s.previous_time!=300) { ORReset(s); }
   long day=ORDay(b.time), start=ORSessionStart(c,b.time), end=start+c.range_minutes*60;
   if(s.day!=day || b.time<start)
   {
      if(b.time<start) { s.previous_time=b.time; s.previous_close=b.close; return false; }
      int prior_signal_day=s.last_signal_day;
      ZeroMemory(s); s.day=day; s.session_start=start; s.session_end=end; s.phase=0; s.last_signal_day=prior_signal_day;
   }
   double tr=b.high-b.low;
   if(s.range_count==0) s.atr=tr;
   else { tr=MathMax(tr,MathMax(MathAbs(b.high-s.previous_close),MathAbs(b.low-s.previous_close))); s.atr+=(tr-s.atr)/c.atr_length; }
   if(b.time>=start && b.time<end)
   {
      if(s.range_count==0) { s.range_high=b.high; s.range_low=b.low; }
      else { s.range_high=MathMax(s.range_high,b.high); s.range_low=MathMin(s.range_low,b.low); }
      s.range_count++; s.previous_time=b.time; s.previous_close=b.close; return true;
   }
   if(s.range_count<c.range_minutes/5 || s.atr<=0) { s.previous_time=b.time; s.previous_close=b.close; return true; }
   if(s.phase==0 && b.time>=end && (s.last_signal_day<0 || day-s.last_signal_day>c.cooldown_days))
   {
      double range=s.range_high-s.range_low, body=range>0 ? MathAbs(b.close-b.open)/range : 0;
      double loc_buy=range>0 ? (b.close-b.low)/range : 0,loc_sell=range>0 ? (b.high-b.close)/range : 0;
      for(int direction=-1;direction<=1;direction+=2)
      {
         if(!ORSideAllowed(c,direction)) continue;
         bool buy=direction==1; double level=buy?s.range_high:s.range_low;
         double penetration=buy?b.close-level:level-b.close;
         if(direction*(b.close-b.open)<=0 || penetration<c.min_break_atr*s.atr ||
            penetration>c.max_break_atr*s.atr || body<c.min_body_ratio ||
            (buy?loc_buy:loc_sell)<c.min_close_location || range<c.min_range_points*c.point) continue;
         s.phase=1; s.direction=direction; s.breakout_time=b.time; s.breakout_index=i; break;
      }
   }
   else if(s.phase==1 && i-s.breakout_index>c.max_retest_bars)
   { s.phase=3; }
   else if(s.phase==1 && i>s.breakout_index)
   {
      bool buy=s.direction==1;
      bool touched=c.retest_mode==OR_RETEST_WICK ? (buy ? b.low<=s.range_high : b.high>=s.range_low) :
                                                  (buy ? b.close<=s.range_high : b.close>=s.range_low);
      bool reclaimed=buy ? b.close>s.range_high && b.close>b.open : b.close<s.range_low && b.close<b.open;
      if((buy && b.close<s.range_low) || (!buy && b.close>s.range_high)) s.phase=3;
      else if(touched && reclaimed)
      {
         double buffer=MathMax(c.point,c.stop_buffer_atr*s.atr+c.stop_buffer_points*c.point);
         double stop=buy?b.low-buffer:b.high+buffer;
         double risk=buy?b.close-stop:stop-b.close;
         double target=b.close+(buy?1:-1)*c.target_rr*risk;
         if(risk>=c.min_stop_atr*s.atr && risk<=c.max_stop_atr*s.atr && stop>0 && target>0)
         {
            out.direction=s.direction; out.time=b.time; out.session_start=s.session_start; out.session_end=s.session_end;
            out.breakout_time=s.breakout_time; out.retest_time=b.time; out.price=b.close;
            out.trigger=buy?s.range_high:s.range_low; out.stop=stop; out.target=target;
            out.range_high=s.range_high; out.range_low=s.range_low; out.atr=s.atr; out.high=b.high; out.low=b.low;
            s.phase=2; s.last_signal_day=(int)s.day;
         }
      }
   }
   s.previous_time=b.time; s.previous_close=b.close;
   return true;
}
bool ORReplay(const ORConfig &c,const ORBar &bars[],const int n,const long horizon,ORSignal &entries[])
{
   ArrayResize(entries,0); if(!ORConfigValid(c)||n<1||ArrayResize(entries,n)!=n)return false;
   ORState s; ORReset(s); int count=0;
   for(int i=0;i<n && bars[i].time+300<=horizon;i++) { if(IsStopped())return false; ORSignal x; if(ORProcess(s,c,bars,i,x)&&x.direction)entries[count++]=x; }
   return ArrayResize(entries,count)==count;
}
#endif
