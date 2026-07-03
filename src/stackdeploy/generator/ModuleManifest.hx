package stackdeploy.generator;

typedef ModuleManifest = {
    id:String,
    name:String,
    description:String,
    version:String,
    ?keywords:Array<String>,
    inputs:Array<ModuleInputDef>,
    files:Array<ModuleFileDef>,
    metadata:Array<ModuleMetadataDef>,
    ?permissions:Array<String>
}

typedef ModuleInputDef = {
    name:String,
    type:String,
    required:Bool,
    ?defaultValue:String
}

typedef ModuleFileDef = {
    kind:String,
    template:String,
    output:String
}

typedef ModuleMetadataDef = {
    template:String,
    category:String
}
