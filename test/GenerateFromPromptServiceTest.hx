package;

import utest.Test;
import utest.Assert;
import stackdeploy.interpreter.GenerateFromPromptService;
import stackdeploy.interpreter.ModulePromptInterpreter;
import stackdeploy.interpreter.GenerateFromPromptRequest;

class GenerateFromPromptServiceTest extends Test {
    var tmpProject:String;
    var tmpTemplates:String;
    var service:GenerateFromPromptService;

    function setup() {
        tmpProject   = "/tmp/stackdeploy-svc-proj-"  + Std.string(Math.floor(Math.random() * 1000000));
        tmpTemplates = "/tmp/stackdeploy-svc-tmpl-"  + Std.string(Math.floor(Math.random() * 1000000));
        sys.FileSystem.createDirectory(tmpProject);
        buildMinimalTemplates(tmpTemplates);
        service = new GenerateFromPromptService(new ModulePromptInterpreter());
    }

    function teardown() {
        deleteRecursive(tmpProject);
        deleteRecursive(tmpTemplates);
    }

    // ── dry-run ──────────────────────────────────────────────────────────────

    function testDryRunWritesNoFiles() {
        var result = service.execute(req(true, false, new Map()));
        Assert.isTrue(result.success);
        Assert.isTrue(result.dryRun);
        Assert.isNull(result.installResult);
        Assert.notNull(result.plan);
        Assert.isTrue(result.plan.expectedFiles.length > 0);
        Assert.isFalse(sys.FileSystem.exists('$tmpProject/Shared'));
    }

    function testDryRunPlanHasCorrectModuleId() {
        var result = service.execute(req(true, false, new Map()));
        Assert.equals("request-form", result.plan.moduleId);
    }

    function testDryRunPlanHasExpectedMetadataFiles() {
        var result = service.execute(req(true, false, new Map()));
        Assert.isTrue(result.plan.expectedMetadataFiles.length > 0);
    }

    // ── apply ─────────────────────────────────────────────────────────────────

    function testApplyWritesFiles() {
        var result = service.execute(req(false, false, new Map()));
        Assert.isTrue(result.success);
        Assert.isFalse(result.dryRun);
        Assert.notNull(result.installResult);
        Assert.isTrue(result.installResult.createdFiles.length > 0);
    }

    // ── overrides ─────────────────────────────────────────────────────────────

    function testOverrideEntityNameWinsOverInterpreted() {
        var overrides = new Map<String,String>();
        overrides.set("entityName",  "GuitarLessonRequest");
        overrides.set("displayName", "Guitar Lesson Request");
        overrides.set("formTitle",   "Request a Guitar Lesson");
        overrides.set("adminTitle",  "Guitar Lesson Requests");
        var result = service.execute(req(true, false, overrides));
        Assert.isTrue(result.success);
        Assert.equals("GuitarLessonRequest", Reflect.field(result.plan.inputs, "entityName"));
    }

    // ── conflicts ─────────────────────────────────────────────────────────────

    function testConflictBlocksWithoutForce() {
        var conflictPath = '$tmpProject/Shared/app/services/ILessonRequestApi.hx';
        sys.FileSystem.createDirectory('$tmpProject/Shared/app/services');
        sys.io.File.saveContent(conflictPath, "existing");

        var result = service.execute(req(false, false, new Map()));
        Assert.isFalse(result.success);
        Assert.notNull(result.plan);
        Assert.equals("blocked", result.plan.risk);
        Assert.isTrue(result.plan.conflicts.length > 0);
        Assert.equals("existing", sys.io.File.getContent(conflictPath));
    }

    function testForceAllowsOverwrite() {
        var conflictPath = '$tmpProject/Shared/app/services/ILessonRequestApi.hx';
        sys.FileSystem.createDirectory('$tmpProject/Shared/app/services');
        sys.io.File.saveContent(conflictPath, "existing");

        var result = service.execute(req(false, true, new Map()));
        Assert.isTrue(result.success);
        Assert.isTrue(result.installResult.overwrittenFiles.length > 0);
    }

    // ── install record enrichment ─────────────────────────────────────────────

    function testInstallRecordContainsPromptMetadata() {
        service.execute(req(false, false, new Map()));
        var recordPath = '$tmpProject/.haxestack/modules/request-form.json';
        Assert.isTrue(sys.FileSystem.exists(recordPath));
        var record:Dynamic = haxe.Json.parse(sys.io.File.getContent(recordPath));
        Assert.equals("Add a lesson request form.", Reflect.field(record, "sourcePrompt"));
        Assert.equals("install_module", Reflect.field(record, "interpretedIntent"));
        Assert.equals("rules", Reflect.field(record, "interpretationMode"));
        Assert.isTrue(Reflect.field(record, "interpretationConfidence") > 0.0);
    }

    // ── rejection paths ───────────────────────────────────────────────────────

    function testLowConfidencePromptFails() {
        var r:GenerateFromPromptRequest = {
            prompt: "Make something nice.",
            projectPath: tmpProject, templatesPath: tmpTemplates,
            dryRun: true, force: false, overrides: new Map()
        };
        var result = service.execute(r);
        Assert.isFalse(result.success);
        Assert.isNull(result.plan);
        Assert.isTrue(result.errors.length > 0);
    }

    function testInvalidEntityNameFails() {
        var overrides = new Map<String,String>();
        overrides.set("entityName", "bad entity name!!!");
        var result = service.execute(req(true, false, overrides));
        Assert.isFalse(result.success);
        Assert.isTrue(result.errors.length > 0);
    }

    function testEmptyDisplayNameFails() {
        var overrides = new Map<String,String>();
        overrides.set("displayName", "");
        var result = service.execute(req(true, false, overrides));
        Assert.isFalse(result.success);
        Assert.isTrue(result.errors.length > 0);
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    function req(dryRun:Bool, force:Bool, overrides:Map<String,String>):GenerateFromPromptRequest {
        return {
            prompt: "Add a lesson request form.",
            projectPath: tmpProject,
            templatesPath: tmpTemplates,
            dryRun: dryRun,
            force: force,
            overrides: overrides
        };
    }

    static function buildMinimalTemplates(root:String):Void {
        sys.FileSystem.createDirectory('$root/request-form/files');
        sys.FileSystem.createDirectory('$root/request-form/metadata');

        // prompt-map.json — lesson mapping only (sufficient for all tests)
        sys.io.File.saveContent('$root/request-form/prompt-map.json', haxe.Json.stringify({
            moduleId: "request-form",
            mappings: [{
                id: "lesson-request",
                keywords: ["lesson", "music lesson", "guitar lesson", "piano lesson"],
                inputs: { entityName: "LessonRequest", displayName: "Lesson Request",
                          formTitle: "Request a Lesson", adminTitle: "Lesson Requests" }
            }]
        }));

        // module.json — minimal: 1 file def, 1 metadata def
        sys.io.File.saveContent('$root/request-form/module.json', haxe.Json.stringify({
            id: "request-form", name: "Request Form", description: "", version: "0.1.0",
            inputs: [
                { name: "entityName",  type: "string", required: true,  defaultValue: "RequestSubmission" },
                { name: "displayName", type: "string", required: true,  defaultValue: "Request Submission" },
                { name: "formTitle",   type: "string", required: true,  defaultValue: "Send a Request" },
                { name: "adminTitle",  type: "string", required: true,  defaultValue: "Request Submissions" }
            ],
            files: [
                { kind: "api-interface",
                  template: "files/IApi.hx.mustache",
                  output: "Shared/app/services/I{{{entityName}}}Api.hx" }
            ],
            metadata: [
                { template: "metadata/permissions.json.mustache", category: "permissions" }
            ],
            permissions: []
        }));

        // Template files
        sys.io.File.saveContent('$root/request-form/files/IApi.hx.mustache',
            "package app.services;\ninterface I{{{entityName}}}Api {}");
        sys.io.File.saveContent('$root/request-form/metadata/permissions.json.mustache',
            '{"entity":"{{{entityName}}}","permissions":["{{{entityName}}}.read","{{{entityName}}}.manage"]}');
    }

    static function deleteRecursive(path:String):Void {
        if (!sys.FileSystem.exists(path)) return;
        if (sys.FileSystem.isDirectory(path)) {
            for (f in sys.FileSystem.readDirectory(path)) deleteRecursive('$path/$f');
            sys.FileSystem.deleteDirectory(path);
        } else {
            sys.FileSystem.deleteFile(path);
        }
    }
}
