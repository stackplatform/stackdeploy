package stackdeploy.interpreter;

import haxe.Json;

private typedef PromptMappingEntry = {
    var id:String;
    var keywords:Array<String>;
    var inputs:Dynamic;
}

private typedef PromptMapFile = {
    var moduleId:String;
    var mappings:Array<PromptMappingEntry>;
}

class ModulePromptInterpreter implements IModulePromptInterpreter {

    static var BLOCKED_TERMS = [
        "stripe", "payment", "login", "sign in", "website", "full app",
        "android", "ios", "dashboard", "calendar", "booking system", "portal"
    ];

    public function new() {}

    public function interpret(prompt:String, templatesPath:String):PromptInterpretationResult {
        var normalized = normalize(prompt);

        for (term in BLOCKED_TERMS) {
            if (normalized.indexOf(term) != -1) {
                return unsupported(
                    'Prompt contains "$term" which is outside Phase 2 scope. ' +
                    'Supported: contact form, quote request, booking request, lesson request, ' +
                    'support request, inquiry form.',
                    0.0
                );
            }
        }

        var entries:Array<{moduleId:String, entry:PromptMappingEntry}> = [];
        if (sys.FileSystem.exists(templatesPath) && sys.FileSystem.isDirectory(templatesPath)) {
            for (dir in sys.FileSystem.readDirectory(templatesPath)) {
                var mapPath = '$templatesPath/$dir/prompt-map.json';
                if (!sys.FileSystem.exists(mapPath)) continue;
                try {
                    var pmf:PromptMapFile = Json.parse(sys.io.File.getContent(mapPath));
                    for (e in pmf.mappings) entries.push({ moduleId: pmf.moduleId, entry: e });
                } catch (_:Dynamic) {}
            }
        }

        var formBonus    = (normalized.indexOf("form") != -1) ? 1 : 0;
        var requestBonus = (normalized.indexOf("request") != -1 || normalized.indexOf("inquiry") != -1) ? 1 : 0;

        var bestConfidence = 0.0;
        var bestModuleId:String    = null;
        var bestMappingId:String   = null;
        var bestInputs:Dynamic     = null;

        for (item in entries) {
            var keywordScore = 0;
            for (kw in item.entry.keywords) {
                var kwNorm = kw.toLowerCase();
                if (normalized.indexOf(kwNorm) != -1) {
                    var score = (kwNorm.indexOf(" ") != -1) ? 2 : 1;
                    if (score > keywordScore) keywordScore = score;
                }
            }
            if (keywordScore == 0) continue;

            var confidence = (keywordScore + formBonus + requestBonus) / 4.0;
            if (confidence > bestConfidence) {
                bestConfidence = confidence;
                bestModuleId   = item.moduleId;
                bestMappingId  = item.entry.id;
                bestInputs     = item.entry.inputs;
            }
        }

        if (bestConfidence < 0.70) {
            return unsupported(
                "Prompt did not match any supported Phase 2 module with sufficient confidence. " +
                "Supported prompts: contact form, quote request form, booking request form, " +
                "lesson request form, support request form, inquiry form.",
                bestConfidence
            );
        }

        var note = bestConfidence < 0.90
            ? 'Interpreted with medium confidence (${Math.round(bestConfidence * 100)}%). Matched module: $bestModuleId.'
            : 'Matched module: $bestModuleId.';

        return {
            supported:          true,
            intent:             "install_module",
            moduleId:           bestModuleId,
            mappingId:          bestMappingId,
            confidence:         bestConfidence,
            interpretationMode: "rules",
            suggestedInputs:    bestInputs,
            explanation:        note,
            warnings:           []
        };
    }

    static function normalize(s:String):String {
        var lower    = s.toLowerCase();
        var stripped = new EReg("[^a-z0-9\\s]", "g").replace(lower, "");
        return StringTools.trim(new EReg("\\s+", "g").replace(stripped, " "));
    }

    static function unsupported(explanation:String, confidence:Float):PromptInterpretationResult {
        return {
            supported:          false,
            intent:             "unsupported",
            moduleId:           null,
            mappingId:          null,
            confidence:         confidence,
            interpretationMode: "rules",
            suggestedInputs:    null,
            explanation:        explanation,
            warnings:           []
        };
    }
}
