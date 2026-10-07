#ifndef OPENING_RANGE_PLAN
#define OPENING_RANGE_PLAN
#include "OpeningCore.mqh"
#include "../ScalpCalculator/ScalpCore.mqh"
struct ORCandidate { ORSignal signal; double pattern_low,pattern_high; };
struct ORTarget { double range_high,range_low; };
bool ORBuildContext(const ORConfig &c,const ORBar &bars[],const int n,const long horizon,
                    ORCandidate &candidate,ORTarget &targets[],string &reason)
{
   ZeroMemory(candidate); ArrayResize(targets,0); ORSignal entries[];
   if(!ORReplay(c,bars,n,horizon,entries)){reason="History unavailable";return false;}
   int count=ArraySize(entries); if(count==0||entries[count-1].time!=horizon-300){reason="No new M5 retest signal";return false;}
   candidate.signal=entries[count-1]; candidate.pattern_low=candidate.signal.low; candidate.pattern_high=candidate.signal.high;
   if(ArrayResize(targets,1)!=1){reason="Target allocation failed";return false;}
   targets[0].range_high=candidate.signal.range_high;targets[0].range_low=candidate.signal.range_low;reason="Ready";return true;
}
double ORStop(const ORCandidate &c,const double tick,const int digits)
{
   if(tick<=0)return 0;bool buy=c.signal.direction==1;double raw=buy?MathMin(c.signal.stop,c.pattern_low-tick):MathMax(c.signal.stop,c.pattern_high+tick);
   double result=ScalpSnap(raw,tick,digits);if(buy&&result>raw+tick*1e-7)result=ScalpSnap(result-tick,tick,digits);if(!buy&&result<raw-tick*1e-7)result=ScalpSnap(result+tick,tick,digits);return result;
}
bool ORMinimumRR(const bool buy,const double entry,const double sl,const double tp,const double minimum)
{return MathIsValidNumber(minimum)&&minimum>=1&&ScalpGeometry(buy,entry,sl,tp)&&ScalpRR(entry,sl,tp)+1e-12>=minimum;}
#endif
