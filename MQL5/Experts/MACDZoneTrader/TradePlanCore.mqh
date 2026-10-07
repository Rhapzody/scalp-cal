#ifndef MACD_ZONE_TRADE_PLAN
#define MACD_ZONE_TRADE_PLAN
#include "PullbackCore.mqh"
#include "ScalpCore.mqh"

struct EACandidate
{
   RPEntry signal;
   long pattern_start;
   double pattern_low,pattern_high;
};

struct EATarget
{
   int type;
   long pivot_time,known_time;
   double price;
};

// Use the exact indicator replay. Only a signal on the latest CLOSED M1 bar
// is eligible. Historical signals are never queued for execution.
bool EABuildContext(const RPConfig &config,const MSBar &one[],const int n1,
                    const MSBar &five[],const int n5,const long horizon,
                    EACandidate &candidate,EATarget &targets[],string &reason)
{
   ZeroMemory(candidate); ArrayResize(targets,0);
   RPState replay;
   RPEntry entries[];
   if(!RPReplay(replay,config,one,n1,five,n5,horizon,entries))
   { reason="Signal history unavailable"; return false; }
   int matches=0;
   for(int k=0;k<ArraySize(entries);k++)
      if(entries[k].time==horizon-60) { candidate.signal=entries[k]; matches++; }
   if(matches==0) { reason="No new M1 entry signal"; return false; }
   if(matches!=1) { reason="Conflicting entry signals"; return false; }
   MSEngine engine;
   MSReset(engine);
   MSEvent high,low,event;
   ZeroMemory(high); ZeroMemory(low);
   int signal_index=-1;
   for(int i=0;i<n1;i++)
   {
      if(one[i].time==candidate.signal.time) { signal_index=i; break; }
      if(one[i].time>candidate.signal.time) break;
      if(!MSProcess(config.macd,one[i],i,engine,event))
      { ZeroMemory(high); ZeroMemory(low); continue; }
      if(event.type==1) high=event;
      if(event.type==-1) low=event;
   }
   MSEvent trigger=candidate.signal.direction==1 ? high : low;
   if(signal_index<0 || trigger.type==0 || trigger.pivot_index<0 ||
      trigger.pivot_index>signal_index || trigger.price!=candidate.signal.trigger)
   { reason="M1 reversal pattern unavailable"; return false; }
   candidate.pattern_start=one[trigger.pivot_index].time;
   candidate.pattern_low=one[trigger.pivot_index].low;
   candidate.pattern_high=one[trigger.pivot_index].high;
   for(int i=trigger.pivot_index;i<=signal_index;i++)
   {
      if(!MSBarValid(one[i]) || (i>trigger.pivot_index && one[i].time-one[i-1].time!=60))
      { reason="Incomplete M1 reversal pattern"; return false; }
      candidate.pattern_low=MathMin(candidate.pattern_low,one[i].low);
      candidate.pattern_high=MathMax(candidate.pattern_high,one[i].high);
   }
   // All targets are confirmed at or before the entry decision, including a
   // M5 swing confirmed at the same close time as the M1 entry signal.
   MSReset(engine);
   if(ArrayResize(targets,n5)!=n5) { reason="Target allocation failed"; return false; }
   int count=0;
   for(int j=0;j<n5 && five[j].time+300<=horizon;j++)
   {
      if(five[j].time<one[0].time) continue;
      if(!MSProcess(config.macd,five[j],j,engine,event) || event.type==0) continue;
      targets[count].type=event.type; targets[count].price=event.price;
      targets[count].pivot_time=event.pivot_time; targets[count].known_time=five[j].time+300;
      count++;
   }
   ArrayResize(targets,count);
   reason="Signal ready";
   return true;
}

// Next swing means the nearest confirmed swing by PRICE in the profit
// direction. Never skip a nearby target just to manufacture a better R:R.
int EANextTarget(const bool buy,const double entry,const long known_by,const EATarget &targets[])
{
   int best=-1;
   for(int i=0;i<ArraySize(targets);i++)
   {
      EATarget t=targets[i];
      if(t.known_time>known_by || t.type!=(buy ? 1 : -1) ||
         !MathIsValidNumber(t.price) || t.price<=0 ||
         (buy ? t.price<=entry : t.price>=entry)) continue;
      if(best<0 || (buy ? t.price<targets[best].price : t.price>targets[best].price) ||
         (t.price==targets[best].price && t.pivot_time>targets[best].pivot_time)) best=i;
   }
   return best;
}

double EAPatternStop(const EACandidate &candidate,const double buffer_points,
                     const double point,const double tick,const int digits)
{
   if(!MathIsValidNumber(buffer_points) || buffer_points<0 || point<=0 || tick<=0) return 0;
   bool buy=candidate.signal.direction==1;
   double edge=buy ? candidate.pattern_low : candidate.pattern_high;
   // Always strictly outside the pattern by at least one tradable tick.
   double distance=MathMax(tick,buffer_points*point);
   double raw=buy ? edge-distance : edge+distance;
   double stop=ScalpSnap(raw,tick,digits);
   if(buy && stop>raw+tick*1e-7) stop=ScalpSnap(stop-tick,tick,digits);
   if(!buy && stop<raw-tick*1e-7) stop=ScalpSnap(stop+tick,tick,digits);
   return stop;
}

bool EAMinimumRR(const bool buy,const double entry,const double sl,const double tp,const double minimum)
{
   return MathIsValidNumber(minimum) && minimum>=1 && ScalpGeometry(buy,entry,sl,tp) &&
          ScalpRR(entry,sl,tp)+1e-12>=minimum;
}

double EATargetPrice(const bool buy,const double target,const double buffer_points,
                     const double point,const double tick,const int digits)
{
   if(!MathIsValidNumber(buffer_points) || buffer_points<0 || point<=0 || tick<=0 ||
      !MathIsValidNumber(buffer_points*point)) return 0;
   double raw=target+(buy ? -1 : 1)*buffer_points*point;
   double price=ScalpSnap(raw,tick,digits);
   // With a nonzero buffer, round toward entry rather than beyond the requested target.
   if(buffer_points>0 && buy && price>raw+tick*1e-7) price=ScalpSnap(price-tick,tick,digits);
   if(buffer_points>0 && !buy && price<raw-tick*1e-7) price=ScalpSnap(price+tick,tick,digits);
   return price;
}
#endif
