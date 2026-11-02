@IsTest
private class GetRfpOfferDataTest {

    private static Id createRfp(Boolean withOffer) {
        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c = 'Test Corp'
        );
        if (withOffer) {
            rfp.Offer_Matrix_Tier__c        = 'Row 1 — Standard';
            rfp.Offer_Matrix_Row__c         = 1;
            rfp.Offer_Routing_Scope__c      = 'All ET Stations';
            rfp.Offer_Economy_Lower_Pct__c  = 8;
            rfp.Offer_Economy_Higher_Pct__c = 10;
            rfp.Offer_D_Class_Pct__c        = 12;
            rfp.Offer_J_Class_Pct__c        = 15;
            rfp.Offer_C_Class_Pct__c        = 20;
            rfp.Offer_Soft_Options_Count__c = 2;
            rfp.Annual_NFR_Target_USD__c    = 350000;
            rfp.Pricing_Approval_Status__c  = 'Approved';
        }
        insert rfp;
        return rfp.Id;
    }

    @IsTest
    static void testGetOfferData_noOffer() {
        Id rfpId = createRfp(false);

        Test.startTest();
        GetRfpOfferData.OfferData d = GetRfpOfferData.getOfferData(rfpId);
        Test.stopTest();

        System.assertEquals(false, d.offerSet, 'offerSet should be false when no offer set');
        System.assertEquals(null, d.tierLabel);
        System.assertEquals(null, d.matrixRow);
        System.assertEquals(false, d.isDefaultRow);
    }

    @IsTest
    static void testGetOfferData_withOfferRow1() {
        Id rfpId = createRfp(true);

        Test.startTest();
        GetRfpOfferData.OfferData d = GetRfpOfferData.getOfferData(rfpId);
        Test.stopTest();

        System.assertEquals(true, d.offerSet);
        System.assertEquals(1, d.matrixRow);
        System.assertEquals(true, d.isDefaultRow, 'Row 1 should be isDefaultRow');
        System.assertEquals(8, d.economyLowerPct);
        System.assertEquals(10, d.economyHigherPct);
        System.assertEquals(12, d.dClassPct);
        System.assertEquals(15, d.jClassPct);
        System.assertEquals(20, d.cClassPct);
        System.assertEquals('Approved', d.approvalStatus);
    }

    @IsTest
    static void testGetOfferData_withSoftBenefitTier() {
        Id rfpId = createRfp(true);

        // Insert a soft benefit tier that matches the RFP's NFR
        ET_Soft_Benefit_Tier__c tier = new ET_Soft_Benefit_Tier__c(
            Tier_Label__c           = 'Mid Tier',
            NFR_Lower_USD__c        = 200000,
            NFR_Upper_USD__c        = 499999,
            Free_Tickets__c         = 2,
            Free_Tickets_Active__c  = true,
            Free_Date_Changes__c    = 1,
            Free_Date_Changes_Active__c = true,
            Baggage_Uplift_Kg__c    = 5,
            Baggage_Active__c       = true,
            Upgrades__c             = 1,
            Upgrades_Active__c      = true,
            Lounge_At_Origin__c     = true,
            Lounge_Active__c        = true,
            Skylight_Hotel_Active__c = true
        );
        insert tier;

        Test.startTest();
        GetRfpOfferData.OfferData d = GetRfpOfferData.getOfferData(rfpId);
        Test.stopTest();

        System.assertNotEquals(0, d.softBenefits.size(), 'Should have soft benefits from tier');
        Boolean hasFreeTickets = false;
        for (GetRfpOfferData.BenefitItem b : d.softBenefits) {
            if (b.label == 'Free Tickets') { hasFreeTickets = true; }
        }
        System.assert(hasFreeTickets, 'Should include Free Tickets benefit');
    }

    @IsTest
    static void testGetOfferData_row2_notDefault() {
        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c         = 'Test Corp 2',
            Offer_Matrix_Tier__c    = 'Row 2 — Escalated',
            Offer_Matrix_Row__c     = 2,
            Annual_NFR_Target_USD__c = 600000
        );
        insert rfp;

        Test.startTest();
        GetRfpOfferData.OfferData d = GetRfpOfferData.getOfferData(rfp.Id);
        Test.stopTest();

        System.assertEquals(2, d.matrixRow);
        System.assertEquals(false, d.isDefaultRow, 'Row 2 should not be isDefaultRow');
    }

    @IsTest
    static void testGetOfferData_rule2Applied() {
        Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
            Company_Name__c               = 'Direct Channel Corp',
            Offer_Matrix_Tier__c          = 'Row 1 — Standard',
            Offer_Matrix_Row__c           = 1,
            Offer_Rule2_Uplift_Applied__c = true,
            Offer_Rule2_Uplift_Pct__c     = 2.5
        );
        insert rfp;

        Test.startTest();
        GetRfpOfferData.OfferData d = GetRfpOfferData.getOfferData(rfp.Id);
        Test.stopTest();

        System.assertEquals(true, d.rule2Applied);
        System.assertEquals(2.5, d.rule2Pct);
    }
}