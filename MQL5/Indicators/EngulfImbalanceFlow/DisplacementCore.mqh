#ifndef FVG_DISPLACEMENT_CORE
#define FVG_DISPLACEMENT_CORE
#include "FVGCore.mqh"

enum ENUM_FVG_DETECTION { FVG_ONLY=0, DISPLACEMENT_ONLY=1, FVG_AND_DISPLACEMENT=2 };
enum ENUM_DP_METHOD { DP_SINGLE_OR_LEG=0, DP_SINGLE_ONLY=1, DP_LEG_ONLY=2 };
enum ENUM_DP_ZONE { DP_BASE_WICK=0, DP_BASE_BODY=1, DP_IMPULSE_BODY=2 };

struct DPConfig
{
   ENUM_DP_METHOD method;
   ENUM_DP_ZONE zone_mode;
   int atr_length,relative_bars,min_leg_bars,max_leg_bars,breakout_bars,base_search_bars;
   double min_body_atr,min_body_ratio,max_tail_ratio,min_relative_body;
   double min_leg_atr,min_efficiency,min_direction_ratio,max_leg_tail_ratio;
   bool require_breakout,reject_time_gaps;
   double breakout_atr;
};

bool DPConfigValid(const DPConfig &c)
{
   return c.method>=DP_SINGLE_OR_LEG && c.method<=DP_LEG_ONLY &&
          c.zone_mode>=DP_BASE_WICK && c.zone_mode<=DP_IMPULSE_BODY &&
          c.atr_length>=1 && c.atr_length<=200 && c.relative_bars>=1 && c.relative_bars<=200 &&
          c.min_leg_bars>=2 && c.max_leg_bars>=c.min_leg_bars && c.max_leg_bars<=10 &&
          c.breakout_bars>=1 && c.breakout_bars<=200 && c.base_search_bars>=1 && c.base_search_bars<=20 &&
          MathIsValidNumber(c.min_body_atr) && c.min_body_atr>0 &&
          MathIsValidNumber(c.min_body_ratio) && c.min_body_ratio>0 && c.min_body_ratio<=1 &&
          MathIsValidNumber(c.max_tail_ratio) && c.max_tail_ratio>=0 && c.max_tail_ratio<=1 &&
          MathIsValidNumber(c.min_relative_body) && c.min_relative_body>=0 &&
          MathIsValidNumber(c.min_leg_atr) && c.min_leg_atr>0 &&
          MathIsValidNumber(c.min_efficiency) && c.min_efficiency>0 && c.min_efficiency<=1 &&
          MathIsValidNumber(c.min_direction_ratio) && c.min_direction_ratio>0 && c.min_direction_ratio<=1 &&
          MathIsValidNumber(c.max_leg_tail_ratio) && c.max_leg_tail_ratio>=0 && c.max_leg_tail_ratio<=1 &&
          MathIsValidNumber(c.breakout_atr) && c.breakout_atr>=0;
}

// SMA of true range strictly BEFORE the impulse, requiring a preceding close.
// Invalid bars and (optionally) discontinuous timestamps reject the whole reference window.
bool DPHistory(const FVGBar &bars[],const long &times[],const int first,const int last,
               const int count,const long seconds,const bool reject_gaps)
{
   if(first<0 || last<first || last>=count || seconds<=0) return false;
   for(int j=first;j<=last;j++)
      if(!FVGValidBar(bars[j]) || (j>first &&
         (times[j]<=times[j-1] || (reject_gaps && times[j]-times[j-1]!=seconds)))) return false;
   return true;
}

double DPATR(const FVGBar &bars[],const int start,const int length)
{
   if(start-length-1<0) return 0;
   double sum=0;
   for(int j=start-length;j<start;j++)
   {
      double tr=bars[j].high-bars[j].low;
      double h=MathAbs(bars[j].high-bars[j-1].close),l=MathAbs(bars[j].low-bars[j-1].close);
      if(h>tr) tr=h;
      if(l>tr) tr=l;
      sum+=tr;
   }
   return sum/length;
}

// Single-candle strength or a complete 2..10 candle impulse ending at index.
// No future bar is read; ATR/breakout references end before the impulse begins.
bool DPTry(const DPConfig &c,const FVGBar &bars[],const long &times[],const int count,
           const int first,const int index,const int length,const long seconds,
           FVGZone &zone,int &source)
{
   int start=index-length+1;
   int history=start-c.atr_length-1;
   if(c.require_breakout && start-c.breakout_bars<history) history=start-c.breakout_bars;
   if(length==1 && c.min_relative_body>0 && start-c.relative_bars<history) history=start-c.relative_bars;
   // Detection/source must be in lookback; reference history may precede it.
   if(start<first || start<=0 || !DPHistory(bars,times,history,index,count,seconds,c.reject_time_gaps)) return false;
   double atr=DPATR(bars,start,c.atr_length);
   if(!MathIsValidNumber(atr) || atr<=0) return false;
   FVGBar last=bars[index];
   double move=length==1 ? last.close-last.open : last.close-bars[start-1].close;
   int direction=move>0 ? 1 : -1;
   double range=last.high-last.low;
   if(move==0 || range<=0 || direction*(last.close-last.open)<=0) return false;
   double tail=direction==1 ? last.high-last.close : last.close-last.low;
   if(length==1)
   {
      double body=MathAbs(last.close-last.open);
      if(body<atr*c.min_body_atr || body/range<c.min_body_ratio || tail/range>c.max_tail_ratio) return false;
      if(c.min_relative_body>0)
      {
         double bodies[];
         if(ArrayResize(bodies,c.relative_bars)!=c.relative_bars) return false;
         for(int j=0;j<c.relative_bars;j++) bodies[j]=MathAbs(bars[start-1-j].close-bars[start-1-j].open);
         ArraySort(bodies);
         int mid=c.relative_bars/2;
         double median=c.relative_bars%2==0 ? (bodies[mid-1]+bodies[mid])/2 : bodies[mid];
         if(median<=0 || body/median<c.min_relative_body) return false;
      }
   }
   else
   {
      double travel=0; int aligned=0;
      for(int j=start;j<=index;j++)
      {
         travel+=MathAbs(bars[j].close-bars[j-1].close);
         if(direction*(bars[j].close-bars[j].open)>0) aligned++;
      }
      if(MathAbs(move)<atr*c.min_leg_atr || travel<=0 || MathAbs(move)/travel<c.min_efficiency ||
         (double)aligned/length<c.min_direction_ratio || tail/range>c.max_leg_tail_ratio) return false;
   }
   if(c.require_breakout)
   {
      double level=direction==1 ? bars[start-1].high : bars[start-1].low;
      for(int j=start-c.breakout_bars;j<start;j++)
      {
         if(direction==1 && bars[j].high>level) level=bars[j].high;
         if(direction==-1 && bars[j].low<level) level=bars[j].low;
      }
      if(direction*(last.close-level)<=c.breakout_atr*atr) return false;
   }
   source=start-1;
   if(c.zone_mode==DP_IMPULSE_BODY)
   {
      source=start;
      zone.lower=bars[start].open; zone.upper=last.close;
      if(zone.lower>zone.upper) { double swap=zone.lower; zone.lower=zone.upper; zone.upper=swap; }
   }
   else
   {
      // Last opposing/doji candle BEFORE the impulse; fallback to the preceding candle.
      for(int j=start-1;j>=first && j>=start-c.base_search_bars;j--)
      {
         if(!FVGValidBar(bars[j]) || (j<start-1 && c.reject_time_gaps && times[j+1]-times[j]!=seconds)) break;
         if(direction*(bars[j].close-bars[j].open)<=0) { source=j; break; }
      }
      if(source<first) return false;
      FVGBar base=bars[source];
      zone.lower=base.low; zone.upper=base.high;
      if(c.zone_mode==DP_BASE_BODY)
      { zone.lower=base.open<base.close ? base.open : base.close; zone.upper=base.open>base.close ? base.open : base.close; }
   }
   if(zone.upper<=zone.lower || (direction==1 ? last.close<zone.upper : last.close>zone.lower)) return false;
   // Base zones need a completed departure; impulse-body zones end at the close by design.
   if(c.zone_mode!=DP_IMPULSE_BODY && (direction==1 ? last.close<=zone.upper : last.close>=zone.lower)) return false;
   zone.direction=direction;
   return true;
}

bool DPDetect(const DPConfig &c,const FVGBar &bars[],const long &times[],const int count,
              const int first,const int index,const long seconds,FVGZone &zone,int &source,int &kind)
{
   zone.direction=0; zone.lower=0; zone.upper=0; source=-1; kind=0;
   if(!DPConfigValid(c) || index<0 || index>=count) return false;
   if(c.method!=DP_LEG_ONLY && DPTry(c,bars,times,count,first,index,1,seconds,zone,source)) { kind=1; return true; }
   if(c.method!=DP_SINGLE_ONLY)
      for(int length=c.min_leg_bars;length<=c.max_leg_bars;length++)
         if(DPTry(c,bars,times,count,first,index,length,seconds,zone,source)) { kind=2; return true; }
   zone.direction=0; zone.lower=0; zone.upper=0; source=-1;
   return false;
}
#endif
