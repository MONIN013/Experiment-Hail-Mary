function write_vm_params(transport, params)
% write_vm_params  VirtualMotorCore の物理パラメータを Port 351 に書き込む。
%
%   experiment.write_vm_params(transport, params)
%
%   transport — 接続済み twincat_ads.IAdsTransport (Port = SystemConfig.MODULE_PORT)
%   params    — struct or RunConfig with fields: m, d, rated_current, max_permille, tau_limit, vel_limit
%               (task_rate_hz は SystemConfig から自動取得)
%
%   書込み先 (VirtualMotor1Parameter):
%     .mass, .damping, .ratedTorque, .maxPermille, .tauLimit, .velLimit, .taskDtNs

  arguments
    transport twincat_ads.IAdsTransport
    params    struct
  end

  sys = experiment.SystemConfig;
  symbols = experiment.VirtualMotorSymbols.from_vm_prefix(sys.VM_PREFIX);
  t = symbols.types;
  vm = symbols.vmParams;

  transport.write_scalar(vm.m, double(params.m), t.double);
  transport.write_scalar(vm.d, double(params.d), t.double);
  transport.write_scalar(vm.ratedTorque, double(params.rated_current), t.double);
  if isfield(symbols.vmParams, 'maxPermille')
    transport.write_scalar(vm.maxPermille, double(params.max_permille), t.double);
  end
  transport.write_scalar(vm.tauLimit, double(params.tau_limit), t.double);
  transport.write_scalar(vm.velLimit, double(params.vel_limit), t.double);
  transport.write_scalar(vm.taskDtNs, sys.task_dt_ns(), t.u64);
end
