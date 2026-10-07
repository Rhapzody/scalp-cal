#ifndef INSTANT_ENGULF_CORE
#define INSTANT_ENGULF_CORE

struct EngulfBar
{
   double open,high,low,close;
};

bool EngulfBarValid(const EngulfBar &bar)
{
   return MathIsValidNumber(bar.open) && MathIsValidNumber(bar.high) &&
          MathIsValidNumber(bar.low) && MathIsValidNumber(bar.close) &&
          bar.low>0 && bar.low<=bar.open && bar.low<=bar.close &&
          bar.high>=bar.open && bar.high>=bar.close && bar.high>=bar.low;
}

// Closed candle endpoint beyond the older candle's BODY edge.
// No requirement to envelop its open or entire body, no previous-color filter.
bool EngulfSignal(const bool buy,const EngulfBar &latest,const EngulfBar &older)
{
   if(!EngulfBarValid(latest) || !EngulfBarValid(older)) return false;
   return buy ? latest.close>MathMax(older.open,older.close) : latest.close<MathMin(older.open,older.close);
}

double EngulfStop(const bool buy,const EngulfBar &latest,const EngulfBar &older)
{
   return buy ? MathMin(latest.low,older.low) : MathMax(latest.high,older.high);
}

double EngulfBufferedStop(const bool buy,const EngulfBar &latest,const EngulfBar &older,
                          const double buffer_points,const double point,const double tick_size,const int digits)
{
   if(buffer_points<0 || point<=0 || tick_size<=0 || !MathIsValidNumber(buffer_points)) return 0;
   double raw=EngulfStop(buy,latest,older)+(buy ? -1.0 : 1.0)*buffer_points*point;
   // Broker tick grid: snap OUTWARD so rounding never reduces the requested buffer.
   double ticks=raw/tick_size;
   return NormalizeDouble((buy ? MathFloor(ticks+1e-8) : MathCeil(ticks-1e-8))*tick_size,digits);
}

// OrderSend acceptance != confirmed execution. Unknown cases remain latched.
enum ENUM_ENGULF_RESULT { ENGULF_FILLED=0,ENGULF_PARTIAL=1,ENGULF_UNCERTAIN=2,ENGULF_REJECTED=3 };
ENUM_ENGULF_RESULT EngulfResult(const bool sent,const uint retcode,const double fill_price,
                               const double fill_volume,const double requested_volume,const double step)
{
   if(sent && retcode==TRADE_RETCODE_DONE_PARTIAL) return ENGULF_PARTIAL;
   if(sent && retcode==TRADE_RETCODE_DONE && fill_price>0 && fill_volume>0)
      return MathAbs(fill_volume-requested_volume)<step*1e-6 ? ENGULF_FILLED : ENGULF_PARTIAL;
   // Explicit server rejections can be retried by another deliberate click.
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_REJECT:
      case TRADE_RETCODE_CANCEL:
      case TRADE_RETCODE_INVALID:
      case TRADE_RETCODE_INVALID_VOLUME:
      case TRADE_RETCODE_INVALID_PRICE:
      case TRADE_RETCODE_INVALID_STOPS:
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_NO_MONEY:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_INVALID_EXPIRATION:
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_SERVER_DISABLES_AT:
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
      case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_ONLY_REAL:
      case TRADE_RETCODE_LIMIT_ORDERS:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case TRADE_RETCODE_INVALID_ORDER:
      case TRADE_RETCODE_LIMIT_POSITIONS:
      case TRADE_RETCODE_LONG_ONLY:
      case TRADE_RETCODE_SHORT_ONLY:
      case TRADE_RETCODE_CLOSE_ONLY:
      case TRADE_RETCODE_HEDGE_PROHIBITED:
         return ENGULF_REJECTED;
   }
   return ENGULF_UNCERTAIN;
}
#endif
