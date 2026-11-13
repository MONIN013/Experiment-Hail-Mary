// Offline regression of the Fig. 8.9 runtime core and simulation ABI.
#include "ControllerAlgorithm.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <vector>
using Core = controllercore::ControllerAlgorithm;
extern "C" int simulate_higs(int, const double*, const double*, const double*,
    const double*, const double*, const double*, unsigned, const unsigned*,
    int, double, double, int, double, double, int, double, double, double,
    const double*, double*);
static void require(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}
static bool close(double a, double b, double tolerance=2e-10) {
    return std::abs(a-b) <= tolerance*std::max({1.0,std::abs(a),std::abs(b)});
}
using Row = std::array<double,5>;
struct Filter {
    Row row;
    double s1=0, s2=0;
    double step(double x) {
        const double y=row[0]*x+s1;
        s1=row[1]*x-row[3]*y+s2; s2=row[2]*x-row[4]*y;
        return y;
    }
};
// Bilinear transform, independently derived for an analog polynomial of order <=2.
static Row tustin(std::array<double,3> b, std::array<double,3> a) {
    constexpr double q=16000;
    if (a[0]==0 && b[0]==0) {
        const double a0=q*a[1]+a[2];
        return {(q*b[1]+b[2])/a0,(-q*b[1]+b[2])/a0,0,(-q*a[1]+a[2])/a0,0};
    }
    auto z=[q](std::array<double,3> v) {
        return std::array<double,3>{v[0]*q*q+v[1]*q+v[2],
            -2*v[0]*q*q+2*v[2],v[0]*q*q-v[1]*q+v[2]};
    };
    const auto bz=z(b), az=z(a);
    return {bz[0]/az[0],bz[1]/az[0],bz[2]/az[0],az[1]/az[0],az[2]/az[0]};
}
struct Element {
    double state=0, previous=0;
    unsigned mode=0;
    double step(double x, double gain, double omegaTs) {
        const double candidate=state+omegaTs*x;
        const double lo=std::min(0.0,gain*x), hi=std::max(0.0,gain*x);
        if (candidate>=lo && candidate<=hi) { state=candidate; mode=1; }
        else if (x*previous>=0) { state=gain*x; mode=2; }
        else { state=0; mode=3; }
        previous=x;
        return state;
    }
};
int main() {
    try {
        const double pi=std::acos(-1.0), kp=0.1866070417529291;
        const double wi=2*pi*2, wz=2*pi*(8.0/3), wp=2*pi*24, wl=2*pi*100;
        const double scale=std::sqrt(1+16/(pi*pi));
        Row hLp=tustin({0,0,wl},{0,1,wl});
        Row vLp=tustin({0,wl,wl*wl},{1,std::sqrt(2.0)*wl,wl*wl});
        Row lead=tustin({0,wp/wz,wp},{0,1,wp});
        for (int j=0;j<3;++j) lead[j]*=kp;
        Row hI=tustin({0,0,wi},{0,1,wi});
        Row vI=tustin({0,1,wi},{0,1,0});
        std::array<Row,6> bank={hLp,vLp,lead,hI,vI,lead};
        Core linear;
        const Core::SectionCounts counts={0,1,1,0,2,0};
        const Core::HigsParameters lp={false,1,wl/8000/scale}, in={false,1,wi/8000/scale};
        require(linear.ApplyParameters(bank[0].data(),6,1,counts,lp,in),"linear setup");
        Row piRow=tustin({0,kp,kp*wi},{0,1,0});
        Row leadOnly=lead; for(int j=0;j<3;++j) leadOnly[j]/=kp;
        Filter directPi{piRow},directLead{leadOnly},directLp{tustin({0,0,wl*wl},{1,std::sqrt(2.0)*wl,wl*wl})};
        std::mt19937_64 rng(20261114); std::normal_distribution<double> normal;
        double maximumError=0;
        for(int k=0;k<100000;++k) {
            const double ref=0.1*normal(rng), pos=0.01*normal(rng), ff=0.001*normal(rng);
            const double expected=directLp.step(directLead.step(directPi.step(ref-pos)))+ff;
            const double actual=linear.Step(ref,ff,pos);
            maximumError=std::max(maximumError,std::abs(actual-expected));
            require(close(actual,expected),"both-linear differs from original PI/lead/Butterworth cascade");
        }
        std::uint64_t samples=0, modes[2][4]={};
        // Populate all six variable segments and both H slots to test offsets/order.
        const std::array<Row,8> shaped={Row{0.7,0.1,0,-0.1,0},hLp,
            Row{1.2,0,0,0,0},Row{0.4,0.05,0,-0.2,0},
            Row{0.8,0.02,0,-0.3,0},hI,Row{0.3,0.03,0,-0.1,0},Row{1.1,0.01,0,-0.2,0}};
        const Core::SectionCounts allCounts={1,1,1,1,1,1};
        for(unsigned bits=0;bits<4;++bits) {
            Core core;
            const Core::HigsParameters l={bool(bits&1),1,0.2}, i={bool(bits&2),2,0.3};
            require(core.ApplyParameters(shaped[0].data(),8,1,allCounts,l,i),"mode setup");
            std::vector<Filter> f; for(auto r:shaped) f.push_back(Filter{r});
            Element le,ie;
            for(int k=0;k<100000;++k) {
                const double x=k%19==0?0:normal(rng)*std::pow(10.0,(k/97)%9-4);
                const double lin=f[0].step(x);
                const double lout=l.enabled?le.step(lin,l.gain,l.omegaTs):f[1].step(lin);
                const double shared=f[2].step(lout), p=f[3].step(shared), iin=f[4].step(shared);
                const double iout=i.enabled?ie.step(iin,i.gain,i.omegaTs):f[5].step(iin);
                const double expected=f[7].step(p+f[6].step(iout))+0.13;
                require(close(core.Step(x,0.13,0),expected),"two-branch reference mismatch");
                require(close(core.HigsLpInput(),lin)&&close(core.HigsLpOutput(),lout),"LP telemetry mismatch");
                require(close(core.HigsIInput(),iin)&&close(core.HigsIOutput(),iout),"I telemetry mismatch");
                require(core.HigsLpMode()==le.mode&&core.HigsIMode()==ie.mode,"trimodal mode mismatch");
                ++modes[0][core.HigsLpMode()]; ++modes[1][core.HigsIMode()]; ++samples;
            }
            const double lBefore=core.HigsLpOutput(),iBefore=core.HigsIOutput();
            require(!core.ApplyParameters(shaped[0].data(),8,2,allCounts,{true,1,2},i),"bad LP accepted");
            require(core.AppliedRevision()==1&&core.ProcessedRevision()==2&&
                core.HigsLpOutput()==lBefore&&core.HigsIOutput()==iBefore,"rejection changed active state");
            core.Reset(); require(core.HigsLpMode()==0&&core.HigsIMode()==0&&
                core.HigsLpOutput()==0&&core.HigsIOutput()==0,"two-element reset failed");
            // Exercise the actual simulation ABI, including all fourteen output columns.
            constexpr int n=64;
            double reference[n],zero[n]={},a[16]={},b[4]={},initial[4]={},out[n*14]={};
            for(int k=0;k<n;++k) reference[k]=std::sin(0.71*k);
            const unsigned c[]={1,1,1,1,1,1};
            require(simulate_higs(n,reference,zero,zero,a,b,shaped[0].data(),8,c,
                int(l.enabled),l.gain,l.omegaTs,int(i.enabled),i.gain,i.omegaTs,
                0,1e10,0,0,initial,out)==0,"simulation ABI failed");
            for(int k=0;k<n;++k) {
                require(close(out[k*14+4],core.Step(reference[k],0,0)),"host feedback mismatch");
                require(out[k*14+9]==core.HigsLpMode()&&out[k*14+13]==core.HigsIMode(),"host mode columns mismatch");
                require(close(out[k*14+7],core.HigsLpInput())&&close(out[k*14+8],core.HigsLpOutput())&&
                    close(out[k*14+11],core.HigsIInput())&&close(out[k*14+12],core.HigsIOutput()),"host signal columns mismatch");
            }
        }
        for(auto& element:modes) for(unsigned mode=1;mode<=3;++mode)
            require(element[mode]>0,"a trimodal region was never exercised");
        std::cout<<"PASS: 100000 linear samples, "<<samples<<" four-mode samples, simulation ABI; max linear error="<<maximumError<<'\n';
        return 0;
    } catch(const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
