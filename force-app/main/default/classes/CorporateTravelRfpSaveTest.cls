@isTest
private class CorporateTravelRfpSaveTest {

    static CorporateTravelRfpSave.Request buildRequest(String json) {
        CorporateTravelRfpSave.Request req = new CorporateTravelRfpSave.Request();
        req.submissionJSON = json;
        return req;
    }

    @isTest
    static void testSaveNewSubmissionCreatesParentAndRoutes() {
        String json = '{"companyName":"Acme Corp","address":"123 Main St, Nairobi","website":"https://acme.com","primaryLineOfBusiness":"Technology","numberOfTravellingStaff":"50","annualTravelBudget":"120000","contactName":"Jane Smith","contactEmail":"jane@acme.com","contactPhone":"+254700000000","requestType":"New","annualNfrTarget":"80000","economyDiscount":"10% (no restriction)","businessDiscount":"15% (RBD: C)","additionalBenefits":"Lounge access","ticketIssuanceEtOffice":true,"ticketIssuanceGsaOffice":false,"ticketIssuanceTravelAgency":false,"requestedBy":"Jane Smith, Head of Travel","routes":[{"origin":"Kenya","destination":"Ethiopia"},{"origin":"Ethiopia","destination":"United Kingdom"}]}';

        Test.startTest();
        List<CorporateTravelRfpSave.Response> responses =
            CorporateTravelRfpSave.saveRfpSubmission(new List<CorporateTravelRfpSave.Request>{ buildRequest(json) });
        Test.stopTest();

        Assert.areEqual(1, responses.size());
        Assert.isNotNull(responses[0].recordId, 'Should return a record ID');

        Corporate_Travel_RFP__c rfp = [
            SELECT Company_Name__c, Request_Type__c, Status__c,
                   Annual_Travel_Budget_USD__c, Ticket_Issuance_ET_Office__c
            FROM Corporate_Travel_RFP__c LIMIT 1
        ];
        Assert.areEqual('Acme Corp', rfp.Company_Name__c);
        Assert.areEqual('New', rfp.Request_Type__c);
        Assert.areEqual('New', rfp.Status__c);
        Assert.areEqual(120000, rfp.Annual_Travel_Budget_USD__c);
        Assert.isTrue(rfp.Ticket_Issuance_ET_Office__c);

        List<Travel_Route__c> routes = [
            SELECT Origin__c, Destination__c
            FROM Travel_Route__c WHERE Corporate_Travel_RFP__c = :rfp.Id
            ORDER BY Origin__c
        ];
        Assert.areEqual(2, routes.size());
        Assert.areEqual('ETHIOPIA', routes[0].Origin__c);
        Assert.areEqual('KENYA', routes[1].Origin__c);
    }

    @isTest
    static void testSaveRenewalPopulatesCorporateId() {
        String json = '{"companyName":"Beta Corp","address":"456 Oak Ave","website":"https://beta.com","primaryLineOfBusiness":"Finance","annualTravelBudget":"200000","contactName":"Bob Jones","contactEmail":"bob@beta.com","contactPhone":"+1-555-0200","requestType":"Renewal","corporateId":"ET-12345","nfrJustification":"Market downturn","annualNfrTarget":"150000","economyDiscount":"12%","businessDiscount":"18%","requestedBy":"Bob Jones, CFO","routes":[{"origin":"JFK","destination":"ADD"}]}';

        Test.startTest();
        List<CorporateTravelRfpSave.Response> responses =
            CorporateTravelRfpSave.saveRfpSubmission(new List<CorporateTravelRfpSave.Request>{ buildRequest(json) });
        Test.stopTest();

        Corporate_Travel_RFP__c rfp = [SELECT Corporate_ID__c, Request_Type__c FROM Corporate_Travel_RFP__c LIMIT 1];
        Assert.areEqual('Renewal', rfp.Request_Type__c);
        Assert.areEqual('ET-12345', rfp.Corporate_ID__c);
    }

    @isTest
    static void testInvalidJsonReturnsErrorMessage() {
        Test.startTest();
        List<CorporateTravelRfpSave.Response> responses =
            CorporateTravelRfpSave.saveRfpSubmission(new List<CorporateTravelRfpSave.Request>{ buildRequest('NOT_JSON') });
        Test.stopTest();

        Assert.isNull(responses[0].recordId, 'recordId should be null on error');
        Assert.isTrue(responses[0].confirmationMessage.contains('error'), 'Should return error message');
    }

    @IsTest
    static void testFileLinking() {
        // Create a ContentVersion to get a real ContentDocumentId
        ContentVersion cv = new ContentVersion(
            Title = 'Business Licence', PathOnClient = 'licence.pdf',
            VersionData = Blob.valueOf('licence content'), IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        String payload = JSON.serialize(new Map<String, Object>{
            'companyName'         => 'Acme Corp',
            'address'             => '1 Main St',
            'website'             => 'https://acme.com',
            'primaryLineOfBusiness' => 'Technology',
            'annualTravelBudget'  => 75000,
            'contactName'         => 'Jane Doe',
            'contactEmail'        => 'jane@acme.com',
            'contactPhone'        => '+1-555-0100',
            'requestType'         => 'New',
            'annualNfrTarget'     => 60000,
            'economyDiscount'     => '10%',
            'businessDiscount'    => '15%',
            'requestedBy'         => 'Jane Doe, Head of Travel',
            'routes'              => new List<Map<String,String>>{
                new Map<String,String>{'origin'=>'ADD','destination'=>'LHR'}
            },
            'contentDocumentIds'  => cv.ContentDocumentId
        });

        Test.startTest();
        Map<String, String> result = CorporateTravelRfpSave.saveRfpFromLwc(payload);
        Test.stopTest();

        System.assertNotEquals(null, result.get('recordId'));

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :result.get('recordId')
            AND ContentDocumentId = :cv.ContentDocumentId
        ];
        System.assertEquals(1, links.size(), 'Business Licence should be linked to RFP record');
    }

    @IsTest
    static void testSaveWithTravelAgencies() {
        Map<String, Object> payload = new Map<String, Object>{
            'companyName'         => 'Agency Corp',
            'address'             => '5 Agency St',
            'website'             => 'https://agencycorp.com',
            'primaryLineOfBusiness' => 'Travel Management',
            'annualTravelBudget'  => 90000,
            'contactName'         => 'Alice Agent',
            'contactEmail'        => 'alice@agencycorp.com',
            'contactPhone'        => '+44-7700-900001',
            'requestType'         => 'New',
            'annualNfrTarget'     => 70000,
            'economyDiscount'     => '9%',
            'businessDiscount'    => '14%',
            'requestedBy'         => 'Alice Agent, Travel Manager',
            'routes'              => new List<Map<String,String>>{
                new Map<String,String>{'origin'=>'ADD','destination'=>'DXB'}
            },
            'travelAgencies'      => new List<Map<String,String>>{
                new Map<String,String>{
                    'iataName' => 'Global Travel Ltd',
                    'iataNumber' => '12345678',
                    'pcc' => 'GT01',
                    'gds' => 'Sabre'
                }
            }
        };

        Test.startTest();
        Map<String, String> result = CorporateTravelRfpSave.saveRfpFromLwc(JSON.serialize(payload));
        Test.stopTest();

        System.assertNotEquals(null, result.get('recordId'), 'RFP should be saved with agencies');
        List<Travel_Agency__c> agencies = [
            SELECT IATA_Name__c FROM Travel_Agency__c
            WHERE Corporate_Travel_RFP__c = :result.get('recordId')
        ];
        System.assertEquals(1, agencies.size(), 'Travel agency should be saved');
        System.assertEquals('Global Travel Ltd', agencies[0].IATA_Name__c);
    }

    @IsTest
    static void testSaveFindsExistingAccountByWebsite() {
        // Pre-insert an account with a matching website domain
        Account existingAcct = new Account(
            Name    = 'Existing Corp',
            Website = 'https://existing-corp.com'
        );
        insert existingAcct;

        Map<String, Object> payload = new Map<String, Object>{
            'companyName'           => 'Existing Corp',
            'address'               => '1 Existing St',
            'website'               => 'https://www.existing-corp.com',
            'primaryLineOfBusiness' => 'Technology',
            'annualTravelBudget'    => 60000,
            'contactName'           => 'Bob Existing',
            'contactEmail'          => 'bob@existing-corp.com',
            'contactPhone'          => '+1-555-0300',
            'requestType'           => 'New',
            'annualNfrTarget'       => 50000,
            'economyDiscount'       => '7%',
            'businessDiscount'      => '12%',
            'requestedBy'           => 'Bob Existing, CEO',
            'routes'                => new List<Map<String,String>>{
                new Map<String,String>{'origin'=>'ADD','destination'=>'NYC'}
            }
        };

        Test.startTest();
        Map<String, String> result = CorporateTravelRfpSave.saveRfpFromLwc(JSON.serialize(payload));
        Test.stopTest();

        System.assertNotEquals(null, result.get('recordId'));
        // Only one account should exist (re-used, not duplicated)
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Website LIKE '%existing-corp.com%']);
    }

    @IsTest
    static void testSaveFindsExistingContactByEmail() {
        Account acct = new Account(Name = 'Contact Lookup Corp');
        insert acct;
        Contact existingContact = new Contact(
            FirstName = 'Jane',
            LastName  = 'Contact',
            Email     = 'jane.contact@lookup.com',
            AccountId = acct.Id
        );
        insert existingContact;

        Map<String, Object> payload = new Map<String, Object>{
            'companyName'           => 'Contact Lookup Corp',
            'address'               => '2 Lookup St',
            'website'               => 'https://lookup.com',
            'primaryLineOfBusiness' => 'Finance',
            'annualTravelBudget'    => 55000,
            'contactName'           => 'Jane Contact',
            'contactEmail'          => 'jane.contact@lookup.com',
            'contactPhone'          => '+1-555-0400',
            'requestType'           => 'New',
            'annualNfrTarget'       => 45000,
            'economyDiscount'       => '8%',
            'businessDiscount'      => '13%',
            'requestedBy'           => 'Jane Contact, CFO',
            'routes'                => new List<Map<String,String>>{
                new Map<String,String>{'origin'=>'LHR','destination'=>'ADD'}
            }
        };

        Test.startTest();
        Map<String, String> result = CorporateTravelRfpSave.saveRfpFromLwc(JSON.serialize(payload));
        Test.stopTest();

        System.assertNotEquals(null, result.get('recordId'));
        // Contact should be reused, not duplicated
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Email = 'jane.contact@lookup.com']);
    }

    @IsTest
    static void testSaveWithRfpDocumentId() {
        ContentVersion cv = new ContentVersion(
            Title        = 'RFP Document',
            PathOnClient = 'rfp.pdf',
            VersionData  = Blob.valueOf('rfp content'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'companyName'           => 'Doc RFP Corp',
            'address'               => '3 Doc St',
            'website'               => 'https://docrfp.com',
            'primaryLineOfBusiness' => 'Logistics',
            'annualTravelBudget'    => 85000,
            'contactName'           => 'Chris Doc',
            'contactEmail'          => 'chris@docrfp.com',
            'contactPhone'          => '+1-555-0500',
            'requestType'           => 'New',
            'annualNfrTarget'       => 70000,
            'economyDiscount'       => '9%',
            'businessDiscount'      => '14%',
            'requestedBy'           => 'Chris Doc, GM',
            'rfpDocumentId'         => cv.ContentDocumentId,
            'routes'                => new List<Map<String,String>>{
                new Map<String,String>{'origin'=>'ADD','destination'=>'CDG'}
            }
        };

        Test.startTest();
        Map<String, String> result = CorporateTravelRfpSave.saveRfpFromLwc(JSON.serialize(payload));
        Test.stopTest();

        System.assertNotEquals(null, result.get('recordId'));
        Corporate_Travel_RFP__c rfp = [
            SELECT RFP_Document_Id__c FROM Corporate_Travel_RFP__c WHERE Id = :result.get('recordId')
        ];
        System.assertEquals(cv.ContentDocumentId, rfp.RFP_Document_Id__c,
            'RFP_Document_Id__c should be set from rfpDocumentId');
    }

    @IsTest
    static void testFileLinkingDoesNotBlockSaveOnBadId() {
        String payload = JSON.serialize(new Map<String, Object>{
            'companyName'         => 'Beta Corp',
            'address'             => '2 Main St',
            'website'             => 'https://beta.com',
            'primaryLineOfBusiness' => 'Finance',
            'annualTravelBudget'  => 80000,
            'contactName'         => 'John Smith',
            'contactEmail'        => 'john@beta.com',
            'contactPhone'        => '+1-555-0200',
            'requestType'         => 'New',
            'annualNfrTarget'     => 65000,
            'economyDiscount'     => '8%',
            'businessDiscount'    => '12%',
            'requestedBy'         => 'John Smith, CFO',
            'routes'              => new List<Map<String,String>>{
                new Map<String,String>{'origin'=>'ADD','destination'=>'CDG'}
            },
            'contentDocumentIds'  => '069000000000000INVALID'
        });

        Test.startTest();
        Map<String, String> result = CorporateTravelRfpSave.saveRfpFromLwc(payload);
        Test.stopTest();

        // Record should still be created even though the document ID is bad
        System.assertNotEquals(null, result.get('recordId'), 'Save should succeed despite bad document ID');
    }
}