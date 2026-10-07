// Generated validation from indicator 1.12; included inside OnInit.
   g_hunt_tf=InpHuntTF==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpHuntTF;
   g_hunt_seconds=PeriodSeconds(g_hunt_tf);
   g_check_seconds=PeriodSeconds(InpCheckTF);
   if(g_hunt_seconds<=0 || g_hunt_seconds>86400 || PeriodSeconds((ENUM_TIMEFRAMES)_Period)<=0 ||
      PeriodSeconds((ENUM_TIMEFRAMES)_Period)>86400 || InpHuntBars<1 || InpHuntBars>1000 ||
      InpHistoryBars<0 || InpHistoryBars>100000 ||
      (InpHistoryBars>0 && InpHistoryBars<InpHuntBars+1) || InpSearchBars<0 || InpSearchBars>100000 ||
      InpObservationMode<WHA_LIVE_TICK || InpObservationMode>WHA_LOWER_TF_CLOSE ||
      InpCheckHistoryBars<0 || InpCheckHistoryBars>100000 ||
      (InpObservationMode==WHA_LOWER_TF_CLOSE &&
       (InpCheckTF==PERIOD_CURRENT || g_check_seconds<=0 || g_check_seconds>=g_hunt_seconds ||
        g_hunt_seconds%g_check_seconds!=0)) ||
      InpAnchorRule<WHA_FVG_OR_STRONG || InpAnchorRule>WHA_STRONG_ONLY ||
      !MathIsValidNumber(InpMinSweptWickBodyPercent) || InpMinSweptWickBodyPercent<0 ||
      !MathIsValidNumber(InpMinHuntPoints) || InpMinHuntPoints<0 ||
      !MathIsValidNumber(InpMinHuntPoints*_Point) ||
      !MathIsValidNumber(InpStrongHeadWickPercent) || InpStrongHeadWickPercent<0 || InpStrongHeadWickPercent>100 ||
      !MathIsValidNumber(InpMinFVGGapPoints) || InpMinFVGGapPoints<0 ||
      !MathIsValidNumber(InpMinFVGGapPoints*_Point) ||
      InpVisibleSignals<0 || InpVisibleSignals>5000 || InpArrowWidth<1 || InpArrowWidth>5 ||
      InpArrowGapPoints<0 || InpArrowGapPoints>100000) return INIT_PARAMETERS_INCORRECT;
