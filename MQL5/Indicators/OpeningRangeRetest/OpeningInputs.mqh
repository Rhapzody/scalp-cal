#ifndef OPENING_RANGE_INPUTS
#define OPENING_RANGE_INPUTS
#include "OpeningCore.mqh"
input group "Opening range - broker server time, M5"
input int InpStartHour=8;
input int InpStartMinute=0;
input int InpRangeMinutes=30;
input int InpATRLength=14;
input int InpMaxRetestBars=12;
input int InpMinRangePoints=0;
input ENUM_OR_SIDE InpTradeSide=OR_BOTH;
input ENUM_OR_RETEST InpRetestMode=OR_RETEST_WICK;
input group "Breakout and risk geometry"
input double InpMinBreakATR=0.10;
input double InpMaxBreakATR=1.50;
input double InpMinBodyRatio=0.45;
input double InpMinCloseLocation=0.70;
input double InpSLBufferATR=0.10;
input double InpSLBufferPoints=0;
input double InpMinStopATR=0.40;
input double InpMaxStopATR=2.50;
input double InpTargetRR=2.0;
input int InpCooldownDays=0;
input int InpHistoryBars=3000;
void ORConfigure(ORConfig &c)
{
   c.start_hour=InpStartHour; c.start_minute=InpStartMinute; c.range_minutes=InpRangeMinutes;
   c.atr_length=InpATRLength; c.max_retest_bars=InpMaxRetestBars; c.cooldown_days=InpCooldownDays;
   c.min_range_points=InpMinRangePoints; c.side=InpTradeSide; c.retest_mode=InpRetestMode;
   c.min_break_atr=InpMinBreakATR; c.max_break_atr=InpMaxBreakATR; c.min_body_ratio=InpMinBodyRatio;
   c.min_close_location=InpMinCloseLocation; c.stop_buffer_atr=InpSLBufferATR;
   c.stop_buffer_points=InpSLBufferPoints; c.min_stop_atr=InpMinStopATR; c.max_stop_atr=InpMaxStopATR;
   c.target_rr=InpTargetRR; c.point=_Point;
}
#endif
