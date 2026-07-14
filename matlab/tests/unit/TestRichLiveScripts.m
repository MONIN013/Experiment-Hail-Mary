classdef TestRichLiveScripts < matlab.unittest.TestCase
  methods (Test)
    function experimentScriptsHaveValidRichOutputStructure(testCase)
      scripts = TestRichLiveScripts.experimentScripts();
      image_count = 0;
      for script = reshape(scripts, 1, [])
        report = experiment.liveeditor.inspect(script);
        testCase.verifyTrue(report.valid, ...
          strjoin(cellstr(report.issues), newline));
        testCase.verifyTrue(report.is_live_code);
        testCase.verifyEqual(report.appendix_count, 1);
        testCase.verifyEqual(report.metadata_count, 1);
        testCase.verifyGreaterThan(report.section_count, 0);
        testCase.verifyGreaterThan(report.text_count, 0);
        testCase.verifyGreaterThan(numel(report.image_output_ids), 0);
        image_count = image_count + numel(report.image_output_ids);
        testCase.verifyEqual( ...
          unique(report.output_reference_ids), ...
          unique(report.output_definition_ids));
      end
      testCase.verifyEqual(image_count, 18, ...
        "The four rich experiment scripts must retain all 18 plot outputs.");
    end

    function missingDefinitionIsRejected(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      source = string(fileread(fixture));
      source = regexprep(source, ...
        '%\[output:[0-9a-f]+\]', '%[output:deadbeef]', "once");
      TestRichLiveScripts.writeText(fixture, source);

      report = experiment.liveeditor.inspect(fixture);
      testCase.verifyFalse(report.valid);
      testCase.verifyTrue(any(contains(report.issues, ...
        "without appendix definitions")));
    end

    function corruptPngIsRejected(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      source = string(fileread(fixture));
      source = string(regexprep(char(source), ...
        'iVBORw0KGgo', 'QUFBQUFBQUFB', "once"));
      TestRichLiveScripts.writeText(fixture, source);

      report = experiment.liveeditor.inspect(fixture);
      testCase.verifyFalse(report.valid);
      testCase.verifyTrue(any(contains(report.issues, "PNG magic bytes")));
    end

    function duplicateMetadataJsonIsRejected(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      source = string(fileread(fixture));
      metadata = "%   data: {""layout"":""onright""}";
      source = replace(source, metadata, metadata + newline + metadata);
      TestRichLiveScripts.writeText(fixture, source);

      report = experiment.liveeditor.inspect(fixture);
      testCase.verifyFalse(report.valid);
      testCase.verifyTrue(any(contains(report.issues, ...
        "metadata must contain exactly one JSON")));
    end

    function outputReferenceReusedAcrossLiveSectionsIsRejected(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      source = string(fileread(fixture));
      token = regexp(char(source), ...
        '%\[output:(?!group:)([A-Za-z0-9_-]+)\]', "tokens", "once");
      testCase.assertNotEmpty(token);
      output_id = string(token{1});
      duplicate_source = "%%" + newline + ...
        "duplicate_reference_probe = 1; %[output:" + output_id + "]" + newline;
      source = replace(source, "%[appendix]", ...
        duplicate_source + "%[appendix]");
      TestRichLiveScripts.writeText(fixture, source);

      report = experiment.liveeditor.inspect(fixture);
      testCase.verifyFalse(report.valid);
      testCase.verifyTrue(any(contains(report.issues, ...
        "exactly one Live section")));
    end

    function duplicateAppendixOutputJsonIsRejected(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      source = string(fileread(fixture));
      token = regexp(char(source), ...
        ['(?m)^%\[output:[A-Za-z0-9_-]+\]\r?\n' ...
         '%   data: ([^\r\n]+)\r?\n%---'], "tokens", "once");
      testCase.assertNotEmpty(token);
      duplicate_id = "duplicatejson";
      duplicate_source = "%%" + newline + ...
        "duplicate_json_probe = 1; %[output:" + duplicate_id + "]" + newline;
      duplicate_definition = "%[output:" + duplicate_id + "]" + newline + ...
        "%   data: " + string(token{1}) + newline + "%---" + newline;
      source = replace(source, "%[appendix]", ...
        duplicate_source + "%[appendix]");
      source = replace(source, "%[metadata:view]", ...
        duplicate_definition + "%[metadata:view]");
      TestRichLiveScripts.writeText(fixture, source);

      report = experiment.liveeditor.inspect(fixture);
      testCase.verifyFalse(report.valid);
      testCase.verifyTrue(any(contains(report.issues, ...
        "output JSON payloads must be unique")));
    end

    function staleOutputBijectionIsRefreshableBeforeFreshExecution(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      TestRichLiveScripts.injectStaleOutput(fixture);

      testCase.verifyFalse(experiment.liveeditor.inspect(fixture).valid);
      report = experiment.liveeditor.assert_refreshable(fixture);
      testCase.verifyTrue(any(contains(report.issues, ...
        "Appendix outputs without source references")));
    end

    function refreshProbeAllowsTargetToRepairStaleBijection(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      TestRichLiveScripts.injectStaleOutput(fixture);
      backup_root = fullfile(testCase.createTemporaryFolder(), "backups");

      report = experiment.liveeditor.refresh( ...
        fixture, "backup_root", backup_root, ...
        "target_executor", @TestRichLiveScripts.removeStaleOutput);

      testCase.verifyFalse(report.probe.valid);
      testCase.verifyTrue(report.after.valid);
      testCase.verifyTrue(isfile(report.backup_path));
    end

    function refreshableCheckStillRejectsCorruptPng(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      source = string(fileread(fixture));
      source = string(regexprep(char(source), ...
        'iVBORw0KGgo', 'QUFBQUFBQUFB', "once"));
      TestRichLiveScripts.writeText(fixture, source);

      testCase.verifyError(@() ...
        experiment.liveeditor.assert_refreshable(fixture), ...
        "experiment:liveeditor:InvalidRefreshSource");
    end

    function refreshCreatesBackupAndRemovesProbe(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      backup_root = fullfile(testCase.createTemporaryFolder(), "backups");
      report = experiment.liveeditor.refresh( ...
        fixture, ...
        "backup_root", backup_root, ...
        "probe_executor", @(~) 0, ...
        "target_executor", @(~) 0);

      testCase.verifyTrue(isfile(report.backup_path));
      testCase.verifyFalse(isfile(report.probe_path));
      testCase.verifyTrue(report.after.valid);
      testCase.verifyEqual( ...
        string(fileread(fixture)), string(fileread(report.backup_path)));
    end

    function defaultProbeValidatesStructureWithoutExecutingScenario(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      backup_root = fullfile(testCase.createTemporaryFolder(), "backups");

      report = experiment.liveeditor.refresh( ...
        fixture, "backup_root", backup_root, ...
        "target_executor", @(~) 0);

      testCase.verifyTrue(report.probe.valid);
      testCase.verifyEqual(report.probe_execution_time_s >= 0, true);
      testCase.verifyFalse(isfile(report.probe_path));
    end

    function refreshRestoresTargetAfterExecutionFailure(testCase)
      fixture = testCase.copyFixture("exp02_FeedBack.m");
      original = string(fileread(fixture));
      backup_root = fullfile(testCase.createTemporaryFolder(), "backups");

      testCase.verifyError(@() experiment.liveeditor.refresh( ...
        fixture, ...
        "backup_root", backup_root, ...
        "probe_executor", @(~) 0, ...
        "target_executor", @TestRichLiveScripts.corruptAndFail), ...
        "experiment:liveeditor:InjectedFailure");
      testCase.verifyEqual(string(fileread(fixture)), original);
    end

    function implementationNeverUsesDocumentTextRewrite(testCase)
      matlab_root = TestRichLiveScripts.matlabRoot();
      implementation = string(fileread(fullfile(matlab_root, ...
        "+experiment", "+liveeditor", "refresh.m")));
      testCase.verifyFalse(contains(implementation, "Document.Text"));
    end

    function liveArtifactsExposeFreshUtcCompletionTime(testCase)
      for script = reshape(TestRichLiveScripts.experimentScripts(), 1, [])
        source = string(fileread(script));
        appendix = strfind(source, "%[appendix]");
        testCase.assertNotEmpty(appendix);
        authored = extractBefore(source, appendix(1));
        testCase.verifyTrue(contains(authored, '"completedAtUtc"'));
        testCase.verifyTrue(contains(authored, ...
          '"TimeZone", "UTC"'));
      end
    end
  end

  methods (Access = private)
    function fixture = copyFixture(testCase, name)
      scripts = TestRichLiveScripts.experimentScripts();
      source = scripts(endsWith(scripts, name));
      testCase.assertNumElements(source, 1);
      fixture = fullfile(testCase.createTemporaryFolder(), name);
      testCase.assertTrue(copyfile(source, fixture));
    end
  end

  methods (Static, Access = private)
    function root = matlabRoot()
      root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
    end

    function scripts = experimentScripts()
      experiment_dir = fullfile(TestRichLiveScripts.matlabRoot(), "experiment");
      scripts = fullfile(experiment_dir, [ ...
        "exp01_SysId.m"; ...
        "exp02_FeedBack.m"; ...
        "exp03_FeedForward.m"; ...
        "exp04_ILC.m"]);
    end

    function writeText(file_path, text)
      file = fopen(file_path, "w", "n", "UTF-8");
      cleanup = onCleanup(@() fclose(file));
      fwrite(file, char(text), "char");
      clear cleanup;
    end

    function varargout = corruptAndFail(file_path) %#ok<STOUT>
      TestRichLiveScripts.writeText(file_path, "corrupt");
      error("experiment:liveeditor:InjectedFailure", "Injected failure.");
    end

    function injectStaleOutput(file_path)
      source = string(fileread(file_path));
      source = replace(source, "%[metadata:view]", ...
        TestRichLiveScripts.staleOutputBlock() + "%[metadata:view]");
      TestRichLiveScripts.writeText(file_path, source);
    end

    function elapsed_s = removeStaleOutput(file_path)
      source = string(fileread(file_path));
      TestRichLiveScripts.writeText(file_path, ...
        replace(source, TestRichLiveScripts.staleOutputBlock(), ""));
      elapsed_s = 0;
    end

    function value = staleOutputBlock()
      value = "%[output:stale123]" + newline + ...
        "%   data: {""dataType"":""text"",""outputData"":{}}" + newline + ...
        "%---" + newline;
    end
  end
end
