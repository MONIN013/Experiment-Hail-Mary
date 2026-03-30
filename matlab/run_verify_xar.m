%% XAR 検証スクリプト — デプロイ済みバイナリの読み込み確認
%
%  192.168.10.3 の XAR に対して以下を検証する:
%    1. 全 4 ポートへの ADS 接続
%    2. シンボル列挙 (SymbolBrowser)
%    3. PLC 必須シンボルの存在検証
%    4. VM パラメータシンボルの存在検証
%    5. Controller パラメータシンボルの存在検証
%    6. 基本スカラー読み取り
%    7. Controller パラメータ読み出し (PIDParams 等)
%
%  参照: docs/MatlabSpec.md §7.3 / §8

base_dir = fileparts(mfilename("fullpath"));
restoredefaultpath;
addpath(genpath(base_dir));

sys = experiment.SystemConfig;

ports = [sys.CONTROL_PORT, sys.SEQ_PORT, sys.MODULE_PORT];
results = {};
n_pass = 0;
n_fail = 0;

fprintf("=== XAR Verification: %s ===\n", char(sys.AMS_NET_ID));
fprintf("Ports: %s\n\n", strjoin(string(ports), ", "));

%% 1. ADS 接続テスト
transports = cell(1, numel(ports));
for k = 1:numel(ports)
  port = ports(k);
  name = sprintf("ADS connect port %d", port);
  try
    tr = twincat_ads.AdsTransport();
    tr.connect(char(sys.AMS_NET_ID), port);
    transports{k} = tr;
    results = add_result(results, name, true, "");
    n_pass = n_pass + 1;
  catch e
    results = add_result(results, name, false, e.message);
    n_fail = n_fail + 1;
  end
end

cleanup = onCleanup(@() disconnect_all(transports));

%% 2. シンボル列挙
name = "Symbol discovery (all ports)";
try
  [t_ports, t_symbols] = twincat_ads.SymbolBrowser.discover_ports_and_symbols( ...
    char(sys.AMS_NET_ID), ports, ...
    "connect_timeout_ms", 2000, ...
    "top_level_only", false, ...
    "force_reload", true);
  n_symbols = height(t_symbols);
  n_ok_ports = sum(t_ports.Status == "ok");
  results = add_result(results, name, true, sprintf("%d ports ok, %d symbols", n_ok_ports, n_symbols));
  n_pass = n_pass + 1;
catch e
  results = add_result(results, name, false, e.message);
  n_fail = n_fail + 1;
end

%% 3. PLC 必須シンボルの存在
seq = find_transport(transports, ports, sys.SEQ_PORT);
if ~isempty(seq)
  plc_symbols = experiment.VirtualMotorSymbols.from_defaults();
  name = "PLC required symbols (port " + string(sys.SEQ_PORT) + ")";
  try
    twincat_ads.SymbolBrowser.validate_symbols(seq, plc_symbols.plcRequiredProbes);
    results = add_result(results, char(name), true, sprintf("%d probes OK", size(plc_symbols.plcRequiredProbes, 1)));
    n_pass = n_pass + 1;
  catch e
    results = add_result(results, char(name), false, e.message);
    n_fail = n_fail + 1;
  end
else
  results = add_result(results, "PLC required symbols", false, "SEQ transport unavailable");
  n_fail = n_fail + 1;
end

%% 4. VM パラメータシンボル
mod = find_transport(transports, ports, sys.MODULE_PORT);
if ~isempty(mod)
  vm_symbols = experiment.VirtualMotorSymbols.from_vm_prefix(char(sys.VM_PLANT_PREFIX));
  name = "VM param symbols (port " + string(sys.MODULE_PORT) + ")";
  try
    twincat_ads.SymbolBrowser.validate_symbols(mod, vm_symbols.vmRequiredProbes);
    results = add_result(results, char(name), true, sprintf("%d probes OK", size(vm_symbols.vmRequiredProbes, 1)));
    n_pass = n_pass + 1;
  catch e
    results = add_result(results, char(name), false, e.message);
    n_fail = n_fail + 1;
  end
else
  results = add_result(results, "VM param symbols", false, "MODULE transport unavailable");
  n_fail = n_fail + 1;
end

%% 5. Controller パラメータシンボル
if ~isempty(mod)
  ctrl_symbols = experiment.VirtualMotorSymbols.from_controller_prefix(char(sys.CTRL_PREFIX));
  name = "Controller param symbols (port " + string(sys.MODULE_PORT) + ")";
  try
    twincat_ads.SymbolBrowser.validate_symbols(mod, ctrl_symbols.controllerRequiredProbes);
    results = add_result(results, char(name), true, sprintf("%d probes OK", size(ctrl_symbols.controllerRequiredProbes, 1)));
    n_pass = n_pass + 1;
  catch e
    results = add_result(results, char(name), false, e.message);
    n_fail = n_fail + 1;
  end
else
  results = add_result(results, "Controller param symbols", false, "MODULE transport unavailable");
  n_fail = n_fail + 1;
end

%% 6. 基本スカラー読み取り
t = twincat_ads.AdsTransport.net_types();
scalar_checks = {
  sys.SEQ_PORT,     "GVL_SEQ.tableLen",          t.u32,    "tableLen"
  sys.CONTROL_PORT, "GVL_MODE.experimentState",   t.u32,    "experimentState"
};
for k = 1:size(scalar_checks, 1)
  port = scalar_checks{k, 1};
  sym  = scalar_checks{k, 2};
  nt   = scalar_checks{k, 3};
  label = scalar_checks{k, 4};
  tr = find_transport(transports, ports, port);
  name = sprintf("Read %s (port %d)", label, port);
  if isempty(tr)
    results = add_result(results, name, false, "transport unavailable");
    n_fail = n_fail + 1;
    continue;
  end
  try
    v = tr.read_scalar(sym, nt);
    results = add_result(results, name, true, sprintf("value=%s", string(v)));
    n_pass = n_pass + 1;
  catch e
    results = add_result(results, name, false, e.message);
    n_fail = n_fail + 1;
  end
end

%% 7. Controller パラメータ読み出し
if ~isempty(mod)
  ctrl_sym = experiment.VirtualMotorSymbols.from_controller_prefix(char(sys.CTRL_PREFIX));
  param_keys = {"pidB0", "leadB0", "notchB0", "resoB0", "enablePid"};
  for k = 1:numel(param_keys)
    key = param_keys{k};
    sym = ctrl_sym.controllerParams.(key);
    if contains(key, "enable")
      nt = t.bool;
    else
      nt = t.double;
    end
    name = sprintf("Read controller %s", key);
    try
      v = mod.read_scalar(char(sym), nt);
      ok = isfinite(double(v)) || islogical(v);
      results = add_result(results, name, ok, sprintf("value=%s", string(v)));
      if ok, n_pass = n_pass + 1; else, n_fail = n_fail + 1; end
    catch e
      results = add_result(results, name, false, e.message);
      n_fail = n_fail + 1;
    end
  end
end

%% サマリー
fprintf("\n=== Verification Summary ===\n");
fprintf("%-50s  %-6s  %s\n", "Check", "Result", "Detail");
fprintf("%s\n", repmat('-', 1, 90));
for k = 1:numel(results)
  r = results{k};
  if r.pass
    tag = "PASS";
  else
    tag = "FAIL";
  end
  fprintf("%-50s  %-6s  %s\n", r.name, tag, r.detail);
end
fprintf("%s\n", repmat('-', 1, 90));
fprintf("Total: %d PASS, %d FAIL (of %d)\n", n_pass, n_fail, n_pass + n_fail);

if n_fail > 0
  warning("experiment:verify:failures", "%d checks failed.", n_fail);
end

%% --- helper functions ---

function results = add_result(results, name, pass, detail)
results{end + 1} = struct("name", char(name), "pass", logical(pass), "detail", char(detail));
end

function disconnect_all(transports)
for k = 1:numel(transports)
  try
    if ~isempty(transports{k})
      transports{k}.disconnect();
    end
  catch
  end
end
end

function tr = find_transport(transports, ports, target_port)
tr = [];
idx = find(ports == target_port, 1);
if ~isempty(idx) && ~isempty(transports{idx})
  tr = transports{idx};
end
end
