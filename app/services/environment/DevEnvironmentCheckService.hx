package app.services.environment;
class DevEnvironmentCheckService {
    public static var instance = new DevEnvironmentCheckService();
    public function new() {}
    public function check(t:Dynamic, p:Dynamic, cb:Dynamic->Void, done:Void->Void):Void { done(); }
}
