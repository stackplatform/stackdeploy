package stackdeploy.commands;

import stackdeploy.interpreter.GenerateFromPromptService;
import stackdeploy.interpreter.ModulePromptInterpreter;
import stackdeploy.interpreter.GenerateFromPromptRequest;
import stackdeploy.interpreter.ModuleInstallPlan;

class GenerateFromPromptCommand {

    static inline var DEFAULT_TEMPLATES = "./Templates/modules";

    public static function run(args:Array<String>):Void {
        if (args.length == 0 || args[0] == "--help") { printUsage(); return; }

        var prompt:String      = null;
        var projectPath:String = null;
        var templatesPath:String = null;
        var dryRun = false;
        var apply  = false;
        var force  = false;
        var overrides = new Map<String, String>();

        var i = 0;
        while (i < args.length) {
            var a = args[i];
            if (a == "--project" && i + 1 < args.length) {
                projectPath = args[++i];
            } else if (a == "--templates" && i + 1 < args.length) {
                templatesPath = args[++i];
            } else if (a == "--dry-run") {
                dryRun = true;
            } else if (a == "--apply") {
                apply = true;
            } else if (a == "--force") {
                force = true;
            } else if (a.length > 2 && a.substr(0, 2) == "--") {
                var key = a.substr(2);
                if (i + 1 < args.length && !StringTools.startsWith(args[i + 1], "--")) {
                    overrides.set(key, args[++i]);
                }
            } else if (prompt == null && !StringTools.startsWith(a, "--")) {
                prompt = a;
            }
            i++;
        }

        if (prompt == null) { Sys.println("Error: prompt is required."); printUsage(); Sys.exit(1); }
        if (projectPath == null) { Sys.println("Error: --project is required."); Sys.exit(1); }
        if (dryRun && apply) { Sys.println("Error: --dry-run and --apply are mutually exclusive."); Sys.exit(1); }
        if (templatesPath == null) templatesPath = DEFAULT_TEMPLATES;
        if (!dryRun && !apply) {
            Sys.println("No action specified — running in dry-run mode. Use --apply to generate files.\n");
            dryRun = true;
        }

        var service = new GenerateFromPromptService(new ModulePromptInterpreter());
        var req:GenerateFromPromptRequest = {
            prompt:       prompt,
            projectPath:  projectPath,
            templatesPath: templatesPath,
            dryRun:       dryRun,
            force:        force,
            overrides:    overrides
        };

        var result = service.execute(req);

        if (!result.success) {
            for (e in result.errors) Sys.println('Error: $e');
            if (result.plan != null && result.plan.conflicts.length > 0) {
                Sys.println("\nConflicting files:");
                for (c in result.plan.conflicts) Sys.println('  $c');
                Sys.println("\nUse --force to overwrite.");
            }
            Sys.exit(1);
        }

        printPlanHeader(prompt, result.plan, result.warnings);

        if (dryRun) {
            Sys.println("Files that would be created:");
            for (f in result.plan.expectedFiles) Sys.println('  $f');
            Sys.println("");
            Sys.println("Metadata that would be created:");
            for (f in result.plan.expectedMetadataFiles) Sys.println('  $f');
            Sys.println("");
            Sys.println("No files were written.");
        } else {
            var r = result.installResult;
            if (r.createdFiles.length > 0) {
                Sys.println("Files created:");
                for (f in r.createdFiles) Sys.println('  $f');
                Sys.println("");
            }
            if (r.skippedFiles.length > 0) {
                Sys.println("Files skipped (use --force to overwrite):");
                for (f in r.skippedFiles) Sys.println('  $f');
                Sys.println("");
            }
            if (r.overwrittenFiles.length > 0) {
                Sys.println("Files overwritten:");
                for (f in r.overwrittenFiles) Sys.println('  $f');
                Sys.println("");
            }
            if (r.metadataFiles.length > 0) {
                Sys.println("Metadata created:");
                for (f in r.metadataFiles) Sys.println('  $f');
                Sys.println("");
            }
            if (r.warnings.length > 0) {
                Sys.println("Warnings:");
                for (w in r.warnings) Sys.println('  WARNING: $w');
                Sys.println("");
            }
            Sys.println('Install record: .haxestack/modules/${result.plan.moduleId}.json');
        }
    }

    static function printPlanHeader(prompt:String, plan:ModuleInstallPlan, warnings:Array<String>):Void {
        Sys.println('Prompt:\n$prompt\n');
        Sys.println('Interpreted action:\nInstall module ${plan.moduleId}\n');
        Sys.println('Feature:\n${Reflect.field(plan.inputs, "entityName")}\n');
        Sys.println("Generator inputs:");
        Sys.println('  entityName:  ${Reflect.field(plan.inputs, "entityName")}');
        Sys.println('  displayName: ${Reflect.field(plan.inputs, "displayName")}');
        Sys.println('  formTitle:   ${Reflect.field(plan.inputs, "formTitle")}');
        Sys.println('  adminTitle:  ${Reflect.field(plan.inputs, "adminTitle")}');
        Sys.println("");
        if (warnings.length > 0) {
            for (w in warnings) Sys.println(w);
            Sys.println("");
        }
    }

    static function printUsage():Void {
        Sys.println("Usage: stackdeploy generate-from-prompt <prompt> --project <path> [options]");
        Sys.println("Options:");
        Sys.println("  --project <path>      Target project directory (required)");
        Sys.println("  --templates <path>    Templates root (default: ./Templates/modules)");
        Sys.println("  --dry-run             Show plan without writing files (default if no action given)");
        Sys.println("  --apply               Generate files");
        Sys.println("  --force               Overwrite existing generated files");
        Sys.println("  --entityName <name>   Override entity class name");
        Sys.println("  --displayName <name>  Override human-readable name");
        Sys.println("  --formTitle <title>   Override public form title");
        Sys.println("  --adminTitle <title>  Override admin section title");
    }
}
