package stackdeploy.generator;

enum FileWriteStatus {
    Created(path:String);
    Skipped(path:String);
    Overwritten(path:String);
}
