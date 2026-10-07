#ifndef FVG_FINDER_CORE
#define FVG_FINDER_CORE

enum ENUM_FVG_FILL
{
   FVG_FILL_FULL=0,  // Wick reaches the far edge of the zone
   FVG_FILL_TOUCH=1  // Wick touches the near edge of the zone
};

struct FVGBar
{
   double open,high,low,close;
};

struct FVGZone
{
   int direction; // +1 bullish, -1 bearish
   double lower,upper;
};

bool FVGValidBar(const FVGBar &bar)
{
   return MathIsValidNumber(bar.open) && MathIsValidNumber(bar.high) &&
          MathIsValidNumber(bar.low) && MathIsValidNumber(bar.close) &&
          bar.low<=bar.open && bar.low<=bar.close &&
          bar.high>=bar.open && bar.high>=bar.close;
}

// Supply three CLOSED candles, oldest first. The middle candle must span
// the gap, so a pure session gap with no middle-candle coverage is excluded.
bool FVGDetect(const FVGBar &first,const FVGBar &middle,const FVGBar &third,
               const double min_points,const double point,const bool require_direction,
               FVGZone &zone)
{
   zone.direction=0; zone.lower=0; zone.upper=0;
   if(!FVGValidBar(first) || !FVGValidBar(middle) || !FVGValidBar(third) ||
      !MathIsValidNumber(min_points) || min_points<0 ||
      !MathIsValidNumber(point) || point<=0) return false;
   if(third.low>first.high)
   {
      zone.direction=1; zone.lower=first.high; zone.upper=third.low;
   }
   else if(third.high<first.low)
   {
      zone.direction=-1; zone.lower=third.high; zone.upper=first.low;
   }
   else return false;
   double minimum=min_points*point;
   bool valid=MathIsValidNumber(minimum) &&
              zone.upper-zone.lower+point*1e-6>=minimum &&
              middle.low<=zone.lower && middle.high>=zone.upper;
   if(require_direction)
      valid=valid && (zone.direction==1 ? middle.close>middle.open : middle.close<middle.open);
   if(!valid) { zone.direction=0; zone.lower=0; zone.upper=0; }
   return valid;
}

// Check only candles AFTER the third candle. Equality counts as a fill.
// A price gap past the threshold also retires the zone.
bool FVGIsFilled(const FVGZone &zone,const FVGBar &bar,const ENUM_FVG_FILL mode)
{
   if(!FVGValidBar(bar) || zone.lower>=zone.upper ||
      (mode!=FVG_FILL_FULL && mode!=FVG_FILL_TOUCH)) return false;
   if(zone.direction==1)
      return bar.low<=(mode==FVG_FILL_TOUCH ? zone.upper : zone.lower);
   if(zone.direction==-1)
      return bar.high>=(mode==FVG_FILL_TOUCH ? zone.lower : zone.upper);
   return false;
}
#endif
