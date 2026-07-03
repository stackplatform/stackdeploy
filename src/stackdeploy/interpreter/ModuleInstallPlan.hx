package stackdeploy.interpreter;

typedef ModuleInstallPlan = {
    var sourcePrompt:String;
    var interpretedIntent:String;
    var moduleId:String;
    var moduleVersion:String;
    var confidence:Float;
    var risk:String;              // "low" | "needs_confirmation" | "medium" | "blocked"
    var requiresConfirmation:Bool;
    var inputs:Dynamic;
    var expectedFiles:Array<String>;
    var expectedMetadataFiles:Array<String>;
    var conflicts:Array<String>;
    var warnings:Array<String>;
}
