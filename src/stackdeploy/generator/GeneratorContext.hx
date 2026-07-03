package stackdeploy.generator;

class GeneratorContext {

    public static function build(inputs:Map<String, String>, manifest:ModuleManifest):Dynamic {
        var entityName  = inputs.get("entityName")  != null ? inputs.get("entityName")  : "RequestSubmission";
        var displayName = inputs.get("displayName") != null ? inputs.get("displayName") : "Request Submission";
        var formTitle   = inputs.get("formTitle")   != null ? inputs.get("formTitle")   : "Send a Request";
        var adminTitle  = inputs.get("adminTitle")  != null ? inputs.get("adminTitle")  : "Request Submissions";

        var kebab        = camelToKebab(entityName);
        var routeSegment = kebab + "s";
        var tableName    = "hs_" + StringTools.replace(routeSegment, "-", "_");

        var now = Date.now();
        var iso = DateTools.format(now, "%Y-%m-%dT%H:%M:%SZ");

        return {
            entityName:              entityName,
            entityNameLower:         lcFirst(entityName),
            entityNamePlural:        entityName + "s",
            entityNameKebab:         kebab,
            routeSegment:            routeSegment,
            tableName:               tableName,
            displayName:             displayName,
            displayNamePlural:       displayName + "s",
            formTitle:               formTitle,
            adminTitle:              adminTitle,
            apiInterfaceName:        "I" + entityName + "Api",
            apiImplementationName:   entityName + "ApiService",
            repositoryInterfaceName: "I" + entityName + "Repository",
            repositoryImplName:      "Sqlite" + entityName + "Repository",
            modelsFileName:          entityName + "Models",
            moduleId:                manifest.id,
            moduleVersion:           manifest.version,
            generatedAt:             iso
        };
    }

    static function lcFirst(s:String):String {
        if (s == null || s.length == 0) return s;
        return s.charAt(0).toLowerCase() + s.substr(1);
    }

    static function camelToKebab(s:String):String {
        var buf = new StringBuf();
        for (i in 0...s.length) {
            var c = s.charAt(i);
            if (i > 0 && c >= 'A' && c <= 'Z') buf.add('-');
            buf.add(c.toLowerCase());
        }
        return buf.toString();
    }
}
