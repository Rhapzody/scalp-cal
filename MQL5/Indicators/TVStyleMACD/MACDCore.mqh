#ifndef TVSTYLE_MACD_CORE
#define TVSTYLE_MACD_CORE

enum ENUM_TV_MA { TV_EMA=0, TV_SMA=1 };
enum ENUM_TV_SOURCE
{
   TV_CLOSE=0,TV_OPEN=1,TV_HIGH=2,TV_LOW=3,TV_HL2=4,TV_HLC3=5,TV_OHLC4=6,TV_HLCC4=7
};

double TVPrice(const ENUM_TV_SOURCE source,const double o,const double h,const double l,const double c)
{
   switch(source)
   {
      case TV_OPEN: return o;
      case TV_HIGH: return h;
      case TV_LOW: return l;
      case TV_HL2: return (h+l)/2.0;
      case TV_HLC3: return (h+l+c)/3.0;
      case TV_OHLC4: return (o+h+l+c)/4.0;
      case TV_HLCC4: return (h+l+2*c)/4.0;
      default: return c;
   }
}

// Chronological, first-valid-source EMA seed; SMA waits for a full window.
// Caller always supplies the previous CLOSED bar, never the last tick state.
double TVMovingAverage(const ENUM_TV_MA type,const int length,const int valid_count,
                       const double source,const double previous,const double previous_sum,
                       const double outgoing,double &sum)
{
   sum=0;
   if(length<1 || valid_count<1 || source==EMPTY_VALUE || !MathIsValidNumber(source)) return EMPTY_VALUE;
   if(type==TV_EMA)
   {
      if(valid_count==1 || previous==EMPTY_VALUE) return source;
      double alpha=2.0/(length+1.0);
      return alpha*source+(1.0-alpha)*previous;
   }
   sum=previous_sum+source-(valid_count>length ? outgoing : 0);
   return valid_count>=length ? sum/length : EMPTY_VALUE;
}

// Four TradingView-style colors. Equal-height bars use the non-rising branch.
// 0 positive rising, 1 positive non-rising, 2 negative rising, 3 negative non-rising.
int TVHistogramColor(const double current,const double previous,const bool four_colors)
{
   if(!four_colors) return current>=0 ? 0 : 3;
   bool rising=previous!=EMPTY_VALUE && previous<current;
   return current>=0 ? (rising ? 0 : 1) : (rising ? 2 : 3);
}

int TVHistogramCross(const double previous,const double current)
{
   if(previous==EMPTY_VALUE || current==EMPTY_VALUE) return 0;
   if(previous<=0 && current>0) return 1;
   if(previous>=0 && current<0) return -1;
   return 0;
}

// MTF selector: only data known by chart-bar close is used historically.
// The latest live bar can optionally use the currently developing source bar.
int TVMappedIndex(const int confirmed,const int developing,const bool live,
                  const bool wait_close,const bool completed_in_chart_bar)
{
   if(wait_close) return completed_in_chart_bar ? confirmed : -1;
   return live && developing>=0 ? developing : confirmed;
}
#endif
