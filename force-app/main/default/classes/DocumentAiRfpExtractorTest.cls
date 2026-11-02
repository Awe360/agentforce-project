@IsTest
private class DocumentAiRfpExtractorTest {

    // ─── Mock responses ───────────────────────────────────────────────────────

    /**
     * Returns the real Document AI response envelope:
     * {data:[{data:"<json-string>"}]} where inner JSON uses {type,value} wrappers.
     */
    private class DocumentAiMockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> innerData = new Map<String, Object>{
                'type'  => 'object',
                'value' => new Map<String, Object>{
                    'companyName'  => new Map<String, Object>{'type'=>'string', 'value'=>'Acme Corp'},
                    'contactEmail' => new Map<String, Object>{'type'=>'string', 'value'=>'test@acme.com'},
                    'routes'       => new Map<String, Object>{
                        'type'  => 'array',
                        'value' => new List<Object>{
                            new Map<String, Object>{
                                'type'  => 'object',
                                'value' => new Map<String, Object>{
                                    'origin'      => new Map<String, Object>{'type'=>'string', 'value'=>'ADD'},
                                    'destination' => new Map<String, Object>{'type'=>'string', 'value'=>'LHR'}
                                }
                            }
                        }
                    }
                }
            };
            String innerJson = JSON.serialize(new List<Object>{ innerData });
            Map<String, Object> envelope = new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{'data' => innerJson}
                }
            };
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(201);
            res.setBody(JSON.serialize(envelope));
            return res;
        }
    }

    private class DocumentAiMockFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    // ─── Helper ───────────────────────────────────────────────────────────────

    private static ContentVersion insertTestFile() {
        ContentVersion cv = new ContentVersion(
            Title          = 'Test RFP',
            PathOnClient   = 'test-rfp.pdf',
            VersionData    = Blob.valueOf('PDF content'),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
    }

    // ─── Test 1: ContentDocumentId path — success ─────────────────────────────

    @IsTest
    static void testSuccessfulExtraction_viaContentDocumentId() {
        ContentVersion cv = insertTestFile();
        Test.setMock(HttpCalloutMock.class, new DocumentAiMockSuccess());

        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        req.contentDocumentId = cv.ContentDocumentId;
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Should succeed');
        System.assertNotEquals(null, results[0].extractedFieldsJSON, 'JSON should not be null');
        System.assert(results[0].extractedFieldsJSON.contains('companyName'), 'JSON should contain companyName');
        System.assertNotEquals(null, results[0].extractionSummary, 'Summary should not be null');
    }

    // ─── Test 2: MessagingSessionId path — success ────────────────────────────

    @IsTest
    static void testSuccessfulExtraction_viaMessagingSessionId() {
        ContentVersion cv = insertTestFile();
        Account acct = new Account(Name = 'Test Org');
        insert acct;
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = acct.Id,
            ShareType         = 'V'
        );
        Test.setMock(HttpCalloutMock.class, new DocumentAiMockSuccess());

        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        req.messagingSessionId = acct.Id;
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success,
            'Should succeed via MessagingSessionId fallback. Error: ' + results[0].errorMessage);
        System.assert(results[0].extractedFieldsJSON.contains('companyName'),
            'JSON should contain companyName');
    }

    // ─── Test 3: Both inputs blank — no CDL in org → error ───────────────────

    @IsTest
    static void testBothInputsBlank_returnsError() {
        // No ContentDocumentLinks exist in a clean test context
        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success, 'Should fail when no file can be located');
        System.assert(results[0].errorMessage != null && results[0].errorMessage.length() > 0,
            'Should have an error message');
    }

    // ─── Test 4: MessagingSessionId provided but no file linked ──────────────

    @IsTest
    static void testMessagingSessionId_noFileLinked_returnsError() {
        Account acct = new Account(Name = 'Empty Org');
        insert acct;

        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        req.messagingSessionId = acct.Id;
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success,
            'Should fail when no CDL found for session or any MessagingSession');
        System.assert(results[0].errorMessage != null, 'Should have error message');
    }

    // ─── Test 5: ContentDocumentId path — HTTP 500 failure ───────────────────

    @IsTest
    static void testCalloutFailure() {
        ContentVersion cv = insertTestFile();
        Test.setMock(HttpCalloutMock.class, new DocumentAiMockFailure());

        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        req.contentDocumentId = cv.ContentDocumentId;
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should fail on HTTP 500');
        System.assertNotEquals(null, results[0].errorMessage, 'Should have error message');
    }

    // ─── Test 6: Direct base64 path ──────────────────────────────────────────

    @IsTest
    static void testDirectBase64Path() {
        Test.setMock(HttpCalloutMock.class, new DocumentAiMockSuccess());

        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        req.fileBase64  = EncodingUtil.base64Encode(Blob.valueOf('part1'));
        req.fileBase64b = EncodingUtil.base64Encode(Blob.valueOf('part2'));
        req.fileExt     = 'pdf';
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success,
            'Direct base64 path should succeed. Error: ' + results[0].errorMessage);
        System.assert(results[0].extractedFieldsJSON.contains('companyName'));
    }

    // ─── Test 7: Cached ET_RFP_Extract__c path ───────────────────────────────

    @IsTest
    static void testCachedExtractionPath() {
        ContentVersion cv = insertTestFile();
        // Pre-populate a successful extraction cache record
        insert new ET_RFP_Extract__c(
            ContentDocumentId__c = cv.ContentDocumentId,
            ExtractedJSON__c     = '{"companyName":"Cached Corp","contactEmail":"cache@test.com"}',
            ExtractionSummary__c = 'Extracted 2 of 16 required fields.',
            Success__c           = true,
            FileExt__c           = 'pdf'
        );

        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        req.contentDocumentId = cv.ContentDocumentId;
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Cached path should succeed');
        System.assert(results[0].extractedFieldsJSON.contains('Cached Corp'),
            'Should return data from cache');
        System.assertNotEquals(null, results[0].extractionSummary);
    }

    // ─── Test 8: URL stripping in extracted fields ────────────────────────────

    private class DocumentAiMockWithUrls implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> innerData = new Map<String, Object>{
                'type'  => 'object',
                'value' => new Map<String, Object>{
                    'website'      => new Map<String, Object>{'type'=>'string', 'value'=>'https://acme.com'},
                    'website2'     => new Map<String, Object>{'type'=>'string', 'value'=>'http://old.acme.com'},
                    'companyName'  => new Map<String, Object>{'type'=>'string', 'value'=>'URL_Redacted'}
                }
            };
            String innerJson = JSON.serialize(new List<Object>{ innerData });
            Map<String, Object> envelope = new Map<String, Object>{
                'data' => new List<Object>{
                    new Map<String, Object>{'data' => innerJson}
                }
            };
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(envelope));
            return res;
        }
    }

    @IsTest
    static void testUrlStripping() {
        ContentVersion cv = insertTestFile();
        Test.setMock(HttpCalloutMock.class, new DocumentAiMockWithUrls());

        Test.startTest();
        DocumentAiRfpExtractor.ExtractRequest req = new DocumentAiRfpExtractor.ExtractRequest();
        req.contentDocumentId = cv.ContentDocumentId;
        List<DocumentAiRfpExtractor.ExtractResponse> results =
            DocumentAiRfpExtractor.extractFromDocument(
                new List<DocumentAiRfpExtractor.ExtractRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Should succeed');
        Map<String, Object> fields = (Map<String, Object>)
            JSON.deserializeUntyped(results[0].extractedFieldsJSON);
        System.assertEquals('acme.com',     fields.get('website'),  'https:// should be stripped');
        System.assertEquals('old.acme.com', fields.get('website2'), 'http:// should be stripped');
        System.assertEquals('',             fields.get('companyName'), 'URL_Redacted should become empty string');
    }

    // ─── Test 9: remapTravelAgencies ─────────────────────────────────────────

    @IsTest
    static void testRemapTravelAgencies() {
        Map<String, Object> extracted = new Map<String, Object>{
            'companyName' => 'Acme',
            'travelAgencies' => new List<Object>{
                new Map<String, Object>{
                    'iataName'   => 'Global Travel',
                    'iataNumber' => '12345678',
                    'pcc'        => 'ABC1',
                    'gds'        => 'Amadeus'
                },
                new Map<String, Object>{
                    'iataName' => '', 'iataNumber' => '', 'pcc' => '', 'gds' => ''
                }
            }
        };

        DocumentAiRfpExtractor.remapTravelAgencies(extracted);

        // Method removes original key and re-adds a filtered version
        List<Object> agencies = (List<Object>) extracted.get('travelAgencies');
        System.assertNotEquals(null, agencies, 'Remapped travelAgencies should exist');
        System.assertEquals(1, agencies.size(),
            'Empty agency row should be filtered out');
        Map<String, Object> agency = (Map<String, Object>) agencies[0];
        System.assertEquals('Global Travel', agency.get('iataName'));
        System.assertEquals('12345678',      agency.get('iataNumber'));
    }

    // ─── Test 10: buildFieldMap edge cases ───────────────────────────────────

    @IsTest
    static void testBuildFieldMap_emptyData() {
        Map<String, Object> apiResponse = new Map<String, Object>{
            'data' => new List<Object>()
        };
        Map<String, Object> result = DocumentAiRfpExtractor.buildFieldMap(apiResponse);
        System.assertEquals(0, result.size(), 'Empty data should return empty map');
    }

    @IsTest
    static void testBuildFieldMap_nullData() {
        Map<String, Object> apiResponse = new Map<String, Object>();
        Map<String, Object> result = DocumentAiRfpExtractor.buildFieldMap(apiResponse);
        System.assertEquals(0, result.size(), 'Null data key should return empty map');
    }

    @IsTest
    static void testBuildFieldMap_mapInput() {
        // Inner JSON as a plain map (not wrapped in a list)
        Map<String, Object> innerFields = new Map<String, Object>{
            'companyName' => new Map<String, Object>{'type'=>'string', 'value'=>'Direct Map Corp'},
            'contactEmail' => 'direct@test.com'
        };
        String innerJson = JSON.serialize(new Map<String, Object>{
            'type'  => 'object',
            'value' => innerFields
        });
        Map<String, Object> apiResponse = new Map<String, Object>{
            'data' => new List<Object>{
                new Map<String, Object>{'data' => innerJson}
            }
        };

        Map<String, Object> result = DocumentAiRfpExtractor.buildFieldMap(apiResponse);
        System.assertEquals('Direct Map Corp', result.get('companyName'));
    }
}