package app.services.environment;
enum abstract EnvironmentCheckStatus(String) {
    var Ready = "ready";
    var Warning = "warning";
    var Missing = "missing";
    var Error = "error";
    var Unknown = "unknown";
    var Optional = "optional";
}
typedef FixAction = { id:String, label:String, ?description:String, ?command:String, ?opensUrl:String }
typedef EnvironmentCheck = {
    ?id:String,
    name:String,
    ?category:String,
    status:EnvironmentCheckStatus,
    message:String,
    ?detectedVersion:String,
    ?detectedPath:String,
    ?details:String,
    ?fixActions:Array<FixAction>
}
