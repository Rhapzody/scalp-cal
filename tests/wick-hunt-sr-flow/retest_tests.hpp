// v1.03: first break, immediate next close holds the SAME SR, live retest.
void retest_tests()
{
    for(int direction:{1,-1}) {
        auto process=[&](WSState& s,long time,double close) {
            return WSProcessClosed(s,config(),bar(time,100,104,96,close),1,60,context(),10,MS_SR_WICK,8);
        };
        auto begin=[&](WSState& s) {
            prime(s,-direction,100);
            s.macd.previous_close=direction==1 ? 99 : 101;
            WSObserve(s,context(),36001,111,89,100);
            process(s,36060,direction==1 ? 101 : 99);
        };
        auto pending=[&](const WSState& s) { return direction==1 ? s.buy_break : s.sell_break; };
        WSState s; WSSignal out{}; begin(s);
        check(pending(s).valid && pending(s).price==100,"first break freezes the SR for both directions");
        check(!WSTakeSignal(s,context(),36120,100,direction,out),"first break cannot signal at a touch");
        process(s,36120,direction==1 ? 102 : 98);
        check(pending(s).hold_close_time==36180 && pending(s).retest_deadline==36660,"eight-bar window starts after second close");
        check(!WSTakeSignal(s,context(),36179,100,direction,out),"cannot enter before second close");
        check(!WSTakeSignal(s,context(),36180,direction==1 ? 100.01 : 99.99,direction,out),"holding beyond SR alone is not a retest");
        check(WSTakeSignal(s,context(),36180,100,direction,out),"first waiting bar exact SR touch enters");
        check(out.hold_time==36180 && out.retest_bar==1 && out.break_time==36060,"entry retains first break and hold provenance");
        check(!WSTakeSignal(s,context(),36181,100,direction,out),"retest entry emits once");

        begin(s); process(s,36120,100);
        check(!pending(s).valid,"second close equal SR discards candidate");
        check(!WSTakeSignal(s,context(),36180,100,direction,out),"rejected second candle cannot later retest");
        // A later fresh cross may retry; failure is not an entry or setup latch.
        s.macd.previous_close=100;
        process(s,36180,direction==1 ? 101 : 99);
        check(pending(s).valid && pending(s).bar_time==36180,"fresh cross after failed hold can start a new candidate");
        begin(s); process(s,36120,direction==1 ? 99.99 : 100.01);
        check(!pending(s).valid,"second close on wrong side discards candidate");
        begin(s); process(s,36180,direction==1 ? 102 : 98);
        check(!pending(s).valid,"missing immediate successor cannot be replaced by a later holding candle");

        begin(s); process(s,36120,direction==1 ? 102 : 98);
        // A new swing may remove the selected level; its frozen SR stays valid.
        s.level_count=1; s.levels[0]=level(direction,direction==1 ? 103 : 97,36120,36060);
        process(s,36180,direction==1 ? 104 : 96);
        check(pending(s).price==100 && pending(s).bar_time==36060,"later swing/cross cannot replace a waiting SR");
        check(!WSTakeSignal(s,context(),36659,direction==1 ? 101 : 99,direction,out),"waiting eight bars without retest gives no entry");
        check(WSTakeSignal(s,context(),36659,direction==1 ? 99.99 : 100.01,direction,out) && out.retest_bar==8,"last quote of eighth waiting bar can retest by crossing SR");
        begin(s); process(s,36120,direction==1 ? 102 : 98);
        check(!WSTakeSignal(s,context(),36660,100,direction,out),"ninth bar open is expired even on exact SR");
        begin(s); process(s,36120,direction==1 ? 102 : 98);
        WSBeginSetup(s,39600);
        check(!pending(s).valid,"main-TF rollover clears waiting retest");
        begin(s); process(s,36120,direction==1 ? 102 : 98);
        WSProcessClosed(s,config(),bar(36180,100,99,101,100),1,60,context(),10,MS_SR_WICK,8);
        check(!pending(s).valid,"invalid OHLC clears holding candidate");
        begin(s); process(s,36120,direction==1 ? 102 : 98);
        check(!WSTakeSignal(s,context(),36200,std::numeric_limits<double>::quiet_NaN(),direction,out),"invalid quote cannot retest");
    }
    // Actual timer body uses the live quote, not this candle's pre-hold low.
    fixture(); InpRetestBars=8;
    g_state.buy_break.retest_bars=8; g_state.buy_break.hold_close_time=36900;
    g_state.buy_break.retest_deadline=39300;
    low_rates={{36900,100,101,97,100}}; g_lower_open=36900;
    live_tick={36910,100,100}; OnTimer();
    check(g_signals.empty(),"timer does not infer retest from the forming candle low");
    live_tick={36911,98,98}; OnTimer();
    check(g_signals.size()==1 && g_signals[0].retest_bar==1 && g_signals[0].hold_time==36900,"timer emits on the new live SR touch");
    OnTimer(); check(g_signals.size()==1,"timer retest dedup survives subsequent observations");
    fixture();
}
