#ifndef WICK_HUNT_ANCHOR_CORE
#define WICK_HUNT_ANCHOR_CORE
#include "FVGCore.mqh"

enum ENUM_WHA_ANCHOR_RULE
{
   WHA_FVG_OR_STRONG=0,  // FVG confirmation OR short leading wick
   WHA_FVG_AND_STRONG=1, // FVG AND Strong
   WHA_FVG_ONLY=2,       // FVG only (no strong-wick filter)
   WHA_STRONG_ONLY=3     // Strong candle only (no FVG requirement)
};

enum ENUM_WHA_OBSERVATION
{
   WHA_LIVE_TICK=0,      // Signal immediately on live return to main-TF Open
   WHA_CLOSED_CANDLE=1,  // Main-TF Close confirms return; historical arrows
   WHA_LOWER_TF_CLOSE=2  // Check at every lower-TF Close; main-TF hunt/anchor
};

struct WHABar
{
   long time;
   double open,high,low,close;
};

struct WHAAnchor
{
   int index,pattern; // pattern bit 1 = FVG, bit 2 = strong
   int fvg_direction;
   long time;
   double head_wick_percent;
};

bool WHAValid(const WHABar &bar)
{
   FVGBar b={bar.open,bar.high,bar.low,bar.close};
   return bar.time>0 && FVGValidBar(b);
}

bool WHASwept(const WHABar &closed[],const int count,const int hunt_bars,
              const double open,const double high,const double low,
              const int direction,const double min_hunt)
{
   if(hunt_bars<1 || count<hunt_bars || (direction!=1 && direction!=-1) ||
      !MathIsValidNumber(open) || !MathIsValidNumber(high) || !MathIsValidNumber(low) ||
      !MathIsValidNumber(min_hunt) || min_hunt<0 || high<open || low>open) return false;
   double edge=direction==1 ? closed[count-1].low : closed[count-1].high;
   for(int i=count-hunt_bars;i<count;i++)
   {
      if(!WHAValid(closed[i])) return false;
      edge=direction==1 ? MathMin(edge,closed[i].low) : MathMax(edge,closed[i].high);
   }
   return direction==1 ? low<edge-min_hunt && low<open : high>edge+min_hunt && high>open;
}

// Only the single preceding MAIN-TF candle is filtered. This is its
// swept-side wick / its own BODY, independent of the anchor Strong threshold.
// A zero-body Doji passes only if it has a wick on the swept side.
bool WHASweptWickBodyAllowed(const WHABar &closed[],const int count,const int hunt_bars,
                            const int direction,const double min_percent)
{
   if(hunt_bars<1 || (direction!=1 && direction!=-1) ||
      !MathIsValidNumber(min_percent) || min_percent<0) return false;
   if(hunt_bars>1 || min_percent==0) return true;
   if(count<1 || count>ArraySize(closed)) return false;
   WHABar bar=closed[count-1];
   if(!WHAValid(bar)) return false;
   double body=MathAbs(bar.close-bar.open);
   double wick=direction==1 ? MathMin(bar.open,bar.close)-bar.low
                            : bar.high-MathMax(bar.open,bar.close);
   return body==0 ? wick>0 : wick/body>=min_percent/100.0;
}

// Use the wick ABOVE the body for a lower hunt, BELOW the body for an upper
// hunt. The denominator is the full HIGH-LOW range, never the candle body.
double WHAHeadWickPercent(const WHABar &bar,const int direction)
{
   if(!WHAValid(bar) || bar.high<=bar.low || (direction!=1 && direction!=-1)) return -1;
   double wick=direction==1 ? bar.high-MathMax(bar.open,bar.close)
                            : MathMin(bar.open,bar.close)-bar.low;
   return 100.0*wick/(bar.high-bar.low);
}

// Only read the supplied CLOSED prefix. The hunt candle and any later
// confirmation are outside count, even when the backing array contains them.
bool WHAConfirmedFVG(const WHABar &closed[],const int count,const int third_index,
                     const int direction,const double min_gap_points,const double point,
                     const bool require_middle,const bool require_fvg_direction,
                     int &fvg_direction)
{
   fvg_direction=0;
   if(third_index<2 || third_index>=count) return false;
   WHABar a=closed[third_index-2],b=closed[third_index-1],c=closed[third_index];
   if(!WHAValid(a) || !WHAValid(b) || !WHAValid(c)) return false;
   FVGBar first={a.open,a.high,a.low,a.close};
   FVGBar middle={b.open,b.high,b.low,b.close};
   FVGBar third={c.open,c.high,c.low,c.close};
   FVGZone zone;
   if(!FVGDetect(first,middle,third,min_gap_points,point,require_middle,zone) ||
      (require_fvg_direction && zone.direction!=direction)) return false;
   fvg_direction=zone.direction;
   return true;
}

// Scan backward from the nearest CLOSED candle. Once any High-Low touches
// the tip, stop even if that candle fails. Never look through an obstruction.
bool WHAFindAnchor(const WHABar &closed[],const int count,const double tip,
                   const int direction,const int search_bars,const ENUM_WHA_ANCHOR_RULE rule,
                   const double max_head_percent,const bool require_color,const bool require_body,
                   const double min_gap_points,const double point,const bool require_middle,
                   const bool require_fvg_direction,
                   WHAAnchor &out)
{
   out.index=-1; out.time=0; out.pattern=0; out.head_wick_percent=-1; out.fvg_direction=0;
   if(count<1 || search_bars<0 || !MathIsValidNumber(tip) ||
      (direction!=1 && direction!=-1) || rule<WHA_FVG_OR_STRONG || rule>WHA_STRONG_ONLY ||
      !MathIsValidNumber(max_head_percent) || max_head_percent<0 || max_head_percent>100) return false;
   int oldest=search_bars==0 ? 0 : (int)MathMax(0,count-search_bars);
   for(int i=count-1;i>=oldest;i--)
   {
      WHABar b=closed[i];
      if(!WHAValid(b)) return false;
      if(b.low>tip || b.high<tip) continue;
      out.index=i; out.time=b.time;
      out.head_wick_percent=WHAHeadWickPercent(b,direction);
      if(require_color && (direction==1 ? b.close<=b.open : b.close>=b.open)) return false;
      if(require_body && (tip<MathMin(b.open,b.close) || tip>MathMax(b.open,b.close))) return false;
      bool strong=out.head_wick_percent>=0 && out.head_wick_percent<max_head_percent;
      // Retain anchors on the third confirmation candle. Also accept the
      // middle creator candle if its third candle is already in this prefix.
      bool fvg=WHAConfirmedFVG(closed,count,i,direction,min_gap_points,point,
                               require_middle,require_fvg_direction,out.fvg_direction);
      if(!fvg)
         fvg=WHAConfirmedFVG(closed,count,i+1,direction,min_gap_points,point,
                             require_middle,require_fvg_direction,out.fvg_direction);
      out.pattern=(fvg ? 1 : 0)+(strong ? 2 : 0);
      // The head-wick threshold classifies Strong only; FVG stays independent.
      if(rule==WHA_FVG_ONLY) return fvg;
      if(rule==WHA_STRONG_ONLY) return strong;
      return rule==WHA_FVG_OR_STRONG ? fvg || strong : fvg && strong;
   }
   return false;
}
#endif
