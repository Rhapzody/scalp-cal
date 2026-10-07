#ifndef SCALP_BROKER_MQH
#define SCALP_BROKER_MQH
#include "ScalpCore.mqh"

struct ScalpSpec
{
   double point,tick_size,min_lot,max_lot,step,volume_limit,stops,freeze;
   int digits;
};

struct ScalpPlan
{
   bool buy,pending;
   double entry,sl,tp,risk_percent;
   int orders;
};

struct ScalpQuote
{
   bool valid;
   string reason;
   MqlTick tick;
   ScalpSpec spec;
   ENUM_ORDER_TYPE type;
   double entry,broker_sl,broker_tp,spread,budget,loss_per_lot;
   double raw_lot,lot,strategy_loss,broker_loss,broker_reward,margin;
};

bool ScalpReadSpec(ScalpSpec &s)
{
   s.point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   s.tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   s.digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   s.min_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   s.max_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   s.step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   s.volume_limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);
   s.stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*s.point;
   s.freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*s.point;
   return s.point>0 && s.tick_size>0 && s.step>0 && s.min_lot>0 && s.max_lot>=s.min_lot;
}

bool ScalpBuyType(const ENUM_ORDER_TYPE type)
{
   return type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT;
}

double ScalpDirectionalVolume(const bool buy)
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)==buy)
         total+=PositionGetDouble(POSITION_VOLUME);
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol &&
         ScalpBuyType((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE))==buy)
         total+=OrderGetDouble(ORDER_VOLUME_CURRENT);
   return total;
}

bool ScalpNettingExposure()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return false;
   if(PositionSelect(_Symbol)) return true;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol) return true;
   return false;
}

bool ScalpFail(ScalpQuote &q,const string reason)
{
   q.valid=false;
   q.reason=reason;
   return false;
}

bool ScalpCalculateMutable(ScalpPlan &p,const double base,const double max_risk,const int max_orders,
                    const double max_spread_points,const bool compensate,const bool freeze_guard,
                    const int quote_age_seconds,ScalpQuote &q,const int remaining_orders,const bool derive_one_to_one)
{
   ZeroMemory(q);
   if(!ScalpReadSpec(q.spec)) return ScalpFail(q,"Symbol specification unavailable");
   if(!SymbolInfoTick(_Symbol,q.tick) || q.tick.bid<=0 || q.tick.ask<q.tick.bid)
      return ScalpFail(q,"Waiting for Bid / Ask");
   q.spread=q.tick.ask-q.tick.bid;
   q.entry=p.pending ? ScalpSnap(p.entry,q.spec.tick_size,q.spec.digits) : (p.buy ? q.tick.ask : q.tick.bid);
   // Instant mode derives TP from the same quote used for lot and broker stops.
   if(derive_one_to_one && !p.pending)
   {
      p.entry=q.entry;
      p.tp=ScalpSnap(2.0*q.entry-p.sl,q.spec.tick_size,q.spec.digits);
   }
   q.type=p.buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(p.pending)
   {
      int kind=ScalpPendingKind(p.buy,q.entry,q.tick.bid,q.tick.ask);
      if(kind<0) return ScalpFail(q,"Move pending entry away from market");
      if(kind==0) q.type=ORDER_TYPE_BUY_LIMIT;
      if(kind==1) q.type=ORDER_TYPE_BUY_STOP;
      if(kind==2) q.type=ORDER_TYPE_SELL_LIMIT;
      if(kind==3) q.type=ORDER_TYPE_SELL_STOP;
   }
   q.broker_sl=ScalpBrokerPrice(p.buy,compensate,p.sl,q.spread,q.spec.tick_size,q.spec.digits);
   q.broker_tp=ScalpBrokerPrice(p.buy,compensate,p.tp,q.spread,q.spec.tick_size,q.spec.digits);
   if(!ScalpGeometry(p.buy,q.entry,p.sl,p.tp)) return ScalpFail(q,"Invalid strategy SL / TP direction");
   if(!ScalpGeometry(p.buy,q.entry,q.broker_sl,q.broker_tp)) return ScalpFail(q,"Broker SL / TP crosses entry after spread");
   if(!MathIsValidNumber(base) || base<=0) return ScalpFail(q,"Set Initial Balance in Inputs");
   if(!MathIsValidNumber(p.risk_percent) || p.risk_percent<=0 || p.risk_percent>max_risk)
      return ScalpFail(q,"Risk is outside Max Risk limit");
   if(p.orders<1 || p.orders>max_orders) return ScalpFail(q,"Orders is outside Max Orders limit");
   q.budget=base*p.risk_percent/100.0;
   // A valid broker volume is the reference; normalize its result to one lot.
   double pnl=0;
   ENUM_ORDER_TYPE side=p.buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(side,_Symbol,q.spec.min_lot,q.entry,p.sl,pnl) || pnl>=0 || !MathIsValidNumber(pnl))
      return ScalpFail(q,"OrderCalcProfit failed; check currency quotes");
   q.loss_per_lot=-pnl/q.spec.min_lot;
   q.raw_lot=q.budget/p.orders/q.loss_per_lot;
   q.lot=ScalpLot(q.budget,p.orders,q.loss_per_lot,q.spec.step);
   if(q.lot+1e-12<MathMax(0.01,q.spec.min_lot))
      return ScalpFail(q,"Lot/order below minimum; reduce Orders");
   if(q.lot>q.spec.max_lot+1e-12) return ScalpFail(q,"Lot/order above broker maximum");
   if(!OrderCalcProfit(side,_Symbol,q.lot,q.entry,p.sl,pnl)) return ScalpFail(q,"Strategy loss estimate failed");
   q.strategy_loss=-pnl*p.orders;
   if(q.strategy_loss>q.budget+1e-7) return ScalpFail(q,"Rounded strategy risk exceeds budget");
   if(!OrderCalcProfit(side,_Symbol,q.lot,q.entry,q.broker_sl,pnl)) return ScalpFail(q,"Broker loss estimate failed");
   q.broker_loss=-pnl*p.orders;
   if(!OrderCalcProfit(side,_Symbol,q.lot,q.entry,q.broker_tp,pnl)) return ScalpFail(q,"Broker reward estimate failed");
   q.broker_reward=pnl*p.orders;
   if(!OrderCalcMargin(side,_Symbol,q.lot,q.entry,q.margin)) return ScalpFail(q,"Margin estimate failed");
   q.margin*=p.orders;
   int outstanding=remaining_orders>0 ? remaining_orders : p.orders;
   if(q.margin/p.orders*outstanding>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return ScalpFail(q,"Insufficient free margin for whole setup");
   if(q.spec.volume_limit>0 && ScalpDirectionalVolume(p.buy)+q.lot*outstanding>q.spec.volume_limit+1e-9)
      return ScalpFail(q,"Symbol directional volume limit exceeded");
   if(q.spread/q.spec.point>max_spread_points+1e-7) return ScalpFail(q,"Spread exceeds Max Spread points");
   datetime now=TimeTradeServer();
   if(now<=0) now=TimeCurrent();
   if(now-q.tick.time>quote_age_seconds) return ScalpFail(q,"Stale quote; waiting for market tick");

   // Market protection is checked from the close side (BUY Bid, SELL Ask).
   // Pending SL/TP distances are checked from the requested entry.
   double anchor=p.pending ? q.entry : (p.buy ? q.tick.bid : q.tick.ask);
   double sl_dist=p.buy ? anchor-q.broker_sl : q.broker_sl-anchor;
   double tp_dist=p.buy ? q.broker_tp-anchor : anchor-q.broker_tp;
   if(!ScalpDistanceOK(sl_dist,q.spec.stops,q.spec.freeze,freeze_guard && !p.pending,q.spec.tick_size) ||
      !ScalpDistanceOK(tp_dist,q.spec.stops,q.spec.freeze,freeze_guard && !p.pending,q.spec.tick_size))
      return ScalpFail(q,"SL / TP inside stop or freeze guard");
   if(p.pending && !ScalpDistanceOK(MathAbs(q.entry-(p.buy ? q.tick.ask : q.tick.bid)),
                                   q.spec.stops,q.spec.freeze,freeze_guard,q.spec.tick_size))
      return ScalpFail(q,"Pending entry inside stop or freeze guard");

   ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
      (p.buy && mode==SYMBOL_TRADE_MODE_SHORTONLY) || (!p.buy && mode==SYMBOL_TRADE_MODE_LONGONLY))
      return ScalpFail(q,"Symbol does not permit this trade side");
   long allowed=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
   long required=p.pending ? ((q.type==ORDER_TYPE_BUY_LIMIT || q.type==ORDER_TYPE_SELL_LIMIT) ? SYMBOL_ORDER_LIMIT : SYMBOL_ORDER_STOP) : SYMBOL_ORDER_MARKET;
   if((allowed & required)==0 || (allowed & SYMBOL_ORDER_SL)==0 || (allowed & SYMBOL_ORDER_TP)==0)
      return ScalpFail(q,"Broker does not support order with SL / TP");
   if(p.pending && (SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_GTC)==0)
      return ScalpFail(q,"Broker does not support GTC pending orders");
   q.valid=true;
   q.reason="Ready";
   return true;
}

// Preserve the calculator API and its immutable caller-owned strategy plan.
bool ScalpCalculate(const ScalpPlan &p,const double base,const double max_risk,const int max_orders,
                    const double max_spread_points,const bool compensate,const bool freeze_guard,
                    const int quote_age_seconds,ScalpQuote &q,const int remaining_orders=0)
{
   ScalpPlan copy=p;
   return ScalpCalculateMutable(copy,base,max_risk,max_orders,max_spread_points,compensate,
                                freeze_guard,quote_age_seconds,q,remaining_orders,false);
}

// Explicit overload used only by the Instant Engulf path.
bool ScalpCalculate(ScalpPlan &p,const double base,const double max_risk,const int max_orders,
                    const double max_spread_points,const bool compensate,const bool freeze_guard,
                    const int quote_age_seconds,ScalpQuote &q,const int remaining_orders,const bool derive_one_to_one)
{
   return ScalpCalculateMutable(p,base,max_risk,max_orders,max_spread_points,compensate,
                                freeze_guard,quote_age_seconds,q,remaining_orders,derive_one_to_one);
}

bool ScalpPermissions(string &reason)
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { reason="Terminal disconnected"; return false; }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      { reason="Enable Algo Trading to execute"; return false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      { reason="Account does not allow EA trading"; return false; }
   return true;
}

bool ScalpRequest(const ScalpPlan &p,const ScalpQuote &q,const ulong magic,const ulong deviation,
                  MqlTradeRequest &request,string &error)
{
   ZeroMemory(request);
   request.action=p.pending ? TRADE_ACTION_PENDING : TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.magic=magic;
   request.volume=q.lot;
   request.type=q.type;
   request.price=q.entry;
   request.sl=q.broker_sl;
   request.tp=q.broker_tp;
   request.deviation=deviation;
   request.type_time=ORDER_TIME_GTC;
   request.comment="ScalpCalculator V1";
   if(p.pending) request.type_filling=ORDER_FILLING_RETURN;
   else
   {
      long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
      ENUM_SYMBOL_TRADE_EXECUTION execution=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE);
      if(execution==SYMBOL_TRADE_EXECUTION_INSTANT || execution==SYMBOL_TRADE_EXECUTION_REQUEST || (filling & SYMBOL_FILLING_FOK)!=0)
         request.type_filling=ORDER_FILLING_FOK;
      else if((filling & SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
      else if(execution!=SYMBOL_TRADE_EXECUTION_MARKET) request.type_filling=ORDER_FILLING_RETURN;
      else { error="No supported market filling policy"; return false; }
   }
   return true;
}

string ScalpTypeName(const ENUM_ORDER_TYPE type)
{
   switch(type)
   {
      case ORDER_TYPE_BUY: return "BUY MARKET";
      case ORDER_TYPE_SELL: return "SELL MARKET";
      case ORDER_TYPE_BUY_LIMIT: return "BUY LIMIT";
      case ORDER_TYPE_BUY_STOP: return "BUY STOP";
      case ORDER_TYPE_SELL_LIMIT: return "SELL LIMIT";
      case ORDER_TYPE_SELL_STOP: return "SELL STOP";
      default: return "PENDING";
   }
}
#endif
