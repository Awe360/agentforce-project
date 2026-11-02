@IsTest
private class GetRfpWithMatrixDataTest {

    @TestSetup
    static void setup() {
        // Account and Contact required by RFP foreign key chain
        Account acct = new Account(Name = 'Test Corp', Website = 'testcorp.example.com');
        insert acct;
        Contact con = new Contact(LastName = 'Smith', Email = 'smith@testcorp.example.com', AccountId = acct.Id);
        insert con;
        Opportunity opp = new Opportunity(
            Name = 'Test Corp - Corporate Travel',
            AccountId = acct.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(3)
        );
        insert opp;
        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c = 'Test Corp',
            Contact_Email__c = 'smith@testcorp.example.com',
            Annual_NFR_Target_USD__c = 2000000,
            Economy_Discount_Pct__c = '10%',
            Business_Discount_Pct__c = '12%',
            Corporate_ID__c = 'ETA135',
            Opportunity__c = opp.Id
        );
        insert rfp;

        // Matrix data — tier covering $2M
        ET_Discount_Tier__c tier1 = new ET_Discount_Tier__c(
            Tier_Label__c = '$2M–2.999M',
            Row_Number__c = 1,
            NFR_Lower_USD__c = 2000000,
            NFR_Upper_USD__c = 2999999,
            Economy_Lower_Pct__c = 10,
            Economy_Higher_Pct__c = 11,
            D_Class_Pct__c = 12,
            J_Class_Pct__c = 13,
            C_Class_Pct__c = 14,
            Soft_Options_Count__c = 3,
            Routing_Scope__c = 'All ET Online Points'
        );
        insert tier1;
        // Insert 4 more rows for same tier so SOQL returns all 5
        for (Integer i = 2; i <= 5; i++) {
            insert new ET_Discount_Tier__c(
                Tier_Label__c = '$2M–2.999M',
                Row_Number__c = i,
                NFR_Lower_USD__c = 2000000,
                NFR_Upper_USD__c = 2999999,
                Economy_Lower_Pct__c = 10 + (i - 1),
                Economy_Higher_Pct__c = 11 + (i - 1),
                D_Class_Pct__c = 12,
                J_Class_Pct__c = 13,
                C_Class_Pct__c = 14,
                Soft_Options_Count__c = 3,
                Routing_Scope__c = 'All ET Online Points'
            );
        }
        insert new ET_Soft_Benefit_Tier__c(
            Tier_Label__c = '$2M–2.999M',
            NFR_Lower_USD__c = 2000000,
            NFR_Upper_USD__c = 2999999,
            Free_Tickets__c = 4,
            Free_Date_Changes__c = 10,
            Baggage_Uplift_Kg__c = 5,
            Upgrades__c = 2,
            Lounge_At_Origin__c = true
        );
    }

    @IsTest
    static void testLookupByRfpId() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        GetRfpWithMatrixData.Result r = results[0];
        System.assertEquals(rfp.Id, r.rfpId);
        System.assertEquals('Test Corp', r.companyName);
        System.assertEquals('$2M–2.999M', r.qualifyingTierLabel);
        System.assertNotEquals(null, r.tierRowsJson, 'tierRowsJson should not be null');
        System.assertNotEquals(null, r.softBenefitJson, 'softBenefitJson should not be null');
        System.assertNotEquals(null, r.negotiationSummary, 'negotiationSummary should not be null');
        System.assertEquals('ETA135', r.corporateId);
        System.assertEquals(null, r.errorMessage);
    }

    @IsTest
    static void testLookupByOpportunityId() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = opp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].rfpId);
        System.assertEquals('$2M–2.999M', results[0].qualifyingTierLabel);
    }

    @IsTest
    static void testBlankCorporateIdReturned() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Corporate_ID__c = null;
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals('', results[0].corporateId, 'blank corporateId should be empty string');
    }

    @IsTest
    static void testReturnsOfferFields() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Matrix_Row__c = 2;
        rfp.Pricing_Approval_Status__c = 'Approved';
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(2, results[0].offerMatrixRow, 'offerMatrixRow should reflect Offer_Matrix_Row__c');
        System.assertEquals('Approved', results[0].pricingApprovalStatus, 'pricingApprovalStatus should reflect Pricing_Approval_Status__c');
    }

    @IsTest
    static void testReturnsNullOfferFieldsWhenNoOffer() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(null, results[0].offerMatrixRow, 'offerMatrixRow should be null when no offer accepted');
        System.assertEquals(null, results[0].pricingApprovalStatus, 'pricingApprovalStatus should be null when no offer');
    }

    @IsTest
    static void testRateAssessmentWithinMatrix() {
        // Setup: row 1 eco lower = 10%, C class = 14%. Request eco 9%, bus 12% — both within.
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Economy_Discount_Pct__c = '9%';
        rfp.Business_Discount_Pct__c = '12%';
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertNotEquals(null, results[0].rateAssessmentSummary, 'rateAssessmentSummary should not be null when rates are provided');
        System.assert(
            results[0].rateAssessmentSummary.containsIgnoreCase('within') || results[0].rateAssessmentSummary.containsIgnoreCase('pre-approved'),
            'Assessment should indicate rates are within pre-approved maximum: ' + results[0].rateAssessmentSummary
        );
        System.assert(
            !results[0].rateAssessmentSummary.containsIgnoreCase('escalation') && !results[0].rateAssessmentSummary.containsIgnoreCase('exceeds'),
            'Assessment should not mention escalation when both rates are within matrix: ' + results[0].rateAssessmentSummary
        );
    }

    @IsTest
    static void testRateAssessmentExceedsMatrix() {
        // Setup: row 1 eco lower = 10%, C class = 14%. Request eco 15% (exceeds), bus 12% (within).
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Economy_Discount_Pct__c = '15%';
        rfp.Business_Discount_Pct__c = '12%';
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertNotEquals(null, results[0].rateAssessmentSummary, 'rateAssessmentSummary should not be null');
        System.assert(
            results[0].rateAssessmentSummary.containsIgnoreCase('exceeds') || results[0].rateAssessmentSummary.containsIgnoreCase('escalation'),
            'Assessment should flag that economy rate exceeds matrix: ' + results[0].rateAssessmentSummary
        );
    }

    @IsTest
    static void testReturnsSoftOptionsCountForAcceptedRow() {
        // Update row 4 to have 0 soft options to distinguish it from other rows
        ET_Discount_Tier__c row4 = [SELECT Id FROM ET_Discount_Tier__c WHERE Row_Number__c = 4 LIMIT 1];
        row4.Soft_Options_Count__c = 0;
        update row4;

        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Matrix_Row__c = 4;
        rfp.Pricing_Approval_Status__c = 'Approved';
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(0, results[0].acceptedRowSoftOptionsCount,
            'Should return 0 soft options for accepted row 4 which has 0 options');
    }

    @IsTest
    static void testReturnsNullSoftOptionsCountWhenNoOfferAccepted() {
        // RFP in setup has no Offer_Matrix_Row__c set — null offer means null count
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(null, results[0].acceptedRowSoftOptionsCount,
            'acceptedRowSoftOptionsCount should be null when no offer row has been accepted');
    }

    @IsTest
    static void testNoTierFound() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Annual_NFR_Target_USD__c = 999; // below all matrix tiers
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertNotEquals(null, results[0].errorMessage, 'should return error when no tier matched');
    }

    @IsTest
    static void testSoftBenefitQuestionUsesActualTicketCount() {
        // Setup: RFP with accepted row 1 (3 soft options); soft benefit tier has Free_Tickets__c = 4 (from @TestSetup)
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Matrix_Row__c = 1;
        rfp.Pricing_Approval_Status__c = null;
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assertNotEquals(null, results[0].softBenefitQuestion, 'softBenefitQuestion should not be null when offer is accepted');
        System.assert(
            results[0].softBenefitQuestion.contains('4 complimentary ticket'),
            'softBenefitQuestion should reference actual free ticket count (4) not hardcoded "one": ' + results[0].softBenefitQuestion
        );
        System.assert(
            !results[0].softBenefitQuestion.contains('one complimentary'),
            'softBenefitQuestion should not contain hardcoded "one complimentary": ' + results[0].softBenefitQuestion
        );
    }

    @IsTest
    static void testSoftBenefitQuestionEmptyWhenNoOffer() {
        // RFP with no accepted offer row — softBenefitQuestion should be blank
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{ req }
        );
        Test.stopTest();

        System.assert(
            String.isBlank(results[0].softBenefitQuestion),
            'softBenefitQuestion should be blank when no offer has been accepted: ' + results[0].softBenefitQuestion
        );
    }

    @IsTest
    static void testReturnsRule2FieldsWhenApplied() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        rfp.Offer_Rule2_Uplift_Applied__c = true;
        rfp.Offer_Rule2_Uplift_Pct__c    = 3.0;
        update rfp;

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(null, results[0].errorMessage, 'Unexpected error: ' + results[0].errorMessage);
        System.assertEquals(true, results[0].offerRule2UpliftApplied,
            'offerRule2UpliftApplied should be true when flag is set');
        System.assertEquals(3.0, results[0].offerRule2UpliftPct,
            'offerRule2UpliftPct should be 3.0');
        System.assert(
            results[0].negotiationSummary.containsIgnoreCase('Rule 2') &&
            !results[0].negotiationSummary.containsIgnoreCase('Stream B'),
            'negotiationSummary should contain Rule 2 info, not the stub'
        );
    }

    @IsTest
    static void testReturnsNullRule2FieldsWhenNotApplied() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        GetRfpWithMatrixData.Request req = new GetRfpWithMatrixData.Request();
        req.recordId = rfp.Id;

        Test.startTest();
        List<GetRfpWithMatrixData.Result> results = GetRfpWithMatrixData.execute(
            new List<GetRfpWithMatrixData.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(null, results[0].errorMessage, 'Unexpected error: ' + results[0].errorMessage);
        Boolean applied = results[0].offerRule2UpliftApplied;
        System.assert(applied == null || applied == false,
            'offerRule2UpliftApplied should be false/null when not applied: ' + applied);
        System.assertEquals(null, results[0].offerRule2UpliftPct,
            'offerRule2UpliftPct should be null when not applied');
        System.assert(
            results[0].negotiationSummary.containsIgnoreCase('Rule 2') &&
            !results[0].negotiationSummary.containsIgnoreCase('Stream B'),
            'negotiationSummary should contain Rule 2 info even when not applied'
        );
    }
}