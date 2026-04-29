function writeParams(conn, plant_cfg, varargin)
% writeParams  VirtualMotorCore の plant parameter を ADS で更新する。
if ~isstruct(conn)
  error("virtualMotor:writeParams:invalidConnection", ...
    "Connection must be a struct returned by ConnectionManager.");
end

parser = inputParser;
parser.addParameter("taskDtNs", config.SystemConfig.task_dt_ns(), @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.addParameter("validateSymbols", true, @(x) islogical(x) || isnumeric(x));
parser.parse(varargin{:});
opts = parser.Results;

module_transport = require_module_transport(conn);
plant = virtualMotor.PlantConfig.from_struct(plant_cfg).to_struct();
symbols = virtualMotor.Symbols.from_defaults();

if logical(opts.validateSymbols)
  twincat_ads.SymbolBrowser.validate_symbols(module_transport, symbols.requiredProbes);
end

t = symbols.types;
vm = symbols.vmParams;
task_dt_ns = uint64(opts.taskDtNs);

module_transport.write_scalar(vm.motor.inertia, double(plant.motor.inertia), t.double);
module_transport.write_scalar(vm.motor.damping, double(plant.motor.damping), t.double);
module_transport.write_scalar(vm.motor.ratedTorque, double(plant.motor.ratedTorque), t.double);
module_transport.write_scalar(vm.motor.tauLimit, double(plant.motor.tauLimit), t.double);
module_transport.write_scalar(vm.motor.velLimit, double(plant.motor.velLimit), t.double);
module_transport.write_scalar(vm.motor.maxPermille, double(plant.motor.maxPermille), t.double);
module_transport.write_scalar(vm.motor.encoderResolution, uint32(plant.motor.encoderResolution), t.u32);

module_transport.write_scalar(vm.load.inertia, double(plant.load.inertia), t.double);
module_transport.write_scalar(vm.load.damping, double(plant.load.damping), t.double);
module_transport.write_scalar(vm.load.ratedTorque, double(plant.load.ratedTorque), t.double);
module_transport.write_scalar(vm.load.tauLimit, double(plant.load.tauLimit), t.double);
module_transport.write_scalar(vm.load.velLimit, double(plant.load.velLimit), t.double);
module_transport.write_scalar(vm.load.encoderResolution, uint32(plant.load.encoderResolution), t.u32);

module_transport.write_scalar(vm.coupling.stiffness, double(plant.coupling.stiffness), t.double);
module_transport.write_scalar(vm.coupling.damping, double(plant.coupling.damping), t.double);
module_transport.write_scalar(vm.taskDtNs, task_dt_ns, t.u64);
end

function module_transport = require_module_transport(conn)
if ~isfield(conn, "module") || isempty(conn.module) || ~isa(conn.module, "twincat_ads.IAdsTransport")
  error("virtualMotor:writeParams:invalidConnection", ...
    "Connection is missing a module transport.");
end
module_transport = conn.module;
end
