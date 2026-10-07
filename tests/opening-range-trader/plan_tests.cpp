#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#define MathIsValidNumber std::isfinite
#define MathAbs std::abs
#define MathMax std::max
#define MathMin std::min
#define MathRound std::round
#define MathFloor std::floor
using string=std::string;
double NormalizeDouble(double v,int d){double p=std::pow(10.,d);return std::round(v*p)/p;}
template<class T>void ZeroMemory(T&v){v=T{};}
template<class T>int ArrayResize(std::vector<T>&a,int n){a.resize(n);return n;}
template<class T>int ArraySize(const std::vector<T>&a){return int(a.size());}
bool IsStopped(){return false;}
#include "TradePlanCore.mqh"
int checks=0;void check(bool ok,const char*why){++checks;if(!ok){std::cerr<<"FAIL: "<<why<<'\n';std::exit(1);}}
int main(){
 ORCandidate c{};c.signal.direction=1;c.signal.stop=99.2;c.pattern_low=99.3;c.pattern_high=100.8;
 check(ORStop(c,.01,2)<c.pattern_low,"buy stop remains outside retest pattern");c.signal.direction=-1;c.signal.stop=100.8;c.pattern_high=100.7;
 check(ORStop(c,.01,2)>c.pattern_high,"sell stop remains outside retest pattern");
 check(ORMinimumRR(true,100,99,102,1.8),"1.8R accepted");check(!ORMinimumRR(true,100,99,101.7,1.8),"below minimum rejected");check(!ORMinimumRR(true,100,99,101,.9),"minimum below one rejected");
 std::cout<<"Opening Range Trader plan: "<<checks<<" checks passed\n";
}
