import stackdeploy.generator.ModuleInstaller;
import utest.Assert;
import utest.Test;

class ModuleInstallerTest extends Test {
    var tmpProject:String;
    var tmpTemplates:String;

    function setup() {
        tmpProject   = "/tmp/stackdeploy-proj-"      + Std.string(Math.floor(Math.random() * 1000000));
        tmpTemplates = "/tmp/stackdeploy-templates-" + Std.string(Math.floor(Math.random() * 1000000));
        sys.FileSystem.createDirectory(tmpProject);
        sys.FileSystem.createDirectory('$tmpTemplates/test-mod');
        sys.FileSystem.createDirectory('$tmpTemplates/test-mod/files/Shared/app/services');
        sys.FileSystem.createDirectory('$tmpTemplates/test-mod/metadata');

        // Minimal module.json
        sys.io.File.saveContent('$tmpTemplates/test-mod/module.json', haxe.Json.stringify({
            id: "test-mod", name: "Test", description: "", version: "0.1.0",
            inputs: [{ name: "entityName", type: "string", required: true }],
            files: [
                { kind: "api-interface",
                  template: "files/Shared/app/services/ITestApi.hx.mustache",
                  output: "Shared/app/services/I{{{entityName}}}Api.hx" }
            ],
            metadata: [
                { template: "metadata/permissions.json.mustache", category: "permissions" }
            ],
            permissions: []
        }));

        // Minimal template files
        sys.io.File.saveContent(
            '$tmpTemplates/test-mod/files/Shared/app/services/ITestApi.hx.mustache',
            "package app.services;\ninterface I{{{entityName}}}Api {}"
        );
        sys.io.File.saveContent(
            '$tmpTemplates/test-mod/metadata/permissions.json.mustache',
            '{"entity":"{{{entityName}}}"}'
        );
    }

    function testInstallCreatesFiles() {
        var inputs = ["entityName" => "Widget"];
        var result = ModuleInstaller.install("test-mod", tmpProject, tmpTemplates, inputs, false, "0.1.0");

        Assert.equals(1, result.createdFiles.length);
        Assert.equals("Shared/app/services/IWidgetApi.hx", result.createdFiles[0]);
        Assert.isTrue(sys.FileSystem.exists('$tmpProject/Shared/app/services/IWidgetApi.hx'));
        Assert.equals(1, result.metadataFiles.length);
        Assert.isTrue(sys.FileSystem.exists('$tmpProject/.haxestack/generated/permissions/test-mod.json'));
        Assert.isTrue(sys.FileSystem.exists('$tmpProject/.haxestack/modules/test-mod.json'));
    }

    function testSkipsExistingWithoutForce() {
        var inputs = ["entityName" => "Widget"];
        ModuleInstaller.install("test-mod", tmpProject, tmpTemplates, inputs, false, "0.1.0");
        var result2 = ModuleInstaller.install("test-mod", tmpProject, tmpTemplates, inputs, false, "0.1.0");
        Assert.equals(0, result2.createdFiles.length);
        Assert.equals(1, result2.skippedFiles.length);
    }
}
