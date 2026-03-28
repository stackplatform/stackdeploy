package tools;

import sys.io.Process;
import Sys;
using StringTools;

class Main {
    public static function main() {
        var args = Sys.args();
        
        // When running via haxelib, the last argument is the CWD
        var cwd = args.pop();
        
        if (args.length == 0) {
            printHelp();
            return;
        }
        
        var command = args[0];
        
        switch (command) {
            case "server-stop":
                stopServer(args);
            case "help":
                printHelp();
            default:
                Sys.println("Unknown command: " + command);
                printHelp();
                Sys.exit(1);
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
        Sys.println("stackdeploy CLI v0.1.0");
        Sys.println("Usage: haxelib run stackdeploy <command> [options]");
        Sys.println("");
        Sys.println("Available commands:");
        Sys.println("  server-stop [name]   Terminate server processes. Defaults to StackServer.exe.");
        Sys.println("                       Options: --name, -n <name>");
        Sys.println("  help                 Display this help message.");
        Sys.println("");
        Sys.println("Examples:");
        Sys.println("  haxelib run stackdeploy server-stop");
        Sys.println("  haxelib run stackdeploy server-stop MyOtherServer.exe");
        Sys.println("  haxelib run stackdeploy server-stop --name CustomProcess.exe");
    }
}

