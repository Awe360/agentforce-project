public without sharing class BusinessLicencePreviewController {

    private ContentVersion cv {
        get {
            if (cv == null) {
                String docId = ApexPages.currentPage().getParameters().get('docId');
                if (String.isBlank(docId) || docId == 'null' || docId == 'undefined') return null;
                try {
                    cv = [
                        SELECT Id, VersionData, FileExtension
                        FROM ContentVersion
                        WHERE ContentDocumentId = :docId
                        AND IsLatest = true
                        LIMIT 1
                    ];
                } catch (Exception e) {
                    cv = null;
                }
            }
            return cv;
        }
        set;
    }

    public Boolean isPdf {
        get {
            if (cv == null) return false;
            String ext = (cv.FileExtension ?? '').toLowerCase();
            return ext == 'pdf';
        }
    }

    public Boolean isWordDoc {
        get {
            if (cv == null) return false;
            String ext = (cv.FileExtension ?? '').toLowerCase();
            return ext == 'doc' || ext == 'docx';
        }
    }

    public String pdfBase64 {
        get {
            if (cv == null || !isPdf) return null;
            return EncodingUtil.base64Encode(cv.VersionData);
        }
    }

    public String renditionUrl {
        get {
            if (cv == null || !isWordDoc) return null;
            String orgUrl = URL.getOrgDomainUrl().toExternalForm();
            return orgUrl + '/sfc/servlet.shepherd/version/renditionDownload'
                + '?rendition=PDF&versionId=' + cv.Id + '&operationContext=CHATTER';
        }
    }
}