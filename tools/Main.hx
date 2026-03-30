package tools;

import sys.io.Process;
import sys.io.File;
import sys.FileSystem;
import haxe.Json;
import Sys;
using StringTools;

class Main {
    public static function main() {
        var args = Sys.args();
        
        // When running via haxelib, the last argument is the CWD
        var cwd = args.pop();
        if (cwd != null && FileSystem.exists(cwd) && FileSystem.isDirectory(cwd)) {
            Sys.setCwd(cwd);
        }
        
        if (args.length == 0) {
            printHelp();
            return;
        }
        
        var command = args[0];
        
        switch (command) {
            case "server-stop":
                stopServer(args);
            case "release":
                handleRelease(args);
            case "build":
                handleBuild(args);
            case "push":
                handlePush(args);
            case "help":
                printHelp();
            default:
                Sys.println("Unknown command: " + command);
                printHelp();
                Sys.exit(1);
        }
    }
    
    static function getTool():ReleaseTool {
        var apiKey = Sys.getEnv("STACK_PROJECT_KEY");
        if (apiKey == null || apiKey == "") {
            Sys.println("Error: STACK_PROJECT_KEY environment variable not set.");
            Sys.exit(1);
        }
        var apiUrl = Sys.getEnv("STACK_SERVER_URL");
        if (apiUrl == null || apiUrl == "") {
            apiUrl = "https://haxestack.com";
        }
        return new ReleaseTool(apiKey, apiUrl);
    }

    static function handleRelease(args:Array<String>) {
        if (args.length < 2) {
            printHelp();
            return;
        }
        var subCommand = args[1];
        switch (subCommand) {
            case "create":
                var version = getArg(args, "--version");
                var description = getArg(args, "--description");
                var gitSha = getArg(args, "--git-sha");
                
                if (version == null) {
                    Sys.println("Error: Missing --version");
                    Sys.exit(1);
                }
                
                if (gitSha == null) {
                    gitSha = runGitCommand("rev-parse HEAD");
                }
                
                var tool = getTool();
                var id = tool.createRelease(version, gitSha, null, description);
                Sys.println(id); // Output ID for piping
                
            case "finalize":
                var releaseId = getArg(args, "--release");
                if (releaseId == null) {
                    Sys.println("Error: Missing --release <id>");
                    Sys.exit(1);
                }
                var tool = getTool();
                tool.finalizeRelease(releaseId);
                Sys.println("Release finalized successfully.");
                
            default:
                Sys.println("Unknown release command: " + subCommand);
                Sys.exit(1);
        }
    }

    static function handleBuild(args:Array<String>) {
        if (args.length < 2) {
            printHelp();
            return;
        }
        var subCommand = args[1];
        switch (subCommand) {
            case "upload":
                var releaseId = getArg(args, "--release");
                var name = getArg(args, "--name");
                var platform = getArg(args, "--platform");
                var arch = getArg(args, "--arch");
                var file = getArg(args, "--file");
                
                if (releaseId == null || platform == null || arch == null || file == null) {
                    Sys.println("Error: Missing required arguments for build upload");
                    Sys.println("Usage: build upload --release <id> --platform <p> --arch <a> --file <f>");
                    Sys.exit(1);
                }
                
                var tool = getTool();
                var buildId = tool.addBuild(releaseId, platform, arch);
                tool.uploadArtifact(buildId, file);
                Sys.println("Build uploaded successfully: " + buildId);
                
            default:
                Sys.println("Unknown build command: " + subCommand);
                Sys.exit(1);
        }
    }

    static function handlePush(args:Array<String>) {
        var configFile = getArg(args, "--config") != null ? getArg(args, "--config") : "stackdeploy.json";
        if (!FileSystem.exists(configFile)) {
            Sys.println("Error: Config file not found: " + configFile);
            Sys.exit(1);
        }
        
        var content = File.getContent(configFile);
        var config:Dynamic = Json.parse(content);
        
        var version = config.version;
        if (version == "auto" || version == null) {
            version = runGitCommand("describe --tags --always");
        }
        
        var gitSha = runGitCommand("rev-parse HEAD");
        
        Sys.println('Creating release $version ($gitSha)...');
        var tool = getTool();
        var releaseId = tool.createRelease(version, gitSha, null, config.description);
        
        var builds:Array<Dynamic> = config.builds;
        if (builds != null) {
            for (build in builds) {
                Sys.println('Target: ${build.name} (${build.platform}/${build.arch})');
                
                if (build.command != null) {
                    Sys.println('Running build command: ${build.command}');
                    var exitCode = Sys.command(build.command);
                    if (exitCode != 0) {
                        Sys.println('Build command failed with exit code $exitCode');
                        Sys.exit(exitCode);
                    }
                }
                
                if (build.artifact != null) {
                    Sys.println('Uploading artifact: ${build.artifact}');
                    var buildId = tool.addBuild(releaseId, build.platform, build.arch);
                    tool.uploadArtifact(buildId, build.artifact);
                }
            }
        }
        
        Sys.println("Finalizing release...");
        tool.finalizeRelease(releaseId);
        Sys.println("Push completed successfully!");
    }

    static function getArg(args:Array<String>, name:String):String {
        for (i in 0...args.length) {
            if (args[i] == name && i + 1 < args.length) {
                return args[i + 1];
            }
        }
        return null;
    }

    static function runGitCommand(cmd:String):String {
        try {
            var proc = new sys.io.Process("git", cmd.split(" "));
            var out = proc.stdout.readAll().toString().trim();
            proc.close();
            return out;
        } catch (e:Dynamic) {
            return "unknown";
        }
    }

    static function stopServer(args:Array<String>) {
        var targetName = "StackServer.exe";
        
        // Skip the command itself
        if (args.length > 1) {
            var i = 1;
            while(i < args.length) {
                var arg = args[i];
                if (arg == "--name" || arg == "-n") {
                    if (i + 1 < args.length) {
                        targetName = args[i + 1];
                        i++;
                    }
                } else if (!arg.startsWith("-")) {
                    targetName = arg;
                }
                i++;
            }
        }

        var isTargetRunning = isProcessRunning(targetName);
        var isHlRunning = isProcessRunning("hl.exe");

        if (!isTargetRunning && !isHlRunning) {
            Sys.println("No running server processes found (" + targetName + ").");
            return;
        }

        Sys.println("Stopping server processes...");
        
        if (isTargetRunning) {
            Sys.command("cmd", ["/c", 'taskkill /F /IM $targetName /T >nul 2>&1']);
        }
        
        // Only kill hl.exe if we're targeting the default or if it's explicitly named
        if (isHlRunning && (targetName == "StackServer.exe" || targetName == "hl.exe")) {
            Sys.command("cmd", ["/c", "taskkill /F /IM hl.exe /T >nul 2>&1"]);
        }
        
        Sys.println("Server stopped successfully.");
    }

    static function isProcessRunning(name:String):Bool {
        try {
            var proc = new sys.io.Process("tasklist", ["/FI", 'IMAGENAME eq $name', "/NH"]);
            var out = proc.stdout.readAll().toString();
            proc.close();
            return out.indexOf(name) != -1;
        } catch (e:Dynamic) {
            return false;
        }
    }
    
    static function printHelp() {
        Sys.println("stackdeploy CLI v0.2.0");
        Sys.println("Usage: haxelib run stackdeploy <command> [options]");
        Sys.println("");
        Sys.println("Available commands:");
        Sys.println("  release create       Create a new release.");
        Sys.println("                       Options: --version <v>, --description <d>, --git-sha <s>");
        Sys.println("  release finalize     Mark a release as ready for deployment.");
        Sys.println("                       Options: --release <id>");
        Sys.println("  build upload         Register and upload a build artifact.");
        Sys.println("                       Options: --release <id>, --platform <p>, --arch <a>, --file <f>");
        Sys.println("  push                 Run builds and upload everything from stackdeploy.json.");
        Sys.println("                       Options: --config <path>");
        Sys.println("  server-stop [name]   Terminate server processes. Defaults to StackServer.exe.");
        Sys.println("                       Options: --name, -n <name>");
        Sys.println("  help                 Display this help message.");
        Sys.println("");
        Sys.println("Examples:");
        Sys.println("  haxelib run stackdeploy push");
        Sys.println("  haxelib run stackdeploy release create --version 1.0.0");
    }
}

