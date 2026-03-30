package tools;

import haxe.Http;
import haxe.Json;
import sys.io.File;
import sys.FileSystem;
import sys.io.Process;
import sys.net.Socket;
import sys.net.Host;
using StringTools;

class ReleaseTool {
    var apiKey:String;
    var apiUrl:String;
    var projectId:String = "self";

    public function new(apiKey:String, apiUrl:String = "https://haxestack.com") {
        this.apiKey = apiKey;
        this.apiUrl = apiUrl;
        if (this.apiUrl.endsWith("/")) {
            this.apiUrl = this.apiUrl.substr(0, this.apiUrl.length - 1);
        }
    }

    public function createRelease(version:String, gitSha:String, ?gitRef:String, ?description:String):String {
        var url = '${apiUrl}/v1/projects/${projectId}/releases/upsert';
        var body = {
            version: version,
            gitSha: gitSha,
            gitRef: gitRef,
            description: description
        };

        var res = post(url, body);
        if (res.id == null) throw "Failed to create release: " + Json.stringify(res);
        return res.id;
    }

    public function addBuild(releaseId:String, platform:String, arch:String, ?githubRunId:String):String {
        var url = '${apiUrl}/v1/projects/${projectId}/releases/${releaseId}/builds';
        var body = {
            platform: platform,
            architecture: arch,
            githubRunId: githubRunId
        };

        var res = post(url, body);
        if (res.id == null) throw "Failed to add build: " + Json.stringify(res);
        return res.id;
    }

    public function uploadArtifact(buildId:String, filePath:String):Void {
        if (!FileSystem.exists(filePath)) throw "File not found: " + filePath;

        var fileName = filePath.split("/").pop().split("\\").pop();
        var sizeBytes = FileSystem.stat(filePath).size;

        // 1. Init upload
        var initUrl = '${apiUrl}/v1/projects/${projectId}/storage/uploads/init';
        var initBody = {
            fileName: fileName,
            sizeBytes: sizeBytes,
            contentType: "application/zip" // Conservative default
        };

        var initRes = post(initUrl, initBody);
        var uploadUrl:String = Reflect.field(initRes, "uploadUrl");
        var uploadId:String = Reflect.field(initRes, "uploadId");
        var requiredHeaders:Dynamic = Reflect.field(initRes, "requiredHeaders");
        if (uploadId == null) throw 'initUpload returned no uploadId. Response: ' + haxe.Json.stringify(initRes);

        Sys.println('Init response - uploadId: $uploadId');
        Sys.println('Upload URL: $uploadUrl');
        if (requiredHeaders != null) {
            Sys.println('Required headers: ' + haxe.Json.stringify(requiredHeaders));
        }

        // 2. Direct upload via Socket - precise control over HTTP headers
        Sys.println('Uploading $fileName ($sizeBytes bytes)...');
        var bytes = File.getBytes(filePath);
        
        // Parse the presigned URL
        var urlRegex = ~/^https?:\/\/([^\/]+)(\/.*)$/;
        if (!urlRegex.match(uploadUrl)) {
            throw 'Invalid upload URL: $uploadUrl';
        }
        var hostPart = urlRegex.matched(1);
        var pathPart = urlRegex.matched(2);
        var isHttps = uploadUrl.indexOf("https://") == 0;
        
        Sys.println('Connecting to: $hostPart');
        
        if (isHttps) {
            // For HTTPS, use PUT method with minimal headers
            Sys.println('Using HTTPS URL - attempting PUT with minimal headers...');
            var http = new Http(uploadUrl);
            
            // Set ONLY the headers that are in the signature
            if (requiredHeaders != null) {
                for (field in Reflect.fields(requiredHeaders)) {
                    http.setHeader(field, Reflect.field(requiredHeaders, field));
                }
            }
            
            http.setPostBytes(bytes);
            
            var uploadSuccess = false;
            var httpStatus = 0;
            var httpError = null;
            var responseData = "";
            
            http.onStatus = function(status) {
                httpStatus = status;
                if (status >= 200 && status < 300) uploadSuccess = true;
            };
            http.onError = function(msg) { httpError = msg; };
            http.onData = function(data) { responseData = data; };
            
            try {
                http.customRequest(false, new haxe.io.BytesOutput(), null, "PUT");
                if (!uploadSuccess) {
                    throw 'HTTPS upload failed: HTTP $httpStatus ($httpError) - Response: $responseData';
                }
            } catch (e:Dynamic) {
                throw 'HTTPS file upload failed: $e';
            }
        } else {
            // For HTTP, we can use Socket for exact header control
            var socket = new Socket();
            socket.connect(new Host(hostPart), 80);
            
            // Build raw HTTP PUT request with ONLY the signed headers
            var httpRequest = 'PUT $pathPart HTTP/1.1\r\n';
            httpRequest += 'Host: $hostPart\r\n';
            httpRequest += 'Content-Length: $sizeBytes\r\n';
            
            // Add required headers from the signature
            if (requiredHeaders != null) {
                for (field in Reflect.fields(requiredHeaders)) {
                    var value = Reflect.field(requiredHeaders, field);
                    httpRequest += '$field: $value\r\n';
                }
            }
            
            httpRequest += 'Connection: close\r\n';
            httpRequest += '\r\n';
            
            Sys.println('Sending raw HTTP PUT request...');
            socket.output.writeString(httpRequest);
            socket.output.writeBytes(bytes, 0, sizeBytes);
            socket.output.flush();
            
            // Read response status line
            var statusLine = socket.input.readLine();
            Sys.println('Response: $statusLine');
            
            var uploadSuccess = statusLine.indexOf(" 200") >= 0 || 
                               statusLine.indexOf(" 201") >= 0 ||
                               statusLine.indexOf(" 204") >= 0;
            
            socket.close();
            
            if (!uploadSuccess) {
                throw 'File upload failed: $statusLine. Upload session $uploadId will not be completed.';
            }
        }
        
        Sys.println('File upload to presigned URL successful');

        var completeUrl = '${apiUrl}/v1/projects/${projectId}/storage/uploads/complete';
        var completeBody = {uploadId: uploadId};
        Sys.println('Calling /complete endpoint...');
        Sys.println('  URL: $completeUrl');
        Sys.println('  Body: ' + haxe.Json.stringify(completeBody));
        Sys.println('  API Key: ${apiKey.substr(0, 10)}...');
        var completeRes = post(completeUrl, completeBody);
        Sys.println('Complete response: ' + haxe.Json.stringify(completeRes));
        var completeSuccess:Bool = Reflect.field(completeRes, "success") == true;
        if (!completeSuccess) {
            var err:String = Reflect.field(completeRes, "error");
            throw 'completeUpload failed: ' + (err != null ? err : haxe.Json.stringify(completeRes));
        }
        var fileObj:Dynamic = Reflect.field(completeRes, "file");
        var finalUrl:String = fileObj != null ? Reflect.field(fileObj, "objectKey") : null;

        // 4. Associate build artifact
        var artifactUrl = '${apiUrl}/v1/builds/${buildId}/artifacts';
        Sys.println('Calling /artifacts endpoint...');
        Sys.println('  URL: $artifactUrl');
        Sys.println('  Body: ' + haxe.Json.stringify({binaryUrl: finalUrl}));
        var artifactRes = post(artifactUrl, {binaryUrl: finalUrl});
        Sys.println('Artifact response: ' + haxe.Json.stringify(artifactRes));

        // 5. Build completed
        var statusUrl = '${apiUrl}/v1/builds/${buildId}/status';
        Sys.println('Calling /status endpoint...');
        Sys.println('  URL: $statusUrl');
        Sys.println('  Body: ' + haxe.Json.stringify({buildId: buildId, status: "COMPLETED"}));
        var statusBody = {
            buildId: buildId,
            status: "COMPLETED"
        };
        put(statusUrl, statusBody);
    }

    public function finalizeRelease(releaseId:String):Void {
        var url = '${apiUrl}/v1/releases/${releaseId}/finalize';
        post(url, {});
    }

    private function post(url:String, body:Dynamic):Dynamic {
        return request("POST", url, body);
    }

    private function put(url:String, body:Dynamic):Dynamic {
        return request("PUT", url, body);
    }

    private function request(method:String, url:String, body:Dynamic):Dynamic {
        var http = new Http(url);
        var responseData:String = null;
        var statusCode:Int = 0;

        if (body != null) {
            http.setPostData(Json.stringify(body));
        }

        http.setHeader("Authorization", "Bearer " + apiKey);
        http.setHeader("Content-Type", "application/json");

        http.onData = function(data) {
            responseData = data;
        };

        http.onStatus = function(status) {
            statusCode = status;
        };

        http.onError = function(msg) {
            // on error, just mark that an error occurred
            // we'll check statusCode after request completes
        };

        if (method == "PUT") {
            http.customRequest(true, new haxe.io.BytesOutput(), null, "PUT");
        } else {
            http.request(method == "POST");
        }

        // Check for HTTP errors (4xx, 5xx)
        if (statusCode >= 400) {
            var errorMsg = 'HTTP $statusCode error on $method $url\nRequest body: ' + (body != null ? Json.stringify(body) : "(none)");
            if (responseData != null && responseData.length > 0) {
                try {
                    var errorJson = Json.parse(responseData);
                    var error:String = Reflect.field(errorJson, "error");
                    if (error != null) {
                        errorMsg += '\nServer error: $error';
                    } else {
                        errorMsg += '\nServer response: $responseData';
                    }
                } catch (e:Dynamic) {
                    errorMsg += '\nServer response: $responseData';
                }
            } else {
                errorMsg += '\nServer response: (empty)';
            }
            throw errorMsg;
        }

        if (responseData == null) return {};
        try {
            return Json.parse(responseData);
        } catch (e:Dynamic) {
            return { raw: responseData };
        }
    }
}
