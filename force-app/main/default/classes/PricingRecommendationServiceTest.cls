@IsTest
private class PricingRecommendationServiceTest {

    @TestSetup
    static void setup() {
        ET_Discount_Tier__c dt1 = new ET_Discount_Tier__c(
            Tier_Label__c         = 'Test Tier $50K–$149K',
            Row_Number__c         = 1,
            NFR_Lower_USD__c      = 50000,
            NFR_Upper_USD__c      = 149999,
            Economy_Lower_Pct__c  = 5.0,
            Economy_Higher_Pct__c = 6.0,
            D_Class_Pct__c        = 6.0,
            J_Class_Pct__c        = 7.0,
            C_Class_Pct__c        = 8.0,
            Soft_Options_Count__c = 3,
            Routing_Scope__c      = 'Requesting Station Only'
        );
        ET_Discount_Tier__c dt2 = new ET_Discount_Tier__c(
            Tier_Label__c         = 'Test Tier $50K–$149K',
            Row_Number__c         = 2,
            NFR_Lower_USD__c      = 50000,
            NFR_Upper_USD__c      = 149999,
            Economy_Lower_Pct__c  = 6.0,
            Economy_Higher_Pct__c = 7.0,
            D_Class_Pct__c        = 7.0,
            J_Class_Pct__c        = 8.0,
            C_Class_Pct__c        = 9.0,
            Soft_Options_Count__c = 2,
            Routing_Scope__c      = 'Requesting Station Only'
        );
        insert new List<ET_Discount_Tier__c>{ dt1, dt2 };

        ET_Soft_Benefit_Tier__c sb = new ET_Soft_Benefit_Tier__c(
            Tier_Label__c               = 'Test Tier $50K–$149K',
            NFR_Lower_USD__c            = 50000,
            NFR_Upper_USD__c            = 149999,
            Free_Tickets__c             = 2,
            Free_Tickets_Active__c      = true,
            Free_Date_Changes__c        = 1,
            Free_Date_Changes_Active__c = true,
            Baggage_Uplift_Kg__c        = 0,
            Baggage_Active__c           = false,
            Upgrades__c                 = 0,
            Upgrades_Active__c          = false,
            Lounge_At_Origin__c         = false,
            Lounge_Active__c            = false,
            Skylight_Hotel_Active__c    = false
        );
        insert sb;

        Account acct = new Account(Name = 'Test Airline Corp');
        insert acct;

        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c          = 'Test Airline Corp',
            Contact_Email__c         = 'rep@testairline.example.com',
            Annual_NFR_Target_USD__c = 75000
        );
        insert rfp;
    }

    @IsTest
    static void testReturnsCorrectTierAndRow1() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        PricingRecommendationService.Input inp = new PricingRecommendationService.Input();
        inp.rfpId = rfp.Id;

        Test.startTest();
        List<PricingRecommendationService.Output> results =
            PricingRecommendationService.calculate(new List<PricingRecommendationService.Input>{ inp });
        Test.stopTest();

        PricingRecommendationService.Output out = results[0];
        System.assertEquals(true, out.tierFound, 'success=false; error=' + out.errorMessage);
        System.assertEquals('Test Tier $50K–$149K', out.tierLabel);
        System.assertEquals('Requesting Station Only', out.routingScope);
        System.assertEquals(5.0, out.row1EconomyLowerPct);
        System.assertEquals(6.0, out.row1EconomyHigherPct);
        System.assertEquals(6.0, out.row1DClassPct);
        System.assertEquals(7.0, out.row1JClassPct);
        System.assertEquals(8.0, out.row1CClassPct);
        System.assertEquals(3, out.row1SoftOptionsCount);
    }

    @IsTest
    static void testAllRowsJsonContainsBothRows() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        PricingRecommendationService.Input inp = new PricingRecommendationService.Input();
        inp.rfpId = rfp.Id;

        Test.startTest();
        List<PricingRecommendationService.Output> results =
            PricingRecommendationService.calculate(new List<PricingRecommendationService.Input>{ inp });
        Test.stopTest();

        List<Object> rows = (List<Object>) JSON.deserializeUntyped(results[0].allRowsJson);
        System.assertEquals(2, rows.size(), 'should return both rows for the tier');
        System.assert(results[0].offerOptionsSummary.contains('Row 1'), results[0].offerOptionsSummary);
        System.assert(results[0].offerOptionsSummary.contains('Row 2'), results[0].offerOptionsSummary);
    }

    @IsTest
    static void testBenefitSummaryContainsActiveItems() {
        Corporate_Travel_RFP__c rfp = [SELECT Id FROM Corporate_Travel_RFP__c LIMIT 1];

        PricingRecommendationService.Input inp = new PricingRecommendationService.Input();
        inp.rfpId = rfp.Id;

        Test.startTest();
        List<PricingRecommendationService.Output> results =
            PricingRecommendationService.calculate(new List<PricingRecommendationService.Input>{ inp });
        Test.stopTest();

        System.assert(results[0].availableBenefitsSummary.contains('2 free tickets'), results[0].availableBenefitsSummary);
        System.assert(results[0].availableBenefitsSummary.contains('1 free date change'), results[0].availableBenefitsSummary);
    }

    @IsTest
    static void testNullNfrReturnsError() {
        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c  = 'No NFR Corp',
            Contact_Email__c = 'rep@nonfr.example.com'
        );
        insert rfp;

        PricingRecommendationService.Input inp = new PricingRecommendationService.Input();
        inp.rfpId = rfp.Id;

        Test.startTest();
        List<PricingRecommendationService.Output> results =
            PricingRecommendationService.calculate(new List<PricingRecommendationService.Input>{ inp });
        Test.stopTest();

        System.assertEquals(false, results[0].tierFound);
        System.assert(results[0].errorMessage != null);
    }
}