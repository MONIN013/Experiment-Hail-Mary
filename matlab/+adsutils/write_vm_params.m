function write_vm_params(client, symbols, params)
adsutils.write_scalar(client, symbols.M, params.M, "System.Double");
adsutils.write_scalar(client, symbols.D, params.D, "System.Double");
adsutils.write_scalar(client, symbols.Kt, params.Kt, "System.Double");
adsutils.write_scalar(client, symbols.tau_limit, params.tau_limit, "System.Double");
adsutils.write_scalar(client, symbols.vel_limit, params.vel_limit, "System.Double");
adsutils.write_scalar(client, symbols.task_dt_ns, uint64(params.task_dt_ns), "System.UInt64");
end
