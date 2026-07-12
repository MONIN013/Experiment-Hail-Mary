classdef TestTsprojMapping < matlab.unittest.TestCase
  methods (Test)
    function driverToLoggerLinksUseMatchingMotorLoadChannels(testCase)
      source = testCase.read_vm_tsproj();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^motor^currentAct" VarB="Inputs^record^motor^currentAct"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^motor^positionRel" VarB="Inputs^record^motor^position"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^motor^velocityAct" VarB="Inputs^record^motor^velocity"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^load^positionRel" VarB="Inputs^record^load^position"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^load^velocityAct" VarB="Inputs^record^load^velocity"/>'));

      testCase.verifyFalse(contains(source, ...
        '<Link VarA="Outputs^load^currentAct" VarB="Inputs^record^motor^currentAct"/>'));
      testCase.verifyFalse(contains(source, ...
        '<Link VarA="Outputs^load^positionRel" VarB="Inputs^record^motor^position"/>'));
      testCase.verifyFalse(contains(source, ...
        '<Link VarA="Outputs^motor^positionRel" VarB="Inputs^record^load^position"/>'));
    end

    function vmProjectUsesVirtualMotorLinksUseMotorLoadContracts(testCase)
      source = testCase.read_vm_tsproj();

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^motorRaw^positionActualValue" VarB="Outputs^motor^positionActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^motorRaw^velocityActualValue" VarB="Outputs^motor^velocityActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^motorRaw^torqueActualValue" VarB="Outputs^motor^torqueActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^motorRaw^statusWord" VarB="Outputs^motor^statusWord"/>'));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^loadRaw^positionActualValue" VarB="Outputs^load^positionActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^loadRaw^velocityActualValue" VarB="Outputs^load^velocityActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^loadRaw^torqueActualValue" VarB="Outputs^load^torqueActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^loadRaw^statusWord" VarB="Outputs^load^statusWord"/>'));

      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^targetTorque" VarB="Inputs^motor^targetTorque"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^motorControlWordOut" VarB="Inputs^motor^controlWord"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^loadControlWordOut" VarB="Inputs^load^controlWord"/>'));
    end

    function realMotorProjectReplacesVirtualMotorOwnerWithRealMotorPdo(testCase)
      source = testCase.read_real_motor_tsproj();

      testCase.verifyFalse(contains(source, ...
        '<OwnerB Name="TIXC^VirtualMotorCore^VirtualMotorCore_Obj1 (Module1)">'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<OwnerB Name="TIID^RealMotorPdo^RealMotorPdo Instance">'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^motorRaw^positionActualValue" VarB="Outputs^motor^positionActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Inputs^loadRaw^positionActualValue" VarB="Outputs^load^positionActualValue"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^targetTorque" VarB="Inputs^motor^targetTorque"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^motorControlWordOut" VarB="Inputs^motor^controlWord"/>'));
      testCase.verifyThat(source, matlab.unittest.constraints.ContainsSubstring( ...
        '<Link VarA="Outputs^loadControlWordOut" VarB="Inputs^load^controlWord"/>'));
    end

    function loggerRecordsSequencerDistValueInBothProjects(testCase)
      vm_source = testCase.read_vm_tsproj();
      real_source = testCase.read_real_motor_tsproj();
      expected_link = '<Link VarA="VirtualMotorTask Outputs^GVL_SEQ.distValue" VarB="Inputs^record^distValue"/>';

      testCase.verifyThat(vm_source, matlab.unittest.constraints.ContainsSubstring(expected_link));
      testCase.verifyThat(real_source, matlab.unittest.constraints.ContainsSubstring(expected_link));
      testCase.verifyThat(vm_source, matlab.unittest.constraints.ContainsSubstring('<Name>distValue</Name>'));
      testCase.verifyThat(real_source, matlab.unittest.constraints.ContainsSubstring('<Name>distValue</Name>'));
    end

    function modeManagerSequencerAndLoggerLinksRemainOwned(testCase)
      expected_links = [
        "<Link VarA=""VirtualMotorTask Outputs^GVL_SEQ.playbackDone"" VarB=""Inputs^control^playbackDone""/>", ...
        "<Link VarA=""PlcTask Inputs^MAIN.loggerErrorCodeIn"" VarB=""Outputs^status^errorCode""/>", ...
        "<Link VarA=""PlcTask Inputs^MAIN.loggerFileReleasedIn"" VarB=""Outputs^status^fileReleased""/>", ...
        "<Link VarA=""PlcTask Inputs^MAIN.loggerReadyIn"" VarB=""Outputs^status^loggerReady""/>", ...
        "<Link VarA=""PlcTask Outputs^MAIN.experimentActiveOut"" VarB=""Inputs^control^loggingReq""/>", ...
        "<Link VarA=""PlcTask Outputs^MAIN.preArmOut"" VarB=""Inputs^control^preArmReq""/>", ...
        "<Link VarA=""PlcTask Outputs^MAIN.resetOut"" VarB=""Inputs^control^resetReq""/>", ...
        "<Link VarA=""VirtualMotorTask Inputs^GVL_SEQ.experimentActive"" VarB=""PlcTask Outputs^MAIN.experimentActiveOut""/>", ...
        "<Link VarA=""VirtualMotorTask Inputs^GVL_SEQ.resetReq"" VarB=""PlcTask Outputs^MAIN.resetOut""/>", ...
        "<Link VarA=""VirtualMotorTask Outputs^GVL_SEQ.playbackDone"" VarB=""PlcTask Inputs^MAIN.seqPlaybackDone""/>", ...
        "<Link VarA=""PlcTask Outputs^MAIN.enableCurrentOut"" VarB=""Inputs^enableCurrentOutput""/>" ...
      ];

      for source = [testCase.read_vm_tsproj(), testCase.read_real_motor_tsproj()]
        for expected_link = expected_links
          testCase.verifyThat(source, ...
            matlab.unittest.constraints.ContainsSubstring(expected_link));
        end
      end
    end

    function projectsPinPanasonicVirtualMotorAndDriverDefaults(testCase)
      for source = [testCase.read_vm_tsproj(), testCase.read_real_motor_tsproj()]
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.motor.inertia")), 7.1e-6, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.motor.ratedTorque")), 0.32, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.motor.tauLimit")), 1.11, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.motor.maxPermille")), 1000);
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.load.inertia")), 7.1e-6, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.coupling.stiffness")), 5.6059352998187553, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.coupling.damping")), 0.0004194811568097506, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "PlantParameter.taskDtNs")), 125000);
        testCase.verifyEqual(str2double(read_parameter_value(source, "MotorParams.ratedCurrentA")), 1.6, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "MotorParams.maxCurrentA")), 1.6, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "LoadParams.ratedCurrentA")), 1.6, "RelTol", 1e-14);
        testCase.verifyEqual(str2double(read_parameter_value(source, "LoadParams.maxCurrentA")), 1.6, "RelTol", 1e-14);
      end
    end
  end

  methods (Static, Access = private)
    function source = read_vm_tsproj()
      repo_root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
      source = string(fileread(fullfile(repo_root, "ExperimentHailMary.tsproj")));
    end

    function source = read_real_motor_tsproj()
      repo_root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
      source = string(fileread(fullfile(repo_root, "ExperimentHailMary.RealMotor.tsproj")));
    end
  end
end

function value = read_parameter_value(source, name)
pattern = sprintf("<Name>%s</Name>\\s*<Value>([^<]+)</Value>", ...
  regexptranslate('escape', char(name)));
tokens = regexp(char(source), pattern, 'tokens', 'once');
if isempty(tokens)
  value = "";
else
  value = string(tokens{1});
end
end
