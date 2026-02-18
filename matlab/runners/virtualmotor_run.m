function out = virtualmotor_run(varargin)
% Minimal virtualMotor runner.
% VM responsibility: current_in -> position_out (every TwinCAT clock).
% Logging is read from upper-layer symbols (GVL_VM_LOG.*).

cfg = parse_inputs(varargin{:});
adsutils.ensure_folder(fileparts(cfg.save_path));

NET.addAssembly(cfg.ads_assembly);
clients = adsutils.create_dual_ads_clients(cfg.ams_net_id, cfg.ams_port, cfg.vm_ams_port);
cleanupObj = onCleanup(@()cleanup_dual_clients(clients)); %#ok<NASGU>
plcClient = clients.plc;
vmClient = clients.vm;

vmSymbols = adsutils.resolve_vm_param_symbols(vmClient, cfg.vm_param_symbol_prefix);
vmParams = struct();
vmParams.M = cfg.M;
vmParams.D = cfg.D;
vmParams.Kt = cfg.Kt;
vmParams.tau_limit = cfg.tau_limit;
vmParams.vel_limit = cfg.vel_limit;
vmParams.task_dt_ns = cfg.task_dt_ns;
adsutils.write_vm_params(vmClient, vmSymbols, vmParams);

profile = cfg.current_profile(:);
useProfile = ~isempty(profile);

tRun = tic;
if useProfile
    profileN = numel(profile);
    if profileN > double(cfg.cmd_max_n)
        error("current_profile length (%d) exceeds cmd_max_n (%d).", profileN, cfg.cmd_max_n);
    end

    adsutils.write_scalar(plcClient, "GVL_VM.play_enable", false, "System.Boolean");
    adsutils.write_scalar(plcClient, "GVL_VM.cmd_idx", uint32(0), "System.UInt32");
    adsutils.write_scalar(plcClient, "GVL_VM.cmd_len", uint32(0), "System.UInt32");
    adsutils.write_scalar(plcClient, "GVL_VM.play_done", false, "System.Boolean");
    adsutils.write_scalar(plcClient, "GVL_VM.experiment_done", false, "System.Boolean");
    adsutils.write_scalar(plcClient, "GVL_VM.reset_req", true, "System.Boolean");

    adsutils.write_array(plcClient, "GVL_VM.cmd_profile", profile, "System.Double");
    adsutils.write_scalar(plcClient, "GVL_VM.cmd_len", uint32(profileN), "System.UInt32");
    adsutils.write_scalar(plcClient, "GVL_VM.play_enable", true, "System.Boolean");

    if cfg.wait_for_done
        done = wait_until_done(plcClient, cfg.done_timeout_s);
        if ~done
            warning("virtualmotor_run:timeout", "Timed out waiting for GVL_VM.experiment_done.");
        end
    else
        while toc(tRun) < cfg.hold_seconds
            pause(min(0.05, cfg.hold_seconds / 10 + eps));
        end
    end
else
    adsutils.write_scalar(plcClient, "GVL_VM.current_in", cfg.current_in, "System.Double");
    while toc(tRun) < cfg.hold_seconds
        pause(min(0.05, cfg.hold_seconds / 10 + eps));
    end
    if cfg.release_to_zero
        adsutils.write_scalar(plcClient, "GVL_VM.current_in", 0.0, "System.Double");
    end
end
elapsedS = toc(tRun);

positionLast = adsutils.read_scalar(plcClient, "GVL_VM.position_out", "System.Double");
currentLast = adsutils.read_scalar(plcClient, "GVL_VM.current_in", "System.Double");
velocityLast = NaN;
try
    velocityLast = adsutils.read_scalar(plcClient, "GVL_VM.velocity_out", "System.Double");
catch
    % Older PLC declaration may not expose velocity_out.
end

raw = struct();
raw.position_last = double(positionLast);
raw.current_last = double(currentLast);
raw.velocity_last = double(velocityLast);

[logData, logReadTime] = read_upper_logs(plcClient, cfg.log_n);
raw.log_seq = logData.log_seq;
raw.log_i = logData.log_i;
raw.log_x = logData.log_x;
raw.log_t = logData.log_t;
raw.log_wr_idx = logData.wr_idx;
raw.log_overflow = logData.overflow;

cmd = struct();
cmd.current_in = cfg.current_in;
cmd.current_profile = profile;
cmd.use_profile = useProfile;
cmd.hold_seconds = cfg.hold_seconds;
cmd.release_to_zero = cfg.release_to_zero;

host = struct();
host.elapsed_s = elapsedS;
host.log_read_time_s = logReadTime;

metrics = preload_eval(raw, cmd, cfg);
config = cfg;

save(cfg.save_path, "raw", "cmd", "host", "metrics", "config");

out = struct();
out.raw = raw;
out.cmd = cmd;
out.host = host;
out.metrics = metrics;
out.config = config;
out.save_path = cfg.save_path;
end

function done = wait_until_done(client, timeoutS)
t0 = tic;
done = false;
while toc(t0) < timeoutS
    try
        done = logical(adsutils.read_scalar(client, "GVL_VM.experiment_done", "System.Boolean"));
    catch
        done = false;
    end
    if done
        return;
    end
    pause(0.01);
end
end

function [logData, readTime] = read_upper_logs(client, logN)
tRead = tic;
logData = struct("log_seq", zeros(0, 1), "log_i", zeros(0, 1), ...
    "log_x", zeros(0, 1), "log_t", zeros(0, 1), "wr_idx", 0, "overflow", false);

try
    wrIdx = adsutils.read_scalar(client, "GVL_VM_LOG.wr_idx", "System.UInt32");
    overflow = adsutils.read_scalar(client, "GVL_VM_LOG.overflow", "System.Boolean");
    validN = uint32(min(double(wrIdx), logN));

    if validN > 0
        logData.log_seq = double(adsutils.read_array(client, "GVL_VM_LOG.log_seq", "System.UInt32", validN));
        logData.log_i = double(adsutils.read_array(client, "GVL_VM_LOG.log_i", "System.Double", validN));
        logData.log_x = double(adsutils.read_array(client, "GVL_VM_LOG.log_x", "System.Double", validN));
        logData.log_t = double(adsutils.read_array(client, "GVL_VM_LOG.log_t", "System.UInt64", validN));
    end

    logData.wr_idx = double(wrIdx);
    logData.overflow = logical(overflow);
catch
    % Logging symbols may be absent; keep empty logs.
end

readTime = toc(tRead);
end

function cfg = parse_inputs(varargin)
p = inputParser;
p.addParameter("ams_net_id", "", @(x) ischar(x) || isstring(x));
p.addParameter("ams_port", 851, @(x) isnumeric(x) && isscalar(x));
p.addParameter("vm_ams_port", 350, @(x) isnumeric(x) && isscalar(x));
p.addParameter("vm_param_symbol_prefix", "", @(x) ischar(x) || isstring(x));
p.addParameter("current_in", 0.0, @(x) isnumeric(x) && isscalar(x));
p.addParameter("current_profile", [], @(x) isnumeric(x));
p.addParameter("hold_seconds", 1.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter("release_to_zero", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("wait_for_done", true, @(x) islogical(x) || isnumeric(x));
p.addParameter("done_timeout_s", 30.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("cmd_max_n", 100000, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("M", 0.01, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("D", 0.1, @(x) isnumeric(x) && isscalar(x));
p.addParameter("Kt", 1.0, @(x) isnumeric(x) && isscalar(x));
p.addParameter("tau_limit", 5.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter("vel_limit", 100.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter("task_rate_hz", 8000, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("log_n", 200000, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter("ads_assembly", "TwinCAT.Ads", @(x) ischar(x) || isstring(x));
p.addParameter("save_path", "", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
cfg = p.Results;

cfg.ams_net_id = char(cfg.ams_net_id);
cfg.ads_assembly = char(cfg.ads_assembly);
cfg.vm_param_symbol_prefix = char(cfg.vm_param_symbol_prefix);
cfg.release_to_zero = logical(cfg.release_to_zero);
cfg.wait_for_done = logical(cfg.wait_for_done);
cfg.current_profile = double(cfg.current_profile(:));
cfg.cmd_max_n = uint32(cfg.cmd_max_n);

if isempty(cfg.ams_net_id)
    error("ams_net_id is required. Example: ""192.168.10.3.1.1"".");
end

cfg.task_dt_ns = uint64(round(1e9 / cfg.task_rate_hz));

if isempty(cfg.save_path)
    stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    cfg.save_path = fullfile("results", "ads_validation", "virtualmotor_io_minimal_" + stamp + ".mat");
else
    cfg.save_path = char(cfg.save_path);
end
cfg.save_path = char(cfg.save_path);
end

function cleanup_dual_clients(clients)
if isfield(clients, "vm") && ~isempty(clients.vm)
    adsutils.safe_disconnect(clients.vm);
end
if isfield(clients, "plc") && ~isempty(clients.plc)
    adsutils.safe_disconnect(clients.plc);
end
end
