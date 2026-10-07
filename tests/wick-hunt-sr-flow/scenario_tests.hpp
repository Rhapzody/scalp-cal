// Real higher-TF core and wrapper integration, mirrored through both directions.
MSBar mirror_bar(const MSBar& b) { return {b.time,212-b.open,212-b.low,212-b.high,212-b.close}; }
std::vector<MSBar> context_bars(int direction)
{
    std::vector<MSBar> bars={bar(18000,70,80,65,75),bar(21600,76,102,74,96),
        bar(25200,91,105,90,103),bar(28800,105,111,101,110),bar(32400,109,112,100,105)};
    if(direction==-1) for(auto& b:bars) b=mirror_bar(b);
    return bars;
}
WHCState higher_state(int direction)
{
    WHCState s; WHCReset(s);
    s.level_count=1; s.levels[0]=level(direction,direction==1 ? 110 : 102,18000,14400,direction==1 ? 109 : 103);
    s.trend={direction,true,21600,14400,25200,28800,direction==1 ? 110. : 102.,
        direction==1 ? 70. : 142.,direction==1 ? 120. : 92.};
    return s;
}
void observe_pattern(WSState& s,const WHCState& h,const std::vector<MSBar>& bars,int direction,
                     ENUM_WS_SCENARIO mode=WS_BOTH,double tip=95,long now=36100)
{
    WSContext c={36000,39600,106,100,112,true};
    WSObservePatterns(s,c,h,bars,int(bars.size()),now,direction==1 ? 108 : 212-tip,
                      direction==1 ? tip : 104,106,mode,1,2,5,MS_SR_WICK,0,0,.01,false);
}
bool reclaimed(const WSState& s,int direction) { return direction==1 ? s.buy_reclaimed : s.sell_reclaimed; }
int pattern(const WSState& s,int direction) { return direction==1 ? s.buy_pattern : s.sell_pattern; }

void scenario_tests()
{
    for(int direction:{1,-1}) {
        auto bars=context_bars(direction); auto h=higher_state(direction);
        double tip=direction==1 ? 95 : 117,sr=0; long anchor=0;
        check(WHCFindAnchor(bars,5,tip,direction,0,0,.01,false,anchor) && anchor==25200,"first collision is a strong same-side FVG confirmation body");
        check(!WHCFindAnchor(bars,5,tip,-direction,0,0,.01,false,anchor),"opposite FVG cannot support hunt");
        check(!WHCFindAnchor(bars,5,tip,direction,2,0,.01,false,anchor),"bounded anchor search does not skip outside its window");
        check(WHCFindAnchor(bars,5,tip,direction,3,0,.01,false,anchor),"anchor at search boundary included");
        auto blocked=bars;
        blocked[3]=direction==1 ? bar(28800,105,111,94,110) : mirror_bar(bar(28800,105,111,94,110));
        check(!WHCFindAnchor(blocked,5,tip,direction,0,0,.01,false,anchor),"intervening non-FVG candle blocks older valid anchor");
        auto weak=bars;
        weak[2]=direction==1 ? bar(25200,91,105,90,100.49) : mirror_bar(bar(25200,91,105,90,100.49));
        check(!WHCFindAnchor(weak,5,tip,direction,0,0,.01,false,anchor),"leading wick over thirty percent is weak");
        weak[2]=direction==1 ? bar(25200,91,105,90,100.5) : mirror_bar(bar(25200,91,105,90,100.5));
        check(WHCFindAnchor(weak,5,tip,direction,0,0,.01,false,anchor),"exactly thirty percent leading wick passes old flow rule");
        weak[2]=direction==1 ? bar(25200,96,105,90,103) : mirror_bar(bar(25200,96,105,90,103));
        check(!WHCFindAnchor(weak,5,tip,direction,0,0,.01,false,anchor),"touching confirmation wick instead of body fails");
        check(WHCFindAnchor(bars,5,tip,direction,0,10,1,false,anchor),"FVG minimum exact gap passes");
        check(!WHCFindAnchor(bars,5,tip,direction,0,10.01,1,false,anchor),"FVG smaller than requested gap fails");
        auto gap=bars;
        gap[1]=direction==1 ? bar(21600,76,89,74,88) : mirror_bar(bar(21600,76,89,74,88));
        check(!WHCFindAnchor(gap,5,tip,direction,0,0,.01,false,anchor),"session gap without middle candle coverage fails");
        check(WHCFindTouch(h,bars,5,5,MS_SR_WICK,sr) && sr==h.levels[0].price,"preceding H1 high-low touch qualifies");
        check(WHCFindTouch(h,bars,5,5,MS_SR_WICK,sr,direction),"correct directional main SR may qualify by touch alone");
        auto wrong_side=h; wrong_side.levels[0].type=-direction;
        check(!WHCFindTouch(wrong_side,bars,5,5,MS_SR_WICK,sr,direction),"opposite SR type cannot define directional breakout base");
        WSState directional;
        WSReset(directional,36000); observe_pattern(directional,wrong_side,bars,direction,WS_BREAKOUT);
        check(!reclaimed(directional,direction),"main breakout cannot be paired with wrong SR/hunt direction");
        auto touch_only=h; WHCClearTrend(touch_only.trend);
        WSReset(directional,36000); observe_pattern(directional,touch_only,bars,direction,WS_BREAKOUT);
        check(reclaimed(directional,direction),"main touch needs no closed structural breakout or ready trend");
        auto touched=h;
        touched.levels[0]=level(direction,direction==1 ? 67 : 145,14400,10800,direction==1 ? 67 : 145);
        check(WHCFindTouch(touched,bars,5,5,MS_SR_WICK,sr),"touch exactly fifth previous H1 qualifies");
        check(!WHCFindTouch(touched,bars,5,4,MS_SR_WICK,sr),"sixth/outside chosen touch window fails");
        touched.levels[0].confirm_time=18000;
        check(!WHCFindTouch(touched,bars,5,5,MS_SR_WICK,sr),"SR confirmed on touching candle cannot be backdated");
        touched.levels[0]=level(direction,direction==1 ? 112 : 100,18000,14400,direction==1 ? 100 : 112);
        check(WHCFindTouch(touched,bars,5,1,MS_SR_WICK,sr),"exact candle high-low boundary counts as SR touch");
        check(WHCFindTouch(touched,bars,5,1,MS_SR_BODY,sr) && sr==(direction==1 ? 100 : 112),"context SR honors body anchor");
        check(!WHCFindTouch(touched,bars,4,5,MS_SR_WICK,sr),"insufficient touch history fails");

        for(auto mode:{WS_BREAKOUT,WS_PULLBACK,WS_BOTH}) {
            WSState s; WSReset(s,36000); WSSignal out{};
            observe_pattern(s,h,bars,direction,mode);
            check(reclaimed(s,direction) && pattern(s,direction)==int(mode),"scenario qualifies at live open reclaim in correct direction");
            check(!reclaimed(s,-direction),"same hunt cannot arm opposite direction");
            check(!WSTakeSignal(s,{36000,39600,106,100,112,true},36100,106,direction,out),"H1 context alone never emits without lower-TF breakout");
            auto changed=h; changed.trend.ready=false; changed.level_count=0;
            observe_pattern(s,changed,blocked,direction,mode,94,36120);
            check(pattern(s,direction)==int(mode) && (direction==1 ? s.buy_reclaim_time : s.sell_reclaim_time)==36100,"scenario and first reclaim remain frozen across later quotes");
            s.macd.count=100; s.macd.fast=106; s.macd.slow=106; s.macd.signal=0; s.macd.atr=1;
            s.macd.previous_close=direction==1 ? 105 : 107;
            s.level_count=1; s.levels[0]=level(-direction,106,35400,35100,106);
            WSContext c={36000,39600,106,100,112,true};
            WSProcessClosed(s,config(),bar(36000,106,109,103,direction==1 ? 107 : 105),1,300,c,10,MS_SR_WICK);
            check(WSTakeSignal(s,c,36300,106,direction,out) && out.pattern==int(mode),"later M5 break confirms tagged scenario using independent M5 SR");
            check(out.anchor_time==(mode==WS_PULLBACK ? 0 : 25200) && out.trend_pivot==(mode==WS_BREAKOUT ? 0 : 25200),"signal retains FVG and/or trend provenance");
            check(!WSTakeSignal(s,c,36301,106,direction,out),"same-direction scenario emits once per H1");
            WSBeginSetup(s,39600);
            check(pattern(s,direction)==0 && !reclaimed(s,direction),"H1 rollover clears scenario and reclaim facts");
        }
        WSState s; auto not_ready=h; not_ready.trend.ready=false;
        WSReset(s,36000); observe_pattern(s,not_ready,bars,direction,WS_PULLBACK);
        check(!reclaimed(s,direction),"break without confirmed terminal H1 swing is not yet pullback");
        not_ready=h; not_ready.trend.direction=-direction;
        WSReset(s,36000); observe_pattern(s,not_ready,bars,direction,WS_PULLBACK);
        check(!reclaimed(s,direction),"countertrend hunt rejected in pullback mode");
        not_ready=h; not_ready.trend.confirm_time=36000;
        WSReset(s,36000); observe_pattern(s,not_ready,bars,direction,WS_PULLBACK);
        check(!reclaimed(s,direction),"future/unavailable terminal swing rejected");
        not_ready=h; not_ready.trend.pivot_price=direction==1 ? 90 : 122;
        WSReset(s,36000); observe_pattern(s,not_ready,bars,direction,WS_PULLBACK);
        check(!reclaimed(s,direction),"must retrace from terminal swing rather than hunt elsewhere");
        WSReset(s,36000); observe_pattern(s,h,blocked,direction,WS_PULLBACK);
        check(!reclaimed(s,direction),"sweeping only nearest H1 wick fails two-wick pullback");
        WSReset(s,36000); observe_pattern(s,h,blocked,direction,WS_PULLBACK,94);
        check(!reclaimed(s,direction),"equality at second wick is not a sweep");
        WSReset(s,36000); observe_pattern(s,h,blocked,direction,WS_PULLBACK,93.99);
        check(reclaimed(s,direction),"one current H1 extreme strictly beyond both wicks qualifies");
        WSReset(s,36000); observe_pattern(s,h,weak,direction,WS_BOTH);
        check(pattern(s,direction)==2,"failed FVG breakout does not suppress valid pullback");
        WSReset(s,36000); observe_pattern(s,h,bars,direction,WS_BOTH,100);
        check(!reclaimed(s,direction),"equal nearest H1 wick fails both scenarios");
        WSReset(s,36000); observe_pattern(s,h,bars,direction,WS_BOTH,95,39600);
        check(!reclaimed(s,direction),"reclaim at expired H1 boundary fails");
        WSReset(s,36000); observe_pattern(s,h,bars,direction,WS_BOTH);
        check(ScenarioText(pattern(s,direction))=="Breakout + Pullback","both conditions labeled as one signal with both tags");
    }

    // Actual structural trend creation, then terminal swing confirmation, then reversal.
    for(int direction:{1,-1}) {
        WHCState h; WHCReset(h);
        h.level_count=2;
        h.levels[0]=level(-direction,direction==1 ? 80 : 132,25200,21600,direction==1 ? 81 : 131);
        h.levels[1]=level(direction,direction==1 ? 110 : 102,28800,25200,direction==1 ? 109 : 103);
        h.macd.count=100; h.macd.fast=direction==1 ? 109 : 103; h.macd.slow=h.macd.fast; h.macd.signal=0;
        h.macd.previous_close=h.macd.fast; h.macd.atr=1; h.macd.direction=direction; h.macd.extreme=direction==1 ? 111 : 101;
        h.macd.extreme_time=32400; h.macd.extreme_index=9;
        MSBar breakout=bar(36000,109,113,106,112),terminal=bar(39600,112,115,100,105),opposite=bar(43200,105,108,78,79);
        if(direction==-1) { breakout=mirror_bar(breakout); terminal=mirror_bar(terminal); opposite=mirror_bar(opposite); }
        auto unavailable=h; unavailable.levels[1].confirm_time=36000;
        check(!WHCStartTrend(unavailable,breakout,h.macd.previous_close,MS_SR_WICK,direction),"H1 breakout cannot use SR confirmed on its own candle");
        unavailable=h; unavailable.levels[0].confirm_time=36000;
        check(!WHCStartTrend(unavailable,breakout,h.macd.previous_close,MS_SR_WICK,direction),"trend requires an already confirmed origin swing");
        check(WHCProcessClosed(h,config(),breakout,10,10,MS_SR_WICK),"closed H1 trend breakout processes");
        check(h.trend.direction==direction && !h.trend.ready && h.trend.origin_time==21600 && h.trend.sr==(direction==1 ? 110 : 102),"origin swing and directional SR breakout establish pending context");
        check(WHCProcessClosed(h,config(),terminal,11,10,MS_SR_WICK),"subsequent H1 swing confirmation processes");
        check(h.trend.ready && h.trend.pivot_time==39600 && h.trend.pivot_price==(direction==1 ? 115 : 97),"only confirmed post-breakout terminal swing enables trend pullback");
        check(WHCProcessClosed(h,config(),opposite,12,10,MS_SR_WICK),"opposite structural breakdown processes");
        check(h.trend.direction==-direction && !h.trend.ready,"opposite structural break replaces preceding trend context");
        check(!WHCProcessClosed(h,config(),bar(46800,100,99,90,100),13,10,MS_SR_WICK) && h.level_count==0 && h.trend.direction==0,"invalid H1 resets trend and SR instead of carrying stale context");
    }

    // Wrapper loads/replays actual CLOSED H1 history; forming H1 must not affect its MACD.
    fixture(); InpScenario=WS_BOTH; high_rates.clear();
    for(int i=0;i<50;i++) { double price=100+std::sin(i*.5)*5; high_rates.push_back({18000+i*3600,price,price+1,price-1,price}); }
    long opened=high_rates.back().time; g_context.time=opened; g_context.end_time=opened+3600;
    check(ReplayHigher(opened+10) && g_higher.macd.count==49 && g_higher_bars.size()==49,"wrapper excludes forming H1 from histogram, trend and FVG");
    double hist=g_higher.macd.histogram;
    high_rates.back().close=120; high_rates.back().high=121;
    check(ReplayHigher(opened+20) && g_higher.macd.histogram==hist,"forming H1 changes do not change confirmed higher-TF context");
    high_rates.back().high=121; high_rates.push_back({opened+3600,120,121,119,120});
    g_context.time=opened+3600; g_context.end_time=opened+7200;
    check(ReplayHigher(opened+3610) && g_higher.macd.count==50,"new H1 advances context while independent lower-TF confirmation continues");
    // Full UpdateLive using a ready bearish/bullish context and observed two-wick reclaim.
    for(int direction:{1,-1}) {
        fixture(); InpScenario=WS_PULLBACK; g_higher=higher_state(direction);
        g_higher_bars=context_bars(direction); g_higher_open=36000; g_higher_available=3;
        high_rates={{28800,106,111,101,108},{32400,106,112,100,105},{36000,106,108,95,106}};
        if(direction==-1) for(auto& r:high_rates) { auto b=mirror_bar({r.time,r.open,r.high,r.low,r.close}); r={b.time,b.open,b.high,b.low,b.close}; }
        WSReset(g_state,36000); live_tick={36650,106,106};
        OnTimer(); check(reclaimed(g_state,direction) && pattern(g_state,direction)==2 && g_signals.empty(),"actual timer arms only correct trend-side two-wick hunt and waits for M5");
        g_state.macd.count=100; g_state.macd.previous_close=direction==1 ? 105 : 107;
        g_state.level_count=1; g_state.levels[0]=level(-direction,106,35400,35100,106);
        WSProcessClosed(g_state,config(),bar(36600,106,109,103,direction==1 ? 107 : 105),1,300,g_context,10,MS_SR_WICK);
        low_rates={{36900,106,109,103,106}}; g_lower_open=36900; live_tick.time=36920;
        OnTimer(); check(g_signals.size()==1 && g_signals[0].pattern==2 && PatternBuffer[0]==2 && TrendPivotBuffer[0]==25200 && FVGTimeBuffer[0]==EMPTY_VALUE,"actual timer and buffers publish pullback metadata after later M5 close");
    }
    fixture(); g_state.buy_pattern=3; g_state.buy_anchor_time=25200; g_state.buy_trend_pivot=28800; g_state.buy_context_sr=110;
    low_rates.clear(); for(int i=0;i<140;i++) { double price=100+std::sin(i*.5)*5; low_rates.push_back({1000+i*300,price,price+1,price-1,price}); }
    g_force_replay=true;
    check(ReplayLower(low_rates.back().time+10) && g_state.buy_pattern==3 && g_state.buy_anchor_time==25200 && g_state.buy_trend_pivot==28800 && g_state.buy_context_sr==110,"actual M5 replay preserves frozen scenario provenance");
    fixture(); WSSignal first{},last{};
    first.time=36600; first.price=106; first.direction=1; first.pattern=1; first.context_sr=110; first.anchor_time=25200;
    last.time=36900; last.price=106; last.direction=-1; last.pattern=2; last.context_sr=102; last.trend_pivot=28800;
    g_signals={first,last}; MapOutput();
    check(PatternBuffer[0]==2 && ContextSRBuffer[0]==102 && FVGTimeBuffer[0]==EMPTY_VALUE && TrendPivotBuffer[0]==28800,"latest chart-bar metadata cannot retain an earlier signal's unused FVG field");
}
