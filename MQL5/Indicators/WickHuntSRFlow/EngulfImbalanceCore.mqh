#ifndef ENGULF_IMBALANCE_CORE
#define ENGULF_IMBALANCE_CORE
#include "EngulfFlowCore.mqh"

// Imbalance flags on the CONFIRMATION candle: bit 1 bullish, bit 2 bearish.
// FVG uses its third candle. Displacement uses the last impulse candle.
#define EI_BULL 1
#define EI_BEAR 2

struct EIResult
{
   int direction; // +1 buy, -1 sell
   int pattern;   // 1 = A, 2 = B, 3 = both
   int anchorA;   // Nearest pattern-A imbalance index, or -1
   int anchorB;   // Nearest pattern-B imbalance index, or -1
   double wickTip;
   int engulfIndex; // Original engulf candle; may precede the entry candle by 1..2 bars
   bool delayed;    // True when entry waited for the post-engulf pullback
   double entryLevel; // Previous candle wick used by the delayed-entry rule
};

int EIDirectionBit(const int direction)
{
   return direction==1 ? EI_BULL : (direction==-1 ? EI_BEAR : 0);
}

// Inclusive: a wick tip exactly on a doji Open/Close counts as touching the body.
bool EIBodyHolds(const WHBar &bar,const double price)
{
   if(!WHValid(bar) || !MathIsValidNumber(price)) return false;
   double lower=MathMin(bar.open,bar.close);
   double upper=MathMax(bar.open,bar.close);
   return price>=lower && price<=upper;
}

double EIWickTip(const WHBar &bar,const int direction)
{
   return direction==1 ? bar.low : bar.high;
}

// Confirmation must close in the imbalance direction, and the wick on that
// side may not exceed 30% of the full high-low range. A doji has no direction.
bool EILeadWickAllows(const WHBar &bar,const int direction)
{
   if(!WHValid(bar) || (direction!=1 && direction!=-1)) return false;
   double range=bar.high-bar.low;
   if(!(range>0)) return false;
   if(direction==1)
      return bar.close>bar.open && bar.high-bar.close<=range*0.30;
   return bar.close<bar.open && bar.close-bar.low<=range*0.30;
}

// The engulfed candle must be red for a buy and green for a sell. A doji has no opposite color.
bool EIOppositeColor(const WHBar &engulfed,const int direction)
{
   if(!WHValid(engulfed)) return false;
   if(direction==1) return engulfed.close<engulfed.open;
   if(direction==-1) return engulfed.close>engulfed.open;
   return false;
}

// The engulf candle's wick in the trade direction may not exceed 10% of its own body.
// Buy uses the wick above the body. Sell uses the wick below the body.
bool EIEngulfThrustWickAllows(const WHBar &bar,const int direction)
{
   if(!WHValid(bar) || (direction!=1 && direction!=-1)) return false;
   double body=MathAbs(bar.close-bar.open);
   double wick=direction==1 ? bar.high-MathMax(bar.open,bar.close)
                            : MathMin(bar.open,bar.close)-bar.low;
   return wick<=body*0.10;
}

// A signal can be pattern A, pattern B, or both.
// Pattern A: confirmation, then exactly one opposite-color candle, then a BODY engulf.
// Wick hunt is not required for A.
// Pattern B: a BODY engulf that also wick-hunts the previous candle. One or more
// candles may sit between the confirmation and that engulf. The first candle
// whose high-low contains the wick tip must be a confirmation whose body holds it.
// maxGap limits only pattern B. 0 means every flagged bar back to searchFrom.
bool EIFind(const int index,const WHBar &bars[],const int &imbalance[],const int count,
            const int searchFrom,const int maxGap,EIResult &out)
{
   out.direction=0; out.pattern=0; out.anchorA=-1; out.anchorB=-1; out.wickTip=0;
   out.engulfIndex=index; out.delayed=false; out.entryLevel=0;
   if(index<2 || index>=count || searchFrom<0 || maxGap<0) return false;
   int direction=WHEngulfDirection(bars[index],bars[index-1],WH_ENGULF_BODY);
   int bit=EIDirectionBit(direction);
   if(bit==0 || !EIEngulfThrustWickAllows(bars[index],direction)) return false;
   int candidate=index-2;
   if(candidate>=searchFrom && EIOppositeColor(bars[index-1],direction) &&
      (imbalance[candidate]&bit)!=0 && EILeadWickAllows(bars[candidate],direction))
      out.anchorA=candidate;
   if(WHSignal(bars[index],bars[index-1],true,WH_ENGULF_BODY)==direction)
   {
      double tip=EIWickTip(bars[index],direction);
      int oldest=searchFrom;
      if(maxGap>0)
      {
         int limited=index-1-maxGap;
         if(limited>oldest) oldest=limited;
      }
      for(int probe=index-1;probe>=oldest;probe--)
      {
         if(!WHValid(bars[probe])) break;
         if(bars[probe].low>tip || bars[probe].high<tip) continue;
         if(probe<=index-2 && (imbalance[probe]&bit)!=0 &&
            EIBodyHolds(bars[probe],tip) && EILeadWickAllows(bars[probe],direction))
         {
            out.anchorB=probe;
            out.wickTip=tip;
         }
         break;
      }
   }
   if(out.anchorA<0 && out.anchorB<0) return false;
   out.direction=direction;
   out.pattern=(out.anchorA>=0 ? 1 : 0)+(out.anchorB>=0 ? 2 : 0);
   return true;
}

// A close that extends beyond the engulfed candle's wick by more than 30% of
// the engulf candle body is too extended for an immediate entry.
bool EIRequiresPullback(const WHBar &engulf,const WHBar &engulfed,const int direction,
                        double &level)
{
   level=0;
   if(!WHValid(engulf) || !WHValid(engulfed) || (direction!=1 && direction!=-1)) return false;
   double body=MathAbs(engulf.close-engulf.open);
   if(!(body>0)) return false;
   level=direction==1 ? engulfed.high : engulfed.low;
   double extension=direction==1 ? engulf.close-level : level-engulf.close;
   return extension>body*0.30;
}

// Reaching to within the recorded spread of the engulfed wick is enough.
bool EIPullbackReached(const WHBar &bar,const int direction,const double level,
                       const double spreadPrice)
{
   if(!WHValid(bar) || (direction!=1 && direction!=-1) ||
      !MathIsValidNumber(level) || !MathIsValidNumber(spreadPrice) || spreadPrice<0)
      return false;
   return direction==1 ? bar.low<=level+spreadPrice : bar.high>=level-spreadPrice;
}

// Returns the entry event for this closed candle. Non-extended engulf setups
// enter immediately. Extended setups enter on the first qualifying pullback in
// either of the next two closed candles; after that they expire.
bool EIFindEntry(const int index,const WHBar &bars[],const int &imbalance[],
                 const double &spreadPrice[],const int count,const int searchFrom,
                 const int maxGap,EIResult &out)
{
   out.direction=0; out.pattern=0; out.anchorA=-1; out.anchorB=-1; out.wickTip=0;
   out.engulfIndex=index; out.delayed=false; out.entryLevel=0;
   if(index<2 || index>=count) return false;

   // Oldest pending setup wins if two delayed entries reach their level on the same candle.
   for(int wait=2;wait>=1;wait--)
   {
      int engulfIndex=index-wait;
      if(engulfIndex<2) continue;
      EIResult candidate;
      if(!EIFind(engulfIndex,bars,imbalance,count,searchFrom,maxGap,candidate)) continue;
      double level=0;
      if(!EIRequiresPullback(bars[engulfIndex],bars[engulfIndex-1],candidate.direction,level))
         continue;
      bool enteredEarlier=false;
      for(int probe=engulfIndex+1;probe<index;probe++)
      {
         if(EIPullbackReached(bars[probe],candidate.direction,level,spreadPrice[probe]))
         {
            enteredEarlier=true;
            break;
         }
      }
      if(enteredEarlier ||
         !EIPullbackReached(bars[index],candidate.direction,level,spreadPrice[index]))
         continue;
      out=candidate;
      out.engulfIndex=engulfIndex;
      out.delayed=true;
      out.entryLevel=level;
      return true;
   }

   EIResult immediate;
   if(!EIFind(index,bars,imbalance,count,searchFrom,maxGap,immediate)) return false;
   double level=0;
   if(EIRequiresPullback(bars[index],bars[index-1],immediate.direction,level)) return false;
   out=immediate;
   return true;
}
#endif
