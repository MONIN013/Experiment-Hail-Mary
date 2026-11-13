// Offline plant harness. The controller is the actual TwinCAT calculation core.
#include "ControllerAlgorithm.h"
#include <algorithm>
#include <cmath>
#include <vector>

extern "C" int simulate_higs(
    int n, const double* reference, const double* disturbance,
    const double* noise, const double* a, const double* b,
    const double* coefficients, unsigned sections, int enabled,
    double gain, double omega_ts, unsigned pre_sections,
    int delay, double current_limit, double current_quantum,
    double encoder_quantum, const double* initial_state, double* output)
{
    controllercore::ControllerAlgorithm controller;
    const controllercore::ControllerAlgorithm::HigsParameters higs = {
        enabled != 0, gain, omega_ts, pre_sections};
    if (n <= 0 || delay < 0 || delay > 64 ||
        !controller.ApplyParameters(coefficients, sections, 1, higs)) return -1;
    double state[4];
    std::copy(initial_state, initial_state + 4, state);
    std::vector<double> queue(static_cast<unsigned>(delay) + 1, 0.0);
    for (int k = 0; k < n; ++k) {
        double y = state[2] + noise[k];
        if (encoder_quantum > 0.0) y = std::round(y / encoder_quantum) * encoder_quantum;
        const double command = controller.Step(reference[k], 0.0, y);
        const double demand = command + disturbance[k];
        double applied = std::max(-current_limit, std::min(current_limit, demand));
        if (current_quantum > 0.0) applied = std::round(applied / current_quantum) * current_quantum;
        queue[k % queue.size()] = applied;
        const double delayed = k >= delay ? queue[(k - delay) % queue.size()] : 0.0;
        double* row = output + k * 11;
        row[0] = state[0]; row[1] = state[1]; row[2] = state[2]; row[3] = state[3];
        row[4] = command; row[5] = delayed; row[6] = y;
        row[7] = controller.HigsInput(); row[8] = controller.HigsOutput();
        row[9] = controller.HigsMode(); row[10] = std::abs(demand) > current_limit;
        double next[4] = {};
        for (int i = 0; i < 4; ++i) {
            next[i] = b[i] * delayed;
            for (int j = 0; j < 4; ++j) next[i] += a[4 * i + j] * state[j];
            if (!std::isfinite(next[i]) || std::abs(next[i]) > 1e6) return k + 1;
        }
        std::copy(next, next + 4, state);
    }
    return 0;
}
