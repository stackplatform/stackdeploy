package app.services.environment;
class HmmInstallService {
    public static var instance = new HmmInstallService();
    public function new() {}
    public function runInstall(dir:String, opts:Dynamic, cb:Dynamic->Void):Void { cb({success:true, stepId:"hmm", message:"", exitCode:0}); }
}
