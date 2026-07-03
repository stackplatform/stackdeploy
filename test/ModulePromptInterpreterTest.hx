package;

import utest.Test;
import utest.Assert;
import stackdeploy.interpreter.ModulePromptInterpreter;

class ModulePromptInterpreterTest extends Test {
    var tmpTemplates:String;
    var interpreter:ModulePromptInterpreter;

    function setup() {
        tmpTemplates = "/tmp/stackdeploy-interp-" + Std.string(Math.floor(Math.random() * 1000000));
        sys.FileSystem.createDirectory('$tmpTemplates/request-form');

        var mappings = [
            { id: "contact-request",
              keywords: ["contact", "contact form", "contact us"],
              inputs: { entityName: "ContactRequest", displayName: "Contact Request",
                        formTitle: "Contact Us", adminTitle: "Contact Requests" } },
            { id: "quote-request",
              keywords: ["quote", "quote request", "request a quote", "quote form"],
              inputs: { entityName: "QuoteRequest", displayName: "Quote Request",
                        formTitle: "Request a Quote", adminTitle: "Quote Requests" } },
            { id: "booking-request",
              keywords: ["booking", "appointment", "booking request", "booking form", "appointment request"],
              inputs: { entityName: "BookingRequest", displayName: "Booking Request",
                        formTitle: "Request a Booking", adminTitle: "Booking Requests" } },
            { id: "lesson-request",
              keywords: ["lesson", "music lesson", "guitar lesson", "piano lesson"],
              inputs: { entityName: "LessonRequest", displayName: "Lesson Request",
                        formTitle: "Request a Lesson", adminTitle: "Lesson Requests" } },
            { id: "support-request",
              keywords: ["support", "help request", "support form", "support request"],
              inputs: { entityName: "SupportRequest", displayName: "Support Request",
                        formTitle: "Request Support", adminTitle: "Support Requests" } },
            { id: "inquiry-request",
              keywords: ["inquiry", "general inquiry", "inquiry form", "enquiry"],
              inputs: { entityName: "InquiryRequest", displayName: "Inquiry",
                        formTitle: "Send an Inquiry", adminTitle: "Inquiries" } }
        ];
        sys.io.File.saveContent(
            '$tmpTemplates/request-form/prompt-map.json',
            haxe.Json.stringify({ moduleId: "request-form", mappings: mappings })
        );
        interpreter = new ModulePromptInterpreter();
    }

    function teardown() {
        deleteRecursive(tmpTemplates);
    }

    function testContactForm() {
        var r = interpreter.interpret("Add a contact form.", tmpTemplates);
        Assert.isTrue(r.supported);
        Assert.equals("install_module", r.intent);
        Assert.equals("request-form", r.moduleId);
        Assert.equals("contact-request", r.mappingId);
        Assert.isTrue(r.confidence >= 0.70);
    }

    function testQuoteRequest() {
        var r = interpreter.interpret("Add a quote request form.", tmpTemplates);
        Assert.isTrue(r.supported);
        Assert.equals("quote-request", r.mappingId);
    }

    function testBookingRequest() {
        var r = interpreter.interpret("Add a booking request form.", tmpTemplates);
        Assert.isTrue(r.supported);
        Assert.equals("booking-request", r.mappingId);
    }

    function testLessonRequestMediumConfidence() {
        var r = interpreter.interpret("Add a lesson request form.", tmpTemplates);
        Assert.isTrue(r.supported);
        Assert.equals("lesson-request", r.mappingId);
        Assert.isTrue(r.confidence >= 0.70);
    }

    function testPianoLessonHighConfidence() {
        // "piano lesson" is multi-word keyword (+2) + "request"(+1) + "form"(+1) = 4/4 = 1.0
        var r = interpreter.interpret("Add a piano lesson request form.", tmpTemplates);
        Assert.isTrue(r.supported);
        Assert.equals("lesson-request", r.mappingId);
        Assert.isTrue(r.confidence >= 0.90);
    }

    function testSupportRequest() {
        var r = interpreter.interpret("Add a support request form.", tmpTemplates);
        Assert.isTrue(r.supported);
        Assert.equals("support-request", r.mappingId);
    }

    function testInquiryForm() {
        // "inquiry form" is multi-word keyword (+2) + "form"(+1) + "inquiry" triggers request bonus (+1) = 4/4 = 1.0
        var r = interpreter.interpret("Add an inquiry form.", tmpTemplates);
        Assert.isTrue(r.supported);
        Assert.equals("inquiry-request", r.mappingId);
    }

    function testInterpretationModeIsRules() {
        var r = interpreter.interpret("Add a contact form.", tmpTemplates);
        Assert.equals("rules", r.interpretationMode);
    }

    function testSuggestedInputsPopulated() {
        var r = interpreter.interpret("Add a lesson request form.", tmpTemplates);
        Assert.notNull(r.suggestedInputs);
        Assert.equals("LessonRequest", Reflect.field(r.suggestedInputs, "entityName"));
    }

    function testFullWebsiteUnsupported() {
        var r = interpreter.interpret("Build me a full website for a music teacher.", tmpTemplates);
        Assert.isFalse(r.supported);
        Assert.equals("unsupported", r.intent);
    }

    function testStripePaymentsUnsupported() {
        var r = interpreter.interpret("Add Stripe payments.", tmpTemplates);
        Assert.isFalse(r.supported);
    }

    function testLoginUnsupported() {
        var r = interpreter.interpret("Add a login page.", tmpTemplates);
        Assert.isFalse(r.supported);
    }

    function testNoKeywordsLowConfidence() {
        var r = interpreter.interpret("Make something nice.", tmpTemplates);
        Assert.isFalse(r.supported);
        Assert.equals(0.0, r.confidence);
    }

    function testMissingPromptMapDirectorySkippedSilently() {
        // tmpTemplates has request-form/, nothing else; should still work
        var r = interpreter.interpret("Add a contact form.", tmpTemplates);
        Assert.isTrue(r.supported);
    }

    static function deleteRecursive(path:String):Void {
        if (!sys.FileSystem.exists(path)) return;
        if (sys.FileSystem.isDirectory(path)) {
            for (f in sys.FileSystem.readDirectory(path)) deleteRecursive('$path/$f');
            sys.FileSystem.deleteDirectory(path);
        } else {
            sys.FileSystem.deleteFile(path);
        }
    }
}
