package app.services.environment;
enum abstract EnvironmentCheckStatus(String) {
    var OK = "ok";
    var Warning = "warning";
    var Missing = "missing";
    var Error = "error";
}
typedef EnvironmentCheck = { name:String, status:EnvironmentCheckStatus, message:String }
