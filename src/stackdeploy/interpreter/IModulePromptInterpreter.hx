package stackdeploy.interpreter;

interface IModulePromptInterpreter {
    function interpret(prompt:String, templatesPath:String):PromptInterpretationResult;
}
