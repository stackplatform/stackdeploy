package stackdeploy.generator;

class GeneratedFileWriter {
    public static function write(outputPath:String, content:String, force:Bool):FileWriteStatus {
        if (sys.FileSystem.exists(outputPath)) {
            if (!force) return Skipped(outputPath);
            sys.io.File.saveContent(outputPath, content);
            return Overwritten(outputPath);
        }
        var dir = haxe.io.Path.directory(outputPath);
        if (dir != null && dir != "") mkdirp(dir);
        sys.io.File.saveContent(outputPath, content);
        return Created(outputPath);
    }

    static function mkdirp(path:String):Void {
        if (path == "" || sys.FileSystem.exists(path)) return;
        var parent = haxe.io.Path.directory(path);
        if (parent != null && parent != "" && parent != path) mkdirp(parent);
        if (!sys.FileSystem.exists(path)) sys.FileSystem.createDirectory(path);
    }
}
