package stackdeploy.interpreter;

class ModulePromptInterpreter implements IModulePromptInterpreter {
    public function new() {}
    public function interpret(prompt:String, templatesPath:String):PromptInterpretationResult {
        return { supported: false, intent: "unsupported", moduleId: null, mappingId: null,
                 confidence: 0.0, interpretationMode: "rules", suggestedInputs: null,
                 explanation: "stub", warnings: [] };
    }
}
