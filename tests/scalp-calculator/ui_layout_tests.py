#!/usr/bin/env python3
"""Exercise production Render/MeasureLayout with a recording MT5 object adapter.

Models Consolas metrics at 96/144/192 DPI; checks object bounds, pairwise
collisions, pagination, collapse/expand and font API failure. This is geometry
regression coverage, not a substitute for native MT5 visual testing.
No trading API is invoked. Requires clang++ and the sibling broker adapter.
"""
from pathlib import Path
import re
import subprocess
import tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'MQL5/Experts/ScalpCalculator/ScalpCalculator.mq5').read_text()
prefix=s[s.index('enum ENUM_SCALP_RISK_BASE'):s.index('void StateSet')]
prefix=re.sub(r'^input group .*\n','',prefix,flags=re.M).replace('input ','')
prefix=re.sub(r"C'(\d+),(\d+),(\d+)'",lambda m:str(int(m[1])+(int(m[2])<<8)+(int(m[3])<<16)),prefix)
render=s[s.index('void Render()'):s.index('void Refresh()')]
head=r'''
#define main broker_test_main
#include "BROKER_PATH"
#undef main
#include <fstream>
#include <cassert>
#include <iomanip>
#include <sstream>
#undef MathMax
#define MathRound std::round
#define MathCeil std::ceil
template<class A,class B> double MathMax(A a,B b) {return a>b?a:b;}
template<class A,class B> double MathMin(A a,B b) {return a<b?a:b;}
using color=int;
const int _Digits=2; const double _Point=.01;
enum { TERMINAL_SCREEN_DPI=1000,CHART_WIDTH_IN_PIXELS,CHART_HEIGHT_IN_PIXELS,ACCOUNT_BALANCE,ACCOUNT_CURRENCY,
OBJ_LABEL,OBJ_BUTTON,OBJ_RECTANGLE_LABEL,OBJPROP_CORNER,OBJPROP_ANCHOR,OBJPROP_XDISTANCE,OBJPROP_YDISTANCE,OBJPROP_COLOR,
OBJPROP_FONTSIZE,OBJPROP_FONT,OBJPROP_SELECTABLE,OBJPROP_HIDDEN,OBJPROP_ZORDER,OBJPROP_TEXT,OBJPROP_TOOLTIP,OBJPROP_XSIZE,
OBJPROP_YSIZE,OBJPROP_BGCOLOR,OBJPROP_BORDER_COLOR,OBJPROP_BORDER_TYPE,CORNER_LEFT_UPPER,ANCHOR_RIGHT_UPPER,ANCHOR_LEFT_UPPER,BORDER_FLAT };
int chart_width=900,chart_height=900,dpi=96,measure_font=9;
bool metrics_ok=true;
struct Object {int type=0; std::map<int,long> p; std::map<int,string> s;};
std::map<string,Object> objects;
int ObjectFind(int,const string &n){return objects.count(n)?0:-1;}
void ObjectCreate(int,const string &n,int t,int,int,int){objects[n].type=t;}
void ObjectSetInteger(int,const string &n,int p,long v){objects[n].p[p]=v;}
void ObjectSetString(int,const string &n,int p,const string &v){objects[n].s[p]=v;}
string ObjectGetString(int,const string &n,int p){return objects[n].s[p];}
void ObjectDelete(int,const string &n){objects.erase(n);}
void ObjectsDeleteAll(int,const string &prefix){for(auto it=objects.begin();it!=objects.end();) if(it->first.find(prefix)==0)it=objects.erase(it);else ++it;}
int ChartGetInteger(int,int p){return p==CHART_WIDTH_IN_PIXELS?chart_width:chart_height;}
void ChartRedraw(){}
bool TextSetFont(const string&,int f,int){measure_font=-f/10;return metrics_ok;}
bool TextGetSize(const string &s,uint &w,uint &h){w=std::ceil(s.size()*measure_font*dpi/72.*.61);h=std::ceil(measure_font*dpi/72.*1.18);return true;}
string AccountInfoString(int){return "USD";}
int StringLen(const string&s){return s.size();}
string StringSubstr(const string&s,int start,int count=-1){return s.substr(start,count<0?string::npos:count);}
int StringGetCharacter(const string&s,int pos){return s.at(pos);}
string IntegerToString(long v){return std::to_string(v);}
string DoubleToString(double v,int digits){std::ostringstream o;o<<std::fixed<<std::setprecision(digits)<<v;return o.str();}
template<class... A> string StringFormat(const char *f,A... a){char buf[512];std::snprintf(buf,sizeof(buf),f,a...);return buf;}
void DeleteUI();
string Countdown(){return "M1  00:00 (wait bar)";}
'''.replace('BROKER_PATH',str(root/'tests/scalp-calculator/broker_tests.cpp'))
tail=r'''
struct Rect{string name;double x,y,w,h;};
void validate(){
 std::vector<Rect> rs;
 for(auto &entry:objects){auto &o=entry.second;if(o.type!=OBJ_LABEL&&o.type!=OBJ_BUTTON)continue;
  double x=o.p[OBJPROP_XDISTANCE]-g_x,y=o.p[OBJPROP_YDISTANCE]-g_y;
  int f=o.p[OBJPROP_FONTSIZE]; string t=o.s[OBJPROP_TEXT];
  double w=o.type==OBJ_BUTTON?o.p[OBJPROP_XSIZE]:std::ceil(t.size()*f*dpi/72.*.61);
  double h=o.type==OBJ_BUTTON?o.p[OBJPROP_YSIZE]:std::ceil(f*dpi/72.*1.18);
  if(o.p[OBJPROP_ANCHOR]==ANCHOR_RIGHT_UPPER)x-=w;
  int ph=objects[Obj("ui.background")].p[OBJPROP_YSIZE];
  if(t.empty())continue;
  if(x<0||y<0||x+w>g_width||y+h>ph){std::cerr<<"bounds "<<entry.first<<" chart "<<chart_width<<"x"<<chart_height<<" dpi "<<dpi<<" rect "<<x<<","<<y<<","<<w<<","<<h<<" panel "<<g_width<<","<<ph<<"\n";exit(1);}
  rs.push_back({entry.first,x,y,w,h});
 }
 for(size_t i=0;i<rs.size();i++)for(size_t j=i+1;j<rs.size();j++){auto a=rs[i],b=rs[j];
 if(a.x<b.x+b.w&&b.x<a.x+a.w&&a.y<b.y+b.h&&b.y<a.y+a.h){std::cerr<<"overlap "<<a.name<<" "<<b.name<<" chart "<<chart_width<<"x"<<chart_height<<" dpi "<<dpi<<"\n";exit(1);}}
}
int main(){
 int buffer_checks_before=checks;
 for(bool isbuy:{false,true})for(bool pending:{false,true})for(double buffer:{0.,15.,150.}){
   reset();g_plan=isbuy?buy():sell();g_plan.pending=pending;
   if(pending)g_plan.entry=isbuy?3649:3651;
   InpSLBufferPoints=buffer;
   auto original=g_plan;auto plan=ManualPlan();auto repeat=ManualPlan();
   check(near(plan.sl,original.sl+(isbuy?-1:1)*buffer*.01),"manual buffer direction and units");
   check(near(g_plan.sl,original.sl)&&near(repeat.sl,plan.sl),"manual refresh cannot accumulate buffer");
   check(near(plan.tp,original.tp)&&near(plan.entry,original.entry),"manual TP and entry retained");
   ScalpQuote quote;check(calculate(plan,quote),"buffered market and pending sizing valid");
   check(quote.strategy_loss<=100+1e-7,"buffered lot respects total setup strategy budget");
   MqlTradeRequest request;string reason;
   check(ScalpRequest(plan,quote,42,20,request,reason),"buffered request builds");
   check(near(request.sl,plan.sl+(isbuy?0:.2)),"request combines buffer and SELL spread once");
   check(near(request.tp,original.tp+(isbuy?0:.2)),"buffer does not move broker TP");
 }
 std::cout<<checks-buffer_checks_before<<" manual buffer integration checks passed\n";
 InpSLBufferPoints=0;
 reset();g_active=true;g_plan=buy();g_plan.sl=4342.09;g_plan.tp=4363.09;g_quote.entry=4349.09;g_quote.tick={1000,4348.75,4349.09};g_quote.spread=.34;
 g_status="Set Initial Balance in Inputs";g_result="Rearmed by user";
 int cases=0;
 for(bool show:{false,true})for(int d:{96,144,192})for(int w:{240,314,480,900})for(int h:{240,362,500,720,1080})for(double scale:{.5,1.,2.}){
 InpShowInstantEngulf=show;dpi=d;props[TERMINAL_SCREEN_DPI]=d;chart_width=w;chart_height=h;InpPanelScale=scale;
 g_collapsed=false;Render();validate();cases++;
 if(!g_tiny){for(int p=0;p<g_page_count;p++){g_page=p;Render();validate();cases++;}g_page=0;Render();validate();cases++;}
 g_collapsed=true;DeleteUI();Render();validate();cases++;
 g_collapsed=false;DeleteUI();
 }
 // Missing font API uses the conservative DPI estimate.
 metrics_ok=false;dpi=96;props[TERMINAL_SCREEN_DPI]=96;chart_width=900;chart_height=720;InpPanelScale=1;Render();validate();cases++;metrics_ok=true;
 // Verify latch styling even after automatic/manual Clear removed the setup.
 int latch_checks=0;
 for(bool active:{false,true})for(bool latched:{false,true}){
   g_active=active;g_latched=latched;g_ready=active;g_status=active?"Ready":"Choose BUY / SELL";
   ApplyRearmStatus();Render();validate();cases++;
   auto &execute=objects[Obj("ui.execute")];auto &rearm=objects[Obj("ui.rearm")];
   check(execute.p[OBJPROP_BGCOLOR]==(latched?RED:active?GREEN:CARD),"execute color reflects latch and readiness");
   check(rearm.p[OBJPROP_BGCOLOR]==(latched?GOLD:CARD),"rearm highlighted only when needed");
   check(rearm.s[OBJPROP_TOOLTIP].find(latched?"NEW batch":"No batch lock")!=string::npos,"rearm tooltip explains batch action");
   if(latched){check(!g_ready&&g_status.find("REARM REQUIRED")==0,"latch status survives Clear");
     check(execute.s[OBJPROP_TEXT]=="LOCKED - REARM","locked execution label");}
   latch_checks+=latched?5:3;
 }
 g_busy=true;g_latched=true;g_ready=false;Render();validate();cases++;
 check(objects[Obj("ui.rearm")].s[OBJPROP_TEXT]=="PLEASE WAIT","sending does not invite rearm");latch_checks++;
 std::cout<<latch_checks<<" rearm UI state checks passed\n";
 std::cout<<cases<<" UI layout scenarios passed (simulated metrics; no native MT5 rendering)\n";

}
'''
with tempfile.TemporaryDirectory(prefix="scalp-ui-tests-") as temp:
    source=Path(temp)/"layout.cpp"
    binary=Path(temp)/"layout"
    source.write_text(head+prefix+render+tail)
    subprocess.run(["clang++", "-std=c++17", "-O2", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
