// Standalone regression of the unchanged runtime core; no TwinCAT dependency.
// Build: g++ -std=c++17 -O2 -Wall -Wextra -Werror -IControllerCore
//   ControllerCore/ControllerAlgorithm.cpp simulations/higs_regression.cpp -o higs_regression
#include "ControllerAlgorithm.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>

using Core = controllercore::ControllerAlgorithm;
static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

int main() {
    try {
        std::mt19937_64 generator(20261113);
        std::normal_distribution<double> normal;
        std::uint64_t samples = 0;
        std::uint64_t modes[4] = {};
        for (double gain : {0.01, 1.0, 4.0}) {
            for (double ratio : {0.005, 0.25, 1.0}) {
                Core controller;
                const double omega_ts = ratio * gain;
                require(controller.ApplyParameters(nullptr, 0, 1, {true, gain, omega_ts, 0}), "valid parameters rejected");
                double expected = 0.0;
                for (int k = 0; k < 100000; ++k) {
                    const double scale = std::pow(10.0, static_cast<double>((k / 97) % 25 - 12));
                    const double z = k % 19 == 0 ? 0.0 : normal(generator) * scale;
                    // Independent interval-projection oracle. For consistent states
                    // and 0 < omegaTs <= gain this equals the book's trimodal rule.
                    expected = std::max(std::min(0.0, gain*z),
                        std::min(std::max(0.0, gain*z), expected + omega_ts*z));
                    const double actual = controller.Step(z, 0.0, 0.0);
                    const double tolerance = 32*std::numeric_limits<double>::epsilon()
                        *std::max({1e-300, std::abs(actual), std::abs(expected)});
                    require(std::abs(actual-expected) <= tolerance, "projection mismatch");
                    require(actual >= std::min(0.0,gain*z)-tolerance &&
                        actual <= std::max(0.0,gain*z)+tolerance, "sector violation");
                    ++modes[controller.HigsMode()]; ++samples;
                }
                const double before = controller.HigsOutput();
                require(!controller.ApplyParameters(nullptr,0,2,{true,gain,2*gain,0}), "invalid omegaTs accepted");
                require(controller.HigsOutput()==before && controller.AppliedRevision()==1, "rejected revision changed state");
                controller.Reset();
                require(controller.HigsOutput()==0.0 && controller.HigsInput()==0.0 && controller.HigsMode()==0, "reset failed");
            }
        }
        Core crossing;
        require(crossing.ApplyParameters(nullptr,0,1,{true,1.0,0.5,0}), "setup failed");
        require(crossing.Step(1.0,0.0,0.0)==0.5, "first integration failed");
        require(crossing.Step(-1.0,0.0,0.0)==0.0 && crossing.HigsMode()==1, "zero crossing incorrectly bypassed candidate test");
        const double sos[] = {2,0,0,0,0, 3,0,0,0,0};
        Core filter;
        require(filter.ApplyParameters(sos,2,1,{true,1.0,0.25,1}), "prefilter setup failed");
        require(filter.Step(1.0,0.1,0.0)==1.6 && filter.HigsInput()==2.0, "SOS/HIGS/FF ordering failed");
        require(filter.ApplyParameters(sos,2,2), "linear setup failed");
        require(filter.Step(1.0,0.1,0.0)==6.1 && filter.HigsMode()==0, "disabled HIGS changed legacy response");
        require(modes[1]>0 && modes[2]>0 && modes[3]>0, "not all HIGS modes exercised");
        std::cout << "{\"projection_samples\":" << samples << ",\"integrator_samples\":" << modes[1]
                  << ",\"gain_samples\":" << modes[2] << ",\"zeroing_samples\":" << modes[3]
                  << ",\"passed\":true}\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
