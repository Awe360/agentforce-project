@IsTest
private class BusinessLicencePreviewControllerTest {

    private static ContentVersion insertPdfFile() {
        ContentVersion cv = new ContentVersion(
            Title        = 'Test Licence',
            PathOnClient = 'licence.pdf',
            VersionData  = Blob.valueOf('%PDF-1.4 test pdf content'),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
    }

    private static ContentVersion insertDocxFile() {
        ContentVersion cv = new ContentVersion(
            Title        = 'Test Licence Word',
            PathOnClient = 'licence.docx',
            VersionData  = Blob.valueOf('docx content'),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
    }

    @IsTest
    static void testWithNoDocId_returnsNoDocument() {
        PageReference pageRef = Page.BusinessLicencePreview;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('docId', null);

        Test.startTest();
        BusinessLicencePreviewController ctrl = new BusinessLicencePreviewController();
        Test.stopTest();

        System.assertEquals(false, ctrl.isPdf,    'isPdf should be false with no docId');
        System.assertEquals(false, ctrl.isWordDoc, 'isWordDoc should be false with no docId');
        System.assertEquals(null,  ctrl.pdfBase64,  'pdfBase64 should be null with no docId');
        System.assertEquals(null,  ctrl.renditionUrl, 'renditionUrl should be null with no docId');
    }

    @IsTest
    static void testWithBlankDocId() {
        PageReference pageRef = Page.BusinessLicencePreview;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('docId', '');

        Test.startTest();
        BusinessLicencePreviewController ctrl = new BusinessLicencePreviewController();
        Test.stopTest();

        System.assertEquals(false, ctrl.isPdf);
        System.assertEquals(false, ctrl.isWordDoc);
    }

    @IsTest
    static void testWithLiteralNullString() {
        PageReference pageRef = Page.BusinessLicencePreview;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('docId', 'null');

        Test.startTest();
        BusinessLicencePreviewController ctrl = new BusinessLicencePreviewController();
        Test.stopTest();

        System.assertEquals(false, ctrl.isPdf);
        System.assertEquals(false, ctrl.isWordDoc);
    }

    @IsTest
    static void testWithPdfDocument() {
        ContentVersion cv = insertPdfFile();
        PageReference pageRef = Page.BusinessLicencePreview;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('docId', cv.ContentDocumentId);

        Test.startTest();
        BusinessLicencePreviewController ctrl = new BusinessLicencePreviewController();
        Test.stopTest();

        System.assertEquals(true,  ctrl.isPdf,    'isPdf should be true for a PDF file');
        System.assertEquals(false, ctrl.isWordDoc, 'isWordDoc should be false for a PDF file');
        System.assertNotEquals(null, ctrl.pdfBase64, 'pdfBase64 should not be null for PDF');
    }

    @IsTest
    static void testWithDocxDocument() {
        ContentVersion cv = insertDocxFile();
        PageReference pageRef = Page.BusinessLicencePreview;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('docId', cv.ContentDocumentId);

        Test.startTest();
        BusinessLicencePreviewController ctrl = new BusinessLicencePreviewController();
        Test.stopTest();

        System.assertEquals(false, ctrl.isPdf,     'isPdf should be false for DOCX');
        System.assertEquals(true,  ctrl.isWordDoc,  'isWordDoc should be true for DOCX');
        System.assertNotEquals(null, ctrl.renditionUrl, 'renditionUrl should not be null for DOCX');
        System.assert(ctrl.renditionUrl.contains('renditionDownload'), 'renditionUrl should use shepherd endpoint');
    }

    @IsTest
    static void testWithInvalidDocId_gracefullyReturnsNoDocument() {
        PageReference pageRef = Page.BusinessLicencePreview;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('docId', '069000000000000AAA');

        Test.startTest();
        BusinessLicencePreviewController ctrl = new BusinessLicencePreviewController();
        Test.stopTest();

        // Invalid ID: SOQL returns no rows, controller should handle gracefully
        System.assertEquals(false, ctrl.isPdf);
        System.assertEquals(false, ctrl.isWordDoc);
    }
}