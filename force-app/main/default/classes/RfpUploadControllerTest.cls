@IsTest
private class RfpUploadControllerTest {

    private class DocAiMockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> innerData = new Map<String, Object>{
                'type'  => 'object',
                'value' => new Map<String, Object>{
                    'companyName'  => new Map<String, Object>{'type'=>'string','value'=>'Acme Corp'},
                    'contactEmail' => new Map<String, Object>{'type'=>'string','value'=>'test@acme.com'},
                    'address'      => new Map<String, Object>{'type'=>'string','value'=>'123 Main St'},
                    'website'      => new Map<String, Object>{'type'=>'string','value'=>'https://acme.com'},
                    'primaryLineOfBusiness' => new Map<String, Object>{'type'=>'string','value'=>'Finance'},
                    'annualTravelBudget'    => new Map<String, Object>{'type'=>'string','value'=>'100000'},
                    'annualNfrTarget'       => new Map<String, Object>{'type'=>'string','value'=>'80000'},
                    'contactName'           => new Map<String, Object>{'type'=>'string','value'=>'Jane Smith'},
                    'contactPhone'          => new Map<String, Object>{'type'=>'string','value'=>'+1-555-0100'},
                    'requestedBy'           => new Map<String, Object>{'type'=>'string','value'=>'Jane Smith, Head of Travel'},
                    'economyDiscount'       => new Map<String, Object>{'type'=>'string','value'=>'10%'},
                    'businessDiscount'      => new Map<String, Object>{'type'=>'string','value'=>'15%'}
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

    private class DocAiMockFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    @IsTest
    static void testUploadAndExtract_success() {
        Test.setMock(HttpCalloutMock.class, new DocAiMockSuccess());
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('PDF content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadAndExtract(base64, 'test-rfp.pdf');
        Test.stopTest();

        System.assertEquals(true, result.success, 'Should succeed. Error: ' + result.errorMessage);
        System.assertNotEquals(null, result.summary, 'Summary should not be null');
        System.assertNotEquals(null, result.contentDocumentId, 'ContentDocumentId should not be null');

        List<ET_RFP_Extract__c> recs = [SELECT ExtractedJSON__c, Success__c FROM ET_RFP_Extract__c LIMIT 1];
        System.assertEquals(1, recs.size(), 'Should have inserted one ET_RFP_Extract__c record');
        System.assertEquals(true, recs[0].Success__c, 'Record Success__c should be true');
        System.assert(recs[0].ExtractedJSON__c.contains('companyName'), 'JSON should contain companyName');
    }

    @IsTest
    static void testUploadAndExtract_httpFailure() {
        Test.setMock(HttpCalloutMock.class, new DocAiMockFailure());
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('PDF content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadAndExtract(base64, 'test-rfp.pdf');
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail on HTTP 500');
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
        // No ET_RFP_Extract__c record should be inserted on HTTP failure
        System.assertEquals(0, [SELECT COUNT() FROM ET_RFP_Extract__c], 'No record should be inserted on failure');
    }

    @IsTest
    static void testUploadAndExtract_docxFile() {
        Test.setMock(HttpCalloutMock.class, new DocAiMockSuccess());
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('DOCX content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadAndExtract(base64, 'my-proposal.docx');
        Test.stopTest();

        System.assertEquals(true, result.success, 'DOCX upload should succeed');
    }

    @IsTest
    static void testUploadDocumentOnly_success() {
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('licence content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadDocumentOnly(base64, 'licence.pdf');
        Test.stopTest();

        System.assertEquals(true, result.success, 'uploadDocumentOnly should succeed');
        System.assertNotEquals(null, result.contentDocumentId,
            'ContentDocumentId should be returned');
        System.assertEquals(null, result.errorMessage,
            'No error message on success');
    }

    @IsTest
    static void testUploadDocumentOnly_noExtension() {
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('file content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadDocumentOnly(base64, 'noextensionfile');
        Test.stopTest();

        System.assertEquals(true, result.success, 'File without extension should still succeed');
        System.assertNotEquals(null, result.contentDocumentId);
    }

    @IsTest
    static void testUploadFileOnly_success() {
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('rfp document content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadFileOnly(base64, 'rfp.pdf');
        Test.stopTest();

        System.assertEquals(true, result.success, 'uploadFileOnly should succeed');
        System.assertNotEquals(null, result.contentDocumentId);

        List<ET_RFP_Extract__c> extracts = [
            SELECT ContentDocumentId__c, FileExt__c FROM ET_RFP_Extract__c LIMIT 1
        ];
        System.assertEquals(1, extracts.size(), 'Should have created an ET_RFP_Extract__c record');
        System.assertEquals('pdf', extracts[0].FileExt__c, 'FileExt__c should be pdf');
    }

    @IsTest
    static void testUploadFileOnly_docxExtension() {
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('word content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadFileOnly(base64, 'proposal.docx');
        Test.stopTest();

        System.assertEquals(true, result.success);
        List<ET_RFP_Extract__c> extracts = [SELECT FileExt__c FROM ET_RFP_Extract__c LIMIT 1];
        System.assertEquals('docx', extracts[0].FileExt__c);
    }

    @IsTest
    static void testUploadAndExtract_xlsxMimeType() {
        Test.setMock(HttpCalloutMock.class, new DocAiMockSuccess());
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('xlsx content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadAndExtract(base64, 'data.xlsx');
        Test.stopTest();

        System.assertEquals(true, result.success, 'XLSX upload should succeed');
    }

    @IsTest
    static void testUploadAndExtract_unknownExtension() {
        Test.setMock(HttpCalloutMock.class, new DocAiMockSuccess());
        String base64 = EncodingUtil.base64Encode(Blob.valueOf('file content'));

        Test.startTest();
        RfpUploadController.UploadResult result =
            RfpUploadController.uploadAndExtract(base64, 'document.rtf');
        Test.stopTest();

        System.assertEquals(true, result.success, 'Unknown extension should use octet-stream and succeed');
    }
}