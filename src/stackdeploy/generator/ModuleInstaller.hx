package stackdeploy.generator;

import app.services.document.DocumentTemplateEngine;
import haxe.Json;

class ModuleInstaller {

    public static function install(
        moduleId:String,
        projectPath:String,
        templatesPath:String,
        inputs:Map<String, String>,
        force:Bool,
        generatorVersion:String
    ):ModuleInstallResult {
        var manifestPath = '$templatesPath/$moduleId/module.json';
        if (!sys.FileSystem.exists(manifestPath)) {
            Sys.println('Error: Module manifest not found at $manifestPath');
            Sys.exit(1);
        }

        var manifest:ModuleManifest = Json.parse(sys.io.File.getContent(manifestPath));

        // Validate + apply defaults
        for (inputDef in manifest.inputs) {
            if (!inputs.exists(inputDef.name)) {
                if (inputDef.defaultValue != null) {
                    inputs.set(inputDef.name, inputDef.defaultValue);
                } else if (inputDef.required) {
                    Sys.println('Error: Required input --${inputDef.name} is missing');
                    Sys.exit(1);
                }
            }
        }

        var context = GeneratorContext.build(inputs, manifest);

        var created:Array<String>       = [];
        var skipped:Array<String>       = [];
        var overwritten:Array<String>   = [];
        var metadataFiles:Array<String> = [];
        var warnings:Array<String>      = [];

        // Render source files
        for (fileDef in manifest.files) {
            var templatePath = '$templatesPath/$moduleId/${fileDef.template}';
            if (!sys.FileSystem.exists(templatePath)) {
                warnings.push('Template not found: ${fileDef.template}');
                continue;
            }

            var templateContent = sys.io.File.getContent(templatePath);

            var pathResult = DocumentTemplateEngine.render(fileDef.output, context, null, null);
            if (pathResult.errors.length > 0)
                warnings.push('Path render error in ${fileDef.output}: ${pathResult.errors[0].message}');
            var resolvedPath = '$projectPath/${pathResult.html}';

            var contentResult = DocumentTemplateEngine.render(templateContent, context, null, null);
            for (e in contentResult.errors)
                warnings.push('Render error in ${fileDef.template} line ${e.line}: ${e.message}');

            switch (GeneratedFileWriter.write(resolvedPath, contentResult.html, force)) {
                case Created(p):     created.push(relativize(p, projectPath));
                case Skipped(p):     skipped.push(relativize(p, projectPath));
                case Overwritten(p): overwritten.push(relativize(p, projectPath));
            }
        }

        // Render metadata files
        for (metaDef in manifest.metadata) {
            var templatePath = '$templatesPath/$moduleId/${metaDef.template}';
            if (!sys.FileSystem.exists(templatePath)) {
                warnings.push('Metadata template not found: ${metaDef.template}');
                continue;
            }
            var contentResult = DocumentTemplateEngine.render(
                sys.io.File.getContent(templatePath), context, null, null
            );
            for (e in contentResult.errors)
                warnings.push('Metadata render error in ${metaDef.template}: ${e.message}');

            var outPath = '$projectPath/.haxestack/generated/${metaDef.category}/$moduleId.json';
            // Metadata is always regenerated — it is derived output, not user-editable
            GeneratedFileWriter.write(outPath, contentResult.html, true);
            metadataFiles.push('.haxestack/generated/${metaDef.category}/$moduleId.json');
        }

        // Build install result
        var inputsObj:Dynamic = {};
        for (k in inputs.keys()) Reflect.setField(inputsObj, k, inputs.get(k));

        var result:ModuleInstallResult = {
            moduleId:         manifest.id,
            moduleVersion:    manifest.version,
            installedAt:      Reflect.field(context, "generatedAt"),
            generatorVersion: generatorVersion,
            inputs:           inputsObj,
            context:          context,
            createdFiles:     created,
            skippedFiles:     skipped,
            overwrittenFiles: overwritten,
            metadataFiles:    metadataFiles,
            warnings:         warnings
        };

        // Write install record (always force=true so re-runs update it)
        var recordPath = '$projectPath/.haxestack/modules/$moduleId.json';
        GeneratedFileWriter.write(recordPath, Json.stringify(result, null, "  "), true);

        return result;
    }

    static function relativize(absPath:String, projectPath:String):String {
        var prefix = StringTools.endsWith(projectPath, "/") ? projectPath : projectPath + "/";
        return StringTools.startsWith(absPath, prefix)
            ? absPath.substr(prefix.length)
            : absPath;
    }
}
