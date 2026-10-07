#ifndef WICK_HUNT_SR_CORE
#define WICK_HUNT_SR_CORE
#include "SwingCore.mqh"

#define WS_MAX_LEVELS 1000

struct WSBreak
{
   bool valid;
   long bar_time,pivot_time,confirm_time;
   double price,close;
   int type; // +1 swing high, -1 swing low; independent of trade direction
   long close_time;
   int retest_bars;
   int confirm_bars,confirmed_bars;
   double close_buffer;
   long hold_close_time,retest_deadline;
   double hold_close;
};

struct WSState
{
   MSEngine macd;
   MSEvent levels[WS_MAX_LEVELS];
   int level_count;
   long setup_time;
   WSBreak buy_break,sell_break;
   bool buy_reclaimed,sell_reclaimed,buy_sent,sell_sent;
   long buy_reclaim_time,sell_reclaim_time;
   int buy_pattern,sell_pattern;
   double buy_context_sr,sell_context_sr;
   long buy_anchor_time,sell_anchor_time,buy_trend_pivot,sell_trend_pivot;
};

struct WSContext
{
   long time,end_time;
   double open,prior_low,prior_high;
   bool valid;
};

struct WSSignal
{
   long time,setup_time,break_time,pivot_time;
   double price,sr;
   int direction,sr_type;
   int pattern; // 0 legacy, 1 breakout, 2 pullback, 3 both
   double context_sr;
   long anchor_time,trend_pivot;
   long hold_time;
   int retest_bar;
};

void WSClearBreak(WSBreak &b)
{
   b.valid=false; b.bar_time=0; b.pivot_time=0; b.confirm_time=0;
   b.price=0; b.close=0; b.type=0; b.close_time=0;
   b.retest_bars=0; b.hold_close_time=0; b.retest_deadline=0; b.hold_close=0;
   b.confirm_bars=0; b.confirmed_bars=0; b.close_buffer=0;
}

void WSBeginSetup(WSState &s,const long time)
{
   s.setup_time=time;
   WSClearBreak(s.buy_break); WSClearBreak(s.sell_break);
   s.buy_reclaimed=false; s.sell_reclaimed=false;
   s.buy_reclaim_time=0; s.sell_reclaim_time=0;
   s.buy_sent=false; s.sell_sent=false;
   s.buy_pattern=0; s.sell_pattern=0; s.buy_context_sr=0; s.sell_context_sr=0;
   s.buy_anchor_time=0; s.sell_anchor_time=0; s.buy_trend_pivot=0; s.sell_trend_pivot=0;
}

void WSReset(WSState &s,const long setup_time)
{
   MSReset(s.macd); s.level_count=0;
   WSBeginSetup(s,setup_time);
}

bool WSCross(const int direction,const double previous,const double close,const double level)
{
   if(!MathIsValidNumber(previous) || !MathIsValidNumber(close) || !MathIsValidNumber(level)) return false;
   if(direction==1) return previous<=level && close>level;
   if(direction==-1) return previous>=level && close<level;
   return false;
}

// Both high and low levels are eligible for either trade direction. Only levels
// confirmed BEFORE this candle opened are eligible: no backdated swing lookup.
void WSFindBreak(WSState &s,const MSBar &bar,const double previous_close,
                 const ENUM_MS_SR_ANCHOR anchor,const int direction,const int seconds,WSBreak &out,
                 const int retest_bars=0,const int confirm_bars=1,const double close_buffer=0)
{
   for(int j=s.level_count-1;j>=0;j--)
   {
      MSEvent level=s.levels[j];
      if(level.confirm_time>=bar.time) continue;
      double price=MSSRPrice(level,anchor);
      if(!WSCross(direction,previous_close,bar.close,price)) continue;
      if(direction==1 ? bar.close<=price+close_buffer : bar.close>=price-close_buffer) continue;
      out.valid=true; out.bar_time=bar.time; out.pivot_time=level.pivot_time;
      out.confirm_time=level.confirm_time; out.price=price; out.close=bar.close; out.type=level.type;
      out.close_time=bar.time+seconds;
      out.retest_bars=retest_bars; out.hold_close_time=0; out.retest_deadline=0; out.hold_close=0;
      out.confirm_bars=confirm_bars; out.confirmed_bars=0; out.close_buffer=close_buffer;
      return; // Most recently confirmed swing wins when a close crosses several levels.
   }
}

// Freeze the first crossed SR until the required consecutive successors close. A failed
// hold discards that candidate; only a later fresh cross can start another one.
// Zero retains the pre-1.03 direct-break core path for regression comparisons.
void WSAdvanceBreak(WSState &s,const MSBar &bar,const double previous_close,
                    const ENUM_MS_SR_ANCHOR anchor,const int direction,const int seconds,
                    const int retest_bars,WSBreak &b,const int confirm_bars=1,const double close_buffer=0)
{
   if(b.valid && b.retest_bars>0)
   {
      if(b.hold_close_time==0)
      {
         long expected=b.close_time+(long)b.confirmed_bars*seconds;
         if(bar.time<expected) return;
         if(bar.time!=expected || (direction==1 ? bar.close<=b.price+b.close_buffer : bar.close>=b.price-b.close_buffer))
         { WSClearBreak(b); return; }
         b.confirmed_bars++;
         if(b.confirmed_bars<b.confirm_bars) return;
         b.hold_close_time=bar.time+seconds; b.hold_close=bar.close;
         b.retest_deadline=b.hold_close_time+(long)b.retest_bars*seconds;
         return;
      }
      if(bar.time<b.retest_deadline) return;
      WSClearBreak(b);
   }
   WSFindBreak(s,bar,previous_close,anchor,direction,seconds,b,retest_bars,confirm_bars,close_buffer);
}

// Chronological CLOSED lower-TF candles only. Break memory belongs exclusively
// to the supplied current higher-TF window and starts only AFTER live reclaim.
// A candle already open at reclaim may qualify if its close is strictly later.
// Levels themselves span windows and must continue updating before reclaim.
bool WSProcessClosed(WSState &s,const MSConfig &config,const MSBar &bar,const int index,
                     const int seconds,const WSContext &context,const int sr_count,
                     const ENUM_MS_SR_ANCHOR anchor,const int retest_bars=0,
                     const int confirm_bars=1,const double close_buffer=0)
{
   if(seconds<=0 || sr_count<1 || sr_count>WS_MAX_LEVELS ||
      config.swing_mode!=MS_HISTOGRAM_COLOR || anchor<MS_SR_WICK || anchor>MS_SR_BODY ||
      retest_bars<0 || retest_bars>1000 || confirm_bars<1 || confirm_bars>1000 ||
      !MathIsValidNumber(close_buffer) || close_buffer<0) return false;
   if(s.setup_time!=context.time) WSBeginSetup(s,context.time);
   if(!MSBarValid(bar))
   {
      MSReset(s.macd); s.level_count=0;
      WSClearBreak(s.buy_break); WSClearBreak(s.sell_break);
      return false;
   }
   bool previous_valid=s.macd.count>0;
   double previous_close=s.macd.previous_close;
   bool in_window=context.valid && bar.time>=context.time && bar.time+seconds<=context.end_time;
   if(previous_valid && in_window)
   {
      if(s.buy_reclaimed && !s.buy_sent && bar.time+seconds>s.buy_reclaim_time)
         WSAdvanceBreak(s,bar,previous_close,anchor,1,seconds,retest_bars,s.buy_break,confirm_bars,close_buffer);
      if(s.sell_reclaimed && !s.sell_sent && bar.time+seconds>s.sell_reclaim_time)
         WSAdvanceBreak(s,bar,previous_close,anchor,-1,seconds,retest_bars,s.sell_break,confirm_bars,close_buffer);
   }
   MSEvent event;
   if(!MSProcess(config,bar,index,s.macd,event)) return false;
   if(event.type!=0)
   {
      if(s.level_count>=sr_count)
      {
         for(int j=1;j<s.level_count;j++) s.levels[j-1]=s.levels[j];
         s.level_count--;
      }
      s.levels[s.level_count++]=event;
   }
   return true;
}

// Latest higher-TF OHLC is used only for LIVE observation. Never feed a closed
// higher-TF candle's final high/low to earlier lower-TF candles in a backtest.
void WSObserve(WSState &s,const WSContext &c,const long now,const double high,
               const double low,const double price,const double min_hunt=0,
               const bool enable_buy=true,const bool enable_sell=true)
{
   if(s.setup_time!=c.time) WSBeginSetup(s,c.time);
   if(!c.valid || now<c.time || now>=c.end_time || !MathIsValidNumber(price) ||
      !MathIsValidNumber(high) || !MathIsValidNumber(low) || low>price || high<price ||
      !MathIsValidNumber(min_hunt) || min_hunt<0) return;
   if(enable_buy && !s.buy_reclaimed && low<c.prior_low-min_hunt && low<c.open && price>=c.open)
   {
      s.buy_reclaimed=true; s.buy_reclaim_time=now; WSClearBreak(s.buy_break);
   }
   if(enable_sell && !s.sell_reclaimed && high>c.prior_high+min_hunt && high>c.open && price<=c.open)
   {
      s.sell_reclaimed=true; s.sell_reclaim_time=now; WSClearBreak(s.sell_break);
   }
}

bool WSTakeSignal(WSState &s,const WSContext &c,const long now,const double price,
                  const int direction,WSSignal &out,const double retest_tolerance=0)
{
   if(!c.valid || s.setup_time!=c.time || now<c.time || now>=c.end_time ||
      !MathIsValidNumber(price) || (direction!=1 && direction!=-1) ||
      !MathIsValidNumber(retest_tolerance) || retest_tolerance<0) return false;
   WSBreak b=direction==1 ? s.buy_break : s.sell_break;
   bool reclaimed=direction==1 ? s.buy_reclaimed : s.sell_reclaimed;
   long reclaim_time=direction==1 ? s.buy_reclaim_time : s.sell_reclaim_time;
   bool sent=direction==1 ? s.buy_sent : s.sell_sent;
   if(!reclaimed || sent || !b.valid || b.bar_time<c.time || reclaim_time<c.time ||
      b.close_time<=reclaim_time || b.close_time>now || b.close_time>c.end_time) return false;
   // Observe the quote itself, never a cumulative candle low/high that could
   // have touched SR before all confirming candles closed. First waiting bar
   // opens at hold_close_time; the bar after the configured window is expired.
   if(b.retest_bars>0 && (b.hold_close_time==0 || now<b.hold_close_time ||
      now>=b.retest_deadline || (direction==1 ? price>b.price+retest_tolerance : price<b.price-retest_tolerance))) return false;
   out.time=now; out.setup_time=c.time; out.break_time=b.bar_time;
   out.pivot_time=b.pivot_time; out.price=price; out.sr=b.price;
   out.direction=direction; out.sr_type=b.type;
   out.pattern=direction==1 ? s.buy_pattern : s.sell_pattern;
   out.context_sr=direction==1 ? s.buy_context_sr : s.sell_context_sr;
   out.anchor_time=direction==1 ? s.buy_anchor_time : s.sell_anchor_time;
   out.trend_pivot=direction==1 ? s.buy_trend_pivot : s.sell_trend_pivot;
   out.hold_time=b.hold_close_time;
   out.retest_bar=b.retest_bars>0 ? 1+(int)((now-b.hold_close_time)/
                        ((b.retest_deadline-b.hold_close_time)/b.retest_bars)) : 0;
   if(direction==1) s.buy_sent=true; else s.sell_sent=true;
   return true;
}
#endif
