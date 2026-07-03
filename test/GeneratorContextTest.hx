package;

import utest.UTest;
import utest.Test;
import utest.Assert;
import stackdeploy.generator.GeneratorContext;
import stackdeploy.generator.ModuleManifest;

class GeneratorContextTest extends Test {
    function testDerivedNames() {
        var inputs = [
            "entityName"  => "LessonRequest",
            "displayName" => "Lesson Request",
            "formTitle"   => "Request a Lesson",
            "adminTitle"  => "Lesson Requests"
        ];
        var manifest:ModuleManifest = {
            id: "request-form", name: "Request Form", description: "", version: "0.1.0",
            inputs: [], files: [], metadata: [], permissions: []
        };
        var ctx:Dynamic = GeneratorContext.build(inputs, manifest);

        Assert.equals("lessonRequest",                 Reflect.field(ctx, "entityNameLower"));
        Assert.equals("lesson-request",                Reflect.field(ctx, "entityNameKebab"));
        Assert.equals("lesson-requests",               Reflect.field(ctx, "routeSegment"));
        Assert.equals("LessonRequests",                Reflect.field(ctx, "entityNamePlural"));
        Assert.equals("Lesson Requests",               Reflect.field(ctx, "displayNamePlural"));
        Assert.equals("ILessonRequestApi",             Reflect.field(ctx, "apiInterfaceName"));
        Assert.equals("LessonRequestApiService",       Reflect.field(ctx, "apiImplementationName"));
        Assert.equals("ILessonRequestRepository",      Reflect.field(ctx, "repositoryInterfaceName"));
        Assert.equals("SqliteLessonRequestRepository", Reflect.field(ctx, "repositoryImplName"));
        Assert.equals("LessonRequestModels",           Reflect.field(ctx, "modelsFileName"));
        Assert.equals("hs_lesson_requests",            Reflect.field(ctx, "tableName"));
        Assert.equals("request-form",                  Reflect.field(ctx, "moduleId"));
        Assert.equals("0.1.0",                         Reflect.field(ctx, "moduleVersion"));
    }
}

