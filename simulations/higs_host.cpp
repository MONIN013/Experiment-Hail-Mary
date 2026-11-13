// Offline plant harness. The controller is the actual TwinCAT calculation core.
#include "ControllerAlgorithm.h"
#include <algorithm>
#include <cmath>
#include <vector>

extern "C" int simulate_higs(
    int n, const double* reference, const double* disturbance,
    const double* noise, const double* a, const double* b,
    const double* coefficients, unsigned sections, const unsigned* counts,
    int lp_enabled, double lp_gain, double lp_omega_ts,
    int i_enabled, double i_gain, double i_omega_ts,
    int delay, double current_limit, double current_quantum,
    double encoder_quantum, const double* initial_state, double* output)
{
    controllercore::ControllerAlgorithm controller;
    const controllercore::ControllerAlgorithm::SectionCounts layout = {
        counts[0], counts[1], counts[2], counts[3], counts[4], counts[5]};
    const controllercore::ControllerAlgorithm::HigsParameters lp = {
        lp_enabled != 0, lp_gain, lp_omega_ts};
    const controllercore::ControllerAlgorithm::HigsParameters integral = {
        i_enabled != 0, i_gain, i_omega_ts};
    if (n <= 0 || delay < 0 || delay > 64 ||
        !controller.ApplyParameters(coefficients, sections, 1, layout, lp, integral)) return -1;
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
        double* row = output + k * 14;
        row[0] = state[0]; row[1] = state[1]; row[2] = state[2]; row[3] = state[3];
        row[4] = command; row[5] = delayed; row[6] = y;
        row[7] = controller.HigsLpInput(); row[8] = controller.HigsLpOutput();
        row[9] = controller.HigsLpMode(); row[10] = std::abs(demand) > current_limit;
        row[11] = controller.HigsIInput(); row[12] = controller.HigsIOutput();
        row[13] = controller.HigsIMode();
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
