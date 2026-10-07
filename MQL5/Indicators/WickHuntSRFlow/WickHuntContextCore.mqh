#ifndef WICK_HUNT_CONTEXT_CORE
#define WICK_HUNT_CONTEXT_CORE
#include "WickHuntSRCore.mqh"
#include "FVGCore.mqh"
#include "EngulfImbalanceCore.mqh"

enum ENUM_WS_SCENARIO
{
   WS_LEGACY=0, WS_BREAKOUT=1, WS_PULLBACK=2, WS_BOTH=3
};

struct WHCTrend
{
   int direction;
   bool ready;
   long break_time,origin_time,pivot_time,confirm_time;
   double sr,origin_price,pivot_price;
};

struct WHCState
{
   MSEngine macd;
   MSEvent levels[WS_MAX_LEVELS];
   int level_count;
   WHCTrend trend;
};

void WHCClearTrend(WHCTrend &t)
{
   t.direction=0; t.ready=false; t.break_time=0; t.origin_time=0;
   t.pivot_time=0; t.confirm_time=0; t.sr=0; t.origin_price=0; t.pivot_price=0;
}

void WHCReset(WHCState &s)
{
   MSReset(s.macd); s.level_count=0; WHCClearTrend(s.trend);
}

// H1 trend is structural: a known low -> close above a known high ->
// confirmed high at/after that breakout. Bearish uses the mirrored sequence.
// Check the old levels before adding the swing confirmed by this candle.
bool WHCStartTrend(WHCState &s,const MSBar &bar,const double previous,
                   const ENUM_MS_SR_ANCHOR anchor,const int direction)
{
   int origin=-1;
   for(int j=s.level_count-1;j>=0;j--)
      if(s.levels[j].type==-direction && s.levels[j].confirm_time<bar.time)
      { origin=j; break; }
   if(origin<0) return false;
   for(int j=s.level_count-1;j>=0;j--)
   {
      MSEvent e=s.levels[j];
      if(e.type!=direction || e.confirm_time>=bar.time ||
         !WSCross(direction,previous,bar.close,MSSRPrice(e,anchor))) continue;
      WHCClearTrend(s.trend);
      s.trend.direction=direction; s.trend.break_time=bar.time;
      s.trend.sr=MSSRPrice(e,anchor);
      s.trend.origin_time=s.levels[origin].pivot_time;
      s.trend.origin_price=s.levels[origin].price;
      return true;
   }
   return false;
}

bool WHCProcessClosed(WHCState &s,const MSConfig &config,const MSBar &bar,
                      const int index,const int sr_count,const ENUM_MS_SR_ANCHOR anchor)
{
   if(sr_count<1 || sr_count>WS_MAX_LEVELS || config.swing_mode!=MS_HISTOGRAM_COLOR ||
      anchor<MS_SR_WICK || anchor>MS_SR_BODY) return false;
   if(!MSBarValid(bar)) { WHCReset(s); return false; }
   if(s.macd.count>0)
   {
      double previous=s.macd.previous_close;
      if(!WHCStartTrend(s,bar,previous,anchor,1)) WHCStartTrend(s,bar,previous,anchor,-1);
   }
   MSEvent e;
   if(!MSProcess(config,bar,index,s.macd,e)) { WHCReset(s); return false; }
   if(e.type!=0)
   {
      if(e.type==s.trend.direction && e.pivot_time>=s.trend.break_time)
      {
         s.trend.ready=true; s.trend.pivot_time=e.pivot_time;
         s.trend.pivot_price=e.price; s.trend.confirm_time=e.confirm_time;
      }
      if(s.level_count>=sr_count)
      {
         for(int j=1;j<s.level_count;j++) s.levels[j-1]=s.levels[j];
         s.level_count--;
      }
      s.levels[s.level_count++]=e;
   }
   return true;
}

bool WHCPriorExtremes(const MSBar &bars[],const int count,const int hunt_bars,
                      double &low,double &high)
{
   if(hunt_bars<1 || count<hunt_bars) return false;
   low=bars[count-1].low; high=bars[count-1].high;
   for(int i=count-hunt_bars;i<count;i++)
   {
      if(!MSBarValid(bars[i])) return false;
      low=MathMin(low,bars[i].low); high=MathMax(high,bars[i].high);
   }
   return true;
}

// Inclusive H/L touch; no higher-TF close through SR is required. For bullish
// breakout bases use a known Swing H resistance, bearish a Swing L support.
// The five-bar window is a search window, not a required five-candle base.
// A level must exist before the touching candle opens; never backdate it.
bool WHCFindTouch(const WHCState &s,const MSBar &bars[],const int count,
                  const int lookback,const ENUM_MS_SR_ANCHOR anchor,double &sr,const int direction=0)
{
   if(lookback<1 || count<lookback || direction<-1 || direction>1) return false;
   for(int i=count-1;i>=count-lookback;i--)
   {
      if(!MSBarValid(bars[i])) return false;
      for(int j=s.level_count-1;j>=0;j--)
      {
         MSEvent e=s.levels[j]; double price=MSSRPrice(e,anchor);
         if(direction!=0 && e.type!=direction) continue;
         if(e.confirm_time<bars[i].time && bars[i].low<=price && bars[i].high>=price)
         { sr=price; return true; }
      }
   }
   return false;
}

// Keep the original flow's strength rule at the default; expose its threshold
// here without changing the copied shared flow core.
bool WHCLeadWickAllows(const WHBar &bar,const int direction,const double max_percent)
{
   if(!MathIsValidNumber(max_percent) || max_percent<0 || max_percent>100) return false;
   if(max_percent==30) return EILeadWickAllows(bar,direction);
   if(!WHValid(bar) || (direction!=1 && direction!=-1)) return false;
   double range=bar.high-bar.low;
   if(!(range>0)) return false;
   if(direction==1) return bar.close>bar.open && bar.high-bar.close<=range*(max_percent/100.0);
   return bar.close<bar.open && bar.close-bar.low<=range*(max_percent/100.0);
}

// Scan every intervening candle. The FIRST high-low collision must itself be
// the third FVG candle, same direction, with a limited leading wick and tip in
// its body. No engulf/opposite-color/10%-wick entry filters are imported.
bool WHCFindAnchor(const MSBar &bars[],const int count,const double tip,
                   const int direction,const int search_bars,const double min_points,
                   const double point,const bool require_middle,long &anchor_time,
                   const double max_lead_percent=30)
{
   anchor_time=0;
   if(count<3 || search_bars<0 || !MathIsValidNumber(tip) ||
      (direction!=1 && direction!=-1) || !MathIsValidNumber(max_lead_percent) ||
      max_lead_percent<0 || max_lead_percent>100) return false;
   int oldest=search_bars==0 ? 0 : (int)MathMax(0,count-search_bars);
   for(int i=count-1;i>=oldest;i--)
   {
      MSBar b=bars[i];
      if(!MSBarValid(b)) return false;
      if(b.low>tip || b.high<tip) continue;
      if(i<2) return false;
      FVGBar first={bars[i-2].open,bars[i-2].high,bars[i-2].low,bars[i-2].close};
      FVGBar middle={bars[i-1].open,bars[i-1].high,bars[i-1].low,bars[i-1].close};
      FVGBar third={b.open,b.high,b.low,b.close};
      FVGZone zone;
      WHBar confirmation={b.open,b.high,b.low,b.close};
      if(!FVGDetect(first,middle,third,min_points,point,require_middle,zone) ||
         zone.direction!=direction || !EIBodyHolds(confirmation,tip) ||
         !WHCLeadWickAllows(confirmation,direction,max_lead_percent)) return false;
      anchor_time=b.time;
      return true;
   }
   return false;
}

// Freeze the scenario that actually qualified at live reclaim. Subsequent
// lower-TF replay cannot qualify an earlier failed hunt retroactively.
void WSObservePatterns(WSState &s,const WSContext &c,const WHCState &higher,
                        const MSBar &closed[],const int count,const long now,
                        const double high,const double low,const double price,
                        const ENUM_WS_SCENARIO scenario,const int hunt_bars,
                        const int pullback_bars,const int touch_bars,
                        const ENUM_MS_SR_ANCHOR anchor,const int search_bars,
                        const double min_points,const double point,const bool require_middle,
                        const double min_hunt=0,const double max_lead_percent=30,
                        const bool enable_buy=true,const bool enable_sell=true)
{
   if(scenario==WS_LEGACY) { WSObserve(s,c,now,high,low,price,min_hunt,enable_buy,enable_sell); return; }
   if(s.setup_time!=c.time) WSBeginSetup(s,c.time);
   if(!c.valid || now<c.time || now>=c.end_time || scenario<WS_BREAKOUT || scenario>WS_BOTH ||
      !MathIsValidNumber(price) || !MathIsValidNumber(high) || !MathIsValidNumber(low) ||
      low>price || high<price || !MathIsValidNumber(min_hunt) || min_hunt<0) return;
   for(int direction=1;direction>=-1;direction-=2)
   {
      if(direction==1 ? !enable_buy : !enable_sell) continue;
      if(direction==1 ? s.buy_reclaimed : s.sell_reclaimed) continue;
      if(direction==1 ? !(low<c.open && price>=c.open) : !(high>c.open && price<=c.open)) continue;
      int pattern=0; double sr=0,prior_low=0,prior_high=0; long fvg_time=0,pivot_time=0;
      bool base=WHCPriorExtremes(closed,count,hunt_bars,prior_low,prior_high) &&
                (direction==1 ? low<prior_low-min_hunt : high>prior_high+min_hunt);
      if((scenario==WS_BREAKOUT || scenario==WS_BOTH) && base &&
         WHCFindTouch(higher,closed,count,touch_bars,anchor,sr,direction) &&
         WHCFindAnchor(closed,count,direction==1 ? low : high,direction,search_bars,
                       min_points,point,require_middle,fvg_time,max_lead_percent)) pattern=1;
      if((scenario==WS_PULLBACK || scenario==WS_BOTH) && higher.trend.ready &&
         higher.trend.direction==direction && higher.trend.confirm_time<c.time &&
         WHCPriorExtremes(closed,count,pullback_bars,prior_low,prior_high) &&
         (direction==1 ? low<prior_low-min_hunt && low<higher.trend.pivot_price
                       : high>prior_high+min_hunt && high>higher.trend.pivot_price))
      {
         pattern+=2; pivot_time=higher.trend.pivot_time;
         if(pattern==2) sr=higher.trend.sr;
      }
      if(pattern==0) continue;
      if(direction==1)
      {
         s.buy_reclaimed=true; s.buy_reclaim_time=now; WSClearBreak(s.buy_break);
         s.buy_pattern=pattern; s.buy_context_sr=sr; s.buy_anchor_time=fvg_time; s.buy_trend_pivot=pivot_time;
      }
      else
      {
         s.sell_reclaimed=true; s.sell_reclaim_time=now; WSClearBreak(s.sell_break);
         s.sell_pattern=pattern; s.sell_context_sr=sr; s.sell_anchor_time=fvg_time; s.sell_trend_pivot=pivot_time;
      }
   }
}
#endif
