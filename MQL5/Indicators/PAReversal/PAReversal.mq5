#property copyright "PA Reversal"
#property version "1.00"
#property description "Closed-candle reversal after an uninterrupted wick-based price-action leg."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots 2
#property indicator_label1 "Buy reversal"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrLimeGreen
#property indicator_width1 2
#property indicator_label2 "Sell reversal"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrRed
#property indicator_width2 2
#property strict
#include "PAReversalCore.mqh"

input group "Reversal detection"
input int InpMinBars=3; // Minimum closed candles BEFORE the reversal candle
input group "Arrows"
input color InpBuyColor=clrLimeGreen;
input color InpSellColor=clrRed;
input int InpArrowWidth=2; // 1..5
input int InpArrowGapPixels=10; // Space below/above the reversal candle wick

double BuyBuffer[],SellBuffer[],DirectionBuffer[],CountBuffer[];
datetime g_first_bar=0,g_current_bar=0;

int OnInit()
{
   if(InpMinBars<1 || InpArrowWidth<1 || InpArrowWidth>5 || InpArrowGapPixels<0)
   {
      Print("PAReversal: MinBars >= 1, ArrowWidth 1..5, ArrowGapPixels >= 0 required.");
      return INIT_PARAMETERS_INCORRECT;
   }
   SetIndexBuffer(0,BuyBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SellBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,DirectionBuffer,INDICATOR_CALCULATIONS);
   SetIndexBuffer(3,CountBuffer,INDICATOR_CALCULATIONS);
   ArraySetAsSeries(BuyBuffer,false);
   ArraySetAsSeries(SellBuffer,false);
   ArraySetAsSeries(DirectionBuffer,false);
   ArraySetAsSeries(CountBuffer,false);
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,InpArrowGapPixels);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,-InpArrowGapPixels);
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpBuyColor);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpSellColor);
   for(int p=0;p<2;p++)
   {
      PlotIndexSetInteger(p,PLOT_LINE_WIDTH,InpArrowWidth);
      PlotIndexSetInteger(p,PLOT_DRAW_BEGIN,InpMinBars);
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   }
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   IndicatorSetString(INDICATOR_SHORTNAME,"PA Reversal ("+IntegerToString(InpMinBars)+")");
   g_first_bar=0;
   g_current_bar=0;
   return INIT_SUCCEEDED;
}

void CalculatePABar(const int i,const double o,const double h,const double l,const double c,
                    const double po,const double ph,const double pl,const double pc)
{
   BuyBuffer[i]=EMPTY_VALUE;
   SellBuffer[i]=EMPTY_VALUE;
   PABar bar={o,h,l,c};
   PAState after;
   if(i==0) PASeed(bar,after);
   else
   {
      PABar previous={po,ph,pl,pc};
      PAState before;
      before.direction=(int)DirectionBuffer[i-1];
      before.count=(int)CountBuffer[i-1];
      int signal=PAStep(bar,previous,before,InpMinBars,after);
      if(signal==1) BuyBuffer[i]=l;
      if(signal==-1) SellBuffer[i]=h;
   }
   DirectionBuffer[i]=after.direction;
   CountBuffer[i]=after.count;
}

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
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
      ArrayInitialize(DirectionBuffer,0);
      ArrayInitialize(CountBuffer,0);
   }
   // The last element is still forming. Never put a signal or leg state there.
   for(int i=start;i<rates_total-1;i++)
   {
      if(IsStopped()) return 0;
      int prior=i>0 ? i-1 : 0;
      CalculatePABar(i,open[i],high[i],low[i],close[i],
                       open[prior],high[prior],low[prior],close[prior]);
   }
   BuyBuffer[rates_total-1]=EMPTY_VALUE;
   SellBuffer[rates_total-1]=EMPTY_VALUE;
   DirectionBuffer[rates_total-1]=0;
   CountBuffer[rates_total-1]=0;
   g_first_bar=time[0];
   g_current_bar=time[rates_total-1];
   return rates_total;
}
