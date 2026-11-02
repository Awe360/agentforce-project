@IsTest
private class rfpProposalAndRequestTest {

    @TestSetup
    static void setupTestData() {
        // 1. Create Test Opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test RFP Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        // 2. Create Base Proposal Version
        Proposal_Version__c proposal = new Proposal_Version__c(
            Opportunity__c = testOpp.Id,
            Business_Discount__c = 10.5,
            Economy_Discount__c = 5.0,
            Min_Target_per_Year_USD__c = 50000,
            Ticket_Issuance_Location__c = 'Addis Ababa',
            Soft_Benefits__c = 'Lounge Access',
            Origin__c = 'ADD',
            Destination__c = 'LHR', 
            Status__c = 'Sent',
            Version_Number__c = 1
        );
        insert proposal;
    }

    // ==========================================
    // 1. TESTS FOR getRecordDetails
    // ==========================================

    @IsTest
    static void testGetRecordDetails_Success() {
        Proposal_Version__c prop = [SELECT Id FROM Proposal_Version__c LIMIT 1];

        System.Test.startTest();
        Proposal_Version__c result = rfpProposalAndRequest.getRecordDetails(prop.Id);
        System.Test.stopTest();

        System.assertNotEquals(null, result, 'Expected proposal record to be returned.');
        System.assertEquals(prop.Id, result.Id, 'Returned record ID should match requested ID.');
    }

    @IsTest
    static void testGetRecordDetails_BlankIdException() {
        System.Test.startTest();
        try {
            rfpProposalAndRequest.getRecordDetails('');
            System.assert(false, 'Expected AuraHandledException for blank ID');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should be thrown for missing ID.');
        }
        System.Test.stopTest();
    }

    @IsTest
    static void testGetRecordDetails_InvalidFormat() {
        System.Test.startTest();
        try {
            rfpProposalAndRequest.getRecordDetails('InvalidID123');
            System.assert(false, 'Expected AuraHandledException for invalid ID format');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should be thrown for invalid ID format.');
        }
        System.Test.stopTest();
    }

    // ==========================================
    // 2. TESTS FOR getLatestProposalByOpportunity
    // ==========================================

    @IsTest
    static void testGetLatestProposalByOpportunity_Success() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        System.Test.startTest();
        Proposal_Version__c latestProp = rfpProposalAndRequest.getLatestProposalByOpportunity(opp.Id);
        System.Test.stopTest();

        System.assertNotEquals(null, latestProp, 'Expected a proposal version to be returned.');
        System.assertEquals(1, latestProp.Version_Number__c, 'Version number should match latest version.');
    }

    @IsTest
    static void testGetLatestProposalByOpportunity_NullIdException() {
        System.Test.startTest();
        try {
            rfpProposalAndRequest.getLatestProposalByOpportunity(null);
            System.assert(false, 'Expected AuraHandledException for null Opportunity ID');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should be thrown when Opportunity ID is null.');
        }
        System.Test.stopTest();
    }

    @IsTest
    static void testGetLatestProposalByOpportunity_NoRecords() {
        Opportunity emptyOpp = new Opportunity(
            Name = 'Empty Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert emptyOpp;

        System.Test.startTest();
        Proposal_Version__c result = rfpProposalAndRequest.getLatestProposalByOpportunity(emptyOpp.Id);
        System.Test.stopTest();

        System.assertEquals(null, result, 'Expected null when no proposal versions exist for Opportunity.');
    }

    // ==========================================
    // 3. TESTS FOR acceptProposal
    // ==========================================

    @IsTest
    static void testAcceptProposal_Success() {
        Proposal_Version__c prop = [SELECT Id, Opportunity__c FROM Proposal_Version__c LIMIT 1];

        System.Test.startTest();
        rfpProposalAndRequest.acceptProposal(prop.Id);
        System.Test.stopTest();

        // Verify Proposal Update
        Proposal_Version__c updatedProp = [SELECT Status__c FROM Proposal_Version__c WHERE Id = :prop.Id];
        System.assertEquals('Accepted', updatedProp.Status__c, 'Proposal status should be updated to Accepted.');

        // Verify Opportunity Update and Field Mappings
        Opportunity updatedOpp = [
            SELECT StageName, 
                   Proposed_Discount_for_Business__c, 
                   Proposed_Discount_for_Economy__c, 
                   Place_of_Ticket_Issuance__c, 
                   Minimum_Annual_TS__c, 
                   Special_services__c, 
                   Origin__c, 
                   Destination__c 
            FROM Opportunity 
            WHERE Id = :prop.Opportunity__c
        ];

        System.assertEquals('Accepted', updatedOpp.StageName, 'Opportunity stage should be Accepted.');
        System.assertEquals(10.5, updatedOpp.Proposed_Discount_for_Business__c, 'Business discount should be mapped.');
        System.assertEquals(5.0, updatedOpp.Proposed_Discount_for_Economy__c, 'Economy discount should be mapped.');
        System.assertEquals('Addis Ababa', updatedOpp.Place_of_Ticket_Issuance__c, 'Ticket issuance location should be mapped.');
        System.assertEquals(50000, updatedOpp.Minimum_Annual_TS__c, 'Minimum target should be mapped.');
        System.assertEquals('Lounge Access', updatedOpp.Special_services__c, 'Soft benefits should be mapped.');
        System.assertEquals('ADD', updatedOpp.Origin__c, 'Origin should be mapped.');
        System.assertEquals('LHR', updatedOpp.Destination__c, 'Destination should be mapped.');
    }

    @IsTest
    static void testAcceptProposal_NullIdException() {
        System.Test.startTest();
        try {
            rfpProposalAndRequest.acceptProposal(null);
            System.assert(false, 'Expected AuraHandledException when passing null record ID');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should be thrown when passing null record ID.');
        }
        System.Test.stopTest();
    }

    // ==========================================
    // 4. TESTS FOR createNewVersion
    // ==========================================

    @IsTest
    static void testCreateNewVersion_Success() {
        Proposal_Version__c oldProp = [SELECT Id, Opportunity__c FROM Proposal_Version__c LIMIT 1];

        Proposal_Version__c updatedFields = new Proposal_Version__c(
            Business_Discount__c = 15.0,
            Economy_Discount__c = 8.0,
            Min_Target_per_Year_USD__c = 75000,
            Soft_Benefits__c = 'Priority Boarding + Lounge Access',
            Customer_Feedback_Request__c = 'Requested higher discount'
        );

        System.Test.startTest();
        Proposal_Version__c newProp = rfpProposalAndRequest.createNewVersion(oldProp.Id, updatedFields);
        System.Test.stopTest();

        // Verify New Version Record
        System.assertNotEquals(null, newProp.Id, 'New proposal version should be inserted.');
        System.assertEquals(2, newProp.Version_Number__c, 'Version number should increment to 2.');
        System.assertEquals('Change Requested', newProp.Status__c, 'Status should set to Change Requested.');
        System.assertEquals('Customer Counter Proposal', newProp.Type__c, 'Type should be Customer Counter Proposal.');
        System.assertEquals(15.0, newProp.Business_Discount__c, 'Updated business discount should be preserved.');

        // Verify Opportunity Stage Update
        Opportunity updatedOpp = [SELECT StageName FROM Opportunity WHERE Id = :oldProp.Opportunity__c];
        System.assertEquals('Negotiation', updatedOpp.StageName, 'Opportunity stage should update to Negotiation.');
    }

    @IsTest
    static void testCreateNewVersion_BlankOldRecordIdException() {
        Proposal_Version__c updatedFields = new Proposal_Version__c();

        System.Test.startTest();
        try {
            rfpProposalAndRequest.createNewVersion('', updatedFields);
            System.assert(false, 'Expected AuraHandledException when passing blank oldRecordId');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Exception should be thrown when passing blank oldRecordId.');
        }
        System.Test.stopTest();
    }
}