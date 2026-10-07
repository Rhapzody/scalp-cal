#property copyright "Scalp Calculator"
#property version   "1.05"
#property description "Manual strategy-line position sizer and execution panel for MT5."
#property description "Risk is strategy price risk; broker loss can differ. No automatic entries."
#property strict
#include "ScalpBroker.mqh"
#include "EngulfCore.mqh"
#include "EngulfTiming.mqh"

enum ENUM_SCALP_RISK_BASE { SCALP_INITIAL_BALANCE=0, SCALP_CURRENT_BALANCE=1 };
input group "Risk and size"
input ENUM_SCALP_RISK_BASE InpRiskBase=SCALP_INITIAL_BALANCE;
input double InpInitialBalance=0; // Enter actual initial account balance; never inferred
input double InpRiskPreset1=0.5;
input double InpRiskPreset2=1.0;
input double InpRiskPreset3=1.5;
input double InpRiskPreset4=2.0;
input double InpDefaultRisk=1.0;
input int InpDefaultOrders=1;
input double InpMaxRiskPercent=2.0;
input int InpMaxOrders=5;
input group "Execution"
input ulong InpMagicNumber=26091201;
input bool InpSellSpreadCompensation=true;
input double InpMaxSpreadPoints=30; // MT5 points, NOT pips or price units
input ulong InpDeviationPoints=20;
input bool InpFreezeGuard=true; // Conservative placement guard outside freeze zone
input int InpMaxQuoteAgeSeconds=10;
input bool InpClearAfterExecute=false;
input bool InpEnableAtStart=true;
input group "Instant Engulf - one market order per click"
input bool InpShowInstantEngulf=true; // Show the independent Instant Buy / Sell section
input double InpEngulfRiskPercent=1.0; // Independent of manual risk presets and Orders
input double InpEngulfSLBufferPoints=0; // Extra beyond the two closed candles, in MT5 points
input ulong InpEngulfMagicNumber=26091202; // Same default identity as standalone InstantEngulf
input bool InpEngulfOneOrderPerSignal=true;
input group "Setup and panel"
input double InpSLBufferPoints=0; // Manual only: extra beyond the SL line, in MT5 points
input double InpDefaultSLPoints=700;
input double InpDefaultRR=2.0;
input double InpPendingOffsetPoints=200;
input int InpPanelX=16;
input int InpPanelY=20;
input double InpPanelScale=1.0;

const string PREFIX="SCALP_V1.";
const color BG=C'17,24,39', CARD=C'30,41,59', INK=C'226,232,240', MUTED=C'148,163,184';
const color GOLD=C'251,191,36', GREEN=C'52,211,153', RED=C'251,113,133', BLUE=C'56,189,248';
ScalpPlan g_plan;
ScalpQuote g_quote;
bool g_active=false,g_enabled=true,g_collapsed=false,g_busy=false,g_latched=false,g_ready=false;
string g_status="Choose BUY or SELL to create a setup",g_result="",g_detail="";
ulong g_engulf_last_click=0;
string g_engulf_pa="Waiting for candles",g_engulf_bar_time="--",g_engulf_pair="--";
bool g_engulf_has_signal=false,g_engulf_valid=false;
ScalpPlan g_engulf_plan;
ScalpQuote g_engulf_quote;

string Obj(const string suffix) { return PREFIX+suffix; }
double RiskBase() { return InpRiskBase==SCALP_INITIAL_BALANCE ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE); }
ScalpPlan ManualPlan()
{
   ScalpPlan plan=g_plan;
   ScalpSpec spec;
   if(!ScalpReadSpec(spec)) { plan.sl=0; return plan; }
   plan.sl=ScalpBufferedStop(plan.buy,plan.sl,InpSLBufferPoints,spec.point,spec.tick_size,spec.digits);
   return plan;
}
string Price(const double value) { return DoubleToString(value,_Digits); }
string Money(const double value) { return DoubleToString(value,2)+" "+AccountInfoString(ACCOUNT_CURRENCY); }
string Lots(const double value)
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   int digits=2;
   for(int i=2;i<=8;i++) { digits=i; if(MathAbs(step-NormalizeDouble(step,i))<1e-10) break; }
   return DoubleToString(value,digits);
}

void SetText(const string name,const string value)
{
   if(ObjectGetString(0,name,OBJPROP_TEXT)!=value) ObjectSetString(0,name,OBJPROP_TEXT,value);
}

// Clear removes the plan but deliberately does not reset the batch latch.
void ApplyRearmStatus()
{
   if(!g_latched) return;
   g_ready=false;
   g_status=g_active ? "REARM REQUIRED - review last batch before a new batch" :
                      "REARM REQUIRED - also create a new BUY / SELL setup";
}

// All geometry is in physical chart pixels. Fonts are measured at the same
// point size as OBJ_LABEL, including the terminal's DPI scaling.
int g_width=460,g_height=740,g_x=16,g_y=20,g_font=9,g_text_height=16;
int g_pad=12,g_gap=8,g_button_height=30,g_body_y=0,g_row_height=26,g_visible_rows=1;
int g_page=0,g_page_count=1,g_footer_y=0,g_layout_id=-1;
bool g_stacked=false,g_tiny=false;
int PanelRows() { return InpShowInstantEngulf ? 31 : 23; }

int TextWidth(const string text,const int font)
{
   uint width=0,height=0;
   if(TextSetFont("Consolas",-10*font,0) && TextGetSize(text,width,height)) return (int)width;
   return (int)MathCeil(StringLen(text)*font*TerminalInfoInteger(TERMINAL_SCREEN_DPI)/72.0);
}

string FitText(const string text,const int width,const int font)
{
   if(width<=0) return "";
   if(TextWidth(text,font)<=width) return text;
   string cut=text;
   while(StringLen(cut)>0 && TextWidth(cut+"...",font)>width) cut=StringSubstr(cut,0,StringLen(cut)-1);
   return TextWidth(cut+"...",font)<=width ? cut+"..." : "";
}

void MeasureLayout()
{
   int old_font=g_font,old_text_height=g_text_height;
   int chart_w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int chart_h=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   bool compact=chart_h<520;
   g_font=(int)MathMax(8,MathRound((compact ? 8 : 9)*InpPanelScale));
   uint width=0,height=0;
   g_text_height=(int)MathCeil(g_font*TerminalInfoInteger(TERMINAL_SCREEN_DPI)/72.0*1.4)+2;
   if(TextSetFont("Consolas",-10*g_font,0) && TextGetSize("Ag09",width,height))
      g_text_height=(int)height+2;
   g_pad=(int)MathMax(8,MathRound((compact ? 8 : 12)*InpPanelScale));
   g_gap=(int)MathMax(5,MathRound((compact ? 5 : 8)*InpPanelScale));
   g_button_height=g_text_height+(compact ? 8 : 14);
   g_x=(int)MathMin(InpPanelX,MathMax(0,chart_w-260));
   g_y=(int)MathMin(InpPanelY,MathMax(0,chart_h-300));
   int available_w=(int)MathMax(1,chart_w-g_x-8);
   int available_h=(int)MathMax(1,chart_h-g_y-8);
   int preferred_w=(int)MathMax(380,460*InpPanelScale);
   g_width=(int)MathMin(preferred_w,available_w);
   g_stacked=(g_width-2*g_pad)*0.43<TextWidth("Broker reward est.",g_font)+2;
   g_row_height=g_stacked ? 2*g_text_height+8 : g_text_height+10;
   // Header: title, clock, side/mode, presets, order count. Navigation below.
   int header=2*g_pad+2*g_text_height+3*(g_button_height+g_gap);
   if(InpShowInstantEngulf) header+=g_text_height+g_button_height+2*g_gap;
   int nav=g_button_height+g_gap;
   int footer=2*g_button_height+2*g_gap+3*g_text_height+2*g_pad;
   g_body_y=header+nav;
   int full_height=g_body_y+PanelRows()*g_row_height+footer;
   g_height=(int)MathMin(full_height,available_h);
   int minimum_width=(int)MathMax(240,2*g_pad+TextWidth("Orders 100",g_font)+2*g_button_height+3*g_gap+60);
   g_tiny=g_width<minimum_width || g_height<g_body_y+g_row_height+footer;
   g_footer_y=g_height-footer;
   g_visible_rows=(int)MathMax(1,(g_footer_y-g_body_y)/g_row_height);
   g_page_count=(PanelRows()+g_visible_rows-1)/g_visible_rows;
   g_page=(int)MathMin(g_page,g_page_count-1);
   int id=g_width+10000*g_height+(g_stacked ? 100000000 : 0);
   if(id!=g_layout_id || old_font!=g_font || old_text_height!=g_text_height) { DeleteUI(); g_layout_id=id; }
}

void Label(const string suffix,const int x,const int y,const string text,const color ink=C'226,232,240',
           const int size=0,const int max_width=0,const bool right=false)
{
   string name=Obj("ui."+suffix);
   int font=size>0 ? size : g_font;
   int room=max_width>0 ? max_width : g_width-g_pad-x;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,g_x+x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,g_y+y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,font);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,12);
   SetText(name,FitText(text,room-2,font));
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
}

void Button(const string suffix,const int x,const int y,const int width,const string text,
            const color bg=C'30,41,59',const color ink=C'226,232,240')
{
   string name=Obj("ui."+suffix);
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,g_x+x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,g_y+y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,g_button_height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,bg);
   int font=g_font;
   while(font>8 && TextWidth(text,font)>width-10) font--;
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,font);
   ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,20);
   SetText(name,FitText(text,width-10,font));
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
}

void Row(const int index,const string key,const string value,const color ink=C'226,232,240')
{
   int local=index-g_page*g_visible_rows;
   if(local<0 || local>=g_visible_rows) return;
   int y=g_body_y+local*g_row_height;
   if(g_stacked)
   {
      Label("key"+IntegerToString(local),g_pad,y,key,MUTED);
      Label("value"+IntegerToString(local),g_pad,y+g_text_height,value,ink);
   }
   else
   {
      int key_width=(int)((g_width-2*g_pad)*0.43);
      Label("key"+IntegerToString(local),g_pad,y,key,MUTED,0,key_width);
      Label("value"+IntegerToString(local),g_width-g_pad,y,value,ink,0,
            g_width-2*g_pad-key_width-g_gap,true);
   }
}

void DeleteUI() { ObjectsDeleteAll(0,Obj("ui.")); }
void DeleteLines()
{
   ObjectDelete(0,Obj("SL")); ObjectDelete(0,Obj("TP")); ObjectDelete(0,Obj("ENTRY"));
}

void StateSet(const string key,const string value)
{
   string name=Obj("state."+key);
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   SetText(name,value);
}
string StateGet(const string key) { return ObjectGetString(0,Obj("state."+key),OBJPROP_TEXT); }
void SaveState()
{
   StateSet("symbol",_Symbol);
   StateSet("account",IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"@"+AccountInfoString(ACCOUNT_SERVER));
   StateSet("active",g_active ? "1" : "0");
   StateSet("buy",g_plan.buy ? "1" : "0");
   StateSet("pending",g_plan.pending ? "1" : "0");
   StateSet("risk",DoubleToString(g_plan.risk_percent,8));
   StateSet("orders",IntegerToString(g_plan.orders));
   StateSet("entry",DoubleToString(g_plan.entry,10));
   StateSet("sl",DoubleToString(g_plan.sl,10));
   StateSet("tp",DoubleToString(g_plan.tp,10));
   StateSet("enabled",g_enabled ? "1" : "0");
   StateSet("collapsed",g_collapsed ? "1" : "0");
   StateSet("latched",g_latched ? "1" : "0");
   StateSet("result",g_result); StateSet("detail",g_detail);
}

bool RestoreState()
{
   if(StateGet("symbol")!=_Symbol || StateGet("account")!=IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"@"+AccountInfoString(ACCOUNT_SERVER)) return false;
   g_active=StateGet("active")=="1"; g_plan.buy=StateGet("buy")=="1";
   g_plan.pending=StateGet("pending")=="1";
   g_plan.risk_percent=StringToDouble(StateGet("risk"));
   g_plan.orders=(int)StringToInteger(StateGet("orders"));
   g_plan.entry=StringToDouble(StateGet("entry"));
   g_plan.sl=StringToDouble(StateGet("sl")); g_plan.tp=StringToDouble(StateGet("tp"));
   g_enabled=StateGet("enabled")=="1"; g_collapsed=StateGet("collapsed")=="1";
   g_latched=StateGet("latched")=="1";
   g_result=StateGet("result"); g_detail=StateGet("detail");
   return true;
}

void Line(const string suffix,const double price,const color ink)
{
   string name=Obj(suffix);
   bool created=ObjectFind(0,name)<0;
   if(created) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   if(created) ObjectSetInteger(0,name,OBJPROP_SELECTED,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetString(0,name,OBJPROP_TEXT,"Scalp strategy "+suffix);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"Strategy "+suffix+" | drag to adjust setup (not an existing trade)");
}

void SyncLines()
{
   if(!g_active) { DeleteLines(); return; }
   Line("SL",g_plan.sl,RED); Line("TP",g_plan.tp,GREEN);
   if(g_plan.pending) Line("ENTRY",g_plan.entry,BLUE); else ObjectDelete(0,Obj("ENTRY"));
}

datetime ServerNow() { return EngulfServerNow(); }

string Countdown()
{
   string tf=EnumToString((ENUM_TIMEFRAMES)_Period); StringReplace(tf,"PERIOD_","");
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return tf+"  OFFLINE";
   datetime opened=iTime(_Symbol,_Period,0);
   if(opened<=0) return tf+"  --:--";
   datetime next=EngulfBarClose(opened);
   int left=(int)MathMax(0,(double)(next-ServerNow()));
   if(left==0) return tf+"  00:00 (wait bar)";
   if(left>=3600) return tf+"  "+StringFormat("%02d:%02d:%02d",left/3600,(left%3600)/60,left%60);
   return tf+"  "+StringFormat("%02d:%02d",left/60,left%60);
}

void Render()
{
   MeasureLayout();
   int header_height=2*g_pad+2*g_text_height;
   int height=g_collapsed || g_tiny ? (int)MathMin(g_height,header_height+g_text_height+g_pad) : g_height;
   string bg=Obj("ui.background");
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,g_x);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,g_y);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,g_width); ObjectSetInteger(0,bg,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,BG); ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,CARD); ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true); ObjectSetInteger(0,bg,OBJPROP_ZORDER,10);
   int hide_width=TextWidth("SHOW",g_font)+18;
   Label("title",g_pad,g_pad,"SCALP / "+_Symbol,GOLD,0,g_width-3*g_pad-hide_width);
   Button("hide",g_width-g_pad-hide_width,g_pad,hide_width,g_collapsed ? "SHOW" : "HIDE");
   Label("clock",g_pad,g_pad+g_text_height+5,Countdown(),INK,0,g_width-3*g_pad-hide_width);
   if(g_collapsed || g_tiny)
   {
      Label("small",g_pad,header_height,g_tiny ? "Enlarge chart to show trading controls" : "Panel hidden",MUTED);
      ChartRedraw(); return;
   }
   int content=g_width-2*g_pad;
   int cell=(content-3*g_gap)/4;
   int y=header_height;
   Button("buy",g_pad,y,cell,"BUY",g_active && g_plan.buy ? GREEN : CARD,g_active && g_plan.buy ? BG : INK);
   Button("sell",g_pad+cell+g_gap,y,cell,"SELL",g_active && !g_plan.buy ? RED : CARD,g_active && !g_plan.buy ? BG : INK);
   Button("market",g_pad+2*(cell+g_gap),y,cell,"MARKET",!g_plan.pending ? BLUE : CARD,!g_plan.pending ? BG : INK);
   Button("pending",g_pad+3*(cell+g_gap),y,cell,"PENDING",g_plan.pending ? BLUE : CARD,g_plan.pending ? BG : INK);
   y+=g_button_height+g_gap;
   double presets[4]={InpRiskPreset1,InpRiskPreset2,InpRiskPreset3,InpRiskPreset4};
   for(int i=0;i<4;i++)
      Button("risk"+IntegerToString(i),g_pad+i*(cell+g_gap),y,cell,DoubleToString(presets[i],2)+"%",
             MathAbs(g_plan.risk_percent-presets[i])<1e-8 ? GOLD : CARD,
             MathAbs(g_plan.risk_percent-presets[i])<1e-8 ? BG : INK);
   y+=g_button_height+g_gap;
   int order_width=TextWidth("Orders 100",g_font)+g_gap;
   Label("orders",g_pad,y+6,"Orders "+IntegerToString(g_plan.orders),INK,0,order_width);
   Button("minus",g_pad+order_width,y,g_button_height,"-");
   Button("plus",g_pad+order_width+g_button_height+g_gap,y,g_button_height,"+");
   int mode_x=g_pad+order_width+2*g_button_height+2*g_gap;
   Label("mode",mode_x,y+6,g_active ? ScalpTypeName(g_quote.type) : "NO SETUP",MUTED);
   y+=g_button_height+g_gap;
   if(InpShowInstantEngulf)
   {
      Label("engulf.caption",g_pad,y,g_engulf_pair+" / "+g_engulf_pa+" / Risk "+DoubleToString(InpEngulfRiskPercent,2)+"%",GOLD);
      ObjectSetString(0,Obj("ui.engulf.caption"),OBJPROP_TOOLTIP,
                      g_engulf_pair+" | "+g_engulf_pa+" | one market order | risk "+DoubleToString(InpEngulfRiskPercent,2)+
                      "% | RR 1:1 | buffer "+DoubleToString(InpEngulfSLBufferPoints,1)+" pts | SELL spread ON");
      y+=g_text_height+g_gap;
      int half=(content-g_gap)/2;
      Button("instant_buy",g_pad,y,half,"INSTANT BUY",g_enabled ? GREEN : CARD,g_enabled ? BG : MUTED);
      Button("instant_sell",g_pad+half+g_gap,y,content-half-g_gap,"INSTANT SELL",g_enabled ? RED : CARD,g_enabled ? BG : MUTED);
      y+=g_button_height+g_gap;
   }
   Label("page",g_pad,y+6,StringFormat("DETAILS %d / %d",g_page+1,g_page_count),MUTED,0,content-2*g_button_height-2*g_gap);
   Button("previous",g_width-g_pad-2*g_button_height-g_gap,y,g_button_height,"<",CARD,g_page>0 ? INK : MUTED);
   Button("next",g_width-g_pad-g_button_height,y,g_button_height,">",CARD,g_page+1<g_page_count ? INK : MUTED);
   for(int i=(int)MathMin(g_visible_rows,PanelRows()-g_page*g_visible_rows);i<g_visible_rows;i++)
   {
      ObjectDelete(0,Obj("ui.key"+IntegerToString(i)));
      ObjectDelete(0,Obj("ui.value"+IntegerToString(i)));
   }
   ScalpPlan manual=ManualPlan();
   string dash="--";
   bool calc=g_active && g_quote.entry>0;
   Row(0,"Entry",calc ? Price(g_quote.entry) : dash);
   Row(1,"Strategy SL",g_active ? Price(manual.sl) : dash,RED);
   Row(2,"Strategy TP",g_active ? Price(g_plan.tp) : dash,GREEN);
   Row(3,"Strategy RR",calc ? "1 : "+DoubleToString(ScalpRR(g_quote.entry,manual.sl,manual.tp),2) : dash,GOLD);
   Row(4,"Risk target",DoubleToString(g_plan.risk_percent,2)+"% / "+Money(RiskBase()*g_plan.risk_percent/100));
   Row(5,"Lot per order",calc && g_quote.lot>0 ? Lots(g_quote.lot)+" x "+IntegerToString(g_plan.orders) : dash,GOLD);
   Row(6,"Spread price / pts",Price(g_quote.spread)+" / "+DoubleToString(g_quote.spread/_Point,1),g_quote.spread/_Point>InpMaxSpreadPoints ? RED : INK);
   Row(7,"SL price / pts",calc ? Price(MathAbs(g_quote.entry-manual.sl))+" / "+DoubleToString(MathAbs(g_quote.entry-manual.sl)/_Point,1) : dash);
   Row(8,"TP price / pts",calc ? Price(MathAbs(g_quote.entry-g_plan.tp))+" / "+DoubleToString(MathAbs(g_quote.entry-g_plan.tp)/_Point,1) : dash);
   Row(9,InpRiskBase==SCALP_INITIAL_BALANCE ? "Initial balance" : "Current balance",Money(RiskBase()));
   Row(10,"Strategy loss",calc && g_quote.strategy_loss>0 ? Money(g_quote.strategy_loss) : dash);
   Row(11,"Broker SL",calc ? Price(g_quote.broker_sl) : dash);
   Row(12,"Broker TP",calc ? Price(g_quote.broker_tp) : dash);
   Row(13,"Broker loss est.",calc && g_quote.broker_loss>0 ? Money(g_quote.broker_loss) : dash,calc && g_quote.broker_loss>g_quote.budget+0.01 ? GOLD : INK);
   Row(14,"Broker reward est.",calc && g_quote.broker_reward>0 ? Money(g_quote.broker_reward) : dash);
   Row(15,"Margin est.",calc && g_quote.margin>0 ? Money(g_quote.margin) : dash);
   Row(16,"Bid / Ask",Price(g_quote.tick.bid)+" / "+Price(g_quote.tick.ask));
   Row(17,"Account mode",AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "HEDGING" : "NETTING");
   Row(18,"SELL spread",InpSellSpreadCompensation ? "ON" : "OFF");
   Row(19,"Max spread",DoubleToString(InpMaxSpreadPoints,1)+" pts");
   Row(20,"Estimates exclude","Fees, swap, slippage");
   Row(21,"Manual SL line",g_active ? Price(g_plan.sl) : dash,RED);
   Row(22,"Manual SL buffer",DoubleToString(InpSLBufferPoints,1)+" pts");
   if(InpShowInstantEngulf)
   {
      Row(23,"Engulf PA",g_engulf_pa,GOLD);
      Row(24,"Engulf Risk",DoubleToString(InpEngulfRiskPercent,2)+"% / "+Money(RiskBase()*InpEngulfRiskPercent/100));
      Row(25,"Engulf SL",g_engulf_has_signal && g_engulf_plan.sl>0 ? Price(g_engulf_plan.sl) : dash,RED);
      Row(26,"Engulf TP 1:1",g_engulf_has_signal && g_engulf_plan.tp>0 ? Price(g_engulf_plan.tp) : dash,GREEN);
      Row(27,"Engulf lot",g_engulf_valid ? Lots(g_engulf_quote.lot) : dash);
      Row(28,"Engulf broker loss",g_engulf_valid ? Money(g_engulf_quote.broker_loss) : dash);
      Row(29,"Engulf SL buffer",DoubleToString(InpEngulfSLBufferPoints,1)+" pts");
      Row(30,"Engulf signal bar",g_engulf_bar_time);
   }
   y=g_footer_y+g_gap;
   int enabled_width=TextWidth("EA OFF",g_font)+20;
   string execute_text=g_busy ? "SENDING..." : (g_latched ? "LOCKED - REARM" :
                       (g_ready ? (g_plan.buy ? "EXECUTE BUY" : "EXECUTE SELL") : "EXECUTE DISABLED"));
   color execute_bg=g_busy ? GOLD : (g_latched ? RED : (g_ready ? GREEN : CARD));
   color execute_ink=g_busy || g_ready || g_latched ? BG : MUTED;
   Button("execute",g_pad,y,content-enabled_width-g_gap,execute_text,execute_bg,execute_ink);
   Button("enabled",g_width-g_pad-enabled_width,y,enabled_width,g_enabled ? "EA ON" : "EA OFF",g_enabled ? CARD : RED,g_enabled ? GREEN : BG);
   y+=g_button_height+g_gap;
   int clear_width=TextWidth("CLEAR",g_font)+24;
   Button("clear",g_pad,y,clear_width,"CLEAR");
   Button("rearm",g_pad+clear_width+g_gap,y,content-clear_width-g_gap,
          g_busy ? "PLEASE WAIT" : (g_latched ? "REARM REQUIRED" : "REARM: NOT NEEDED"),
          g_latched && !g_busy ? GOLD : CARD,g_latched && !g_busy ? BG : MUTED);
   ObjectSetString(0,Obj("ui.rearm"),OBJPROP_TOOLTIP,g_latched ?
                   "Review Trade / History, then unlock a NEW batch. This does not retry missing orders." :
                   "No batch lock. Execute still requires a valid setup and trading permissions.");
   y+=g_button_height+g_gap;
   // Two bounded status lines; full messages remain available via tooltip.
   string first=g_status,rest="";
   if(TextWidth(first,g_font)>content)
   {
      int split=StringLen(first);
      while(split>0 && TextWidth(StringSubstr(first,0,split),g_font)>content) split--;
      int word=split;
      while(word>0 && StringGetCharacter(first,word-1)!=32) word--;
      if(word>0) split=word;
      rest=StringSubstr(first,split); first=StringSubstr(first,0,split);
   }
   Label("status",g_pad,y,first,g_latched ? RED : (g_ready ? GREEN : GOLD));
   Label("status2",g_pad,y+g_text_height,rest,g_latched ? RED : (g_ready ? GREEN : GOLD));
   Label("result",g_pad,y+2*g_text_height,g_result,INK);
   ObjectSetString(0,Obj("ui.status"),OBJPROP_TOOLTIP,g_status);
   ObjectSetString(0,Obj("ui.status2"),OBJPROP_TOOLTIP,g_status);
   ObjectSetString(0,Obj("ui.result"),OBJPROP_TOOLTIP,g_result+"\n"+g_detail);
   ChartRedraw();
}

void Refresh()
{
   if(g_busy) return;
   bool lines_present=!g_active || (ObjectFind(0,Obj("SL"))>=0 && ObjectFind(0,Obj("TP"))>=0 &&
                                   (!g_plan.pending || ObjectFind(0,Obj("ENTRY"))>=0));
   // Read chart objects on each refresh too, so native dragging updates the
   // calculator while the mouse is held, not only on the drop event.
   if(g_active && lines_present)
   {
      ScalpSpec spec;
      if(ScalpReadSpec(spec))
      {
         double sl=ScalpSnap(ObjectGetDouble(0,Obj("SL"),OBJPROP_PRICE),spec.tick_size,spec.digits);
         double tp=ScalpSnap(ObjectGetDouble(0,Obj("TP"),OBJPROP_PRICE),spec.tick_size,spec.digits);
         if(sl!=g_plan.sl)
         {
            tp=ScalpSnap(ScalpFollowTP(g_plan.buy,g_plan.sl,sl,tp),spec.tick_size,spec.digits);
            ObjectSetDouble(0,Obj("TP"),OBJPROP_PRICE,tp);
         }
         g_plan.sl=sl; g_plan.tp=tp;
         if(g_plan.pending) g_plan.entry=ScalpSnap(ObjectGetDouble(0,Obj("ENTRY"),OBJPROP_PRICE),spec.tick_size,spec.digits);
      }
   }
   ZeroMemory(g_quote);
   SymbolInfoTick(_Symbol,g_quote.tick);
   g_quote.spread=g_quote.tick.ask-g_quote.tick.bid;
   g_ready=false;
   if(!g_active) g_status="Choose BUY or SELL to create a setup";
   else
   {
      ScalpPlan manual=ManualPlan();
      ScalpCalculate(manual,RiskBase(),InpMaxRiskPercent,InpMaxOrders,InpMaxSpreadPoints,
                     InpSellSpreadCompensation,InpFreezeGuard,InpMaxQuoteAgeSeconds,g_quote);
      g_ready=g_quote.valid;
      if(g_ready && !ScalpGeometry(g_plan.buy,g_quote.entry,g_plan.sl,g_plan.tp))
      { g_ready=false; g_quote.reason="SL line / TP must be on the valid side of entry"; }
      g_status=g_quote.reason;
      if(!lines_present) { g_ready=false; g_status="Setup line missing; choose BUY / SELL to rebuild"; }
      if(g_ready && ScalpNettingExposure()) { g_ready=false; g_status="Netting: symbol already has exposure"; }
      if(g_ready && !ScalpPermissions(g_status)) g_ready=false;
      if(!g_enabled) { g_ready=false; g_status="EA OFF - calculator remains active"; }
   }
   ApplyRearmStatus();
   RefreshEngulfPreview();
   Render();
}

void NewSetup(const bool buy)
{
   MqlTick tick; ScalpSpec spec;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || !ScalpReadSpec(spec))
   { g_result="Waiting for a valid quote"; return; }
   double entry=buy ? tick.ask : tick.bid;
   if(g_plan.pending) entry+=(buy ? -1 : 1)*InpPendingOffsetPoints*spec.point;
   double distance=MathMax(InpDefaultSLPoints*spec.point,MathMax(spec.stops,spec.freeze)+tick.ask-tick.bid+spec.tick_size*2);
   g_plan.buy=buy;
   g_plan.entry=ScalpSnap(entry,spec.tick_size,spec.digits);
   g_plan.sl=ScalpSnap(entry+(buy ? -distance : distance),spec.tick_size,spec.digits);
   g_plan.tp=ScalpSnap(entry+(buy ? distance : -distance)*InpDefaultRR,spec.tick_size,spec.digits);
   g_active=true;
   // A result latch survives line, risk and side changes; only REARM unlocks it.
   SyncLines(); SaveState();
}

bool FrozenLevelsValid(const ScalpPlan &p,const ScalpQuote &live,const ScalpQuote &snapshot)
{
   if(!ScalpGeometry(p.buy,live.entry,snapshot.broker_sl,snapshot.broker_tp)) return false;
   double anchor=p.pending ? snapshot.entry : (p.buy ? live.tick.bid : live.tick.ask);
   return ScalpDistanceOK(p.buy ? anchor-snapshot.broker_sl : snapshot.broker_sl-anchor,
                          live.spec.stops,live.spec.freeze,InpFreezeGuard && !p.pending,live.spec.tick_size) &&
          ScalpDistanceOK(p.buy ? snapshot.broker_tp-anchor : anchor-snapshot.broker_tp,
                          live.spec.stops,live.spec.freeze,InpFreezeGuard && !p.pending,live.spec.tick_size);
}

void Execute()
{
   if(g_busy) return;
   Refresh();
   if(!g_ready) { Alert("Scalp Calculator: ",g_status); return; }
   g_busy=true; g_ready=false; g_latched=true; SaveState(); Render();
   ScalpPlan plan=ManualPlan();
   ScalpQuote snapshot=g_quote;
   int completed=0,accepted=0,partial=0;
   double consumed=0;
   string reason="",details="";
   for(int i=0;i<plan.orders;i++)
   {
      ScalpQuote live;
      if(!ScalpPermissions(reason)) break;
      if(!ScalpCalculate(plan,RiskBase(),InpMaxRiskPercent,InpMaxOrders,InpMaxSpreadPoints,
                         InpSellSpreadCompensation,InpFreezeGuard,InpMaxQuoteAgeSeconds,live,plan.orders-i))
      { reason=live.reason; break; }
      if(plan.pending && live.type!=snapshot.type) { reason="Market crossed pending entry; remaining orders stopped"; break; }
      if(!FrozenLevelsValid(plan,live,snapshot)) { reason="Market moved: fixed broker stops no longer valid"; break; }
      // Every ticket uses the same lot and SL/TP captured at Execute.
      // If prices make the remaining equal lots exceed strategy budget, stop.
      if(consumed+live.loss_per_lot*snapshot.lot*(plan.orders-i)>snapshot.budget+1e-7)
      { reason="Price moved: equal lots would exceed strategy budget"; break; }
      live.lot=snapshot.lot; live.broker_sl=snapshot.broker_sl; live.broker_tp=snapshot.broker_tp;
      if(plan.pending) { live.entry=snapshot.entry; live.type=snapshot.type; }
      MqlTradeRequest request; MqlTradeCheckResult check={}; MqlTradeResult result={};
      if(!ScalpRequest(plan,live,InpMagicNumber,InpDeviationPoints,request,reason)) break;
      ResetLastError();
      if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE))
      { reason=StringFormat("Check %u: %s (error %d)",check.retcode,check.comment,GetLastError()); break; }
      ResetLastError();
      bool sent=OrderSend(request,result);
      string item=StringFormat("#%d code=%u order=%I64u deal=%I64u lot=%.8f price=%.*f SL=%.*f TP=%.*f: %s",
                                i+1,result.retcode,result.order,result.deal,request.volume,_Digits,result.price,
                                _Digits,request.sl,_Digits,request.tp,result.comment);
      Print("Scalp Calculator ",item); details+=item+"\n";
      if(!sent || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_PLACED && result.retcode!=TRADE_RETCODE_DONE_PARTIAL))
      { reason=StringFormat("Send %u: %s; no automatic retry",result.retcode,result.comment); break; }
      if(result.retcode==TRADE_RETCODE_DONE_PARTIAL)
      { partial++; reason="Partial fill; remainder of batch stopped"; break; }
      if(!plan.pending && (result.retcode==TRADE_RETCODE_PLACED || result.price<=0 || result.volume<=0))
      { accepted++; reason="Accepted; fill unconfirmed. Check Trade / History"; break; }
      completed++;
      if(plan.pending) consumed+=snapshot.loss_per_lot*snapshot.lot;
      else
      {
         double pnl=0;
         if(!OrderCalcProfit(plan.buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,result.volume,result.price,plan.sl,pnl))
         { reason="Fill risk unavailable; remaining orders stopped"; break; }
         consumed+=MathMax(0.0,-pnl);
         if(MathAbs(result.volume-snapshot.lot)>snapshot.spec.step*1e-6)
         { reason="Filled volume differs; remaining orders stopped"; break; }
         if(consumed>snapshot.budget+1e-7) { reason="Slippage exceeded strategy budget"; break; }
      }
   }
   string verb=plan.pending ? "placed" : "filled";
   g_result=StringFormat("%d/%d %s",completed,plan.orders,verb);
   if(partial>0) g_result+=" + partial fill";
   if(accepted>0) g_result+=" + accepted (unconfirmed)";
   if(completed==plan.orders && reason=="") g_result="SUCCESS: "+g_result;
   else g_result="REVIEW: "+g_result;
   g_detail=reason+"\n"+details;
   Print("Scalp Calculator ",g_result," ",g_detail);
   if(reason!="") Alert("Scalp Calculator: ",g_result,"\n",reason);
   if(completed==plan.orders && reason=="" && InpClearAfterExecute) { g_active=false; DeleteLines(); }
   g_busy=false; SaveState(); Refresh();
}

#include "ScalpEngulf.mqh"

int OnInit()
{
   if(InpMaxOrders<1 || InpMaxOrders>100 || InpDefaultOrders<1 || InpDefaultOrders>InpMaxOrders ||
      InpMaxRiskPercent<=0 || InpDefaultRisk<=0 || InpDefaultRisk>InpMaxRiskPercent ||
      !MathIsValidNumber(InpSLBufferPoints) || InpSLBufferPoints<0 ||
      !MathIsValidNumber(InpSLBufferPoints*_Point) ||
      InpDefaultSLPoints<=0 || InpDefaultRR<=0 || InpPendingOffsetPoints<=0 ||
      InpMaxSpreadPoints<=0 || InpMaxQuoteAgeSeconds<1 || InpPanelScale<0.5 || InpPanelScale>2 ||
      InpPanelX<0 || InpPanelY<0 || InpInitialBalance<0 ||
      (InpShowInstantEngulf && (!MathIsValidNumber(InpEngulfRiskPercent) || InpEngulfRiskPercent<=0 ||
       InpEngulfRiskPercent>InpMaxRiskPercent || !MathIsValidNumber(InpEngulfSLBufferPoints) || InpEngulfSLBufferPoints<0)))
   { Print("Scalp Calculator: invalid Inputs"); return INIT_PARAMETERS_INCORRECT; }
   double presets[4]={InpRiskPreset1,InpRiskPreset2,InpRiskPreset3,InpRiskPreset4};
   for(int i=0;i<4;i++) if(presets[i]<=0 || presets[i]>InpMaxRiskPercent)
   { Print("Risk presets must be positive and <= Max Risk"); return INIT_PARAMETERS_INCORRECT; }
   g_plan.buy=true; g_plan.pending=false;
   g_plan.risk_percent=InpDefaultRisk; g_plan.orders=InpDefaultOrders;
   g_enabled=InpEnableAtStart;
   if(!RestoreState()) ObjectsDeleteAll(0,PREFIX);
   DeleteUI(); SyncLines(); SaveState();
   if(!EventSetMillisecondTimer(250)) return INIT_FAILED;
   Refresh();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(reason==REASON_CHARTCHANGE) { SaveState(); DeleteUI(); }
   else ObjectsDeleteAll(0,PREFIX);
   ChartRedraw();
}
void OnTick() { Refresh(); }
void OnTimer() { Refresh(); }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(g_busy) return;
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      Refresh(); return;
   }
   if((id==CHARTEVENT_OBJECT_DRAG || id==CHARTEVENT_OBJECT_CHANGE) && g_active)
   {
      ScalpSpec spec; if(!ScalpReadSpec(spec)) return;
      if(sparam==Obj("SL"))
      {
         double value=ScalpSnap(ObjectGetDouble(0,sparam,OBJPROP_PRICE),spec.tick_size,spec.digits);
         g_plan.tp=ScalpSnap(ScalpFollowTP(g_plan.buy,g_plan.sl,value,g_plan.tp),spec.tick_size,spec.digits);
         g_plan.sl=value;
      }
      else if(sparam==Obj("TP")) g_plan.tp=ScalpSnap(ObjectGetDouble(0,sparam,OBJPROP_PRICE),spec.tick_size,spec.digits);
      else if(sparam==Obj("ENTRY") && g_plan.pending) g_plan.entry=ScalpSnap(ObjectGetDouble(0,sparam,OBJPROP_PRICE),spec.tick_size,spec.digits);
      else return;
      SyncLines(); SaveState(); Refresh(); return;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK || StringFind(sparam,Obj("ui."))!=0) return;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   string action=StringSubstr(sparam,StringLen(Obj("ui.")));
   if(action=="previous") { g_page=(int)MathMax(0,g_page-1); Refresh(); return; }
   if(action=="next") { g_page=(int)MathMin(g_page_count-1,g_page+1); Refresh(); return; }
   if(action=="instant_buy" || action=="instant_sell") { ExecuteEngulf(action=="instant_buy"); return; }
   if(action=="execute") { Execute(); return; }
   if(action=="buy" || action=="sell") NewSetup(action=="buy");
   if(action=="market" || action=="pending")
   {
      bool pending=action=="pending";
      if(g_plan.pending!=pending)
      {
         g_plan.pending=pending;
         if(g_active && pending)
         {
            MqlTick tick; ScalpSpec spec;
            if(SymbolInfoTick(_Symbol,tick) && ScalpReadSpec(spec))
               g_plan.entry=ScalpSnap((g_plan.buy ? tick.ask : tick.bid)+(g_plan.buy ? -1 : 1)*InpPendingOffsetPoints*spec.point,spec.tick_size,spec.digits);
         }
         SyncLines();
      }
   }
   if(action=="risk0") g_plan.risk_percent=InpRiskPreset1;
   if(action=="risk1") g_plan.risk_percent=InpRiskPreset2;
   if(action=="risk2") g_plan.risk_percent=InpRiskPreset3;
   if(action=="risk3") g_plan.risk_percent=InpRiskPreset4;
   if(action=="minus") g_plan.orders=(int)MathMax(1,g_plan.orders-1);
   if(action=="plus") g_plan.orders=(int)MathMin(InpMaxOrders,g_plan.orders+1);
   if(action=="enabled") g_enabled=!g_enabled;
   if(action=="clear") { g_active=false; DeleteLines(); }
   if(action=="hide") { g_collapsed=!g_collapsed; DeleteUI(); }
   if(action=="rearm") { g_latched=false; g_result="Rearmed by user"; g_detail=""; }
   SaveState(); Refresh();
}
