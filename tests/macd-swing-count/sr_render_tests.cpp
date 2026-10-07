#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <map>
#include <string>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
template<class A,class B> double MathMax(A a,B b) { return std::max(double(a),double(b)); }
#include "../../MQL5/Indicators/MACDSwingCount/SwingCore.mqh"
using string=std::string;
using datetime=long long;
enum ENUM_TIMEFRAMES { PERIOD_CURRENT=0 };
const int _Period=0,_Digits=2,OBJ_TREND=1,STYLE_SOLID=0;
enum { OBJPROP_RAY_LEFT,OBJPROP_RAY_RIGHT,OBJPROP_COLOR,OBJPROP_WIDTH,OBJPROP_STYLE,
       OBJPROP_BACK,OBJPROP_SELECTABLE,OBJPROP_HIDDEN,OBJPROP_TOOLTIP };
bool InpShowSR=true;
int InpSRCount=2,InpSRWidth=2,InpResistanceColor=10,InpSupportColor=20;
ENUM_MS_SR_ANCHOR InpSRAnchor=MS_SR_WICK;
string g_prefix="instance1_";
std::vector<MSEvent> g_events;
int g_event_count=0;
struct Object { int type=0; datetime first=0,second=0; double p1=0,p2=0; std::map<int,long> props; string tooltip; };
std::map<string,Object> objects;
int PeriodSeconds(ENUM_TIMEFRAMES) { return 60; }
string IntegerToString(int n) { return std::to_string(n); }
string DoubleToString(double n,int) { return std::to_string(n); }
void ObjectsDeleteAll(long,const string& prefix)
{
    for(auto it=objects.begin();it!=objects.end();) {
        if(it->first.find(prefix)==0) it=objects.erase(it); else ++it;
    }
}
bool ObjectCreate(long,const string& name,int type,int,datetime t1,double p1,datetime t2,double p2)
{
    Object o; o.type=type; o.first=t1; o.second=t2; o.p1=p1; o.p2=p2; objects[name]=o; return true;
}
void ObjectSetInteger(long,const string& name,int prop,long value) { objects.at(name).props[prop]=value; }
void ObjectSetString(long,const string& name,int prop,const string& value) { objects.at(name).tooltip=value; }
#include "sr_render_under_test.hpp"
int checks=0;
void check(bool ok,const char* reason)
{
    ++checks; if(!ok) { std::cerr<<"FAIL: "<<reason<<'\n'; std::exit(1); }
}
int ownLevels()
{
    int n=0;
    for(auto pair:objects) if(pair.first.find(g_prefix+"sr_")==0) n++;
    return n;
}
MSEvent event(int type,long time,double wick,double body)
{
    MSEvent e{}; e.type=type; e.pivot_time=time; e.confirm_time=time+120; e.price=wick; e.body_price=body; return e;
}
int main()
{
    objects["instance2_sr_1"]=Object{};
    objects["instance1_view_label_1"]=Object{};
    objects["instance1_view_line_1"]=Object{};
    g_events={event(1,1000,130,115),event(-1,1060,70,85),event(1,1120,140,120)};
    g_event_count=3;
    RenderSRLevels();
    check(ownLevels()==2,"count is latest N swings combined, independent of other chart objects");
    auto resistance=objects.at("instance1_sr_1"),support=objects.at("instance1_sr_2");
    check(resistance.type==OBJ_TREND && resistance.p1==140 && resistance.p2==140,"resistance ray is horizontal at high wick");
    check(support.p1==70 && support.p2==70,"support ray is horizontal at low wick");
    check(resistance.first==1120 && resistance.second==1180,"ray starts at pivot with distinct time anchors");
    check(resistance.props[OBJPROP_RAY_RIGHT]==1 && resistance.props[OBJPROP_RAY_LEFT]==0,"ray extends right only");
    check(resistance.props[OBJPROP_COLOR]==10 && support.props[OBJPROP_COLOR]==20,"separate resistance/support colors");
    check(resistance.props[OBJPROP_WIDTH]==2,"line width applied");
    check(objects.count("instance2_sr_1")==1 && objects.count("instance1_view_label_1")==1 && objects.count("instance1_view_line_1")==1,
          "SR render preserves another instance, labels and connecting lines");
    InpSRAnchor=MS_SR_BODY; RenderSRLevels();
    check(objects.at("instance1_sr_1").p1==120 && objects.at("instance1_sr_2").p1==85,"body mode uses upper high body and lower low body");
    check(objects.at("instance1_sr_1").tooltip.find("swing body")!=string::npos,"tooltip identifies body anchor");
    InpSRCount=1; RenderSRLevels(); check(ownLevels()==1 && objects.count("instance1_sr_2")==0,"reducing count deletes older levels");
    InpSRCount=0; RenderSRLevels(); check(ownLevels()==0,"zero count hides levels");
    InpSRCount=1000; RenderSRLevels(); check(ownLevels()==3,"fewer confirmed swings than requested draws available swings only");
    InpShowSR=false; RenderSRLevels(); check(ownLevels()==0,"turn off removes own levels");
    check(objects.count("instance2_sr_1")==1 && objects.count("instance1_view_label_1")==1,"turn off preserves unrelated objects");
    InpShowSR=true; g_event_count=0; RenderSRLevels(); check(ownLevels()==0,"no history yields no lines");
    g_events={event(-1,2000,0,5),event(1,2060,-5,-10)}; g_event_count=2;
    InpSRAnchor=MS_SR_WICK; RenderSRLevels();
    check(objects.at("instance1_sr_2").p1==0 && objects.at("instance1_sr_1").p1==-5,"zero and negative levels supported");
    auto count=objects.size(); g_prefix=""; RenderSRLevels(); check(objects.size()==count,"empty prefix cannot delete unrelated lines");
    std::cout<<"MACD Swing S/R renderer: "<<checks<<" checks passed\n";
}
