@IsTest
private class AcceptPricingRowTest {

    @TestSetup
    static void setup() {
        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c          = 'Test Corp',
            Annual_NFR_Target_USD__c = 75000
        );
        insert rfp;

        insert new List<ET_Discount_Tier__c>{
            new ET_Discount_Tier__c(
                Tier_Label__c       = '$50K-$149K', Row_Number__c = 1,
                NFR_Lower_USD__c    = 50000,         NFR_Upper_USD__c = 149999,
                Economy_Lower_Pct__c = 5,            Economy_Higher_Pct__c = 6,
                D_Class_Pct__c      = 7,             J_Class_Pct__c  = 8,
                C_Class_Pct__c      = 9,             Soft_Options_Count__c = 3,
                Routing_Scope__c    = 'Requesting Station Only'
            ),
            new ET_Discount_Tier__c(
                Tier_Label__c       = '$50K-$149K', Row_Number__c = 2,
                NFR_Lower_USD__c    = 50000,         NFR_Upper_USD__c = 149999,
                Economy_Lower_Pct__c = 7,            Economy_Higher_Pct__c = 8,
                D_Class_Pct__c      = 9,             J_Class_Pct__c  = 10,
                C_Class_Pct__c      = 11,            Soft_Options_Count__c = 4,
                Routing_Scope__c    = 'All ET Online Points'
            )
        };
    }

    @IsTest
    static void testRow1NoEscalation() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId     = rfp.Id;
        req.rowNumber = 1;

        Test.startTest();
        List<AcceptPricingRow.Result> results = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one result');
        AcceptPricingRow.Result r = results[0];
        System.assertEquals(true, r.success, 'success=false; error=' + r.errorMessage);
        System.assertEquals(false, r.escalationRequired, 'Row 1 should not need escalation');
        System.assertEquals(1, r.updatedVersion, 'First write should yield version 1');
        System.assertEquals('$50K-$149K', r.tierLabel, 'Wrong tier label');

        Corporate_Travel_RFP__c upd = [
            SELECT Offer_Matrix_Row__c, Offer_Economy_Lower_Pct__c,
                   Escalation_Required__c, Pricing_Approval_Status__c, Status__c
            FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id
        ];
        System.assertEquals(1, Integer.valueOf(upd.Offer_Matrix_Row__c), 'Matrix row should be 1');
        System.assertEquals(5, upd.Offer_Economy_Lower_Pct__c, 'Economy lower should be 5%');
        System.assertEquals(false, upd.Escalation_Required__c, 'No escalation flag');
        System.assertEquals(null, upd.Pricing_Approval_Status__c, 'No approval status for default row');
        System.assertEquals('Offer Prepared', upd.Status__c, 'Status should be Offer Prepared');
    }

    @IsTest
    static void testRow2SetsEscalation() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId                  = rfp.Id;
        req.rowNumber              = 2;
        req.escalationJustification = 'Strategic account — high growth potential';

        Test.startTest();
        List<AcceptPricingRow.Result> results = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'success=false; error=' + results[0].errorMessage);
        System.assertEquals(true, results[0].escalationRequired, 'Row 2 should require escalation');
        System.assertEquals('Pending', results[0].approvalStatus, 'Approval status should be Pending');

        Corporate_Travel_RFP__c upd = [
            SELECT Escalation_Required__c, Escalation_Type__c,
                   Escalation_Justification__c, Pricing_Approval_Status__c,
                   Offer_Matrix_Row__c, Offer_Economy_Lower_Pct__c
            FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id
        ];
        System.assertEquals(true, upd.Escalation_Required__c, 'Escalation flag not set');
        System.assertEquals('In-Tier Row Increase', upd.Escalation_Type__c, 'Wrong escalation type');
        System.assertEquals('Strategic account — high growth potential', upd.Escalation_Justification__c, 'Wrong justification');
        System.assertEquals('Pending', upd.Pricing_Approval_Status__c, 'Approval status should be Pending');
        System.assertEquals(2, Integer.valueOf(upd.Offer_Matrix_Row__c), 'Row should be 2');
        System.assertEquals(7, upd.Offer_Economy_Lower_Pct__c, 'Row 2 economy lower should be 7%');
    }

    @IsTest
    static void testMissingNfrReturnsError() {
        Corporate_Travel_RFP__c noNfr = new Corporate_Travel_RFP__c(
            Company_Name__c = 'No NFR Corp'
        );
        insert noNfr;

        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId     = noNfr.Id;
        req.rowNumber = 1;

        Test.startTest();
        List<AcceptPricingRow.Result> results = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should fail when NFR is null');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be set');
    }

    @IsTest
    static void testInvalidRowNumberReturnsError() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];
        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId     = rfp.Id;
        req.rowNumber = 99;

        Test.startTest();
        List<AcceptPricingRow.Result> results = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should fail with non-existent row 99');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be set');
    }

    @IsTest
    static void testVersionIncrements() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId     = rfp.Id;
        req.rowNumber = 1;

        Test.startTest();
        AcceptPricingRow.accept(new List<AcceptPricingRow.Request>{req});
        List<AcceptPricingRow.Result> second = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(2, second[0].updatedVersion, 'Second acceptance should yield version 2');
    }

    @IsTest
    static void testRule2UpliftAddsToAllRatesAndSetsPending() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c
                                       WHERE Company_Name__c = 'Test Corp' LIMIT 1];
        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId            = rfp.Id;
        req.rowNumber        = 1;
        req.applyRule2Uplift = true;
        req.rule2UpliftPct   = 3.0;

        Test.startTest();
        List<AcceptPricingRow.Result> res = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(true, res[0].success, 'success=false: ' + res[0].errorMessage);
        System.assertEquals(true, res[0].escalationRequired, 'Rule 2 must require escalation');
        System.assertEquals('Pending', res[0].approvalStatus, 'Approval must be Pending');

        Corporate_Travel_RFP__c upd = [
            SELECT Offer_Economy_Lower_Pct__c, Offer_Economy_Higher_Pct__c,
                   Offer_D_Class_Pct__c, Offer_J_Class_Pct__c, Offer_C_Class_Pct__c,
                   Offer_Rule2_Uplift_Applied__c, Offer_Rule2_Uplift_Pct__c,
                   Pricing_Approval_Status__c, Escalation_Type__c
            FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id
        ];
        // Row 1 base rates: 5, 6, 7, 8, 9 — each + 3.0
        System.assertEquals(8.0,  upd.Offer_Economy_Lower_Pct__c,  'T-K: 5+3=8');
        System.assertEquals(9.0,  upd.Offer_Economy_Higher_Pct__c, 'M-Y: 6+3=9');
        System.assertEquals(10.0, upd.Offer_D_Class_Pct__c,        'D: 7+3=10');
        System.assertEquals(11.0, upd.Offer_J_Class_Pct__c,        'J: 8+3=11');
        System.assertEquals(12.0, upd.Offer_C_Class_Pct__c,        'C: 9+3=12');
        System.assertEquals(true, upd.Offer_Rule2_Uplift_Applied__c, 'Flag must be true');
        System.assertEquals(3.0,  upd.Offer_Rule2_Uplift_Pct__c,   'Stored pct must be 3.0');
        System.assertEquals('Pending', upd.Pricing_Approval_Status__c, 'Must be Pending');
        System.assertEquals('Rule 2 Uplift', upd.Escalation_Type__c, 'Escalation type must be Rule 2 Uplift');
    }

    @IsTest
    static void testRule2WithRow2BothEscalate() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c
                                       WHERE Company_Name__c = 'Test Corp' LIMIT 1];
        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId                   = rfp.Id;
        req.rowNumber               = 2;
        req.escalationJustification = 'Major strategic account';
        req.applyRule2Uplift        = true;
        req.rule2UpliftPct          = 2.0;

        Test.startTest();
        List<AcceptPricingRow.Result> res = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(true, res[0].success, 'success=false: ' + res[0].errorMessage);
        System.assertEquals(true, res[0].escalationRequired);

        Corporate_Travel_RFP__c upd = [
            SELECT Offer_Economy_Lower_Pct__c, Offer_C_Class_Pct__c,
                   Offer_Rule2_Uplift_Applied__c, Offer_Rule2_Uplift_Pct__c
            FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id
        ];
        // Row 2 base: eco lower 7, C class 11 — each + 2.0
        System.assertEquals(9.0,  upd.Offer_Economy_Lower_Pct__c, 'Row2 T-K (7) + uplift (2) = 9');
        System.assertEquals(13.0, upd.Offer_C_Class_Pct__c,       'Row2 C (11) + uplift (2) = 13');
        System.assertEquals(true, upd.Offer_Rule2_Uplift_Applied__c);
        System.assertEquals(2.0,  upd.Offer_Rule2_Uplift_Pct__c);
    }

    @IsTest
    static void testRule2TrueNullPctNoRateChange() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c
                                       WHERE Company_Name__c = 'Test Corp' LIMIT 1];
        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId            = rfp.Id;
        req.rowNumber        = 1;
        req.applyRule2Uplift = true;
        req.rule2UpliftPct   = null;

        Test.startTest();
        List<AcceptPricingRow.Result> res = AcceptPricingRow.accept(
            new List<AcceptPricingRow.Request>{req}
        );
        Test.stopTest();

        System.assertEquals(true, res[0].success);

        Corporate_Travel_RFP__c upd = [
            SELECT Offer_Economy_Lower_Pct__c, Offer_Rule2_Uplift_Pct__c
            FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id
        ];
        System.assertEquals(5.0, upd.Offer_Economy_Lower_Pct__c,
            'Null uplift pct must not change row rate');
        System.assertEquals(null, upd.Offer_Rule2_Uplift_Pct__c,
            'Stored uplift pct must be null');
    }

    @IsTest
    static void testNoRule2LeavesFlagsUnset() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c
                                       WHERE Company_Name__c = 'Test Corp' LIMIT 1];
        AcceptPricingRow.Request req = new AcceptPricingRow.Request();
        req.rfpId            = rfp.Id;
        req.rowNumber        = 1;
        req.applyRule2Uplift = false;

        Test.startTest();
        AcceptPricingRow.accept(new List<AcceptPricingRow.Request>{req});
        Test.stopTest();

        Corporate_Travel_RFP__c upd = [
            SELECT Offer_Economy_Lower_Pct__c, Offer_Rule2_Uplift_Applied__c,
                   Offer_Rule2_Uplift_Pct__c
            FROM Corporate_Travel_RFP__c WHERE Id = :rfp.Id
        ];
        System.assertEquals(5.0,  upd.Offer_Economy_Lower_Pct__c, 'Base rate unchanged');
        System.assertEquals(false, upd.Offer_Rule2_Uplift_Applied__c, 'Flag must be false');
        System.assertEquals(null,  upd.Offer_Rule2_Uplift_Pct__c, 'Pct must be null');
    }
}