#ifndef SCALP_CORE_MQH
#define SCALP_CORE_MQH

// Pure functions: also compiled directly by tests/core_tests.cpp.
double ScalpSnap(const double price,const double tick,const int digits)
{
   if(tick<=0 || !MathIsValidNumber(price)) return 0;
   return NormalizeDouble(MathRound(price/tick)*tick,digits);
}

double ScalpFloorVolume(const double raw,const double step)
{
   if(raw<=0 || step<=0 || !MathIsValidNumber(raw)) return 0;
   double result=NormalizeDouble(MathFloor(raw/step+1e-10)*step,8);
   // Do not let a tolerance promote a genuinely smaller volume.
   if(result>raw+1e-12) result=NormalizeDouble(result-step,8);
   return MathMax(0.0,result);
}

double ScalpLot(const double budget,const int orders,const double loss_per_lot,const double step)
{
   if(budget<=0 || orders<1 || loss_per_lot<=0) return 0;
   return ScalpFloorVolume(budget/orders/loss_per_lot,step);
}

bool ScalpGeometry(const bool buy,const double entry,const double sl,const double tp)
{
   if(!MathIsValidNumber(entry) || !MathIsValidNumber(sl) || !MathIsValidNumber(tp)) return false;
   if(entry<=0 || sl<=0 || tp<=0) return false;
   return buy ? (sl<entry && tp>entry) : (sl>entry && tp<entry);
}

double ScalpFollowTP(const bool buy,const double old_sl,const double new_sl,const double tp)
{
   // Called only for an SL edit, never for a live entry price change.
   double outward=buy ? old_sl-new_sl : new_sl-old_sl;
   if(outward<=0) return tp;
   return buy ? tp+outward : tp-outward;
}

double ScalpRR(const double entry,const double sl,const double tp)
{
   double risk=MathAbs(entry-sl);
   return risk>0 ? MathAbs(tp-entry)/risk : 0;
}

// 0 buy limit, 1 buy stop, 2 sell limit, 3 sell stop, -1 at market.
int ScalpPendingKind(const bool buy,const double entry,const double bid,const double ask)
{
   double current=buy ? ask : bid;
   if(entry==current) return -1;
   if(buy) return entry<current ? 0 : 1;
   return entry>current ? 2 : 3;
}

double ScalpBrokerPrice(const bool buy,const bool compensate,const double strategy,
                        const double spread,const double tick,const int digits)
{
   return ScalpSnap(strategy+(!buy && compensate ? spread : 0),tick,digits);
}

// Distances already oriented in the valid direction. Freeze is an optional
// conservative placement guard, not a claim that the broker requires it here.
bool ScalpDistanceOK(const double distance,const double stops,const double freeze,
                     const bool guard_freeze,const double tick)
{
   double eps=tick*1e-7;
   if(distance<=eps || distance+eps<stops) return false;
   if(guard_freeze && freeze>0 && distance<=freeze+eps) return false;
   return true;
}
#endif
