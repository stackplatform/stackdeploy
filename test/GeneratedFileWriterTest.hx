package;

import utest.UTest;
import utest.Test;
import utest.Assert;
import stackdeploy.generator.GeneratedFileWriter;
import stackdeploy.generator.FileWriteStatus;

class GeneratedFileWriterTest extends Test {
    var tmpDir:String;

    function setup() {
        tmpDir = "/tmp/stackdeploy-test-" + Std.string(Math.floor(Math.random() * 1000000));
        sys.FileSystem.createDirectory(tmpDir);
    }

    function teardown() {
        // clean up recursively
        function deleteRecursive(path:String) {
            if (sys.FileSystem.isDirectory(path)) {
                for (f in sys.FileSystem.readDirectory(path)) {
                    deleteRecursive('$path/$f');
                }
                sys.FileSystem.deleteDirectory(path);
            } else {
                sys.FileSystem.deleteFile(path);
            }
        }
        if (sys.FileSystem.exists(tmpDir)) {
            deleteRecursive(tmpDir);
        }
    }

    function testCreatesNewFile() {
        var path = '$tmpDir/sub/dir/new.txt';
        var status = GeneratedFileWriter.write(path, "hello", false);
        Assert.isTrue(sys.FileSystem.exists(path));
        Assert.equals("hello", sys.io.File.getContent(path));
        switch (status) {
            case Created(_): Assert.pass();
            default: Assert.fail("Expected Created");
        }
    }

    function testSkipsExistingWithoutForce() {
        var path = '$tmpDir/existing.txt';
        sys.io.File.saveContent(path, "original");
        var status = GeneratedFileWriter.write(path, "new content", false);
        Assert.equals("original", sys.io.File.getContent(path));
        switch (status) {
            case Skipped(_): Assert.pass();
            default: Assert.fail("Expected Skipped");
        }
    }

    function testOverwritesExistingWithForce() {
        var path = '$tmpDir/existing.txt';
        sys.io.File.saveContent(path, "original");
        var status = GeneratedFileWriter.write(path, "new content", true);
        Assert.equals("new content", sys.io.File.getContent(path));
        switch (status) {
            case Overwritten(_): Assert.pass();
            default: Assert.fail("Expected Overwritten");
        }
    }
}
