package stackdeploy.interpreter;

typedef GenerateFromPromptRequest = {
    var prompt:String;
    var projectPath:String;
    var templatesPath:String;
    var dryRun:Bool;
    var force:Bool;
    var overrides:Map<String, String>;
}
