#ifndef INSTANT_ENGULF_TIMING_MQH
#define INSTANT_ENGULF_TIMING_MQH
// Server quote time plus a monotonic timer, shared by countdown and selection.
datetime g_engulf_server_anchor=0;
ulong g_engulf_clock_anchor=0;
datetime EngulfServerNow()
{
   datetime server=TimeCurrent();
   if(server!=g_engulf_server_anchor || g_engulf_clock_anchor==0)
   { g_engulf_server_anchor=server; g_engulf_clock_anchor=GetTickCount64(); }
   return g_engulf_server_anchor+(datetime)((GetTickCount64()-g_engulf_clock_anchor)/1000);
}

datetime EngulfBarClose(const datetime opened)
{
   if(opened<=0) return 0;
   if(_Period==PERIOD_MN1)
   {
      MqlDateTime dt;
      if(!TimeToStruct(opened,dt)) return 0;
      dt.mon++; if(dt.mon>12) { dt.mon=1; dt.year++; }
      return StructToTime(dt);
   }
   int seconds=PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   return seconds>0 ? opened+seconds : 0;
}

struct EngulfPairContext
{
   int shift;
   datetime chart_bar,close_time;
};

string EngulfPairLabel(const EngulfPairContext &context)
{
   return context.shift==0 ? "LIVE [0/1]" : "CLOSED [1/2]";
}

bool EngulfSelectionCurrent(const EngulfPairContext &context,string &reason)
{
   datetime now=EngulfServerNow();
   if(iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0)!=context.chart_bar ||
      now<context.chart_bar || now>=context.close_time ||
      (context.close_time-now<=5 ? 0 : 1)!=context.shift)
   { reason="Candle selection expired; click again for the current PA"; return false; }
   return true;
}

EngulfBar EngulfRateBar(const MqlRates &rate)
{
   EngulfBar result;
   result.open=rate.open; result.high=rate.high; result.low=rate.low; result.close=rate.close;
   return result;
}

bool EngulfReadSelectedPair(MqlRates &latest,MqlRates &older,EngulfPairContext &context,string &reason)
{
   if(!SeriesInfoInteger(_Symbol,(ENUM_TIMEFRAMES)_Period,SERIES_SYNCHRONIZED))
   { reason="Waiting for synchronized candles"; return false; }
   context.chart_bar=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0);
   context.close_time=EngulfBarClose(context.chart_bar);
   datetime now=EngulfServerNow();
   if(context.chart_bar<=0 || now<context.chart_bar || context.close_time<=now)
   { reason="Waiting for current candle / new bar"; return false; }
   // Only the final 5,4,3,2,1 seconds use the still-forming candle.
   context.shift=context.close_time-now<=5 ? 0 : 1;
   MqlRates pair[];
   ArraySetAsSeries(pair,true);
   if(CopyRates(_Symbol,(ENUM_TIMEFRAMES)_Period,context.shift,2,pair)!=2)
   { reason="Waiting for two candles"; return false; }
   latest=pair[0]; older=pair[1];
   if(iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0)!=context.chart_bar ||
      iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,context.shift)!=latest.time ||
      older.time>=latest.time || (context.shift==1 && latest.time>=context.chart_bar))
   { reason="Candle history changed; click again"; return false; }
   EngulfBar a=EngulfRateBar(latest),b=EngulfRateBar(older);
   if(!EngulfBarValid(a) || !EngulfBarValid(b)) { reason="Invalid candle OHLC"; return false; }
   return true;
}

// Recheck the selected pair after broker preflight. Do not silently switch
// between a closed signal and a live signal, or send after its PA/SL changed.
bool EngulfPairStillValid(const bool buy,const EngulfPairContext &snapshot,const datetime signal_time,
                          const double sl,const double buffer,const ScalpSpec &spec,string &reason)
{
   MqlRates latest,older; EngulfPairContext current;
   if(!EngulfReadSelectedPair(latest,older,current,reason)) return false;
   if(current.chart_bar!=snapshot.chart_bar || current.shift!=snapshot.shift || latest.time!=signal_time)
   { reason="Candle selection changed; click again to check the new PA"; return false; }
   EngulfBar a=EngulfRateBar(latest),b=EngulfRateBar(older);
   if(!EngulfSignal(buy,a,b)) { reason="PA changed during preflight; order not sent"; return false; }
   if(MathAbs(EngulfBufferedStop(buy,a,b,buffer,spec.point,spec.tick_size,spec.digits)-sl)>spec.tick_size*1e-6)
   { reason="Candle SL changed during preflight; click again"; return false; }
   return true;
}
#endif
