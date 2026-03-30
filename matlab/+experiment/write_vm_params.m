function write_vm_params(transport, vm_param_symbol_prefix, params, task_dt_ns)
% write_vm_params  VirtualMotorCore の 2 慣性 plant parameter を Port 351 に書き込む。
%
%   experiment.write_vm_params(transport, vm_param_symbol_prefix, params, task_dt_ns)
%
%   params は PlantConfig.to_struct() 相当の nested struct:
%     .motor.{inertia,damping,ratedTorque,tauLimit,velLimit,maxPermille,encoderResolution}
%     .load.{inertia,damping,ratedTorque,tauLimit,velLimit,encoderResolution}
%     .coupling.{stiffness,damping}
%   書込み先は PlantParameter.* とする。

  arguments
    transport twincat_ads.IAdsTransport
    vm_param_symbol_prefix {mustBeTextScalar}
    params struct
    task_dt_ns (1,1) uint64
  end

  symbols = experiment.VirtualMotorSymbols.from_vm_prefix(char(string(vm_param_symbol_prefix)));
  t = symbols.types;
  vm = symbols.vmParams;

  transport.write_scalar(vm.motor.inertia, double(params.motor.inertia), t.double);
  transport.write_scalar(vm.motor.damping, double(params.motor.damping), t.double);
  transport.write_scalar(vm.motor.ratedTorque, double(params.motor.ratedTorque), t.double);
  transport.write_scalar(vm.motor.tauLimit, double(params.motor.tauLimit), t.double);
  transport.write_scalar(vm.motor.velLimit, double(params.motor.velLimit), t.double);
  transport.write_scalar(vm.motor.maxPermille, double(params.motor.maxPermille), t.double);
  transport.write_scalar(vm.motor.encoderResolution, uint32(params.motor.encoderResolution), t.u32);

  transport.write_scalar(vm.load.inertia, double(params.load.inertia), t.double);
  transport.write_scalar(vm.load.damping, double(params.load.damping), t.double);
  transport.write_scalar(vm.load.ratedTorque, double(params.load.ratedTorque), t.double);
  transport.write_scalar(vm.load.tauLimit, double(params.load.tauLimit), t.double);
  transport.write_scalar(vm.load.velLimit, double(params.load.velLimit), t.double);
  transport.write_scalar(vm.load.encoderResolution, uint32(params.load.encoderResolution), t.u32);

  transport.write_scalar(vm.coupling.stiffness, double(params.coupling.stiffness), t.double);
  transport.write_scalar(vm.coupling.damping, double(params.coupling.damping), t.double);
  transport.write_scalar(vm.taskDtNs, task_dt_ns, t.u64);
end
