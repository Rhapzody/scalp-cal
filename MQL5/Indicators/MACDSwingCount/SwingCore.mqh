#ifndef MACD_SWING_COUNT_CORE
#define MACD_SWING_COUNT_CORE

enum ENUM_MS_THRESHOLD { MS_PRICE=0,MS_POINTS=1,MS_ATR=2 };
enum ENUM_MS_LABEL { MS_NUMBER=0,MS_STRUCTURE=1,MS_NUMBER_STRUCTURE=2 };
enum ENUM_MS_SR_ANCHOR
{
   MS_SR_WICK=0, // Swing candle wick
   MS_SR_BODY=1  // Swing candle body edge
};
enum ENUM_MS_SWING_MODE
{
   MS_MACD_CROSS=0,       // MACD / Signal cross (major swings)
   MS_HISTOGRAM_COLOR=1   // Histogram color (minor swings)
};
// Positive classifications are highs, negative classifications are lows.
enum ENUM_MS_CLASS
{
   MS_HH=1,MS_LH=2,MS_EH=3,MS_FIRST_HIGH=4,
   MS_HL=-1,MS_LL=-2,MS_EL=-3,MS_FIRST_LOW=-4
};

struct MSConfig
{
   int fast,slow,signal,warmup,atr_length;
   ENUM_MS_THRESHOLD threshold_mode;
   double threshold,point;
   ENUM_MS_SWING_MODE swing_mode;
};

struct MSBar
{
   long time;
   double open,high,low,close;
};

struct MSEvent
{
   int type; // +1 confirmed high, -1 confirmed low, 0 no event
   int classification;
   int pivot_index,confirm_index;
   long pivot_time,confirm_time; // Candle OPEN times, not wall-clock confirmation time
   double price;
   double body_price; // Edge of the BODY of this exact pivot candle, not the confirmation candle
};

struct MSEngine
{
   int count,direction,extreme_index;
   long extreme_time;
   double fast,slow,signal,histogram,atr,previous_close,threshold,extreme;
   bool has_high,has_low;
   double last_high,last_low;
   double previous_histogram;
   bool has_previous_histogram;
   double extreme_body;
};

void MSReset(MSEngine &s)
{
   s.count=0; s.direction=0; s.extreme_index=-1; s.extreme_time=0;
   s.fast=0; s.slow=0; s.signal=0; s.histogram=0; s.atr=0;
   s.previous_close=0; s.threshold=0; s.extreme=0;
   s.has_high=false; s.has_low=false; s.last_high=0; s.last_low=0;
   s.previous_histogram=0; s.has_previous_histogram=false;
   s.extreme_body=0;
}

bool MSConfigValid(const MSConfig &c)
{
   return c.fast>=1 && c.fast<=100000 && c.slow>=1 && c.slow<=100000 &&
          c.signal>=1 && c.signal<=100000 && c.warmup>=0 && c.warmup<=1000000 &&
          c.atr_length>=1 && c.atr_length<=100000 &&
          c.threshold_mode>=MS_PRICE && c.threshold_mode<=MS_ATR &&
          c.swing_mode>=MS_MACD_CROSS && c.swing_mode<=MS_HISTOGRAM_COLOR &&
          MathIsValidNumber(c.threshold) && c.threshold>=0 &&
          MathIsValidNumber(c.point) && c.point>0;
}

bool MSBarValid(const MSBar &b)
{
   return MathIsValidNumber(b.open) && MathIsValidNumber(b.high) &&
          MathIsValidNumber(b.low) && MathIsValidNumber(b.close) &&
          b.low<=b.open && b.low<=b.close && b.high>=b.open && b.high>=b.close;
}

double MSBodyEdge(const MSBar &b,const int type)
{
   return type==1 ? (b.open>b.close ? b.open : b.close) : (b.open<b.close ? b.open : b.close);
}

double MSSRPrice(const MSEvent &event,const ENUM_MS_SR_ANCHOR anchor)
{
   return anchor==MS_SR_BODY ? event.body_price : event.price;
}

// Same first-source seed / recurrence as TVStyleMACD's EMA mode.
double MSEma(const double value,const double previous,const int length)
{
   double alpha=2.0/(length+1.0);
   return alpha*value+(1.0-alpha)*previous;
}

int MSWarmup(const MSConfig &c)
{
   if(c.warmup>0) return c.warmup;
   int n=(c.fast>c.slow ? c.fast : c.slow)+c.signal-1;
   return c.swing_mode==MS_MACD_CROSS && c.threshold_mode==MS_ATR && c.atr_length>n ? c.atr_length : n;
}

int MSQualifiedSide(const double histogram,const double threshold)
{
   if(histogram>0 && histogram>=threshold) return 1;
   if(histogram<0 && -histogram>=threshold) return -1;
   return 0; // Zero never flips a leg, including with threshold=0.
}

// TVStyleMACD's four-color rule: rising = dark green / light red (up),
// non-rising = light green / dark red (down). A zero crossing therefore also
// points in its crossing direction. Repeated colors keep the current leg.
int MSHistogramColorSide(const double current,const double previous,const bool has_previous)
{
   if(!has_previous || !MathIsValidNumber(current) || !MathIsValidNumber(previous)) return 0;
   if(current==0 && previous==0) return 0; // No direction from a flat zero series.
   return current>previous ? 1 : -1; // Equal nonzero values use TV's non-rising color.
}

// Consume one eligible closed bar after MACD / warmup. Kept separate so the
// swing engine can be tested with exact histogram boundary cases.
void MSDetectSwing(const MSBar &b,const int index,MSEngine &s,MSEvent &event,
                   const ENUM_MS_SWING_MODE mode=MS_MACD_CROSS)
{
   event.type=0;
   int side=mode==MS_HISTOGRAM_COLOR ?
            MSHistogramColorSide(s.histogram,s.previous_histogram,s.has_previous_histogram) :
            MSQualifiedSide(s.histogram,s.threshold);
   if(s.direction==0)
   {
      if(side==0) return;
      s.direction=side; s.extreme=side==1 ? b.high : b.low;
      s.extreme_body=MSBodyEdge(b,side);
      s.extreme_index=index; s.extreme_time=b.time;
      return; // First eligible leg begins here; no invented initial swing.
   }
   if((s.direction==1 && b.high>=s.extreme) || (s.direction==-1 && b.low<=s.extreme))
   {
      s.extreme=s.direction==1 ? b.high : b.low; s.extreme_index=index; s.extreme_time=b.time;
      s.extreme_body=MSBodyEdge(b,s.direction);
   }
   if(side==0 || side==s.direction) return;

   event.type=s.direction;
   event.price=s.extreme; event.pivot_index=s.extreme_index; event.pivot_time=s.extreme_time;
   event.body_price=s.extreme_body;
   event.confirm_index=index; event.confirm_time=b.time;
   if(event.type==1)
   {
      event.classification=!s.has_high ? MS_FIRST_HIGH :
                           (event.price>s.last_high ? MS_HH : (event.price<s.last_high ? MS_LH : MS_EH));
      s.last_high=event.price; s.has_high=true;
   }
   else
   {
      event.classification=!s.has_low ? MS_FIRST_LOW :
                           (event.price>s.last_low ? MS_HL : (event.price<s.last_low ? MS_LL : MS_EL));
      s.last_low=event.price; s.has_low=true;
   }
   // The confirming candle belongs to both adjacent legs, as in the source concept.
   s.direction=side; s.extreme=side==1 ? b.high : b.low;
   s.extreme_body=MSBodyEdge(b,side);
   s.extreme_index=index; s.extreme_time=b.time;
   return;
}

// One call per CLOSED candle, in chronological order. No reading future bars.
// Return false only for invalid input; reset then require fresh warmup.
bool MSProcess(const MSConfig &c,const MSBar &b,const int index,MSEngine &s,MSEvent &event)
{
   event.type=0; event.classification=0; event.price=0;
   event.body_price=0;
   event.pivot_index=-1; event.confirm_index=-1; event.pivot_time=0; event.confirm_time=0;
   if(!MSConfigValid(c) || !MSBarValid(b)) { MSReset(s); return false; }
   s.has_previous_histogram=s.count>0;
   s.previous_histogram=s.histogram;
   if(s.count==0)
   {
      s.fast=b.close; s.slow=b.close; s.signal=0; s.atr=b.high-b.low;
   }
   else
   {
      s.fast=MSEma(b.close,s.fast,c.fast);
      s.slow=MSEma(b.close,s.slow,c.slow);
      s.signal=MSEma(s.fast-s.slow,s.signal,c.signal);
      double tr=MathMax(b.high-b.low,MathMax(MathAbs(b.high-s.previous_close),MathAbs(b.low-s.previous_close)));
      s.atr=s.atr+(tr-s.atr)/c.atr_length; // Wilder smoothing, first TR seed
   }
   s.previous_close=b.close;
   s.histogram=s.fast-s.slow-s.signal;
   // Color mode follows every color turn; the cross-distance filter is not applied.
   s.threshold=c.swing_mode==MS_HISTOGRAM_COLOR ? 0 :
               c.threshold*(c.threshold_mode==MS_POINTS ? c.point : (c.threshold_mode==MS_ATR ? s.atr : 1.0));
   if(!MathIsValidNumber(s.fast) || !MathIsValidNumber(s.slow) || !MathIsValidNumber(s.signal) ||
      !MathIsValidNumber(s.histogram) || !MathIsValidNumber(s.atr) || !MathIsValidNumber(s.threshold))
   { MSReset(s); return false; }
   if(s.count<1000000) s.count++;
   if(s.count<MSWarmup(c)) return true;
   MSDetectSwing(b,index,s,event,c.swing_mode);
   return true;
}
#endif
