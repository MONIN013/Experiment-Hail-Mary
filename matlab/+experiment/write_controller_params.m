function write_controller_params(transport, params)
% write_controller_params  ControllerCore の biquad フィルタパラメータを Port 351 に書き込む。
%
%   experiment.write_controller_params(transport, params)
%
%   transport — 接続済み twincat_ads.IAdsTransport (Port = SystemConfig.MODULE_PORT)
%   params    — struct or RunConfig with fields:
%               pid_b0..pid_a2, lead_b0..lead_a2, notch_b0..notch_a2, reso_b0..reso_a2,
%               enable_pid, enable_lead, enable_notch, enable_reso
%
%   書込み先 (ControllerCore):
%     PIDParams.pidB0..pidA2, LeadParams.leadB0..leadA2,
%     NotchParams.notchB0..notchA2, ResoParams.resoB0..resoA2,
%     EnableParams.enablePid/Lead/Notch/Reso

  arguments
    transport twincat_ads.IAdsTransport
    params    struct
  end

  sys = experiment.SystemConfig;
  symbols = experiment.VirtualMotorSymbols.from_controller_prefix(sys.CTRL_PREFIX);
  t = symbols.types;
  p = symbols.controllerParams;

  % PID
  transport.write_scalar(p.pidB0, double(params.pid_b0), t.double);
  transport.write_scalar(p.pidB1, double(params.pid_b1), t.double);
  transport.write_scalar(p.pidB2, double(params.pid_b2), t.double);
  transport.write_scalar(p.pidA1, double(params.pid_a1), t.double);
  transport.write_scalar(p.pidA2, double(params.pid_a2), t.double);

  % Lead
  transport.write_scalar(p.leadB0, double(params.lead_b0), t.double);
  transport.write_scalar(p.leadB1, double(params.lead_b1), t.double);
  transport.write_scalar(p.leadB2, double(params.lead_b2), t.double);
  transport.write_scalar(p.leadA1, double(params.lead_a1), t.double);
  transport.write_scalar(p.leadA2, double(params.lead_a2), t.double);

  % Notch
  transport.write_scalar(p.notchB0, double(params.notch_b0), t.double);
  transport.write_scalar(p.notchB1, double(params.notch_b1), t.double);
  transport.write_scalar(p.notchB2, double(params.notch_b2), t.double);
  transport.write_scalar(p.notchA1, double(params.notch_a1), t.double);
  transport.write_scalar(p.notchA2, double(params.notch_a2), t.double);

  % Reso
  transport.write_scalar(p.resoB0, double(params.reso_b0), t.double);
  transport.write_scalar(p.resoB1, double(params.reso_b1), t.double);
  transport.write_scalar(p.resoB2, double(params.reso_b2), t.double);
  transport.write_scalar(p.resoA1, double(params.reso_a1), t.double);
  transport.write_scalar(p.resoA2, double(params.reso_a2), t.double);

  % Enable flags
  transport.write_scalar(p.enablePid, logical(params.enable_pid), t.bool);
  transport.write_scalar(p.enableLead, logical(params.enable_lead), t.bool);
  transport.write_scalar(p.enableNotch, logical(params.enable_notch), t.bool);
  transport.write_scalar(p.enableReso, logical(params.enable_reso), t.bool);
end
