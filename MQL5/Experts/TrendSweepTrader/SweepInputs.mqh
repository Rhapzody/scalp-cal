#ifndef TREND_SWEEP_INPUTS
#define TREND_SWEEP_INPUTS
#include "SweepCore.mqh"
input group "M5 trend and sweep - match between indicator and EA"
input int InpFastEMA=50;
input int InpSlowEMA=200;
input int InpATRLength=14;
input int InpSweepLookback=8;
input int InpRoomLookback=40;
input int InpCooldownBars=6;
input ENUM_TS_SIDE InpTradeSide=TS_BOTH;
input double InpMinSweepATR=0.05;
input double InpMaxSweepATR=0.80;
input double InpMinBodyRatio=0.35;
input double InpMinCloseLocation=0.65;
input double InpMaxExtensionATR=2.0;
input group "Signal levels - before execution spread and tick rounding"
input double InpSLBufferATR=0.10;
input double InpSLBufferPoints=0;
input double InpMinStopATR=0.5;
input double InpMaxStopATR=2.5;
input double InpTargetRR=2.0;
input double InpRoomBufferATR=0.10;
input group "History and hours - broker server time"
input int InpHistoryBars=3000;
input int InpStartHour=0;
input int InpEndHour=0; // Equal = all hours; overnight intervals supported
void TSConfigure(TSConfig &c)
{
   c.fast=InpFastEMA; c.slow=InpSlowEMA; c.atr_length=InpATRLength;
   c.lookback=InpSweepLookback; c.room_bars=InpRoomLookback; c.cooldown=InpCooldownBars;
   c.side=InpTradeSide; c.min_sweep_atr=InpMinSweepATR; c.max_sweep_atr=InpMaxSweepATR;
   c.min_body=InpMinBodyRatio; c.min_close_location=InpMinCloseLocation; c.max_extension_atr=InpMaxExtensionATR;
   c.stop_atr=InpSLBufferATR; c.stop_points=InpSLBufferPoints; c.point=_Point;
   c.min_stop_atr=InpMinStopATR; c.max_stop_atr=InpMaxStopATR; c.target_rr=InpTargetRR;
   c.room_buffer_atr=InpRoomBufferATR; c.start_hour=InpStartHour; c.end_hour=InpEndHour;
}
#endif
