package app.services.environment;
class ProjectOnboardingService {
    public static var instance = new ProjectOnboardingService();
    public function new() {}
    public function onboardProject(cfg:Dynamic, cb:Dynamic->Void):Void { cb(null); }
}
