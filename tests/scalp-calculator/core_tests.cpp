// Run the production .mqh functions directly, with only MQL numeric primitives
// mapped to the host C++ runtime. No copied calculation implementation.
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <random>
#define MathIsValidNumber std::isfinite
#define MathRound std::round
#define MathFloor std::floor
#define MathMax std::max
#define MathAbs std::abs
double NormalizeDouble(double value,int digits) {
    double scale=std::pow(10.,digits); return std::round(value*scale)/scale;
}
#include "../../MQL5/Experts/ScalpCalculator/ScalpCore.mqh"

int checks=0;
void check(bool condition,const char* description) {
    ++checks;
    if(!condition) { std::cerr << "FAIL: " << description << '\n'; std::exit(1); }
}
bool near(double a,double b) { return std::abs(a-b)<1e-8; }
int main() {
    check(near(ScalpLot(100,1,700,.01),.14),"$100 budget / $700 per lot -> .14");
    check(near(ScalpLot(100,2,700,.01),.07),"risk is divided between two equal orders");
    check(near(ScalpLot(15,2,100,.01),.07),".15 total / 2 -> .07 each, not .08 + .07");
    check(near(ScalpLot(1.5,2,100,.01),0),"under minimum floors to zero");
    check(near(ScalpFloorVolume(.149,.01),.14),"floor, never nearest");
    check(near(ScalpFloorVolume(.3,.1),.3),"binary decimal boundary");
    check(near(ScalpFloorVolume(.02999999999,.01),.02),"do not round almost .03 upward");
    check(near(ScalpFloorVolume(.74,.25),.5),"non-decimal step .25");
    check(near(ScalpFloorVolume(.0019,.001),.001),"three-digit lot step");
    check(ScalpLot(100,0,700,.01)==0,"zero orders");
    check(ScalpLot(100,2,0,.01)==0,"zero loss");
    check(ScalpFloorVolume(NAN,.01)==0,"NaN volume");
    check(ScalpFloorVolume(INFINITY,.01)==0,"infinite volume");
    check(ScalpSnap(3650.03,.05,2)==3650.05,"tick size differs from point");
    check(near(ScalpSnap(1.100125,.00001,5),1.10013),"five-digit price");
    check(ScalpGeometry(true,3650,3643,3664),"buy direction");
    check(ScalpGeometry(false,3650,3657,3636),"sell direction");
    check(!ScalpGeometry(true,3650,3650,3664),"SL at entry blocked");
    check(!ScalpGeometry(false,3650,3657,3651),"sell TP wrong side");
    check(!ScalpGeometry(true,3650,NAN,3664),"NaN price rejected");
    check(near(ScalpFollowTP(true,3645,3643,3660),3662),"buy outward follows by two");
    check(near(ScalpFollowTP(true,3645,3647,3660),3660),"buy inward leaves TP");
    check(near(ScalpFollowTP(false,3655,3657,3640),3638),"sell outward follows by two");
    check(near(ScalpFollowTP(false,3655,3653,3640),3640),"sell inward leaves TP");
    check(near(ScalpFollowTP(true,3645,3645,3660),3660),"duplicate drag callback is idempotent");
    double tp=ScalpFollowTP(true,3645,3643,3660);
    tp=ScalpFollowTP(true,3643,3645,tp);
    check(near(tp,3662),"outward then inward does not retract reward");
    check(near(ScalpRR(3650,3657,3636),2),"strategy RR remains 2");
    check(near(ScalpBrokerPrice(false,true,3657,.2,.01,2),3657.2),"sell SL moves UP");
    check(near(ScalpBrokerPrice(false,true,3636,.2,.01,2),3636.2),"sell TP moves UP");
    check(near(ScalpBrokerPrice(true,true,3643,.2,.01,2),3643),"buy no compensation");
    check(near(ScalpBrokerPrice(false,false,3657,.2,.01,2),3657),"compensation disabled");
    check(ScalpPendingKind(true,3649,3650,3650.2)==0,"buy limit uses Ask");
    check(ScalpPendingKind(true,3651,3650,3650.2)==1,"buy stop uses Ask");
    check(ScalpPendingKind(false,3650.1,3650,3650.2)==2,"sell limit uses Bid, not Ask");
    check(ScalpPendingKind(false,3649,3650,3650.2)==3,"sell stop uses Bid");
    check(ScalpPendingKind(false,3650,3650,3650.2)==-1,"pending exactly at bid invalid");
    check(ScalpDistanceOK(.3,.3,0,true,.01),"exact minimum stops accepted");
    check(!ScalpDistanceOK(.29,.3,0,true,.01),"inside minimum stops blocked");
    check(!ScalpDistanceOK(.3,.1,.3,true,.01),"freeze boundary guarded");
    check(ScalpDistanceOK(.3,.1,.3,false,.01),"optional freeze guard disabled");
    check(!ScalpDistanceOK(0,0,0,false,.01),"zero distance still invalid");
    check(near(ScalpBufferedStop(true,3000,0,.01,.05,2),3000),"zero buffer preserves SL");
    check(near(ScalpBufferedStop(true,3000,15,.01,.01,2),2999.85),"buy adds buffer below line");
    check(near(ScalpBufferedStop(false,3000,15,.01,.01,2),3000.15),"sell adds buffer above line");
    check(near(ScalpBufferedStop(true,3000,1,.01,.05,2),2999.95),"buy rounds outward on coarse tick");
    check(near(ScalpBufferedStop(false,3000,1,.01,.05,2),3000.05),"sell rounds outward on coarse tick");
    check(near(ScalpBufferedStop(true,3000,15,.001,.001,3),2999.985),"three-digit point units");
    check(ScalpBufferedStop(true,3000,-1,.01,.01,2)==0,"negative buffer rejected");
    check(ScalpBufferedStop(true,3000,NAN,.01,.01,2)==0,"NaN buffer rejected");
    check(ScalpBufferedStop(true,3000,INFINITY,.01,.01,2)==0,"infinite buffer rejected");
    check(ScalpBufferedStop(true,1,200,.01,.01,2)==0,"nonpositive buffered price rejected");
    std::mt19937 rng(260912);
    std::uniform_real_distribution<double> budget(1,100000),loss(1,200000);
    double steps[]={.001,.01,.1,.25,1};
    for(int i=0;i<20000;++i) {
        double b=budget(rng),l=loss(rng),step=steps[i%5]; int count=1+i%13;
        double lot=ScalpLot(b,count,l,step);
        check(lot*count*l<=b+1e-6,"randomized total risk never exceeds budget");
        check(near(lot/step,std::round(lot/step)),"randomized lot obeys step");
        check(lot>=0,"randomized volume nonnegative");
        check((lot+step)*count*l>b-1e-6,"floor is largest admissible lot");
    }
    std::cout << "PASS: " << checks << " core checks (production ScalpCore.mqh)\n";
}
