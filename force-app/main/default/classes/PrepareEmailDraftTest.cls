@IsTest
private class PrepareEmailDraftTest {

    @IsTest
    static void testBasicPreparation() {
        PrepareEmailDraft.Request req = new PrepareEmailDraft.Request();
        req.subject   = 'Ethiopian Airlines Corporate Agreement — Nordic Cargo Solutions Ltd';
        req.emailBody = 'Dear Mrs. Al-Hussein,\n\nPlease find attached the corporate agreement.\n\nBest regards,\nEthiopian Airlines Global Corporate Sales';
        req.toEmail   = 'contact@nordiccargo.com';
        req.toName    = 'Mrs. Fatima Al-Hussein';

        Test.startTest();
        List<PrepareEmailDraft.Result> results = PrepareEmailDraft.prepare(
            new List<PrepareEmailDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertNotEquals(null, results[0].emailDraftCard, 'emailDraftCard must not be null');
        String j = results[0].emailDraftCard.contractEmailDraftJSON;
        System.assertNotEquals(null, j, 'contractEmailDraftJSON must not be null');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(j);
        System.assertEquals(req.subject,   (String) parsed.get('subject'),  'subject must match');
        System.assertEquals(req.toEmail,   (String) parsed.get('toEmail'),  'toEmail must match');
        System.assertEquals(req.toName,    (String) parsed.get('toName'),   'toName must match');
        System.assert(((String) parsed.get('body')).contains('Dear Mrs. Al-Hussein'), 'body must contain greeting');

        System.assert(results[0].draftReadyMessage.contains('Mrs. Fatima Al-Hussein'), 'draftReadyMessage must include recipient name');
    }

    @IsTest
    static void testNullToName() {
        PrepareEmailDraft.Request req = new PrepareEmailDraft.Request();
        req.subject   = 'Test Subject';
        req.emailBody = 'Body text';
        req.toEmail   = 'test@test.com';
        // toName intentionally null

        Test.startTest();
        List<PrepareEmailDraft.Result> results = PrepareEmailDraft.prepare(
            new List<PrepareEmailDraft.Request>{ req }
        );
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            results[0].emailDraftCard.contractEmailDraftJSON
        );
        System.assertEquals('', (String) parsed.get('toName'), 'null toName must serialise as empty string');
        System.assert(results[0].draftReadyMessage.contains('test@test.com'), 'draftReadyMessage must fall back to email when toName is null');
    }

    @IsTest
    static void testNullBodyAndSubject() {
        PrepareEmailDraft.Request req = new PrepareEmailDraft.Request();
        req.toEmail = 'test@test.com';
        // subject and emailBody null — should not throw

        Test.startTest();
        List<PrepareEmailDraft.Result> results = PrepareEmailDraft.prepare(
            new List<PrepareEmailDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertNotEquals(null, results[0].emailDraftCard.contractEmailDraftJSON);
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            results[0].emailDraftCard.contractEmailDraftJSON
        );
        System.assertEquals('', (String) parsed.get('subject'), 'null subject must serialise as empty string');
        System.assertEquals('', (String) parsed.get('body'),    'null body must serialise as empty string');
    }
}