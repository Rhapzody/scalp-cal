#ifndef ENGULF_REVERSAL_CORE
#define ENGULF_REVERSAL_CORE

struct WHBar
{
   double open,high,low,close;
};

enum ENUM_WH_ENGULF_MODE
{
   WH_ENGULF_BODY=0, // Close beyond previous body
   WH_ENGULF_WICK=1  // Close beyond previous high/low
};

struct WHLeg
{
   int direction; // +1 up, -1 down, 0 unknown
   int count;     // Closed candles including the leg's first candle
};

bool WHValid(const WHBar &bar)
{
   return MathIsValidNumber(bar.open) && MathIsValidNumber(bar.high) &&
          MathIsValidNumber(bar.low) && MathIsValidNumber(bar.close) &&
          bar.low<=MathMin(bar.open,bar.close) &&
          bar.high>=MathMax(bar.open,bar.close);
}

int WHEngulfDirection(const WHBar &bar,const WHBar &previous,const ENUM_WH_ENGULF_MODE mode)
{
   if(!WHValid(bar) || !WHValid(previous)) return 0;
   if(mode!=WH_ENGULF_BODY && mode!=WH_ENGULF_WICK) return 0;
   double upper=mode==WH_ENGULF_BODY ? MathMax(previous.open,previous.close) : previous.high;
   double lower=mode==WH_ENGULF_BODY ? MathMin(previous.open,previous.close) : previous.low;
   return bar.close>upper ? 1 : (bar.close<lower ? -1 : 0);
}

// No full-body enclosure / candle-color filter. With hunt disabled a real
// opposite wick is not required either. Multi-candle sweeps are checked by caller.
int WHSignal(const WHBar &bar,const WHBar &previous,const bool hunt=true,
             const ENUM_WH_ENGULF_MODE mode=WH_ENGULF_BODY)
{
   int signal=WHEngulfDirection(bar,previous,mode);
   if(!hunt) return signal;
   if(signal==1 && bar.low<previous.low && bar.low<MathMin(bar.open,bar.close)) return 1;
   if(signal==-1 && bar.high>previous.high && bar.high>MathMax(bar.open,bar.close)) return -1;
   return 0;
}

void WHSeedLeg(const WHBar &bar,WHLeg &state)
{
   state.direction=0; state.count=0;
   if(!WHValid(bar)) return;
   state.direction=bar.close>bar.open ? 1 : (bar.close<bar.open ? -1 : 0);
   state.count=state.direction==0 ? 0 : 1;
}

// Movement always uses BODY engulf, independently of signal mode and hunt.
// Inside candles, opposite colors and equality do not end an established leg.
// An opposing body engulf starts the new leg at 1 (never part of the old leg).
void WHStepLeg(const WHBar &bar,const WHBar &previous,const WHLeg &before,
               const int minimum,WHLeg &after)
{
   after.direction=0; after.count=0;
   if(!WHValid(bar)) return;
   if(!WHValid(previous)) { WHSeedLeg(bar,after); return; }
   int direction=WHEngulfDirection(bar,previous,WH_ENGULF_BODY);
   if(before.direction==0 || before.count<1)
   {
      WHSeedLeg(bar,after);
      if(direction!=0) { after.direction=direction; after.count=1; }
      return;
   }
   if(direction==-before.direction)
   {
      after.direction=direction; after.count=1;
      return;
   }
   after.direction=before.direction;
   // Saturate at the required threshold, avoiding overflow on long histories.
   after.count=before.count<minimum ? before.count+1 : before.count;
}

bool WHPriorMoveAllows(const int signal,const WHLeg &prior,const int minimum)
{
   return signal!=0 && minimum>=1 && prior.direction==-signal && prior.count>=minimum;
}

bool WHPreviewWindow(const long now,const long opened,const long closes)
{
   return opened>0 && closes>opened && now>=opened && now>=closes-5;
   // At/after the scheduled boundary keep evaluating the latest OHLC until
   // MT5 supplies the next candle; only that rollover confirms the old bar.
}
#endif
