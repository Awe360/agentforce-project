public without sharing class RfpUploadController {

    private static final String ENDPOINT =
        'callout:DocumentAI_NC/services/data/v65.0/ssot/document-processing/actions/extract-data?htmlEncode=false';
    private static final String SCHEMA_NAME = 'ET_Corporate_RFP';

    private static final List<String> REQUIRED_FIELDS = new List<String>{
        'companyName','street','city','country','website','primaryLineOfBusiness',
        'annualTravelBudget','annualNfrTarget','contactName','contactEmail',
        'contactPhone','requestedBy','economyDiscount','businessDiscount'
    };

    public class UploadResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String summary;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String contentDocumentId;
    }

    /**
     * Called from the wizard LWC when a business licence is attached in the form.
     * Creates a ContentVersion and returns the ContentDocumentId so it can be linked
     * to the RFP record at save time. No callout — safe to call after or without any DML.
     * Future: pass the ContentDocumentId to a Document AI validation action.
     */
    @AuraEnabled
    public static UploadResult uploadDocumentOnly(String base64Data, String filename) {
        UploadResult result = new UploadResult();
        try {
            Integer dotIdx = filename.lastIndexOf('.');
            ContentVersion cv = new ContentVersion(
                Title          = dotIdx > 0 ? filename.substring(0, dotIdx) : filename,
                PathOnClient   = filename,
                VersionData    = EncodingUtil.base64Decode(base64Data),
                IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            result.success           = true;
            result.contentDocumentId = cv.ContentDocumentId;
        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    /**
     * Called from rfpUploadClt LWC for the business licence and RFP document upload paths.
     * Creates the ContentVersion only — no callout. The agent action (running as the
     * agent user who has Named Credential access) handles Document AI extraction separately.
     */
    @AuraEnabled
    public static UploadResult uploadFileOnly(String base64Data, String filename) {
        UploadResult result = new UploadResult();
        try {
            String ext = '';
            Integer dotIdx = filename.lastIndexOf('.');
            if (dotIdx >= 0) ext = filename.substring(dotIdx + 1).toLowerCase();

            // Create ContentVersion so the RFP document can be retained on the saved record.
            ContentVersion cv = new ContentVersion(
                Title          = dotIdx > 0 ? filename.substring(0, dotIdx) : filename,
                PathOnClient   = filename,
                VersionData    = EncodingUtil.base64Decode(base64Data),
                IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            // Store ContentDocumentId for agent-side Document AI extraction.
            // The agent action reads ContentVersion.VersionData directly — no base64 staging needed.
            insert new ET_RFP_Extract__c(
                ContentDocumentId__c = cv.ContentDocumentId,
                FileExt__c           = ext
            );
            result.success           = true;
            result.contentDocumentId = cv.ContentDocumentId;
        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    /**
     * Called from rfpUploadClt LWC.
     * Callout happens FIRST (no prior DML in this transaction) to satisfy Apex rules.
     * DML (ContentVersion + ET_RFP_Extract__c) happens after the callout returns.
     */
    @AuraEnabled
    public static UploadResult uploadAndExtract(String base64Data, String filename) {
        UploadResult result = new UploadResult();
        try {
            String ext = '';
            Integer dotIdx = filename.lastIndexOf('.');
            if (dotIdx >= 0) ext = filename.substring(dotIdx + 1).toLowerCase();

            // Step 1: HTTP callout first — no prior DML
            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(ENDPOINT);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(buildBody(base64Data, ext));
            httpReq.setTimeout(120000);

            HttpResponse httpRes = new Http().send(httpReq);

            String extractedJSON;
            String summary;
            Boolean success;

            if (httpRes.getStatusCode() / 100 == 2) {
                Map<String, Object> parsed = (Map<String, Object>)
                    JSON.deserializeUntyped(httpRes.getBody());
                Map<String, Object> fields = parseDocAiResponse(parsed);
                extractedJSON = JSON.serialize(fields);
                summary = buildSummary(fields);
                success = true;
            } else {
                result.success = false;
                result.errorMessage = 'Document AI returned HTTP ' + httpRes.getStatusCode()
                    + ': ' + httpRes.getBody();
                return result;
            }

            // Step 2: DML after callout
            ContentVersion cv = new ContentVersion(
                Title          = dotIdx > 0 ? filename.substring(0, dotIdx) : filename,
                PathOnClient   = filename,
                VersionData    = EncodingUtil.base64Decode(base64Data),
                IsMajorVersion = true
            );
            insert cv;
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            insert new ET_RFP_Extract__c(
                ContentDocumentId__c  = cv.ContentDocumentId,
                ExtractedJSON__c      = extractedJSON,
                ExtractionSummary__c  = summary,
                Success__c            = success
            );

            result.success           = success;
            result.summary           = summary;
            result.contentDocumentId = cv.ContentDocumentId;

        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    // ─── Parsing helpers ─────────────────────────────────────────────────────

    private static String buildBody(String base64Data, String ext) {
        Map<String, Object> body = new Map<String, Object>{
            'idpConfigurationIdOrName' => SCHEMA_NAME,
            'files' => new List<Object>{
                new Map<String, Object>{
                    'mimeType' => mimeTypeFor(ext),
                    'data'     => base64Data
                }
            }
        };
        return JSON.serialize(body);
    }

    private static String mimeTypeFor(String ext) {
        if (ext == 'pdf')  return 'application/pdf';
        if (ext == 'docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        if (ext == 'doc')  return 'application/msword';
        if (ext == 'xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        return 'application/octet-stream';
    }

    private static Map<String, Object> parseDocAiResponse(Map<String, Object> apiResponse) {
        Map<String, Object> result = new Map<String, Object>();
        List<Object> outerData = (List<Object>) apiResponse.get('data');
        if (outerData == null || outerData.isEmpty()) return result;
        Map<String, Object> firstItem = (Map<String, Object>) outerData[0];
        String innerJson = (String) firstItem.get('data');
        if (String.isBlank(innerJson)) return result;
        innerJson = innerJson
            .replace('&quot;', '"').replace('&#92;', '\\')
            .replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>');
        Object parsed;
        try { parsed = JSON.deserializeUntyped(innerJson); }
        catch (Exception e) { return result; }
        Map<String, Object> fieldsMap = extractFieldsMap(parsed);
        if (fieldsMap == null) return result;
        for (String key : fieldsMap.keySet()) {
            result.put(key, unwrapValue(fieldsMap.get(key)));
        }
        return result;
    }

    private static Map<String, Object> extractFieldsMap(Object parsed) {
        if (parsed instanceof List<Object>) {
            List<Object> rows = (List<Object>) parsed;
            if (rows.isEmpty()) return null;
            Object first = rows[0];
            if (!(first instanceof Map<String, Object>)) return null;
            Map<String, Object> row = (Map<String, Object>) first;
            Object val = row.get('value');
            return (val instanceof Map<String, Object>) ? (Map<String, Object>) val : row;
        }
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) parsed;
            Object val = m.get('value');
            return (val instanceof Map<String, Object>) ? (Map<String, Object>) val : m;
        }
        return null;
    }

    private static Object unwrapValue(Object val) {
        if (val instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) val;
            if (m.containsKey('type') && m.containsKey('value')) {
                return unwrapValue(m.get('value'));
            }
            Map<String, Object> r = new Map<String, Object>();
            for (String k : m.keySet()) { r.put(k, unwrapValue(m.get(k))); }
            return r;
        }
        if (val instanceof List<Object>) {
            List<Object> lst = (List<Object>) val;
            List<Object> r = new List<Object>();
            for (Object item : lst) { r.add(unwrapValue(item)); }
            return r;
        }
        return val;
    }

    private static String buildSummary(Map<String, Object> extracted) {
        List<String> found   = new List<String>();
        List<String> missing = new List<String>();
        for (String f : REQUIRED_FIELDS) {
            Object v = extracted.get(f);
            if (v != null && String.valueOf(v).trim() != '') {
                found.add(f);
            } else {
                missing.add(f);
            }
        }
        String summary = 'Extracted ' + found.size() + ' of ' + REQUIRED_FIELDS.size()
            + ' required fields.';
        if (!missing.isEmpty()) {
            summary += ' Missing: ' + String.join(missing, ', ') + '.';
        }
        return summary;
    }

}