package;

import utest.UTest;

class TestMain {
    static function main() {
        UTest.run([new GeneratorContextTest(), new GeneratedFileWriterTest(), new ModuleInstallerTest(), new ModulePromptInterpreterTest(), new GenerateFromPromptServiceTest()]);
    }
}
