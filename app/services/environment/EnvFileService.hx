package app.services.environment;
class EnvFileService {
    public static var instance = new EnvFileService();
    public function new() {}
    public function updateEnvFile(dir:String, key:String, val:String):Bool { return false; }
}
