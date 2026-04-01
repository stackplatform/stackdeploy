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
        var last = args.length > 0 ? args[args.length - 1] : null;
        if (last != null && FileSystem.exists(last) && FileSystem.isDirectory(last)) {
            Sys.setCwd(args.pop());
        }
        
        if (args.length == 0) {
            printHelp();
            return;
        }
        
        var command = args[0];
        
        switch (command) {
            case "server-stop":
                stopServer(args);
            case "compile":
                handleCompile(args);
            case "release":
                handleRelease(args);
            case "build":
                handleBuild(args);
            case "push":
                handlePush(args);
            case "deploy":
                handleDeploy(args);
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
        
        // If not set as env var, try to read from .env file
        if (apiKey == null || apiKey == "") {
            apiKey = readFromEnvFile("STACK_PROJECT_KEY");
        }
        
        if (apiKey == null || apiKey == "") {
            Sys.println("Error: STACK_PROJECT_KEY environment variable not set.");
            Sys.println("Set it or create a .env file with: STACK_PROJECT_KEY=spk_proj_...");
            Sys.exit(1);
        }
        
        var apiUrl = Sys.getEnv("STACK_SERVER_URL");
        if (apiUrl == null || apiUrl == "") {
            apiUrl = readFromEnvFile("STACK_SERVER_URL");
        }
        if (apiUrl == null || apiUrl == "") {
            apiUrl = "https://haxestack.com";
        }
        return new ReleaseTool(apiKey, apiUrl);
    }

    static function readFromEnvFile(key:String):String {
        if (!FileSystem.exists(".env")) {
            return null;
        }
        
        try {
            var content = File.getContent(".env");
            var lines = content.split("\n");
            for (line in lines) {
                line = line.trim();
                if (line.startsWith("#") || line == "") continue;
                
                if (line.indexOf("=") > 0) {
                    var eqIndex = line.indexOf("=");
                    var varName = line.substring(0, eqIndex).trim();
                    var varValue = line.substring(eqIndex + 1).trim();
                    
                    // Remove quotes if present
                    if (varValue.length >= 2) {
                        var first = varValue.charAt(0);
                        var last = varValue.charAt(varValue.length - 1);
                        if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
                            varValue = varValue.substring(1, varValue.length - 1);
                        }
                    }
                    
                    if (varName == key) {
                        return varValue;
                    }
                }
            }
        } catch (e:Dynamic) {
            return null;
        }
        
        return null;
    }

    static function handleCompile(args:Array<String>) {
        var version = getArg(args, "--version");
        var platform = getArg(args, "--platform");
        var outputDir = getArg(args, "--output");
        
        // Default version to 0.0.0 if not specified
        if (version == null) {
            version = "0.0.0";
        }
        
        // Map platform names to lime targets
        var limePlatform:String = null;
        if (platform == null || platform == "windows") {
            limePlatform = "windows";
        } else if (platform == "linux") {
            limePlatform = "linux";
        } else if (platform == "macos") {
            limePlatform = "mac";
        } else {
            Sys.println("Error: Unknown platform: " + platform);
            Sys.exit(1);
        }
        
        if (outputDir == null) {
            outputDir = "builds";
        }
        
        // Ensure output directory exists
        if (!FileSystem.exists(outputDir)) {
            FileSystem.createDirectory(outputDir);
        }
        
        var cwd = Sys.getCwd();
        Sys.println('[Compile] Building for $limePlatform (v$version)...');
        
        // Step 1: Build client HTML and copy to server static directory
        Sys.println("\n[Step 1/3] Building client HTML...");
        Sys.setCwd(cwd + "/Client");
        var clientHtmlExit = Sys.command("haxelib", ["run", "lime", "build", "html5", "-release"]);
        if (clientHtmlExit != 0) {
            Sys.println("Error: Client HTML build failed");
            Sys.exit(clientHtmlExit);
        }
        Sys.println("✅ Client HTML built");
        
        // Copy HTML to server static directory
        Sys.println("   Copying to server static directory...");
        var htmlSourceDir = cwd + "/Client/Export/html5/bin";
        var htmlDestDir = cwd + "/Server/static/client";
        copyDirectory(htmlSourceDir, htmlDestDir);
        Sys.println("✅ Copied to " + htmlDestDir);
        
        // Step 2: Build server using HashLink
        Sys.println("\n[Step 2/3] Building server (HashLink)...");
        Sys.setCwd(cwd + "/Server");
        var serverExit = Sys.command("haxelib", ["run", "lime", "build", "hashlink", "-release"]);
        if (serverExit != 0) {
            Sys.println("Error: Server build failed");
            Sys.exit(serverExit);
        }
        Sys.println("✅ Server built");
        
        // Step 3: Build client using HashLink
        Sys.println("\n[Step 3/3] Building client (HashLink)...");
        Sys.setCwd(cwd + "/Client");
        var clientHlExit = Sys.command("haxelib", ["run", "lime", "build", "hashlink", "-release"]);
        if (clientHlExit != 0) {
            Sys.println("Error: Client HashLink build failed");
            Sys.exit(clientHlExit);
        }
        Sys.println("✅ Client built");
        
        Sys.setCwd(cwd);
        
        // Zip server
        Sys.println("\n[Package] Creating server zip...");
        var serverZip = '$outputDir/server-${limePlatform}-x64-$version.zip';
        zipDirectory("Server/Export/hl/bin", serverZip);
        Sys.println("✅ Server zip created: " + serverZip);
        
        // Zip client
        Sys.println("[Package] Creating client zip...");
        var clientZip = '$outputDir/client-${limePlatform}-x64-$version.zip';
        zipDirectory("Client/Export/hl/bin", clientZip);
        Sys.println("✅ Client zip created: " + clientZip);
        
        // Output result
        Sys.println("");
        Sys.println("✅ Build complete!");
        Sys.println("Ready for release:");
        Sys.println('  • $serverZip');
        Sys.println('  • $clientZip');
        Sys.println("");
        Sys.println("Next step:");
        Sys.println('  haxelib run stackdeploy release create --version $version');
    }

    static function zipDirectory(sourceDir:String, destZip:String) {
        if (!FileSystem.exists(sourceDir)) {
            throw 'Source directory not found: $sourceDir';
        }
        
        // Remove old zip if exists
        if (FileSystem.exists(destZip)) {
            FileSystem.deleteFile(destZip);
        }
        
        // Convert to absolute paths for PowerShell
        var absSourceDir = FileSystem.fullPath(sourceDir);
        var absDestZip = FileSystem.fullPath(destZip);
        
        // Use system zip command - platform agnostic approach
        var exitCode = if (Sys.systemName() == "Windows") {
            // PowerShell: Compress-Archive - simpler approach without Get-ChildItem
            Sys.command("powershell", [
                "-NoProfile",
                "-Command",
                'Compress-Archive -Path "${absSourceDir}" -DestinationPath "${absDestZip}" -Force'
            ]);
        } else {
            // Unix: zip
            var proc = new sys.io.Process("bash", ["-c", 'cd "$sourceDir" && zip -r "../${absDestZip}" .'  ]);
            var exitCode = proc.exitCode();
            proc.close();
            exitCode;
        };
        
        if (exitCode != 0) {
            throw 'Failed to create zip: $destZip';
        }
    }

    static function deleteRecursive(path:String) {
        if (!FileSystem.exists(path)) {
            return;
        }
        if (FileSystem.isDirectory(path)) {
            for (file in FileSystem.readDirectory(path)) {
                deleteRecursive(path + "/" + file);
            }
            FileSystem.deleteDirectory(path);
        } else {
            FileSystem.deleteFile(path);
        }
    }

    static function copyDirectory(src:String, dest:String) {
        if (!FileSystem.exists(src)) {
            throw 'Source directory not found: $src';
        }
        
        // Create destination if it doesn't exist
        if (FileSystem.exists(dest)) {
            deleteRecursive(dest);
        }
        FileSystem.createDirectory(dest);
        
        // Copy all files recursively
        function copyRecursive(srcPath:String, destPath:String) {
            if (FileSystem.isDirectory(srcPath)) {
                for (file in FileSystem.readDirectory(srcPath)) {
                    var srcFile = srcPath + "/" + file;
                    var destFile = destPath + "/" + file;
                    copyRecursive(srcFile, destFile);
                }
            } else {
                if (!FileSystem.exists(destPath)) {
                    var destDir = haxe.io.Path.directory(destPath);
                    if (!FileSystem.exists(destDir)) {
                        FileSystem.createDirectory(destDir);
                    }
                }
                File.copy(srcPath, destPath);
            }
        }
        
        copyRecursive(src, dest);
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

    static function handleDeploy(args:Array<String>) {
        var version = getArg(args, "--version");
        var tag = getArg(args, "--env");
        if (tag == null) tag = getArg(args, "--tag");

        if (version == null) {
            Sys.println("Error: --version <v> is required.");
            Sys.exit(1);
        }

        var tool = getTool();
        Sys.println('Triggering deployment of version $version' + (tag != null ? ' to $tag matches...' : ' to all instances...'));
        
        var jobs:Array<Dynamic> = tool.deployReleaseByVersion(version, tag);
        if (jobs.length == 0) {
            Sys.println("No matching instances found for deployment.");
            return;
        }

        Sys.println('Created ${jobs.length} deployment jobs. Monitoring progress...');
        
        // Monitoring loop
        var completed = new Map<String, Bool>();
        var total = jobs.length;
        var finishedCount = 0;

        while (finishedCount < total) {
            Sys.sleep(2);
            finishedCount = 0;
            
            for (job in jobs) {
                var jobId:String = job.id;
                if (completed.exists(jobId)) {
                    finishedCount++;
                    continue;
                }

                // Poll for status
                // We need an endpoint for job status by ID
                try {
                    var statusUrl = '${tool.apiUrl}/v1/projects/${tool.projectId}/deployments/${job.instanceId}/jobs/$jobId';
                    var status:Dynamic = tool.request("GET", statusUrl, null);
                    
                    var currentStatus:String = status.status;
                    var progress:Float = status.progress;
                    
                    if (currentStatus == "succeeded" || currentStatus == "completed") {
                        Sys.println('  [Node ${job.instanceId}] SUCCESS: $currentStatus');
                        completed.set(jobId, true);
                        finishedCount++;
                    } else if (currentStatus == "failed") {
                        Sys.println('  [Node ${job.instanceId}] FAILED: ${status.errorMessage}');
                        completed.set(jobId, true);
                        finishedCount++;
                    } else {
                        Sys.println('  [Node ${job.instanceId}] $currentStatus (${progress}%)');
                    }
                } catch(e:Dynamic) {
                    // Silently retry
                }
            }
        }

        Sys.println("Deployment finished.");
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
        Sys.println("  compile              Build server and client, create zips for release.");
        Sys.println("                       Options: [--version <v>] (defaults to 0.0.0), [--platform <p>], [--output <dir>]");
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
        Sys.println("  haxelib run stackdeploy compile --version 1.0.0");
        Sys.println("  haxelib run stackdeploy push");
        Sys.println("  haxelib run stackdeploy release create --version 1.0.0");
    }
}

