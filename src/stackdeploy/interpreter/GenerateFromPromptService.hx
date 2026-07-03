package stackdeploy.interpreter;

class GenerateFromPromptService {
    var interpreter:IModulePromptInterpreter;
    public function new(interpreter:IModulePromptInterpreter) { this.interpreter = interpreter; }
    public function execute(request:GenerateFromPromptRequest):GenerateFromPromptResult {
        return { success: false, dryRun: request.dryRun, plan: null, installResult: null,
                 errors: ["stub"], warnings: [] };
    }
}
