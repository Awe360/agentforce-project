@IsTest
private class SendContractEmailTest {

    @TestSetup
    static void setup() {
        ContentVersion cv = new ContentVersion(
            Title        = 'Test Contract',
            PathOnClient = 'contract.docx',
            VersionData  = Blob.valueOf('test contract content')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c              = 'Test Corp',
            Contact_Name__c              = 'Test Person',
            Contact_Email__c             = 'contact@testcorp.com',
            Offer_Contract_Content_Id__c = docId
        );
        insert rfp;

        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId    = rfp.Id,
            ShareType         = 'V'
        );
    }

    @IsTest
    static void testMissingContactEmail() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Contact_Email__c = null;
        update rfp;

        SendContractEmail.Request req = new SendContractEmail.Request();
        req.rfpId        = rfp.Id;
        req.emailSubject = 'Test Subject';
        req.emailBody    = '<p>Test body</p>';

        Test.startTest();
        List<SendContractEmail.Result> results = SendContractEmail.send(
            new List<SendContractEmail.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(
            results[0].errorMessage.toLowerCase().contains('email'),
            'Error should mention email address: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testMissingContractDocument() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Contract_Content_Id__c = null;
        update rfp;

        SendContractEmail.Request req = new SendContractEmail.Request();
        req.rfpId        = rfp.Id;
        req.emailSubject = 'Test Subject';
        req.emailBody    = '<p>Test body</p>';

        Test.startTest();
        List<SendContractEmail.Result> results = SendContractEmail.send(
            new List<SendContractEmail.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(
            results[0].errorMessage.toLowerCase().contains('contract'),
            'Error should mention contract draft: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testMissingOrgWideEmailAddress() {
        // Test.isRunningTest() guard in SendContractEmail simulates no org-wide address
        // in orgs where it hasn't been configured. Validates hard error, not silent degradation.
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        SendContractEmail.Request req = new SendContractEmail.Request();
        req.rfpId        = rfp.Id;
        req.emailSubject = 'Ethiopian Airlines Corporate Agreement — Test Corp';
        req.emailBody    = '<p>Dear Contact,</p><p>Please find attached...</p>';

        Test.startTest();
        List<SendContractEmail.Result> results = SendContractEmail.send(
            new List<SendContractEmail.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success,
            'Missing org-wide address should return error, not silently degrade');
        System.assert(
            results[0].errorMessage.toLowerCase().contains('email address'),
            'Error should identify org-wide address as missing: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testStatusNotUpdatedOnFailure() {
        // Guards fail before the send in test context — status must stay unchanged
        Corporate_Travel_RFP__c rfp = [SELECT Id, Status__c FROM Corporate_Travel_RFP__c LIMIT 1];
        String originalStatus = rfp.Status__c;

        SendContractEmail.Request req = new SendContractEmail.Request();
        req.rfpId        = rfp.Id;
        req.emailSubject = 'Test';
        req.emailBody    = 'Test body';

        Test.startTest();
        SendContractEmail.send(new List<SendContractEmail.Request>{ req });
        Test.stopTest();

        Corporate_Travel_RFP__c updated = [SELECT Status__c FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id];
        System.assertEquals(originalStatus, updated.Status__c, 'Status should not change when send fails');
    }

    @IsTest
    static void testContractSentStatusValueIsValid() {
        // Verifies 'Contract Sent' is a valid picklist value for Status__c
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Status__c = 'Contract Sent';
        update rfp;
        Corporate_Travel_RFP__c updated = [SELECT Status__c FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id];
        System.assertEquals('Contract Sent', updated.Status__c, 'Contract Sent must be a valid Status__c picklist value');
    }

    @IsTest
    static void testBuildHtmlBodyContainsBranding() {
        String body = 'Dear Mrs. Al-Hussein,\n\nPlease find attached the agreement.\n\nKind regards,\nEthiopian Airlines';
        String html = SendContractEmail.buildHtmlBody(body, 'Nordic Cargo Solutions Ltd');

        System.assert(html.contains('#1a5c38'),      'Should contain ET green header colour');
        System.assert(html.contains('#c8a951'),      'Should contain ET gold accent strip');
        System.assert(html.contains('logo.png'),     'Should contain logo image');
        System.assert(html.contains('Nordic Cargo Solutions Ltd'), 'Should contain company name in heading');
        System.assert(html.contains('Dear Mrs. Al-Hussein'), 'Should contain agent-drafted body text');
        System.assert(html.contains('GlobalCorporateSales@ethiopianairlines.com'), 'Should contain footer contact email');
    }

    @IsTest
    static void testBuildHtmlBodyEscapesSpecialChars() {
        String body = 'Rate: 5% & 6% <Economy>';
        String html = SendContractEmail.buildHtmlBody(body, 'Test & Co <Ltd>');

        System.assert(!html.contains('<Economy>'),   'Unescaped angle brackets should not appear in body');
        System.assert(html.contains('&amp;'),        'Ampersand should be HTML-escaped');
    }
}