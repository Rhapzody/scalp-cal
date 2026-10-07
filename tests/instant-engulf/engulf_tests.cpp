// Reuse the MT5 mock adapter, but include this EA's own broker implementation.
#ifndef SCALP_BROKER_HEADER
#define SCALP_BROKER_HEADER "../../MQL5/Experts/InstantEngulf/InstantBroker.mqh"
#endif
#define main PreviousBrokerTests
#include "../scalp-calculator/broker_tests.cpp"
#undef main
#define MathMin std::min
#define MathCeil std::ceil
enum {
 TRADE_RETCODE_REQUOTE=10004,TRADE_RETCODE_REJECT=10006,TRADE_RETCODE_CANCEL=10007,
 TRADE_RETCODE_PLACED=10008,TRADE_RETCODE_DONE=10009,TRADE_RETCODE_DONE_PARTIAL=10010,
 TRADE_RETCODE_ERROR=10011,TRADE_RETCODE_TIMEOUT=10012,TRADE_RETCODE_INVALID=10013,
 TRADE_RETCODE_INVALID_VOLUME=10014,TRADE_RETCODE_INVALID_PRICE=10015,TRADE_RETCODE_INVALID_STOPS=10016,
 TRADE_RETCODE_TRADE_DISABLED=10017,TRADE_RETCODE_MARKET_CLOSED=10018,TRADE_RETCODE_NO_MONEY=10019,
 TRADE_RETCODE_PRICE_CHANGED=10020,TRADE_RETCODE_PRICE_OFF=10021,TRADE_RETCODE_INVALID_EXPIRATION=10022,
 TRADE_RETCODE_TOO_MANY_REQUESTS=10024,TRADE_RETCODE_SERVER_DISABLES_AT=10026,TRADE_RETCODE_CLIENT_DISABLES_AT=10027,
 TRADE_RETCODE_INVALID_FILL=10030,TRADE_RETCODE_ONLY_REAL=10032,TRADE_RETCODE_LIMIT_ORDERS=10033,
 TRADE_RETCODE_LIMIT_VOLUME=10034,TRADE_RETCODE_INVALID_ORDER=10035,TRADE_RETCODE_LIMIT_POSITIONS=10040,
 TRADE_RETCODE_LONG_ONLY=10042,TRADE_RETCODE_SHORT_ONLY=10043,TRADE_RETCODE_CLOSE_ONLY=10044,
 TRADE_RETCODE_HEDGE_PROHIBITED=10046
};
#ifndef ENGULF_CORE_HEADER
#define ENGULF_CORE_HEADER "../../MQL5/Experts/InstantEngulf/EngulfCore.mqh"
#endif
#include ENGULF_CORE_HEADER

bool build(const bool buy,const EngulfBar& latest,const EngulfBar& older,double buffer,ScalpPlan &p,ScalpQuote &q) {
    if(!EngulfSignal(buy,latest,older)) return false;
    p=ScalpPlan{}; p.buy=buy; p.orders=1; p.risk_percent=1;
    p.sl=EngulfBufferedStop(buy,latest,older,buffer,props[SYMBOL_POINT],props[SYMBOL_TRADE_TICK_SIZE],int(props[SYMBOL_DIGITS]));
    return ScalpCalculate(p,10000,2,1,30,true,true,10,q,0,true);
}
#ifndef ENGULF_TEST_MAIN
#define ENGULF_TEST_MAIN main
#endif
int ENGULF_TEST_MAIN() {
    PreviousBrokerTests();
    EngulfBar older{3648,3650,3643,3645},up{3645,3653,3644,3652};
    check(EngulfSignal(true,up,older),"BUY close beyond old wick");
    check(!EngulfSignal(false,up,older),"BUY pattern does not authorize SELL");
    auto wick=up; wick.close=3647;
    check(!EngulfSignal(true,wick,older),"wick beyond body without close beyond body fails");
    wick.close=3648;
    check(!EngulfSignal(true,wick,older),"equal body top is not above");
    wick.close=3649.5;
    check(EngulfSignal(true,wick,older),"BUY close above body but below wick now passes");
    EngulfBar down{3648,3654,3640,3642};
    check(EngulfSignal(false,down,older),"SELL close below old wick still passes");
    check(!EngulfSignal(true,down,older),"SELL pattern does not authorize BUY");
    down.close=3645;
    check(!EngulfSignal(false,down,older),"equal body bottom is not below");
    down.close=3644;
    check(EngulfSignal(false,down,older),"SELL close below body but above wick now passes");
    down.close=3646;
    check(!EngulfSignal(false,down,older),"SELL wick-only break does not pass");
    auto bull=older; bull.open=3645; bull.close=3648;
    check(EngulfSignal(true,wick,bull),"bullish older body uses Close as top");
    down.close=3644;
    check(EngulfSignal(false,down,bull),"bullish older body uses Open as bottom");
    auto doji=older; doji.open=doji.close=3647;
    wick.close=3647;
    check(!EngulfSignal(true,wick,doji)&&!EngulfSignal(false,wick,doji),"equal doji body rejects both sides");
    wick.close=3647.5;
    check(EngulfSignal(true,wick,doji),"strictly above doji body passes");
    down.close=3642;
    check(near(EngulfStop(true,up,older),3643),"BUY lowest Low comes from older candle");
    up.low=3641;
    check(near(EngulfStop(true,up,older),3641),"BUY lowest Low comes from latest candle");
    check(near(EngulfStop(false,down,older),3654),"SELL highest High from latest candle");
    older.high=3655;
    check(near(EngulfStop(false,down,older),3655),"SELL highest High from older candle");
    older.high=3650; up.low=3644;
    auto bullish_old=older; bullish_old.open=3644; bullish_old.close=3648;
    check(EngulfSignal(true,up,bullish_old),"no invented opposite-color requirement");
    auto gap=up; gap.open=3652.5;
    check(EngulfSignal(true,gap,older),"close rule is literal even on a gapped candle");
    auto invalid=up; invalid.close=3654;
    check(!EngulfSignal(true,invalid,older),"malformed OHLC rejected");
    invalid=up; invalid.low=NAN;
    check(!EngulfSignal(true,invalid,older),"NaN OHLC rejected");
    check(near(EngulfBufferedStop(true,up,older,0,.01,.01,2),3643),"zero buffer exactly original BUY SL");
    check(near(EngulfBufferedStop(false,down,older,0,.01,.01,2),3654),"zero buffer exactly original SELL SL");
    check(near(EngulfBufferedStop(true,up,older,20,.01,.01,2),3642.8),"BUY buffer subtracts points times point");
    check(near(EngulfBufferedStop(false,down,older,20,.01,.01,2),3654.2),"SELL buffer adds points times point");
    check(near(EngulfBufferedStop(true,up,older,20,.001,.001,3),3642.98),"broker .001 point handled");
    check(near(EngulfBufferedStop(true,up,older,3,.01,.05,2),3642.95),"BUY tick rounding outward");
    check(near(EngulfBufferedStop(false,down,older,3,.01,.05,2),3654.05),"SELL tick rounding outward");
    check(EngulfBufferedStop(true,up,older,-1,.01,.01,2)==0,"negative buffer blocked");
    check(EngulfBufferedStop(true,up,older,NAN,.01,.01,2)==0,"NaN buffer blocked");
    reset(); tick={1000,3652,3652.2}; ScalpPlan p; ScalpQuote q;
    check(build(true,up,older,0,p,q),"BUY broker plan valid");
    check(tick_reads==1,"TP and lot use a single market tick snapshot");
    check(near(p.sl,3643) && near(p.tp,3661.4),"BUY 1:1 from live Ask");
    check(near(q.broker_sl,p.sl) && near(q.broker_tp,p.tp),"BUY no SELL compensation");
    check(near(q.lot,.1) && near(q.strategy_loss,92),"BUY volume floored from strategy risk");
    double old_lot=q.lot,old_tp=p.tp;
    check(build(true,up,older,1000,p,q),"BUY buffer included in sizing");
    check(p.tp>old_tp && q.lot<old_lot,"larger buffer expands TP and reduces lot");
    reset(); tick={1000,3642,3642.2};
    check(build(false,down,older,20,p,q),"SELL broker plan valid");
    check(near(p.sl,3654.2) && near(p.tp,3629.8),"SELL buffered strategy SL/TP symmetric around Bid");
    check(near(q.broker_sl,3654.4) && near(q.broker_tp,3630),"SELL adds spread after buffer to both levels");
    check(q.broker_loss>q.strategy_loss,"compensated actual loss estimate distinct from strategy loss");
    MqlTradeRequest request; string error;
    check(ScalpRequest(p,q,123,20,request,error),"protected market request built");
    check(request.action==TRADE_ACTION_DEAL && request.sl>0 && request.tp>0,"market SL and TP accompany initial request");
#ifndef ENGULF_EXPECTED_REQUEST_COMMENT
#define ENGULF_EXPECTED_REQUEST_COMMENT "InstantEngulf V1"
#endif
    check(request.comment==ENGULF_EXPECTED_REQUEST_COMMENT && request.magic==123,"EA request identity");
    p.tp=1; p.entry=9999; tick.bid=3641.5; tick.ask=3641.7; tick_reads=0;
    check(ScalpCalculate(p,10000,2,1,30,true,true,10,q,0,true),"derive mode discards stale entry and TP");
    check(tick_reads==1 && near(p.entry,3641.5) && near(p.tp,2*p.entry-p.sl),"fresh quote drives all calculations");
    reset(); tick={1000,3642,3642.31};
    check(!build(false,down,older,0,p,q),"pattern cannot bypass max spread");
    check(EngulfResult(true,TRADE_RETCODE_DONE,100,.1,.1,.01)==ENGULF_FILLED,"confirmed full fill");
    check(EngulfResult(true,TRADE_RETCODE_DONE,100,.05,.1,.01)==ENGULF_PARTIAL,"unexpected smaller filled volume");
    check(EngulfResult(true,TRADE_RETCODE_DONE_PARTIAL,100,.05,.1,.01)==ENGULF_PARTIAL,"explicit partial fill");
    check(EngulfResult(true,TRADE_RETCODE_PLACED,0,0,.1,.01)==ENGULF_UNCERTAIN,"accepted is not filled; retain duplicate guard");
    check(EngulfResult(false,TRADE_RETCODE_TIMEOUT,0,0,.1,.01)==ENGULF_UNCERTAIN,"timeout never auto-retries");
    check(EngulfResult(false,TRADE_RETCODE_ERROR,0,0,.1,.01)==ENGULF_UNCERTAIN,"generic error cannot prove no trade");
    check(EngulfResult(false,0,0,0,.1,.01)==ENGULF_UNCERTAIN,"missing result remains uncertain");
    check(EngulfResult(true,TRADE_RETCODE_DONE,0,0,.1,.01)==ENGULF_UNCERTAIN,"DONE without price/volume not falsely reported filled");
    check(EngulfResult(false,TRADE_RETCODE_INVALID_STOPS,0,0,.1,.01)==ENGULF_REJECTED,"definite rejection allows deliberate retry");
    for(int i=0;i<1000;++i) {
        bool buy=i%2==0; reset(); tick=buy ? MqlTick{1000,3652,3652.2} : MqlTick{1000,3642,3642.2};
        check(build(buy,buy ? up : down,older,i,p,q),"generated valid buffer plan");
        check(near(std::abs(p.entry-p.sl),std::abs(p.tp-p.entry)),"1:1 after every buffer setting");
        check(q.strategy_loss<=q.budget+1e-7,"floor sizing never exceeds strategy budget");
        check(buy ? p.sl<=EngulfStop(buy,up,older) : p.sl>=EngulfStop(buy,down,older),"buffer only expands stop");
    }
    std::cout<<"PASS: "<<checks<<" total Instant Engulf checks (includes shared broker regression)\n";
    return 0;
}
