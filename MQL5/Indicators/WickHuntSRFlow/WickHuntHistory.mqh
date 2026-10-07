#ifndef WICK_HUNT_HISTORY
#define WICK_HUNT_HISTORY
#include "WickHuntContextCore.mqh"

// Indicator-only adapters. The Telegram EA keeps using the original tick core.
enum ENUM_WH_OBSERVATION
{
   WH_TICK_LIVE=0,       // Original live tick observation; no historical arrows
   WH_LOWER_TF_CLOSE=1   // Closed lower-TF reclaim and historical replay
};

enum ENUM_WH_CLOSED_RETEST
{
   WH_RETEST_HIGH_LOW=0, // Closed waiting candle's High/Low reaches SR
   WH_RETEST_CLOSE=1     // Waiting candle's Close reaches SR
};

// Called BEFORE this candle advances the break/hold state. Thus a confirming
// candle's own wick cannot be reused as a retest. Eligibility belongs to the
// waiting candle's interval, including the eighth candle that CLOSES exactly
// at the deadline. Its event is reported only after the entire candle closes.
bool WHRTakeRetest(WSState &s,const WSContext &c,const MSBar &bar,const int seconds,
                   const int direction,const ENUM_WH_CLOSED_RETEST mode,
                   const double tolerance,WSSignal &out)
{
   WSBreak b=direction==1 ? s.buy_break : s.sell_break;
   if(!MSBarValid(bar) || seconds<=0 || !c.valid || !b.valid || b.retest_bars<=0 ||
      b.hold_close_time==0 || bar.time<b.hold_close_time ||
      bar.time+seconds>b.retest_deadline || bar.time<c.time ||
      bar.time+seconds>c.end_time) return false;
   double price=bar.close;
   if(mode==WH_RETEST_HIGH_LOW)
   {
      double threshold=b.price+direction*tolerance;
      if(direction==1 ? bar.low>threshold : bar.high<threshold) return false;
      // Indicative touch price: the threshold, or the open when it has already
      // gapped beyond it. This is not a reconstructed tick or execution fill.
      price=direction==1 ? MathMin(bar.open,threshold) : MathMax(bar.open,threshold);
   }
   // Reuse the original candidate checks at the waiting interval's start.
   // All OHLC is known at confirmation; do not pass a fabricated live tick.
   if(!WSTakeSignal(s,c,bar.time,price,direction,out,tolerance)) return false;
   out.time=bar.time+seconds;
   return true;
}
#endif
