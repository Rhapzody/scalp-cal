#property copyright "EngulfFlow"
#property version "1.05"
#property description "Body/wick engulf with optional hunt, prior movement and EMA 20/54 filters; final 5-second preview."
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots 2
#property indicator_label1 "Engulf buy"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrLimeGreen
#property indicator_width1 2
#property indicator_label2 "Engulf sell"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrRed
#property indicator_width2 2
#property strict
#include "EngulfFlowCore.mqh"

input group "Wick hunt"
input int InpHuntBars=1; // Previous candles whose wicks must ALL be swept; 0 disables hunt

input group "Engulf"
input ENUM_WH_ENGULF_MODE InpEngulfMode=WH_ENGULF_BODY;

input group "Prior movement"
input bool InpUsePriorMove=false; // Require an uninterrupted movement opposite to signal
input int InpPriorMoveBars=3; // Minimum closed candles in the prior movement (>=1)

input group "Arrows"
input color InpBuyColor=clrLimeGreen;
input color InpSellColor=clrRed;
input int InpArrowWidth=2; // 1..5
input int InpArrowGapPixels=10; // Distance from signal candle wick

input group "EMA trend filter"
input bool InpUseEMAFilter=false; // EMA 20 > 54: Buy only; EMA 20 < 54: Sell only (Close price)

double BuyBuffer[],SellBuffer[],LegDirectionBuffer[],LegCountBuffer[];
double EMA20Buffer[],EMA54Buffer[],EMAValidCountBuffer[];
datetime g_first_bar=0,g_current_bar=0,g_close_time=0;
datetime g_server_anchor=0;
ulong g_clock_anchor=0;
int g_live_index=-1;
int g_live_signal=0;
WHBar g_live;

datetime WHServerNow()
{
   // TimeCurrent alone stops between quotes. Advance its server-time anchor
   // with a monotonic clock, so a quiet symbol still enters the preview window.
   datetime server=TimeCurrent();
   ulong clock=GetTickCount64();
   if(server<=0) return 0;
   if(server!=g_server_anchor)
   {
      g_server_anchor=server;
      g_clock_anchor=clock;
   }
   return server+(datetime)((clock-g_clock_anchor)/1000);
}

datetime WHBarClose(const datetime opened)
{
   if(opened<=0) return 0;
   if(_Period==PERIOD_MN1)
   {
      MqlDateTime dt;
      if(!TimeToStruct(opened,dt)) return 0;
      dt.mon++;
      if(dt.mon>12) { dt.mon=1; dt.year++; }
      return StructToTime(dt);
   }
   int seconds=PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   return seconds>0 ? opened+seconds : 0;
}

int OnInit()
{
   if(InpHuntBars<0 || (InpEngulfMode!=WH_ENGULF_BODY && InpEngulfMode!=WH_ENGULF_WICK) ||
      InpPriorMoveBars<1 || InpArrowWidth<1 || InpArrowWidth>5 || InpArrowGapPixels<0)
      return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,BuyBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SellBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,LegDirectionBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(3,LegCountBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,EMA20Buffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,EMA54Buffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,EMAValidCountBuffer,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(BuyBuffer,false);
   ArraySetAsSeries(SellBuffer,false);
   ArraySetAsSeries(LegDirectionBuffer,false);
   ArraySetAsSeries(LegCountBuffer,false);
   ArraySetAsSeries(EMA20Buffer,false);
   ArraySetAsSeries(EMA54Buffer,false);
   ArraySetAsSeries(EMAValidCountBuffer,false);
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,InpArrowGapPixels);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,-InpArrowGapPixels);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpBuyColor);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpSellColor);
   for(int p=0;p<2;p++)
   {
      PlotIndexSetInteger(p,PLOT_LINE_WIDTH,InpArrowWidth);
      int begin=(int)MathMax(1,InpHuntBars);
      if(InpUsePriorMove) begin=(int)MathMax(begin,InpPriorMoveBars);
      if(InpUseEMAFilter) begin=(int)MathMax(begin,53);
      PlotIndexSetInteger(p,PLOT_DRAW_BEGIN,begin);
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   }
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   string mode=InpEngulfMode==WH_ENGULF_BODY ? "body" : "wick";
   string movement=InpUsePriorMove ? IntegerToString(InpPriorMoveBars) : "off";
   string ema=InpUseEMAFilter ? "20/54" : "off";
   IndicatorSetString(INDICATOR_SHORTNAME,"EngulfFlow ("+mode+", hunt "+
                      IntegerToString(InpHuntBars)+", move "+movement+", EMA "+ema+", 5s)");
   g_first_bar=0; g_current_bar=0; g_close_time=0;
   g_server_anchor=0; g_clock_anchor=0; g_live_index=-1;
   g_live_signal=0;
   if(!EventSetTimer(1))
   {
      Print("EngulfFlow: unable to start preview timer: ",GetLastError());
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void WHWrite(const int index,const WHBar &bar,const int signal)
{
   BuyBuffer[index]=signal==1 ? bar.low : EMPTY_VALUE;
   SellBuffer[index]=signal==-1 ? bar.high : EMPTY_VALUE;
}

// EMA of chart Close, seeded by the first valid Close. Recompute each live
// value from the preceding CLOSED bar, never from the previous tick's EMA.
void WHUpdateEMA(const int i,const double price)
{
   EMA20Buffer[i]=EMPTY_VALUE;
   EMA54Buffer[i]=EMPTY_VALUE;
   EMAValidCountBuffer[i]=0;
   if(!MathIsValidNumber(price) || price==EMPTY_VALUE) return;
   if(i==0 || EMAValidCountBuffer[i-1]<1)
   {
      EMA20Buffer[i]=price;
      EMA54Buffer[i]=price;
      EMAValidCountBuffer[i]=1;
      return;
   }
   const double fast_alpha=2.0/21.0,slow_alpha=2.0/55.0;
   EMA20Buffer[i]=fast_alpha*price+(1.0-fast_alpha)*EMA20Buffer[i-1];
   EMA54Buffer[i]=slow_alpha*price+(1.0-slow_alpha)*EMA54Buffer[i-1];
   EMAValidCountBuffer[i]=MathMin(54.0,EMAValidCountBuffer[i-1]+1.0);
}

// Chronological arrays. Engulf compares with the immediate previous candle.
// Hunt, if enabled, must sweep EVERY candle in the requested lookback window.
int WHSignalAt(const int i,const double &open[],const double &high[],
               const double &low[],const double &close[])
{
   if(InpHuntBars<0 || i<1 || i<InpHuntBars) return 0;
   WHBar bar={open[i],high[i],low[i],close[i]};
   WHBar previous={open[i-1],high[i-1],low[i-1],close[i-1]};
   int signal=WHSignal(bar,previous,InpHuntBars>0,InpEngulfMode);
   if(signal==0) return 0;
   if(InpUseEMAFilter)
   {
      // Require 54 consecutive valid closes including the signal bar. Equality
      // has no trend, so both directions are suppressed. Use this bar's EMA.
      if(EMAValidCountBuffer[i]<54 || !MathIsValidNumber(EMA20Buffer[i]) ||
         !MathIsValidNumber(EMA54Buffer[i]) || EMA20Buffer[i]==EMPTY_VALUE ||
         EMA54Buffer[i]==EMPTY_VALUE) return 0;
      if((signal==1 && EMA20Buffer[i]<=EMA54Buffer[i]) ||
         (signal==-1 && EMA20Buffer[i]>=EMA54Buffer[i])) return 0;
   }
   if(InpUsePriorMove)
   {
      WHLeg prior;
      prior.direction=(int)LegDirectionBuffer[i-1];
      prior.count=(int)LegCountBuffer[i-1];
      if(!WHPriorMoveAllows(signal,prior,InpPriorMoveBars)) return 0;
   }
   for(int j=i-2;j>=i-InpHuntBars;j--)
   {
      if(IsStopped()) return 0;
      WHBar older={open[j],high[j],low[j],close[j]};
      if(!WHValid(older) || (signal==1 && bar.low>=older.low) ||
         (signal==-1 && bar.high<=older.high)) return 0;
   }
   return signal;
}

void WHRefreshLive(const datetime now,const bool available)
{
   if(g_live_index<1 || g_live_index>=ArraySize(BuyBuffer) ||
      g_live_index>=ArraySize(SellBuffer)) return;
   int signal=available && WHPreviewWindow(now,g_current_bar,g_close_time)
              ? g_live_signal : 0;
   WHWrite(g_live_index,g_live,signal);
}

void OnTimer()
{
   if(g_live_index<1) return;
   // A new quote/history update may resize or shift the buffers before the
   // next OnCalculate. Never write the cached candle into a different slot.
   if(ArraySize(BuyBuffer)!=g_live_index+1 ||
      iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,0)!=g_current_bar ||
      iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,g_live_index)!=g_first_bar) return;
   bool available=(bool)TerminalInfoInteger(TERMINAL_CONNECTED) &&
                  (bool)SeriesInfoInteger(_Symbol,(ENUM_TIMEFRAMES)_Period,SERIES_SYNCHRONIZED);
   WHRefreshLive(WHServerNow(),available);
   ChartRedraw();
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   if(rates_total<1) { g_live_index=-1; return 0; }
   ArraySetAsSeries(time,false);
   ArraySetAsSeries(open,false);
   ArraySetAsSeries(high,false);
   ArraySetAsSeries(low,false);
   ArraySetAsSeries(close,false);
   bool reset=prev_calculated<=0 || prev_calculated>rates_total || g_first_bar!=time[0] ||
              (prev_calculated==rates_total && g_current_bar!=time[rates_total-1]);
   int start=reset ? 0 : (int)MathMax(0,prev_calculated-1);
   if(reset)
   {
      ArrayInitialize(BuyBuffer,EMPTY_VALUE);
      ArrayInitialize(SellBuffer,EMPTY_VALUE);
      ArrayInitialize(LegDirectionBuffer,0.0);
      ArrayInitialize(LegCountBuffer,0.0);
      ArrayInitialize(EMA20Buffer,EMPTY_VALUE);
      ArrayInitialize(EMA54Buffer,EMPTY_VALUE);
      ArrayInitialize(EMAValidCountBuffer,0.0);
   }
   // Always recalculate the previously live bar from its FINAL OHLC. Preview
   // presence is irrelevant: a qualifying close also counts without a preview.
   for(int i=start;i<rates_total-1;i++)
   {
      if(IsStopped()) { g_live_index=-1; return 0; }
      WHBar bar={open[i],high[i],low[i],close[i]};
      WHUpdateEMA(i,close[i]);
      WHWrite(i,bar,WHSignalAt(i,open,high,low,close));
      WHLeg after;
      if(i==0) WHSeedLeg(bar,after);
      else
      {
         WHBar previous={open[i-1],high[i-1],low[i-1],close[i-1]};
         WHLeg before;
         before.direction=(int)LegDirectionBuffer[i-1];
         before.count=(int)LegCountBuffer[i-1];
         WHStepLeg(bar,previous,before,InpPriorMoveBars,after);
      }
      LegDirectionBuffer[i]=after.direction;
      LegCountBuffer[i]=after.count;
   }
   g_first_bar=time[0];
   g_current_bar=time[rates_total-1];
   g_close_time=WHBarClose(g_current_bar);
   g_live_index=rates_total-1;
   WHUpdateEMA(g_live_index,close[g_live_index]);
   BuyBuffer[g_live_index]=EMPTY_VALUE;
   SellBuffer[g_live_index]=EMPTY_VALUE;
   // The live candle cannot extend or reset the confirmed prior movement.
   LegDirectionBuffer[g_live_index]=0;
   LegCountBuffer[g_live_index]=0;
   g_live_signal=0;
   if(rates_total>=2)
   {
      int i=g_live_index;
      g_live.open=open[i]; g_live.high=high[i]; g_live.low=low[i]; g_live.close=close[i];
      g_live_signal=WHSignalAt(i,open,high,low,close);
      WHRefreshLive(WHServerNow(),(bool)TerminalInfoInteger(TERMINAL_CONNECTED));
   }
   return rates_total;
}
