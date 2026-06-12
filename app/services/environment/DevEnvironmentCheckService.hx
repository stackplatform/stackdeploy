package app.services.environment;
class DevEnvironmentCheckService {
    public static var instance = new DevEnvironmentCheckService();
    public function new() {}
    public function check(t:Dynamic, p:Dynamic, cb:Dynamic->Void):Void { cb(null); }
}
