package stackdeploy.interpreter;

import haxe.Json;
import stackdeploy.generator.ModuleInstaller;
import stackdeploy.generator.ModuleManifest;
import stackdeploy.generator.GeneratorContext;
import stackdeploy.generator.ModuleInstallResult;
import app.services.document.DocumentTemplateEngine;

class GenerateFromPromptService {

    static inline var GENERATOR_VERSION = "0.2.0";

    var interpreter:IModulePromptInterpreter;

    public function new(interpreter:IModulePromptInterpreter) {
        this.interpreter = interpreter;
    }

    public function execute(request:GenerateFromPromptRequest):GenerateFromPromptResult {

        // Step 1 — interpret
        var interp = interpreter.interpret(request.prompt, request.templatesPath);
        if (!interp.supported || interp.confidence < 0.70) {
            return fail(request.dryRun, [interp.explanation]);
        }

        // Step 2 — load manifest
        var manifestPath = '${request.templatesPath}/${interp.moduleId}/module.json';
        if (!sys.FileSystem.exists(manifestPath)) {
            return fail(request.dryRun, ['Module manifest not found: ${interp.moduleId}']);
        }
        var manifest:ModuleManifest = Json.parse(sys.io.File.getContent(manifestPath));

        // Step 3 — merge inputs: suggestedInputs then overrides win
        var inputs = new Map<String, String>();
        if (interp.suggestedInputs != null) {
            for (f in Reflect.fields(interp.suggestedInputs))
                inputs.set(f, Reflect.field(interp.suggestedInputs, f));
        }
        for (k in request.overrides.keys()) inputs.set(k, request.overrides.get(k));

        // Step 4 — validate
        var entityName = inputs.get("entityName");
        if (entityName == null || !new EReg("^[A-Z][A-Za-z0-9]*$", "").match(entityName)) {
            var bad = entityName != null ? entityName : "(missing)";
            return fail(request.dryRun, ['Invalid entityName: "$bad". Must be PascalCase with no spaces, e.g. LessonRequest.']);
        }
        for (field in ["displayName", "formTitle", "adminTitle"]) {
            if (inputs.get(field) == null || inputs.get(field) == "")
                return fail(request.dryRun, ['Input "$field" must not be empty.']);
        }

        // Step 5 — build expected file list
        var context = GeneratorContext.build(inputs, manifest);
        var expectedFiles:Array<String> = [];
        for (fd in manifest.files) {
            var r = DocumentTemplateEngine.render(fd.output, context, null, null);
            expectedFiles.push(r.html);
        }
        var expectedMetadataFiles:Array<String> = [];
        for (md in manifest.metadata)
            expectedMetadataFiles.push('.haxestack/generated/${md.category}/${manifest.id}.json');

        // Step 6 — check conflicts
        var conflicts:Array<String> = [];
        for (f in expectedFiles)
            if (sys.FileSystem.exists('${request.projectPath}/$f')) conflicts.push(f);

        if (conflicts.length > 0 && !request.force) {
            var plan = buildPlan(request.prompt, interp, manifest, inputs, "blocked",
                expectedFiles, expectedMetadataFiles, conflicts, []);
            return {
                success: false, dryRun: request.dryRun, plan: plan, installResult: null,
                errors: ['Cannot generate: ${conflicts.length} file(s) already exist. Use --force to overwrite.'],
                warnings: []
            };
        }

        // Step 7 — compute risk
        var risk:String;
        if (conflicts.length > 0 && request.force) risk = "medium";
        else if (interp.confidence < 0.90)          risk = "needs_confirmation";
        else                                          risk = "low";

        var warnings:Array<String> = [];
        if (interp.confidence < 0.90)
            warnings.push('Note: Interpreted with medium confidence (${Math.round(interp.confidence * 100)}%). ${interp.explanation}');

        var plan = buildPlan(request.prompt, interp, manifest, inputs, risk,
            expectedFiles, expectedMetadataFiles, conflicts, warnings);

        // Step 8 — dry-run
        if (request.dryRun) {
            return { success: true, dryRun: true, plan: plan, installResult: null, errors: [], warnings: warnings };
        }

        // Step 9 — apply
        var installResult = ModuleInstaller.install(
            interp.moduleId, request.projectPath, request.templatesPath,
            inputs, request.force, GENERATOR_VERSION
        );

        // Enrich install record with prompt metadata
        var recordPath = '${request.projectPath}/.haxestack/modules/${interp.moduleId}.json';
        if (sys.FileSystem.exists(recordPath)) {
            try {
                var raw:Dynamic = Json.parse(sys.io.File.getContent(recordPath));
                Reflect.setField(raw, "sourcePrompt",            request.prompt);
                Reflect.setField(raw, "interpretedIntent",       "install_module");
                Reflect.setField(raw, "interpretationConfidence", interp.confidence);
                Reflect.setField(raw, "interpretationMode",      interp.interpretationMode);
                sys.io.File.saveContent(recordPath, Json.stringify(raw, null, "  "));
            } catch (_:Dynamic) {}
        }

        return { success: true, dryRun: false, plan: plan, installResult: installResult, errors: [], warnings: warnings };
    }

    static function buildPlan(
        sourcePrompt:String, interp:PromptInterpretationResult, manifest:ModuleManifest,
        inputs:Map<String,String>, risk:String,
        expectedFiles:Array<String>, expectedMetadataFiles:Array<String>,
        conflicts:Array<String>, warnings:Array<String>
    ):ModuleInstallPlan {
        var inputsObj:Dynamic = {};
        for (k in inputs.keys()) Reflect.setField(inputsObj, k, inputs.get(k));
        return {
            sourcePrompt:          sourcePrompt,
            interpretedIntent:     "install_module",
            moduleId:              manifest.id,
            moduleVersion:         manifest.version,
            confidence:            interp.confidence,
            risk:                  risk,
            requiresConfirmation:  true,
            inputs:                inputsObj,
            expectedFiles:         expectedFiles,
            expectedMetadataFiles: expectedMetadataFiles,
            conflicts:             conflicts,
            warnings:              warnings
        };
    }

    static function fail(dryRun:Bool, errors:Array<String>):GenerateFromPromptResult {
        return { success: false, dryRun: dryRun, plan: null, installResult: null, errors: errors, warnings: [] };
    }
}
