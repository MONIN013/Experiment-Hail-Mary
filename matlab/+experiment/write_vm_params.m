function write_vm_params(transport, vm_param_symbol_prefix, params, task_dt_ns)
% write_vm_params  VirtualMotorCore の物理パラメータを Port 351 に書き込む。
%
%   experiment.write_vm_params(transport, vm_param_symbol_prefix, params, task_dt_ns)
%
%   transport — 接続済み twincat_ads.IAdsTransport (Port = SystemConfig.MODULE_PORT)
%   vm_param_symbol_prefix — VirtualMotor1Parameter prefix
%   params    — struct with fields: m, d, rated_current, max_permille, tau_limit, vel_limit
%   task_dt_ns — task period [ns]
%
%   書込み先 (VirtualMotor1Parameter):
%     .mass, .damping, .ratedTorque, .maxPermille, .tauLimit, .velLimit, .taskDtNs
%
%   外部契約は rated_current [A] で統一する。
%   VirtualMotorCore は内部で物理トルク [Nm] を扱うため ADS シンボル名は
%   .ratedTorque のままだが、kt = 1 前提で params.rated_current をそのまま書き込む。
%   これは VirtualMotorCore 内部契約の例外であり、MATLAB 側の torque 契約ではない。

  arguments
    transport twincat_ads.IAdsTransport
    vm_param_symbol_prefix {mustBeTextScalar}
    params struct
    task_dt_ns (1,1) uint64
  end

  symbols = experiment.VirtualMotorSymbols.from_vm_prefix(char(string(vm_param_symbol_prefix)));
  t = symbols.types;
  vm = symbols.vmParams;

  transport.write_scalar(vm.m, double(params.m), t.double);
  transport.write_scalar(vm.d, double(params.d), t.double);
  transport.write_scalar(vm.ratedTorque, double(params.rated_current), t.double);
  transport.write_scalar(vm.maxPermille, double(params.max_permille), t.double);
  transport.write_scalar(vm.tauLimit, double(params.tau_limit), t.double);
  transport.write_scalar(vm.velLimit, double(params.vel_limit), t.double);
  transport.write_scalar(vm.taskDtNs, task_dt_ns, t.u64);
end
