#ifndef TREND_SWEEP_CORE
#define TREND_SWEEP_CORE
// All decisions use closed M5 bars and only levels/EMA/ATR known before that bar.
enum ENUM_TS_SIDE { TS_BOTH=0, TS_BUY_ONLY=1, TS_SELL_ONLY=2 };
struct TSBar { long time; double open,high,low,close; };
struct TSConfig
{
   int fast,slow,atr_length,lookback,room_bars,cooldown;
   ENUM_TS_SIDE side;
   double min_sweep_atr,max_sweep_atr,min_body,min_close_location,max_extension_atr;
   double stop_atr,stop_points,point,min_stop_atr,max_stop_atr,target_rr,room_buffer_atr;
   int start_hour,end_hour; // Broker server time; equal means all hours.
};
struct TSSignal
{
   int direction;
   long time;
   double price,trigger,stop,target,obstacle,atr,high,low;
};
struct TSState
{
   int count,last_signal,last_gap;
   double fast,slow,previous_slow,atr,previous_close;
   long previous_time;
};
bool TSValid(const TSConfig &c)
{
   return c.fast>=2 && c.fast<c.slow && c.slow<=1000 && c.atr_length>=2 && c.atr_length<=200 &&
          c.lookback>=2 && c.lookback<=100 && c.room_bars>=c.lookback && c.room_bars<=500 &&
          c.cooldown>=0 && c.cooldown<=500 && c.side>=TS_BOTH && c.side<=TS_SELL_ONLY &&
          MathIsValidNumber(c.min_sweep_atr) && c.min_sweep_atr>=0 &&
          MathIsValidNumber(c.max_sweep_atr) && c.max_sweep_atr>c.min_sweep_atr &&
          MathIsValidNumber(c.min_body) && c.min_body>=0 && c.min_body<=1 &&
          MathIsValidNumber(c.min_close_location) && c.min_close_location>=0.5 && c.min_close_location<=1 &&
          MathIsValidNumber(c.max_extension_atr) && c.max_extension_atr>0 &&
          MathIsValidNumber(c.stop_atr) && c.stop_atr>=0 &&
          MathIsValidNumber(c.stop_points) && c.stop_points>=0 && MathIsValidNumber(c.stop_points*c.point) &&
          MathIsValidNumber(c.point) && c.point>0 &&
          MathIsValidNumber(c.min_stop_atr) && c.min_stop_atr>0 &&
          MathIsValidNumber(c.max_stop_atr) && c.max_stop_atr>=c.min_stop_atr &&
          MathIsValidNumber(c.target_rr) && c.target_rr>=1 && c.target_rr<=10 &&
          MathIsValidNumber(c.room_buffer_atr) && c.room_buffer_atr>=0 &&
          c.start_hour>=0 && c.start_hour<=23 && c.end_hour>=0 && c.end_hour<=23;
}
bool TSBarValid(const TSBar &b)
{
   return b.time>0 && MathIsValidNumber(b.open) && MathIsValidNumber(b.high) &&
          MathIsValidNumber(b.low) && MathIsValidNumber(b.close) && b.low>0 &&
          b.high>=b.low && b.open>=b.low && b.open<=b.high && b.close>=b.low && b.close<=b.high;
}
int TSWarmup(const TSConfig &c) { return (int)MathMax(3*c.slow,MathMax(c.atr_length,c.room_bars)); }
void TSReset(TSState &s) { ZeroMemory(s); s.last_signal=-1000000; s.last_gap=-1000000; }
bool TSHourAllowed(const TSConfig &c,const long close_time)
{
   int hour=(int)((close_time/3600)%24);
   if(c.start_hour==c.end_hour) return true;
   return c.start_hour<c.end_hour ? (hour>=c.start_hour && hour<c.end_hour) :
                                   (hour>=c.start_hour || hour<c.end_hour);
}
// One closed bar may sweep and reclaim: its close necessarily follows its extremum.
// This detects a price pattern, not actual stop orders or order-book liquidity.
bool TSProcess(TSState &s,const TSConfig &c,const TSBar &bars[],const int i,TSSignal &out)
{
   ZeroMemory(out);
   TSBar b=bars[i];
   if(!TSBarValid(b) || (s.count>0 && b.time<=s.previous_time)) { TSReset(s); return false; }
   if(s.count>0 && b.time-s.previous_time!=300) s.last_gap=i;
   if(s.count>=TSWarmup(c) && i>=c.room_bars && i-s.last_gap>=c.lookback &&
      i-s.last_signal>c.cooldown && s.atr>0 && TSHourAllowed(c,b.time+300))
   {
      double floor=bars[i-1].low,ceiling=bars[i-1].high;
      double room_low=floor,room_high=ceiling;
      for(int j=i-c.room_bars;j<i;j++)
      {
         room_low=MathMin(room_low,bars[j].low); room_high=MathMax(room_high,bars[j].high);
         if(j>=i-c.lookback) { floor=MathMin(floor,bars[j].low); ceiling=MathMax(ceiling,bars[j].high); }
      }
      double range=b.high-b.low;
      if(range>0)
      {
         for(int direction=-1;direction<=1;direction+=2)
         {
            bool buy=direction==1;
            if((buy && c.side==TS_SELL_ONLY) || (!buy && c.side==TS_BUY_ONLY)) continue;
            if(buy ? !(s.fast>s.slow && s.slow>s.previous_slow && b.close>s.slow) :
                     !(s.fast<s.slow && s.slow<s.previous_slow && b.close<s.slow)) continue;
            if(direction*(b.close-s.fast)>c.max_extension_atr*s.atr) continue;
            double level=buy ? floor : ceiling;
            double penetration=buy ? level-b.low : b.high-level;
            double location=buy ? (b.close-b.low)/range : (b.high-b.close)/range;
            if(penetration<=0 || penetration<c.min_sweep_atr*s.atr || penetration>c.max_sweep_atr*s.atr ||
               direction*(b.close-level)<=0 || direction*(b.close-b.open)<=0 ||
               direction*(b.close-b.open)/range<c.min_body || location<c.min_close_location) continue;
            double buffer=MathMax(c.point,c.stop_atr*s.atr+c.stop_points*c.point);
            double stop=(buy ? b.low : b.high)-direction*buffer;
            double risk=direction*(b.close-stop);
            double target=b.close+direction*c.target_rr*risk;
            double obstacle=(buy ? room_high : room_low)-direction*c.room_buffer_atr*s.atr;
            if(!MathIsValidNumber(target) || stop<=0 || target<=0 ||
               risk<c.min_stop_atr*s.atr || risk>c.max_stop_atr*s.atr || direction*(obstacle-target)<0) continue;
            out.direction=direction; out.time=b.time; out.price=b.close; out.trigger=level;
            out.stop=stop; out.target=target; out.obstacle=obstacle; out.atr=s.atr; out.high=b.high; out.low=b.low;
            s.last_signal=i;
            break;
         }
      }
   }
   double tr=b.high-b.low;
   if(s.count==0) { s.fast=b.close; s.slow=b.close; s.previous_slow=b.close; s.atr=tr; }
   else
   {
      tr=MathMax(tr,MathMax(MathAbs(b.high-s.previous_close),MathAbs(b.low-s.previous_close)));
      s.fast+=2.0/(c.fast+1)*(b.close-s.fast);
      s.previous_slow=s.slow; s.slow+=2.0/(c.slow+1)*(b.close-s.slow);
      s.atr+=(tr-s.atr)/c.atr_length;
   }
   s.count++; s.previous_close=b.close; s.previous_time=b.time;
   return true;
}
bool TSReplay(const TSConfig &c,const TSBar &bars[],const int n,const long horizon,TSSignal &entries[])
{
   ArrayResize(entries,0);
   if(!TSValid(c) || n<1 || ArrayResize(entries,n)!=n) return false;
   TSState state; TSReset(state); int count=0;
   for(int i=0;i<n && bars[i].time+300<=horizon;i++)
   {
      if(IsStopped()) return false;
      TSSignal signal;
      if(TSProcess(state,c,bars,i,signal) && signal.direction!=0) entries[count++]=signal;
   }
   return ArrayResize(entries,count)==count;
}
#endif
