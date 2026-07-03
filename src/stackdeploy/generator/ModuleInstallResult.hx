package stackdeploy.generator;

typedef ModuleInstallResult = {
    moduleId:String,
    moduleVersion:String,
    installedAt:String,
    generatorVersion:String,
    inputs:Dynamic,
    context:Dynamic,
    createdFiles:Array<String>,
    skippedFiles:Array<String>,
    overwrittenFiles:Array<String>,
    metadataFiles:Array<String>,
    warnings:Array<String>
}
