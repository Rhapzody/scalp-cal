#ifndef TREND_SWEEP_EXECUTION
#define TREND_SWEEP_EXECUTION
#include "ScalpBroker.mqh"
bool EAPrepare(const EACandidate &candidate,const EATarget &targets[],
               const double equity,const double risk_percent,const double max_risk,
               const double minimum_rr,const double target_rr,
               const double max_spread,const int quote_age,const bool freeze_guard,
               const double commission_per_lot,const ulong magic,const ulong deviation,
               ScalpPlan &plan,ScalpQuote &quote,MqlTradeRequest &request,string &reason)
{
   ZeroMemory(plan); ZeroMemory(quote); ZeroMemory(request);
   if((candidate.signal.direction!=1 && candidate.signal.direction!=-1) || ArraySize(targets)!=1 ||
      !MathIsValidNumber(candidate.signal.atr) || candidate.signal.atr<=0 ||
      !MathIsValidNumber(target_rr) || target_rr<1 || target_rr>10)
   { reason="Invalid signal/target"; return false; }
   ScalpSpec spec; MqlTick initial;
   if(!ScalpReadSpec(spec) || !SymbolInfoTick(_Symbol,initial)) { reason="Quote unavailable"; return false; }
   bool buy=candidate.signal.direction==1;
   double entry=buy ? initial.ask : initial.bid;
   double spread=initial.ask-initial.bid;
   if(spread<0 || spread>InpMaxSpreadATR*candidate.signal.atr ||
      MathAbs(initial.bid-candidate.signal.price)>InpMaxEntryDriftATR*candidate.signal.atr)
   { reason="Spread/entry drift exceeds ATR limit"; return false; }
   plan.buy=buy; plan.pending=false; plan.orders=1; plan.risk_percent=risk_percent;
   plan.sl=TSStop(candidate,spec.tick_size,spec.digits);
   double broker_sl=ScalpBrokerPrice(buy,true,plan.sl,spread,spec.tick_size,spec.digits);
   double risk=buy ? entry-broker_sl : broker_sl-entry;
   if(risk<g_config.min_stop_atr*candidate.signal.atr || risk>g_config.max_stop_atr*candidate.signal.atr)
   { reason="Executable stop distance outside ATR limits"; return false; }
   double broker_tp=entry+(buy ? 1 : -1)*target_rr*risk;
   plan.tp=ScalpSnap(broker_tp-(!buy ? spread : 0),spec.tick_size,spec.digits);
   if(!MathIsValidNumber(targets[0].price) || (buy ? plan.tp>targets[0].price : plan.tp<targets[0].price))
   { reason="Insufficient room for target after entry/spread"; return false; }
   if(!ScalpCalculate(plan,equity,max_risk,1,max_spread,true,freeze_guard,quote_age,quote))
   { reason=quote.reason; return false; }
   if(quote.tick.bid!=initial.bid || quote.tick.ask!=initial.ask)
   { reason="Quote changed during preparation"; return false; }
   if(!EAMinimumRR(buy,quote.entry,quote.broker_sl,quote.broker_tp,minimum_rr))
   { reason="R:R below minimum after spread compensation"; return false; }
   if(!MathIsValidNumber(commission_per_lot) || commission_per_lot<0)
   { reason="Invalid commission input"; return false; }
   double loss_per_lot=quote.broker_loss/quote.lot+commission_per_lot;
   double reward_per_lot=quote.broker_reward/quote.lot-commission_per_lot;
   if(!MathIsValidNumber(loss_per_lot) || !MathIsValidNumber(reward_per_lot) || loss_per_lot<=0 ||
      reward_per_lot<=0 || reward_per_lot/loss_per_lot+1e-12<minimum_rr)
   { reason="R:R below minimum after broker profit calculation / commission"; return false; }
   // ScalpCalculate initially sizes strategy risk; reduce if SELL compensation
   // or commission makes the broker risk larger. Never increase its initial lot.
   double lot=ScalpFloorVolume(MathMin(quote.lot,quote.budget/loss_per_lot),spec.step);
   if(lot+1e-12<MathMax(0.01,spec.min_lot))
   { reason="Broker risk budget cannot support minimum lot"; return false; }
   double ratio=lot/quote.lot;
   quote.lot=lot; quote.strategy_loss*=ratio; quote.broker_loss*=ratio;
   quote.broker_reward*=ratio; quote.margin*=ratio;
   if(quote.broker_loss+lot*commission_per_lot>quote.budget+1e-7)
   { reason="Broker risk exceeds budget"; return false; }
   if(!ScalpRequest(plan,quote,magic,deviation,request,reason)) return false;
   request.comment="TrendSweepTrader 1.00";
   reason="Ready";
   return true;
}

bool EADefiniteRejection(const uint code)
{
   return code==TRADE_RETCODE_REQUOTE || code==TRADE_RETCODE_REJECT ||
          code==TRADE_RETCODE_CANCEL || code==TRADE_RETCODE_INVALID ||
          code==TRADE_RETCODE_INVALID_VOLUME || code==TRADE_RETCODE_INVALID_PRICE ||
          code==TRADE_RETCODE_INVALID_STOPS || code==TRADE_RETCODE_TRADE_DISABLED ||
          code==TRADE_RETCODE_MARKET_CLOSED || code==TRADE_RETCODE_NO_MONEY ||
          code==TRADE_RETCODE_PRICE_CHANGED || code==TRADE_RETCODE_PRICE_OFF ||
          code==TRADE_RETCODE_INVALID_FILL;
}

bool EACompleteFill(const bool sent,const MqlTradeResult &result,const MqlTradeRequest &request,
                    const double step)
{
   return sent && result.retcode==TRADE_RETCODE_DONE && result.deal>0 &&
          MathIsValidNumber(result.price) && MathIsValidNumber(result.volume) &&
          result.price>0 && result.volume>0 && MathAbs(result.volume-request.volume)<step*0.5;
}

// Host adapters below are implemented by the EA and replaced by deterministic
// test doubles in the execution tests. This is the sole OrderSend call path.
void EAExecute(const EACandidate &candidate,const EATarget &targets[])
{
   string reason="";
   if(!InpExecuteTrades) { EAReport("SIGNAL ONLY",candidate,"Enable InpExecuteTrades to submit orders"); return; }
   if(!EAFresh(candidate)) { EAReport("SKIP",candidate,"Signal expired"); return; }
   if(!ScalpPermissions(reason)) { EAReport("SKIP",candidate,reason); return; }
   int lock=EALock();
   if(lock==INVALID_HANDLE) { EAReport("SKIP",candidate,"Another instance holds the symbol lock"); return; }
   do
   {
      if(EAHalted()) { EAReport("PAUSED",candidate,"Uncertain prior request; inspect Trade/History and recovery manual"); break; }
      if(EAAttempted(candidate)) { EAReport("SKIP",candidate,"Signal already attempted"); break; }
      if(EAHasExposure()) { EAReport("SKIP",candidate,"Symbol has an open position or pending order"); break; }
      ScalpPlan plan; ScalpQuote quote;
      MqlTradeRequest request; MqlTradeCheckResult check; MqlTradeResult result;
      ZeroMemory(plan); ZeroMemory(quote); ZeroMemory(request); ZeroMemory(check); ZeroMemory(result);
      bool ready=false;
      // Requote only before submission; never retry OrderSend.
      for(int attempt=0;attempt<3;attempt++)
      {
         if(!EAPrepare(candidate,targets,AccountInfoDouble(ACCOUNT_EQUITY),InpRiskPercent,InpMaxRiskPercent,
                       InpMinRR,InpTargetRR,InpMaxSpreadPoints,InpMaxQuoteAgeSeconds,InpFreezeGuard,
                       InpCommissionPerLot,InpMagicNumber,InpDeviationPoints,plan,quote,request,reason)) break;
         ZeroMemory(check);
         if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
         { reason="OrderCheck rejected: "+check.comment; break; }
         MqlTick fresh;
         if(!SymbolInfoTick(_Symbol,fresh)) { reason="Final quote unavailable"; break; }
         if(fresh.bid==quote.tick.bid && fresh.ask==quote.tick.ask)
         { ready=true; break; }
         reason="Quote changed during OrderCheck";
      }
      if(!ready) { EAReport("SKIP",candidate,reason); break; }
      if(!EAFresh(candidate) || !ScalpPermissions(reason) || EAHasExposure())
      { EAReport("SKIP",candidate,"Signal, permissions or exposure changed before send"); break; }
      // Persist intent and a pending latch BEFORE sending, including crash recovery.
      if(!EAMarkAttempt(candidate)) { EAReport("SKIP",candidate,"Cannot persist order intent"); break; }
      if(!EAFresh(candidate))
      { EAClearHalt(); EAReport("SKIP",candidate,"Signal expired during persistence"); break; }
      MqlTick final_tick;
      if(!SymbolInfoTick(_Symbol,final_tick) || final_tick.bid!=quote.tick.bid || final_tick.ask!=quote.tick.ask)
      { EAClearHalt(); EAReport("SKIP",candidate,"Quote changed while persisting intent"); break; }
      ZeroMemory(result);
      bool sent=OrderSend(request,result);
      bool filled=EACompleteFill(sent,result,request,quote.spec.step);
      if(filled || EADefiniteRejection(result.retcode)) EAClearHalt();
      // Partial, timeout, PLACED and ambiguous responses keep the persistent latch.
      EATradeReport(candidate,plan,quote,request,result,filled);
   } while(false);
   EAUnlock(lock);
}
#endif
