package stackdeploy.interpreter;

import stackdeploy.generator.ModuleInstallResult;

typedef GenerateFromPromptResult = {
    var success:Bool;
    var dryRun:Bool;
    var plan:Null<ModuleInstallPlan>;
    var installResult:Null<ModuleInstallResult>;
    var errors:Array<String>;
    var warnings:Array<String>;
}
