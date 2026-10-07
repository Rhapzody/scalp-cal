#ifndef PA_REVERSAL_CORE
#define PA_REVERSAL_CORE

struct PABar
{
   double open,high,low,close;
};

struct PAState
{
   int direction; // +1 up, -1 down, 0 not yet established
   int count;     // Closed candles in this leg, including its seed candle
};

bool PAValid(const PABar &bar)
{
   return MathIsValidNumber(bar.open) && MathIsValidNumber(bar.high) &&
          MathIsValidNumber(bar.low) && MathIsValidNumber(bar.close) &&
          bar.low<=bar.open && bar.low<=bar.close &&
          bar.high>=bar.open && bar.high>=bar.close;
}

void PASeed(const PABar &bar,PAState &state)
{
   state.direction=0;
   state.count=0;
   if(!PAValid(bar)) return;
   state.direction=bar.close>bar.open ? 1 : (bar.close<bar.open ? -1 : 0);
   state.count=state.direction==0 ? 0 : 1;
}

// Feed CLOSED candles in chronological order. A close strictly outside the
// immediately preceding wick reverses the leg, irrespective of candle color.
// The reversal candle starts the new leg; it is NOT counted in the old leg.
int PAStep(const PABar &bar,const PABar &previous,const PAState &before,
           const int minimum,PAState &after)
{
   after.direction=0;
   after.count=0;
   if(!PAValid(bar)) return 0;
   if(!PAValid(previous)) { PASeed(bar,after); return 0; }
   int breakout=bar.close>previous.high ? 1 : (bar.close<previous.low ? -1 : 0);
   if(before.direction==0 || before.count<1)
   {
      PASeed(bar,after);
      // A gap / doji can establish direction by its close beyond a wick.
      if(breakout!=0) { after.direction=breakout; after.count=1; }
      return 0;
   }
   if(breakout==-before.direction)
   {
      after.direction=breakout;
      after.count=1;
      return minimum>=1 && before.count>=minimum ? breakout : 0;
   }
   after.direction=before.direction;
   // Saturate safely: only the minimum threshold matters for future signals.
   after.count=before.count<minimum ? before.count+1 : before.count;
   return 0;
}
#endif
