package tools;

import sys.io.Process;
import sys.io.File;
import sys.FileSystem;
import haxe.Json;
import Sys;
using StringTools;

import app.services.environment.DevEnvironmentCheckService;
import app.services.environment.EnvironmentModels;
import app.services.environment.EnvironmentModels.EnvironmentCheck;
import app.services.environment.EnvironmentModels.EnvironmentCheckStatus;
import app.services.environment.EnvironmentConfig;
import app.services.environment.EnvFileService;
import app.services.environment.HmmInstallService;
import app.services.environment.ProjectTemplateCloneService;
import app.services.environment.ProjectOnboardingService;
import app.models.BootstrapModels.BootstrapStepResult;

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
            case "refresh-env":
                handleRefreshEnv(args);
            case "doctor":
                handleDoctor(args);
            case "init":
                handleInit(args);
            case "hmm":
                var subCommand = args.length > 1 ? args[1] : null;
                if (subCommand == "install") {
                    handleHmmInstall(args);
                } else {
                    Sys.println("Unknown hmm command: " + subCommand);
                    printHelp();
                    Sys.exit(1);
                }
            case "env":
                var subCommand = args.length > 1 ? args[1] : null;
                if (subCommand == "set-project") {
                    handleEnvSetProject(args);
                } else {
                    Sys.println("Unknown env command: " + subCommand);
                    printHelp();
                    Sys.exit(1);
                }
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

    static function getBuildNumber(?args:Array<String>):Int {
        // Explicit arg override
        if (args != null) {
            var buildArg = getArg(args, "--build");
            if (buildArg != null) return Std.parseInt(buildArg);
        }

        // CI check: GitHub Actions
        var ghRun = Sys.getEnv("GITHUB_RUN_NUMBER");
        if (ghRun != null && ghRun != "") {
            return Std.parseInt(ghRun);
        }
        
        if (!FileSystem.exists("build_number")) {
            return 0;
        }
        try {
            return Std.parseInt(File.getContent("build_number").trim());
        } catch (e:Dynamic) {
            return 0;
        }
    }

    static function incrementBuildNumber(?args:Array<String>):Int {
        // Check if GitHub Actions is active - we don't increment local file there
        var ghRun = Sys.getEnv("GITHUB_RUN_NUMBER");
        if ((ghRun != null && ghRun != "") || (args != null && getArg(args, "--build") != null)) {
            return getBuildNumber(args);
        }

        var current = getBuildNumber();
        var next = current + 1;
        File.saveContent("build_number", Std.string(next));
        return next;
    }

    static function handleCompile(args:Array<String>) {
        var version = getArg(args, "--version");
        var platform = getArg(args, "--platform");
        var outputDir = getArg(args, "--output");
        
        // If version not provided by CLI, try to read from stackdeploy.json
        if (version == null) {
            var configFile = "stackdeploy.json";
            if (FileSystem.exists(configFile)) {
                try {
                    var config:Dynamic = Json.parse(File.getContent(configFile));
                    if (config.version != null && config.version != "auto") {
                        version = config.version;
                    }
                } catch (e:Dynamic) {}
            }
        }
        
        // Default version to 0.0.0 if not specified anywhere
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
        var buildNumber = incrementBuildNumber(args);
        Sys.println('[Compile] Building for $limePlatform (v$version, build $buildNumber)...');
        
        // Step 1: Build client HTML and copy to server static directory
        Sys.println("\n[Step 1/3] Building client HTML...");
        Sys.setCwd(cwd + "/Client");
        var clientHtmlExit = Sys.command("haxelib", ["run", "lime", "build", "html5", "-release"]);
        if (clientHtmlExit != 0) {
            Sys.println("Error: Client HTML build failed");
            Sys.exit(clientHtmlExit);
        }
        Sys.println("[OK] Client HTML built");
        
        // Copy HTML to server static directory
        Sys.println("   Copying to server static directory...");
        var htmlSourceDir = cwd + "/Client/Export/html5/bin";
        var htmlDestDir = cwd + "/Server/static/client";
        copyDirectory(htmlSourceDir, htmlDestDir);
        Sys.println("[OK] Copied to " + htmlDestDir);
        
        // Step 2: Build server using HashLink
        Sys.println("\n[Step 2/3] Building server (HashLink)...");
        Sys.setCwd(cwd + "/Server");
        var serverExit = Sys.command("haxelib", ["run", "lime", "build", "hashlink", "-release"]);
        if (serverExit != 0) {
            Sys.println("Error: Server build failed");
            Sys.exit(serverExit);
        }
        Sys.println("[OK] Server built");
        
        // Step 3: Build client using HashLink
        Sys.println("\n[Step 3/3] Building client (HashLink)...");
        Sys.setCwd(cwd + "/Client");
        var clientHlExit = Sys.command("haxelib", ["run", "lime", "build", "hashlink", "-release"]);
        if (clientHlExit != 0) {
            Sys.println("Error: Client HashLink build failed");
            Sys.exit(clientHlExit);
        }
        Sys.println("[OK] Client built");
        
        Sys.setCwd(cwd);
        
        // Zip server
        Sys.println("\n[Package] Creating server zip...");
        var serverZip = '$outputDir/server-${limePlatform}-x64-$version-b$buildNumber.zip';
        zipDirectory("Server/Export/hl/bin", serverZip);
        Sys.println("[OK] Server zip created: " + serverZip);
        
        // Zip client
        Sys.println("[Package] Creating client zip...");
        var clientZip = '$outputDir/client-${limePlatform}-x64-$version-b$buildNumber.zip';
        zipDirectory("Client/Export/hl/bin", clientZip);
        Sys.println("[OK] Client zip created: " + clientZip);
        
        // Output result
        Sys.println("");
        Sys.println("[OK] Build complete!");
        Sys.println("Ready for release:");
        Sys.println('  * $serverZip');
        Sys.println('  * $clientZip');
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
                
            case "list":
                var tool = getTool();
                var releases = tool.listReleases();
                Sys.println(StringTools.rpad("ID", " ", 30) + " | " + StringTools.rpad("Version", " ", 15) + " | " + StringTools.rpad("Status", " ", 10) + " | " + "Created");
                Sys.println("----------------------------------------------------------------------");
                for (r in releases) {
                    var line = StringTools.rpad(r.id, " ", 30) + " | " + 
                               StringTools.rpad(r.version, " ", 15) + " | " + 
                               StringTools.rpad(r.status, " ", 10) + " | " + 
                               Date.fromTime(r.createdAt).toString();
                    Sys.println(line);
                }
                
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
                var buildId = tool.addBuild(releaseId, platform, arch, name);
                tool.uploadArtifact(buildId, file);
                Sys.println("Build uploaded successfully: " + buildId);
            
            case "list":
                var version = getArg(args, "--version");
                var releaseId = getArg(args, "--release");
                var tool = getTool();
                
                if (releaseId == null && version != null) {
                    var r = tool.getReleaseByVersion(version);
                    if (r != null) releaseId = r.id;
                }
                
                if (releaseId == null) {
                    Sys.println("Error: Must provide --release <id> or --version <v>");
                    Sys.exit(1);
                }
                
                var builds = tool.listBuilds(releaseId);
                Sys.println(StringTools.rpad("Name", " ", 20) + " | " + StringTools.rpad("Platform", " ", 15) + " | " + StringTools.rpad("Status", " ", 10) + " | " + "Artifact");
                Sys.println("---------------------------------------------------------------------------");
                for (b in builds) {
                    var platStr = b.platform + "/" + b.architecture;
                    var line = StringTools.rpad(b.name, " ", 20) + " | " + 
                               StringTools.rpad(platStr, " ", 15) + " | " + 
                               StringTools.rpad(b.status, " ", 10) + " | " + 
                               (b.binaryUrl != null ? b.binaryUrl : "N/A");
                    Sys.println(line);
                }
                
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
        var config:Dynamic = {};
        if (FileSystem.exists(configFile)) {
            var content = File.getContent(configFile);
            config = Json.parse(content);
        }
        
        var version = config.version;
        if (version == "auto" || version == null) {
            version = runGitCommand("describe --tags --always");
        }
        
        var gitSha = runGitCommand("rev-parse HEAD");
        var buildNumber = getBuildNumber(args);
        
        Sys.println('Creating release $version ($gitSha) - Build $buildNumber...');
        var tool = getTool();
        var releaseId = tool.createRelease(version, gitSha, null, config.description);
        
        var builds:Array<Dynamic> = config.builds;
        if (builds == null) {
            builds = [];
        }
        
        // Auto-detect artifacts if builds is empty or we want to supplement it
        var outputDir = "builds"; // Default
        if (FileSystem.exists(outputDir) && FileSystem.isDirectory(outputDir)) {
            var files = FileSystem.readDirectory(outputDir);
            for (file in files) {
                // Look for zips that match our version and build number
                // Pattern: server-platform-arch-version-bBuildNum.zip
                if (file.endsWith(".zip") && file.indexOf("-b" + buildNumber + ".zip") != -1) {
                    var parts = file.split("-");
                    if (parts.length >= 4) {
                        var name = parts[0];
                        var platform = parts[1];
                        var arch = parts[2];
                        // version and build number are in the rest
                        
                        var artifactPath = outputDir + "/" + file;
                        
                        // Check if this artifact is already in the explicit builds list
                        var alreadyExists = false;
                        for (b in builds) {
                            if (b.artifact == artifactPath) {
                                alreadyExists = true;
                                break;
                            }
                        }
                        
                        if (!alreadyExists) {
                            Sys.println('Auto-detected artifact: $file');
                            builds.push({
                                name: name,
                                platform: platform,
                                arch: arch,
                                artifact: artifactPath
                            });
                        }
                    }
                }
            }
        }

        if (builds.length > 0) {
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
                    // Resolve glob pattern to actual file path
                    var resolvedArtifact = build.artifact;
                    if (resolvedArtifact.indexOf("*") != -1) {
                        var dir = haxe.io.Path.directory(resolvedArtifact);
                        var pattern = haxe.io.Path.withoutDirectory(resolvedArtifact);
                        var prefix = pattern.split("*")[0];
                        var suffix = pattern.split("*")[1];
                        if (dir == "") dir = ".";
                        var found:Null<String> = null;
                        if (sys.FileSystem.exists(dir) && sys.FileSystem.isDirectory(dir)) {
                            for (f in sys.FileSystem.readDirectory(dir)) {
                                if (StringTools.startsWith(f, prefix) && StringTools.endsWith(f, suffix)) {
                                    found = dir + "/" + f;
                                    break;
                                }
                            }
                        }
                        if (found == null) {
                            Sys.println('Error: No file matching ${build.artifact}');
                            Sys.exit(1);
                        }
                        resolvedArtifact = found;
                    }
                    Sys.println('Uploading artifact: $resolvedArtifact');
                    try {
                        var buildId = tool.addBuild(releaseId, build.platform, build.arch, build.name);
                        tool.uploadArtifact(buildId, resolvedArtifact);
                    } catch (e:Dynamic) {
                        Sys.println('Error uploading artifact $resolvedArtifact: $e');
                        Sys.exit(1);
                    }
                }
            }
        } else {
            Sys.println("No builds or artifacts found to push.");
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
    
    static function handleRefreshEnv(args:Array<String>) {
        var envName = args.length > 1 ? args[1] : "development";
        var tool = getTool();
        
        Sys.println('Refreshing environment variables from $envName...');
        
        // 1. Find environment ID
        var environments = tool.listEnvironments();
        var envId = null;
        for (e in environments) {
            if (e.name == envName || e.id == envName) {
                envId = e.id;
                break;
            }
        }
        
        if (envId == null) {
            Sys.println('Error: Environment "$envName" not found.');
            Sys.println('Available environments: ' + [for (e in environments) e.name].join(", "));
            Sys.exit(1);
        }
        
        // 2. Fetch config
        try {
            var config = tool.getDevConfig(envId);
            
            // 3. Write to .env.shared
            var content = "# GENERATED BY STACKDEPLOY - DO NOT EDIT\n";
            content += "# These variables are synced from the HaxeStack Platform ($envName)\n";
            content += "# To override locally, use a .env.local file which is gitignored.\n\n";
            
            var fields = Reflect.fields(config);
            fields.sort((a, b) -> a < b ? -1 : 1);
            for (f in fields) {
                var val = Reflect.field(config, f);
                content += '$f=$val\n';
            }
            
            File.saveContent(".env.shared", content);
            Sys.println('Successfully synced ${fields.length} variables to .env.shared');
            Sys.println('Tip: Ensure your application loads both .env.shared and .env.local (overrides)');
            
        } catch (e:Dynamic) {
            Sys.println('Error fetching dev config: $e');
            Sys.exit(1);
        }
    }

    static function getEnvironmentProvider():app.services.environment.IEnvironmentProvider {
        var sysName = Sys.systemName();
        if (sysName == "Windows") {
            return new app.services.environment.WindowsEnvironmentProvider();
        } else {
            return new app.services.environment.MacEnvironmentProvider();
        }
    }

    static function hasArg(args:Array<String>, name:String):Bool {
        for (arg in args) {
            if (arg == name) return true;
        }
        return false;
    }

    static function checkToJson(check:EnvironmentCheck):Dynamic {
        return {
            id: check.id,
            name: check.name,
            category: check.category,
            status: Std.string(check.status),
            detectedVersion: check.detectedVersion,
            detectedPath: check.detectedPath,
            message: check.message,
            details: check.details,
            fixActions: check.fixActions != null ? [for (a in check.fixActions) {
                id: a.id,
                label: a.label,
                description: a.description,
                command: a.command,
                opensUrl: a.opensUrl
            }] : null
        };
    }

    static function handleDoctor(args:Array<String>) {
        var target = getArg(args, "--target");
        if (target == null) target = "desktop";
        
        var jsonMode = hasArg(args, "--json");
        var verboseMode = hasArg(args, "--verbose");
        
        var checks = new Array<EnvironmentCheck>();
        var isDone = false;
        var hasRequiredMissing = false;
        
        var provider = getEnvironmentProvider();
        
        DevEnvironmentCheckService.instance.check(target, provider, function(check) {
            checks.push(check);
            if (check.status == EnvironmentCheckStatus.Missing || check.status == EnvironmentCheckStatus.Error) {
                hasRequiredMissing = true;
            }
        }, function() {
            isDone = true;
        });
        
        while (!isDone) {
            #if sys
            @:privateAccess haxe.MainLoop.tick();
            #end
            Sys.sleep(0.01);
        }
        
        if (jsonMode) {
            var jsonChecks = [for (c in checks) checkToJson(c)];
            Sys.println(haxe.Json.stringify(jsonChecks, null, "  "));
        } else {
            Sys.println("HaxeStack Environment Doctor for Target: " + target);
            Sys.println("=================================================");
            var lastCategory = "";
            for (c in checks) {
                if (c.category != lastCategory) {
                    Sys.println("\nCategory: " + c.category);
                    lastCategory = c.category;
                }
                var statusStr = switch (c.status) {
                    case Ready: "Ready";
                    case Warning: "Warning";
                    case Missing: "Missing";
                    case Error: "Error";
                    case Unknown: "Unknown";
                    case Optional: "Optional";
                };
                var statusBracket = "[" + StringTools.rpad(statusStr, " ", 7) + "]";
                var versionInfo = c.detectedVersion != null ? " (v" + c.detectedVersion + ")" : "";
                var pathInfo = c.detectedPath != null ? " - " + c.detectedPath : "";
                Sys.println("  " + statusBracket + " " + c.name + versionInfo + pathInfo);
                
                if (c.status == EnvironmentCheckStatus.Missing || c.status == EnvironmentCheckStatus.Error || c.status == EnvironmentCheckStatus.Warning || verboseMode) {
                    if (c.message != null && c.message != "") {
                        Sys.println("            Message: " + c.message);
                    }
                    if (c.details != null && c.details != "") {
                        Sys.println("            Details: " + c.details);
                    }
                    if (c.fixActions != null) {
                        for (action in c.fixActions) {
                            Sys.println("            Fix: " + action.label);
                            if (action.description != null) Sys.println("              " + action.description);
                            if (action.opensUrl != null) Sys.println("              Link: " + action.opensUrl);
                            if (action.command != null && action.command != "") Sys.println("              Command: " + action.command);
                        }
                    }
                }
            }
            Sys.println("");
            if (hasRequiredMissing) {
                Sys.println("[-] Doctor found missing or broken required dependencies.");
            } else {
                Sys.println("[+] Environment is healthy!");
            }
        }
        
        if (hasRequiredMissing) {
            Sys.exit(3);
        }
    }

    static function handleHmmInstall(args:Array<String>) {
        var dir = getArg(args, "--dir");
        if (dir == null) dir = ".";
        
        var dryRun = hasArg(args, "--dry-run");
        var continueOnError = hasArg(args, "--continue-on-error");
        
        var isDone = false;
        var resultRes:BootstrapStepResult = null;
        
        Sys.println("Scanning '" + dir + "' recursively for hmm.json files...");
        HmmInstallService.instance.runInstall(dir, {
            dryRun: dryRun,
            continueOnError: continueOnError,
            onLog: function(msg) {
                Sys.println(msg);
            }
        }, function(res) {
            resultRes = res;
            isDone = true;
        });
        
        while (!isDone) {
            #if sys
            @:privateAccess haxe.MainLoop.tick();
            #end
            Sys.sleep(0.01);
        }
        
        if (resultRes != null && !resultRes.success) {
            Sys.println("Error: " + resultRes.message);
            Sys.exit(resultRes.exitCode != null ? resultRes.exitCode : 1);
        } else {
            Sys.println("HMM installation complete.");
        }
    }

    static function handleEnvSetProject(args:Array<String>) {
        var projectId = getArg(args, "--project-id");
        var dir = getArg(args, "--dir");
        if (dir == null) dir = ".";
        
        if (projectId == null) {
            Sys.print("Enter HaxeStack Project ID: ");
            projectId = Sys.stdin().readLine().trim();
            if (projectId == "") {
                Sys.println("Error: Project ID is required.");
                Sys.exit(1);
            }
        }
        
        Sys.println("Setting PROJECT_ID=" + projectId + " in " + dir + "/.env...");
        var success = EnvFileService.instance.updateEnvFile(dir, "PROJECT_ID", projectId);
        if (success) {
            Sys.println("Successfully updated .env file.");
        } else {
            Sys.println("Failed to update .env file.");
            Sys.exit(1);
        }
    }

    static function handleInit(args:Array<String>) {
        var projectId = getArg(args, "--project-id");
        var dir = getArg(args, "--dir");
        var template = getArg(args, "--template");
        
        var skipClone = hasArg(args, "--skip-clone");
        var runHmmInstall = hasArg(args, "--run-hmm-install");
        var skipHmmInstall = hasArg(args, "--skip-hmm-install");
        var force = hasArg(args, "--force");
        var dryRun = hasArg(args, "--dry-run");
        var jsonMode = hasArg(args, "--json");
        var verbose = hasArg(args, "--verbose");
        
        // Logical resolution
        var actualRunHmm = true;
        if (skipHmmInstall) actualRunHmm = false;
        else if (runHmmInstall) actualRunHmm = true;
        
        // Interactive prompts if not in JSON mode and missing required parameters
        if (!jsonMode) {
            if (projectId == null) {
                Sys.print("Enter HaxeStack Project ID: ");
                projectId = Sys.stdin().readLine().trim();
                if (projectId == "") {
                    Sys.println("Error: Project ID is required.");
                    Sys.exit(1);
                }
            }
            if (dir == null) {
                Sys.print("Enter Target Directory (default: ./my-haxestack-project): ");
                dir = Sys.stdin().readLine().trim();
                if (dir == "") dir = "./my-haxestack-project";
            }
            if (template == null && !skipClone) {
                Sys.print("Enter Template Git URL (default: https://github.com/stackplatform/starter-template.git): ");
                template = Sys.stdin().readLine().trim();
                if (template == "") template = "https://github.com/stackplatform/starter-template.git";
            }
        } else {
            // In JSON mode, raise errors if arguments are missing
            if (projectId == null) {
                Sys.println(haxe.Json.stringify({success: false, message: "Missing required option: --project-id", exitCode: 1}));
                Sys.exit(1);
            }
            if (dir == null) {
                Sys.println(haxe.Json.stringify({success: false, message: "Missing required option: --dir", exitCode: 1}));
                Sys.exit(1);
            }
            if (template == null && !skipClone) {
                template = "https://github.com/stackplatform/starter-template.git";
            }
        }
        
        // If template doesn't look like a URL and is "starter-template", map it
        if (template == "starter-template") {
            template = "https://github.com/stackplatform/starter-template.git";
        }
        
        var resultRes:BootstrapStepResult = null;
        
        if (skipClone) {
            if (!jsonMode) Sys.println("Writing environment variables...");
            var envSuccess = true;
            if (dryRun) {
                if (!jsonMode) Sys.println("(Dry Run) Would write PROJECT_ID to .env");
            } else {
                envSuccess = EnvFileService.instance.updateEnvFile(dir, "PROJECT_ID", projectId);
            }
            
            if (!envSuccess) {
                resultRes = {
                    stepId: "onboard_env",
                    success: false,
                    message: "Failed to update .env file",
                    exitCode: -5
                };
            } else {
                if (actualRunHmm) {
                    if (!jsonMode) Sys.println("Running hmm install recursively...");
                    var isDone = false;
                    HmmInstallService.instance.runInstall(dir, {
                        dryRun: dryRun,
                        onLog: function(msg) {
                            if (!jsonMode) Sys.println(msg);
                        }
                    }, function(res) {
                        resultRes = res;
                        isDone = true;
                    });
                    while (!isDone) {
                        #if sys
                        @:privateAccess haxe.MainLoop.tick();
                        #end
                        Sys.sleep(0.01);
                    }
                } else {
                    resultRes = {
                        stepId: "onboard",
                        success: true,
                        message: "Onboarding completed (skipped clone and hmm install)",
                        exitCode: 0
                    };
                }
            }
        } else {
            var config = {
                projectId: projectId,
                repoUrl: template,
                targetDir: dir,
                runHmmInstall: actualRunHmm,
                force: force,
                dryRun: dryRun,
                verbose: verbose,
                onLog: function(msg) {
                    if (!jsonMode) Sys.println(msg);
                }
            };
            
            var isDone = false;
            ProjectOnboardingService.instance.onboardProject(config, function(res) {
                resultRes = res;
                isDone = true;
            });
            
            while (!isDone) {
                #if sys
                @:privateAccess haxe.MainLoop.tick();
                #end
                Sys.sleep(0.01);
            }
        }
        
        if (jsonMode) {
            var status = {
                success: resultRes != null ? resultRes.success : true,
                message: resultRes != null ? resultRes.message : "Onboarding finished",
                exitCode: resultRes != null ? (resultRes.exitCode != null ? resultRes.exitCode : 0) : 0
            };
            Sys.println(haxe.Json.stringify(status, null, "  "));
        } else {
            if (resultRes != null && !resultRes.success) {
                Sys.println("Error: " + resultRes.message);
                Sys.exit(resultRes.exitCode != null ? resultRes.exitCode : 1);
            } else {
                Sys.println("\nNext steps:");
                Sys.println("  1. Change directory: cd " + dir);
                if (!actualRunHmm) {
                    Sys.println("  2. Install dependencies: haxelib run hmm install");
                }
                Sys.println("  3. Build project: haxelib run lime build hl");
                Sys.println("  4. Open project in VS Code: code .");
            }
        }
    }

    static function printHelp() {
        Sys.println("stackdeploy CLI v0.3.0");
        Sys.println("Usage: haxelib run stackdeploy <command> [options]");
        Sys.println("");
        Sys.println("Available commands:");
        Sys.println("  compile              Build server and client, create zips for release.");
        Sys.println("                       Increments build number automatically.");
        Sys.println("                       Options: [--version <v>] (defaults to 0.0.0), [--platform <p>], [--output <dir>], [--build <n>]");
        Sys.println("  release create       Create a new release.");
        Sys.println("                       Options: --version <v>, --description <d>, --git-sha <s>");
        Sys.println("  release finalize     Mark a release as ready for deployment.");
        Sys.println("                       Options: --release <id>");
        Sys.println("  build upload         Register and upload a build artifact.");
        Sys.println("                       Options: --release <id>, --platform <p>, --arch <a>, --file <f>");
        Sys.println("  push                 Run builds and upload everything from stackdeploy.json.");
        Sys.println("                       Note: Automatically detects zips in builds/ folder.");
        Sys.println("                       Options: --config <path>, --build <n>");
        Sys.println("  server-stop [name]   Terminate server processes. Defaults to StackServer.exe.");
        Sys.println("                       Options: --name, -n <name>");
        Sys.println("  deploy [version]     Trigger deployment of a release.");
        Sys.println("  refresh-env [env]    Fetch environment variables and save to .env.shared (default: development).");
        Sys.println("  doctor               Check whether required development software is installed.");
        Sys.println("                       Options: [--target <name>] (default: desktop), [--json], [--verbose]");
        Sys.println("  init                 Perform the project onboarding flow.");
        Sys.println("                       Options: [--project-id <id>], [--dir <path>], [--template <url>],");
        Sys.println("                                [--run-hmm-install], [--skip-clone], [--skip-hmm-install],");
        Sys.println("                                [--force], [--dry-run], [--json], [--verbose]");
        Sys.println("  hmm install          Recursively scan directories and run 'hmm install'.");
        Sys.println("                       Options: [--dir <path>] (default: .), [--dry-run], [--continue-on-error]");
        Sys.println("  env set-project      Write/update the PROJECT_ID in the .env file.");
        Sys.println("                       Options: [--project-id <id>], [--dir <path>] (default: .)");
        Sys.println("  help                 Display this help message.");
        Sys.println("");
        Sys.println("Examples:");
        Sys.println("  haxelib run stackdeploy compile --version 1.0.0");
        Sys.println("  haxelib run stackdeploy push");
        Sys.println("  haxelib run stackdeploy doctor");
        Sys.println("  haxelib run stackdeploy init --project-id proj123 --dir ./MyApp --run-hmm-install");
    }
}

