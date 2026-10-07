#ifndef TREND_SWEEP_PLAN
#define TREND_SWEEP_PLAN
#include "SweepCore.mqh"
#include "ScalpCore.mqh"
struct EACandidate { TSSignal signal; double pattern_low,pattern_high; };
struct EATarget { double price; };
bool EABuildContext(const TSConfig &c,const TSBar &bars[],const int n,const long horizon,
                    EACandidate &candidate,EATarget &targets[],string &reason)
{
   ZeroMemory(candidate); ArrayResize(targets,0);
   TSSignal entries[];
   if(!TSReplay(c,bars,n,horizon,entries)) { reason="History unavailable"; return false; }
   int count=ArraySize(entries);
   if(count==0 || entries[count-1].time!=horizon-300) { reason="No new closed M5 signal"; return false; }
   candidate.signal=entries[count-1]; candidate.pattern_low=candidate.signal.low; candidate.pattern_high=candidate.signal.high;
   if(ArrayResize(targets,1)!=1) { reason="Allocation failed"; return false; }
   targets[0].price=candidate.signal.obstacle;
   reason="Ready"; return true;
}
bool EAMinimumRR(const bool buy,const double entry,const double sl,const double tp,const double minimum)
{
   return MathIsValidNumber(minimum) && minimum>=1 && ScalpGeometry(buy,entry,sl,tp) && ScalpRR(entry,sl,tp)+1e-12>=minimum;
}
// Snap away from entry so a tick-size mismatch never puts the SL inside the sweep.
double TSStop(const EACandidate &c,const double tick,const int digits)
{
   if(tick<=0) return 0;
   bool buy=c.signal.direction==1;
   double raw=buy ? MathMin(c.signal.stop,c.pattern_low-tick) : MathMax(c.signal.stop,c.pattern_high+tick);
   double stop=ScalpSnap(raw,tick,digits);
   if(buy && stop>raw+tick*1e-7) stop=ScalpSnap(stop-tick,tick,digits);
   if(!buy && stop<raw-tick*1e-7) stop=ScalpSnap(stop+tick,tick,digits);
   return stop;
}
#endif
