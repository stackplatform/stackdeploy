package stackdeploy.interpreter;

typedef PromptInterpretationResult = {
    var supported:Bool;
    var intent:String;             // "install_module" | "unsupported"
    var moduleId:Null<String>;
    var mappingId:Null<String>;
    var confidence:Float;          // 0.0–1.0
    var interpretationMode:String; // "rules"
    var suggestedInputs:Null<Dynamic>;
    var explanation:String;
    var warnings:Array<String>;
}
