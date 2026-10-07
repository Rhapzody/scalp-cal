#ifndef SCALP_ENGULF_PANEL_MQH
#define SCALP_ENGULF_PANEL_MQH
// Integrated with InstantEngulf body-breakout rules. All order submission remains click-only.
EngulfBar PanelEngulfBar(const MqlRates &rate) { return EngulfRateBar(rate); }

bool PanelEngulfReadPair(MqlRates &latest,MqlRates &older,EngulfPairContext &context,string &reason)
{
   return EngulfReadSelectedPair(latest,older,context,reason);
}

string PanelEngulfSignalKey(const bool buy)
{
   string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+
                   _Symbol+"|"+IntegerToString(_Period)+"|"+IntegerToString((long)InpEngulfMagicNumber);
   ulong hash=14695981039346656037;
   for(int i=0;i<StringLen(identity);i++) { hash^=(ulong)StringGetCharacter(identity,i); hash*=1099511628211; }
   return StringFormat("IE1.%I64X.%s",hash,buy ? "B" : "S");
}

bool PanelEngulfAttempted(const bool buy,const datetime candle_time)
{
   if(!InpEngulfOneOrderPerSignal) return false;
   string key=PanelEngulfSignalKey(buy);
   return GlobalVariableCheck(key) && GlobalVariableGet(key)>=(double)candle_time;
}

void PanelEngulfFail(const string reason)
{
   g_result="INSTANT NOT SENT"; g_detail=reason;
   Print("Instant Engulf: ",reason); Alert("Instant Engulf: ",reason);
}

// Called only by a user button click. OnTick and OnTimer never submit orders.
void ExecuteEngulf(const bool buy)
{
   if(g_busy) return;
   ulong now_ms=GetTickCount64();
   if(g_engulf_last_click>0 && now_ms-g_engulf_last_click<1200) return;
   g_engulf_last_click=now_ms;
   g_busy=true;
   int lock=INVALID_HANDLE;
   string reason="",key=PanelEngulfSignalKey(buy);
   MqlRates latest,older; EngulfPairContext selected;
   ScalpPlan plan={}; ScalpQuote quote;
   MqlTradeRequest request={}; MqlTradeCheckResult check={}; MqlTradeResult result={};
   do
   {
      if(!InpShowInstantEngulf) { PanelEngulfFail("Instant Engulf section disabled"); break; }
      if(!g_enabled) { PanelEngulfFail("EA OFF"); break; }
      if(!PanelEngulfReadPair(latest,older,selected,reason)) { PanelEngulfFail(reason); break; }
      EngulfBar a=PanelEngulfBar(latest),b=PanelEngulfBar(older);
      if(!EngulfSignal(buy,a,b))
      {
         PanelEngulfFail(EngulfPairLabel(selected)+(buy ? ": BUY ต้องผ่านขอบบนเนื้อเทียนแท่งที่เทียบ" : ": SELL ต้องผ่านขอบล่างเนื้อเทียนแท่งที่เทียบ"));
         break;
      }
      if(!ScalpPermissions(reason)) { PanelEngulfFail(reason); break; }
      // Exclusive terminal-local file lock serializes multiple chart instances.
      lock=FileOpen(key+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
      if(lock==INVALID_HANDLE) { PanelEngulfFail("Another instance is processing this signal; check Trade"); break; }
      if(PanelEngulfAttempted(buy,latest.time)) { PanelEngulfFail("This PA signal was already submitted; check Trade / History"); break; }
      if(ScalpNettingExposure()) { PanelEngulfFail("Netting: symbol already has position or pending exposure"); break; }
      plan.buy=buy; plan.pending=false; plan.orders=1; plan.risk_percent=InpEngulfRiskPercent;
      ScalpSpec spec;
      if(!ScalpReadSpec(spec)) { PanelEngulfFail("Symbol specification unavailable"); break; }
      plan.sl=EngulfBufferedStop(buy,a,b,InpEngulfSLBufferPoints,spec.point,spec.tick_size,spec.digits);
      if(!ScalpCalculate(plan,RiskBase(),InpMaxRiskPercent,1,InpMaxSpreadPoints,true,
                         InpFreezeGuard,InpMaxQuoteAgeSeconds,quote,0,true)) { PanelEngulfFail(quote.reason); break; }
      if(!ScalpRequest(plan,quote,InpEngulfMagicNumber,InpDeviationPoints,request,reason)) { PanelEngulfFail(reason); break; }
      request.comment="Scalp InstantEngulf";
      ResetLastError();
      if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
      { PanelEngulfFail(StringFormat("OrderCheck %u: %s (error %d)",check.retcode,check.comment,GetLastError())); break; }
      if(!EngulfPairStillValid(buy,selected,latest.time,plan.sl,InpEngulfSLBufferPoints,quote.spec,reason))
      { PanelEngulfFail(reason); break; }
      double previous_marker=GlobalVariableCheck(key) ? GlobalVariableGet(key) : 0;
      if(InpEngulfOneOrderPerSignal)
      {
         if(GlobalVariableSet(key,(double)latest.time)==0) { PanelEngulfFail("Could not persist duplicate protection"); break; }
         GlobalVariablesFlush(); // Also protects against a crash after the send.
      }
      // Disk persistence can take time; check the window once more before send.
      if(!EngulfSelectionCurrent(selected,reason))
      {
         if(InpEngulfOneOrderPerSignal) { GlobalVariableSet(key,previous_marker); GlobalVariablesFlush(); }
         PanelEngulfFail(reason); break;
      }
      bool sent=OrderSend(request,result);
      ENUM_ENGULF_RESULT outcome=EngulfResult(sent,result.retcode,result.price,result.volume,request.volume,quote.spec.step);
      if(outcome==ENGULF_REJECTED && InpEngulfOneOrderPerSignal)
         { GlobalVariableSet(key,0); GlobalVariablesFlush(); }
      string side=buy ? "BUY" : "SELL";
      g_result=outcome==ENGULF_FILLED ? side+" FILLED" :
               (outcome==ENGULF_PARTIAL ? side+" PARTIAL FILL - CHECK TRADE" :
               (outcome==ENGULF_UNCERTAIN ? side+" UNCONFIRMED - CHECK TRADE" : side+" REJECTED"));
      g_result="INSTANT "+g_result+" / "+EngulfPairLabel(selected);
      g_detail=StringFormat("code %u | order %I64u | deal %I64u | %s",result.retcode,result.order,result.deal,result.comment);
      PrintFormat("Instant Engulf %s | PA=%s TF=%s | requested lot=%.8f entry=%.*f strategy SL=%.*f TP=%.*f | spread=%.*f broker SL=%.*f TP=%.*f | strategy risk=%.2f broker risk=%.2f | fill price=%.*f volume=%.8f | %s",
                  g_result,TimeToString(latest.time),EnumToString((ENUM_TIMEFRAMES)_Period),request.volume,_Digits,quote.entry,
                  _Digits,plan.sl,_Digits,plan.tp,_Digits,quote.spread,_Digits,request.sl,_Digits,request.tp,
                  quote.strategy_loss,quote.broker_loss,_Digits,result.price,result.volume,g_detail);
      if(outcome!=ENGULF_FILLED) Alert("Instant Engulf: ",g_result,"\n",g_detail);
      // No retry, auto-close, or post-fill adjustment of the submitted SL/TP.
   } while(false);
   if(lock!=INVALID_HANDLE) FileClose(lock);
   g_busy=false;
   SaveState(); Refresh();
}

void RefreshEngulfPreview()
{
   g_engulf_pa="Disabled"; g_engulf_bar_time="--"; g_engulf_pair="--";
   g_engulf_has_signal=false; g_engulf_valid=false;
   ZeroMemory(g_engulf_plan); ZeroMemory(g_engulf_quote);
   if(!InpShowInstantEngulf) return;
   MqlRates latest,older; EngulfPairContext selected; string reason="";
   if(!PanelEngulfReadPair(latest,older,selected,reason)) { g_engulf_pa=reason; return; }
   g_engulf_pair=EngulfPairLabel(selected);
   EngulfBar a=PanelEngulfBar(latest),b=PanelEngulfBar(older);
   g_engulf_bar_time=TimeToString(latest.time,TIME_DATE|TIME_MINUTES);
   bool buy=EngulfSignal(true,a,b),sell=EngulfSignal(false,a,b);
   g_engulf_pa=buy ? "BUY PA" : (sell ? "SELL PA" : "No PA");
   if(!buy && !sell) return;
   g_engulf_has_signal=true;
   g_engulf_plan.buy=buy; g_engulf_plan.orders=1; g_engulf_plan.risk_percent=InpEngulfRiskPercent;
   ScalpSpec spec;
   if(!ScalpReadSpec(spec)) { g_engulf_pa="Waiting for symbol specification"; return; }
   g_engulf_plan.sl=EngulfBufferedStop(buy,a,b,InpEngulfSLBufferPoints,spec.point,spec.tick_size,spec.digits);
   g_engulf_valid=ScalpCalculate(g_engulf_plan,RiskBase(),InpMaxRiskPercent,1,InpMaxSpreadPoints,true,
                                 InpFreezeGuard,InpMaxQuoteAgeSeconds,g_engulf_quote,0,true);
   if(PanelEngulfAttempted(buy,latest.time)) { g_engulf_pa+=" / already submitted"; g_engulf_valid=false; }
}

#endif
