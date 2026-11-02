@IsTest
private class GenerateContractDraftTest {

    @TestSetup
    static void setup() {
        insert new Corporate_Travel_RFP__c(
            Company_Name__c             = 'Test Corp',
            Address__c                  = '1 Test Street',
            City__c                     = 'Addis Ababa',
            Country__c                  = 'Ethiopia',
            Website__c                  = 'www.testcorp.com',
            Contact_Email__c            = 'test@testcorp.com',
            Contact_Name__c             = 'Test Person',
            Annual_NFR_Target_USD__c    = 500000,
            Offer_Matrix_Row__c         = 1,
            Offer_Contract_Template__c  = 'Main',
            Offer_Economy_Lower_Pct__c  = 8,
            Offer_Economy_Higher_Pct__c = 10,
            Offer_D_Class_Pct__c        = 12,
            Offer_J_Class_Pct__c        = 15,
            Offer_C_Class_Pct__c        = 20,
            Offer_Routing_Scope__c      = 'All ET Stations'
        );
        // Discount tier row so soft benefit validation can resolve Soft_Options_Count__c
        insert new ET_Discount_Tier__c(
            Tier_Label__c        = '$200K–$999,999',
            Row_Number__c        = 1,
            NFR_Lower_USD__c     = 200000,
            NFR_Upper_USD__c     = 999999,
            Economy_Lower_Pct__c = 8,
            Economy_Higher_Pct__c= 10,
            D_Class_Pct__c       = 12,
            J_Class_Pct__c       = 15,
            C_Class_Pct__c       = 20,
            Soft_Options_Count__c= 3,
            Routing_Scope__c     = 'All ET Stations'
        );
    }

    @IsTest
    static void testGateBlocked_PendingApproval() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Matrix_Row__c = 2;
        rfp.Pricing_Approval_Status__c = 'Pending';
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Pending approval should block generation');
        System.assert(
            results[0].errorMessage.toLowerCase().contains('approved'),
            'Error should mention approval: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testGateBlocked_RejectedOffer() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Matrix_Row__c = 2;
        rfp.Pricing_Approval_Status__c = 'Rejected';
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Rejected offer should block generation');
        System.assert(
            results[0].errorMessage.toLowerCase().contains('approved'),
            'Error should mention approval: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testRow1_GatePassesWithoutApprovalStatus() {
        // Row 1 passes gate regardless of Pricing_Approval_Status__c
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected success. Error: ' + results[0].errorMessage);
        System.assertEquals(1, results[0].contractVersion);

        Corporate_Travel_RFP__c updated = [
            SELECT Offer_Contract_Content_Id__c, Offer_Contract_Generated_Date__c, Offer_Contract_Version__c, Status__c
            FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id
        ];
        System.assertNotEquals(null, updated.Offer_Contract_Content_Id__c, 'Content ID should be written back after Queueable runs');
        System.assertEquals(Date.today(), updated.Offer_Contract_Generated_Date__c);
        System.assertEquals(1, updated.Offer_Contract_Version__c);
        System.assertEquals('Contract Draft', updated.Status__c, 'Status should be updated to Contract Draft');
    }

    @IsTest
    static void testRow1_RevertAfterRejectedRow2_StillPasses() {
        // Review Focus item 1: row reverted to 1 after a row-2 rejection must still generate
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Matrix_Row__c = 1;
        rfp.Pricing_Approval_Status__c = 'Rejected'; // stale status from prior row-2 attempt
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success,
            'Row 1 should always pass gate regardless of approval status: ' + results[0].errorMessage);
    }

    @IsTest
    static void testApprovedEscalatedOffer() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Matrix_Row__c = 2;
        rfp.Pricing_Approval_Status__c = 'Approved';
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success,
            'Approved escalated offer should generate: ' + results[0].errorMessage);
    }

    @IsTest
    static void testVersionIncrement() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Contract_Version__c = 3;
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Expected success. Error: ' + results[0].errorMessage);
        System.assertEquals(4, results[0].contractVersion, 'Should increment from 3 to 4');

        Corporate_Travel_RFP__c updated = [SELECT Offer_Contract_Version__c FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id];
        System.assertEquals(4, updated.Offer_Contract_Version__c);
    }

    @IsTest
    static void testVersionOverflowGuard() {
        // Review Focus item 5: Number(3,0) max is 999
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Contract_Version__c = 999;
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should block at version 999');
        System.assert(
            results[0].errorMessage.toLowerCase().contains('version'),
            'Error should mention version limit: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testAutoGeneratesCorporateId() {
        Corporate_Travel_RFP__c rfp = [SELECT Id, Corporate_ID__c FROM Corporate_Travel_RFP__c LIMIT 1];
        System.assertEquals(null, rfp.Corporate_ID__c, 'Precondition: no Corporate_ID__c in setup');

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        GenerateContractDraft.generate(new List<GenerateContractDraft.Request>{ req });
        Test.stopTest();

        Corporate_Travel_RFP__c updated = [SELECT Corporate_ID__c FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id];
        System.assertNotEquals(null, updated.Corporate_ID__c, 'Corporate ID should be auto-generated');
        System.assert(
            updated.Corporate_ID__c.startsWith('ETA'),
            'Corporate ID should start with ETA: ' + updated.Corporate_ID__c
        );
        System.assertEquals(6, updated.Corporate_ID__c.length(), 'Corporate ID should be ETA + 3 digits');
    }

    @IsTest
    static void testPreservesExistingCorporateId() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Corporate_ID__c = 'ETA042';
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        GenerateContractDraft.generate(new List<GenerateContractDraft.Request>{ req });
        Test.stopTest();

        Corporate_Travel_RFP__c updated = [SELECT Corporate_ID__c FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id];
        System.assertEquals('ETA042', updated.Corporate_ID__c, 'Existing Corporate ID should not be overwritten');
    }

    @IsTest
    static void testSoftBenefitFlagsAccepted() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;
        req.includeFreeDateChanges = true;
        req.includeFreeTickets = true;
        req.includeHotelDiscount = true;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success,
            'Soft benefit flags should not break generation: ' + results[0].errorMessage);
    }

    @IsTest
    static void testSoftBenefitLimitExceeded() {
        // RFP row 1 has Soft_Options_Count__c = 3 in setup; override tier to 1 soft option
        ET_Discount_Tier__c tier = [SELECT Id FROM ET_Discount_Tier__c LIMIT 1];
        tier.Soft_Options_Count__c = 1;
        update tier;

        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;
        req.includeFreeDateChanges = true;
        req.includeFreeTickets     = true; // 2 selected, max is 1
        req.includeHotelDiscount   = false;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Over-limit soft benefit selection should be rejected');
        System.assert(
            results[0].errorMessage != null && results[0].errorMessage.containsIgnoreCase('soft benefit limit'),
            'Error should mention soft benefit limit: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testMissingTemplateId() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Contract_Template__c = null;
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Missing template should block generation');
        System.assert(
            results[0].errorMessage.toLowerCase().contains('template'),
            'Error should mention template: ' + results[0].errorMessage
        );
    }

    @IsTest
    static void testWithRoutesAndAgencies() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        // Insert routes for the RFP
        insert new Travel_Route__c(
            Corporate_Travel_RFP__c = rfp.Id,
            Origin__c               = 'ADD',
            Destination__c          = 'LHR'
        );
        insert new Travel_Route__c(
            Corporate_Travel_RFP__c = rfp.Id,
            Origin__c               = 'ADD',
            Destination__c          = 'CDG'
        );

        // Insert a travel agency
        insert new Travel_Agency__c(
            Corporate_Travel_RFP__c = rfp.Id,
            IATA_Name__c            = 'Global Travel',
            IATA_Number__c          = '12345678',
            PCC__c                  = 'GT01',
            GDS__c                  = 'Amadeus'
        );

        // Insert a soft benefit tier matching the RFP's NFR
        insert new ET_Soft_Benefit_Tier__c(
            Tier_Label__c    = 'Upper Tier',
            NFR_Lower_USD__c = 400000,
            NFR_Upper_USD__c = 999999,
            Free_Tickets__c  = 2
        );

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId               = rfp.Id;
        req.etSignatoryName     = 'Yohannes Tefera';
        req.includeFreeDateChanges = true;
        req.includeFreeTickets     = true;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success,
            'Generation with routes and agencies should succeed: ' + results[0].errorMessage);
    }

    @IsTest
    static void testRequestingStationOnlyScope() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Routing_Scope__c = 'Requesting Station Only';
        rfp.City__c = 'Nairobi';
        update rfp;

        GenerateContractDraft.Request req = new GenerateContractDraft.Request();
        req.rfpId = rfp.Id;

        Test.startTest();
        List<GenerateContractDraft.Result> results = GenerateContractDraft.generate(
            new List<GenerateContractDraft.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success,
            'Requesting Station Only scope should succeed: ' + results[0].errorMessage);
    }
}