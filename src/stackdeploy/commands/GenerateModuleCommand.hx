package stackdeploy.commands;

import stackdeploy.generator.ModuleInstaller;
import stackdeploy.generator.ModuleInstallResult;

class GenerateModuleCommand {
    static inline var DEFAULT_TEMPLATES = "./Templates/modules";
    static inline var GENERATOR_VERSION = "0.1.0";

    public static function run(args:Array<String>):Void {
        if (args.length == 0 || args[0] == "--help") { printUsage(); return; }

        var moduleId      = args[0];
        var projectPath   = getArg(args, "--project");
        var templatesPath = getArg(args, "--templates");
        var force         = hasFlag(args, "--force");

        if (projectPath == null) {
            Sys.println("Error: --project is required");
            Sys.exit(1);
        }
        if (templatesPath == null) templatesPath = DEFAULT_TEMPLATES;

        var inputs = new Map<String, String>();
        var i = 1;
        while (i < args.length) {
            var a = args[i];
            if (a.length > 2 && a.substr(0, 2) == "--"
                    && a != "--project" && a != "--templates" && a != "--force") {
                var name = a.substr(2);
                if (i + 1 < args.length && !StringTools.startsWith(args[i + 1], "--")) {
                    inputs.set(name, args[i + 1]);
                    i += 2;
                    continue;
                }
            }
            i++;
        }

        var result = ModuleInstaller.install(moduleId, projectPath, templatesPath, inputs, force, GENERATOR_VERSION);
        printSummary(result, moduleId);
    }

    static function printSummary(r:ModuleInstallResult, moduleId:String):Void {
        var ctx = r.context;
        Sys.println('Generated module: ${r.moduleId}');
        Sys.println('Feature: ${Reflect.field(ctx, "entityName")}');
        Sys.println("");
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
        Sys.println('Install record: .haxestack/modules/${moduleId}.json');
        Sys.println("");
        printNextSteps(ctx);
    }

    static function printNextSteps(ctx:Dynamic):Void {
        var rs  = Reflect.field(ctx, "routeSegment");
        var tn  = Reflect.field(ctx, "tableName");
        var ri  = Reflect.field(ctx, "repositoryInterfaceName");
        var rl  = Reflect.field(ctx, "repositoryImplName");
        var ai  = Reflect.field(ctx, "apiInterfaceName");
        var av  = Reflect.field(ctx, "apiImplementationName");
        var enl = Reflect.field(ctx, "entityNameLower");
        Sys.println("Next manual steps:");
        Sys.println('  1. Add migration: Server/migrations/sqlite/YYYYMMDDNN-${rs}.sql');
        Sys.println('       CREATE TABLE ${tn} (');
        Sys.println('         id TEXT PRIMARY KEY, project_id TEXT NOT NULL,');
        Sys.println('         name TEXT NOT NULL, email TEXT NOT NULL, message TEXT NOT NULL,');
        Sys.println("         status TEXT NOT NULL DEFAULT 'pending',");
        Sys.println('         created_at REAL NOT NULL);');
        Sys.println('  2. Register in Server/Source/app/ServerApp.hx configureServices():');
        Sys.println('       services.addService(ServiceType.Scoped, app.domain.${ri}, app.infrastructure.sqlite.${rl});');
        Sys.println('       ServiceRouter.register(this, services, ServiceType.Scoped, app.services.${ai}, app.services.${av});');
        Sys.println('  3. Register in PlatformUI/Source/app/services/AsyncServiceRegistry.hx:');
        Sys.println('       public var ${enl}s:AsyncClient<app.services.${ai}>;');
        Sys.println('       Wire in createClients() and updateToken().');
        Sys.println('  4. Server routing is via AutoRouter — no Controller generated.');
        Sys.println('  5. Client views use AutoClient<${ai}> — no custom HTTP wrapper generated.');
    }

    static function getArg(args:Array<String>, name:String):String {
        for (i in 0...args.length)
            if (args[i] == name && i + 1 < args.length) return args[i + 1];
        return null;
    }

    static function hasFlag(args:Array<String>, name:String):Bool {
        for (a in args) if (a == name) return true;
        return false;
    }

    static function printUsage():Void {
        Sys.println("Usage: stackdeploy generate-module <moduleId> --project <path> [options]");
        Sys.println("Options:");
        Sys.println("  --project <path>      Target project directory (required)");
        Sys.println("  --templates <path>    Templates root (default: ./Templates/modules)");
        Sys.println("  --force               Overwrite existing files");
        Sys.println("  --entityName <name>   Entity class name, e.g. LessonRequest");
        Sys.println('  --displayName <name>  Human name, e.g. "Lesson Request"');
        Sys.println('  --formTitle <title>   Public form page title');
        Sys.println('  --adminTitle <title>  Admin section title');
    }
}
