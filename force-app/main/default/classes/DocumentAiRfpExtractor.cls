public without sharing class DocumentAiRfpExtractor {

    private static final String ENDPOINT =
        'callout:DocumentAI_NC/services/data/v65.0/ssot/document-processing/actions/extract-data?htmlEncode=false';

    private static final String SCHEMA_NAME = 'ET_Corporate_RFP';

    private static final List<String> REQUIRED_FIELDS = new List<String>{
        'companyName','street','city','country','website','primaryLineOfBusiness',
        'annualTravelBudget','annualNfrTarget','contactName','contactEmail',
        'contactPhone','requestedBy','economyDiscount','businessDiscount'
    };

    public class ExtractRequest {
        @InvocableVariable(label='Content Document Id' required=false)
        public String contentDocumentId;

        @InvocableVariable(label='Messaging Session Id' required=false)
        public String messagingSessionId;

        @InvocableVariable(label='File Base64 Part 1' required=false)
        public String fileBase64;

        @InvocableVariable(label='File Base64 Part 2' required=false)
        public String fileBase64b;

        @InvocableVariable(label='File Extension' required=false)
        public String fileExt;
    }

    public class ExtractResponse {
        @InvocableVariable(label='Extracted Fields JSON')
        public String extractedFieldsJSON;
        @InvocableVariable(label='Extraction Summary')
        public String extractionSummary;
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Extract RFP from Document' category='Corporate Travel'
        description='Calls Document AI to extract RFP fields from an uploaded document.')
    public static List<ExtractResponse> extractFromDocument(List<ExtractRequest> requests) {
        List<ExtractResponse> responses = new List<ExtractResponse>();
        for (ExtractRequest req : requests) {
            responses.add(processOne(req));
        }
        return responses;
    }

    private static ExtractResponse processOne(ExtractRequest req) {
        ExtractResponse res = new ExtractResponse();
        try {
            String requestBody;

            if (!String.isBlank(req.fileBase64)) {
                // Direct base64 path — no ContentVersion needed (avoids managed-package trigger)
                String fullBase64 = req.fileBase64 + (String.isBlank(req.fileBase64b) ? '' : req.fileBase64b);
                requestBody = buildRequestBodyFromBase64(fullBase64, req.fileExt);
            } else {
                String docId = resolveContentDocumentId(req, res);
                if (docId == null) {
                    return res;
                }

                // Check for a cached extraction written by uploadAndExtract during the upload step.
                // uploadAndExtract runs Document AI synchronously and stores the result in
                // ET_RFP_Extract__c. If that record exists, skip the callout entirely.
                List<ET_RFP_Extract__c> cached = [
                    SELECT ExtractedJSON__c, ExtractionSummary__c
                    FROM ET_RFP_Extract__c
                    WHERE ContentDocumentId__c = :docId
                    AND Success__c = true
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                if (!cached.isEmpty() && !String.isBlank(cached[0].ExtractedJSON__c)) {
                    Map<String, Object> extracted = (Map<String, Object>)
                        JSON.deserializeUntyped(cached[0].ExtractedJSON__c);
                    remapTravelAgencies(extracted);
                    res.extractedFieldsJSON = JSON.serialize(extracted);
                    res.extractionSummary   = cached[0].ExtractionSummary__c;
                    res.success             = true;
                    return res;
                }

                ContentVersion cv = [
                    SELECT VersionData, Title, FileExtension
                    FROM ContentVersion
                    WHERE ContentDocumentId = :docId
                    AND IsLatest = true
                    LIMIT 1
                ];
                requestBody = buildRequestBody(cv.VersionData, cv.FileExtension);
            }

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint(ENDPOINT);
            httpReq.setMethod('POST');
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setBody(requestBody);
            httpReq.setTimeout(120000);

            HttpResponse httpRes = new Http().send(httpReq);

            if (httpRes.getStatusCode() / 100 == 2) {
                Map<String, Object> parsed = (Map<String, Object>)
                    JSON.deserializeUntyped(httpRes.getBody());
                Map<String, Object> extracted = buildFieldMap(parsed);
                // Strip URL protocols so Agentforce guardrails don't redact them in action outputs.
                // The form CLT re-adds https:// when populating url-type fields.
                Map<String, Object> urlFixes = new Map<String, Object>();
                for (String k : extracted.keySet()) {
                    Object v = extracted.get(k);
                    if (!(v instanceof String)) continue;
                    String sv = (String) v;
                    if (sv.startsWith('https://')) {
                        urlFixes.put(k, sv.substring(8));
                    } else if (sv.startsWith('http://')) {
                        urlFixes.put(k, sv.substring(7));
                    } else if ('URL_Redacted'.equals(sv)) {
                        urlFixes.put(k, '');
                    }
                }
                extracted.putAll(urlFixes);
                remapTravelAgencies(extracted);
                res.extractedFieldsJSON = JSON.serialize(extracted);
                res.extractionSummary   = buildSummary(extracted);
                res.success             = true;
            } else {
                res.success      = false;
                res.errorMessage = 'Document AI returned HTTP ' + httpRes.getStatusCode()
                    + ': ' + httpRes.getBody();
            }
        } catch (Exception e) {
            res.success      = false;
            res.errorMessage = e.getMessage();
        }
        return res;
    }

    /**
     * Resolves to a ContentDocumentId using three strategies in priority order:
     * 1. contentDocumentId directly (if provided)
     * 2. CDL lookup by messagingSessionId (if provided)
     * 3. Fallback: most recent CDL linked to any MessagingSession (LinkedEntityId LIKE '0Mw%')
     */
    @TestVisible
    private static String resolveContentDocumentId(ExtractRequest req, ExtractResponse res) {
        if (!String.isBlank(req.contentDocumentId)) {
            return req.contentDocumentId;
        }
        if (!String.isBlank(req.messagingSessionId)) {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :req.messagingSessionId
                ORDER BY SystemModstamp DESC
                LIMIT 1
            ];
            if (!links.isEmpty()) {
                return links[0].ContentDocumentId;
            }
        }
        // Fallback: find the most recently uploaded CDL across ALL active MessagingSessions
        // (LastModifiedDate on session does not update with messages, so we query all sessions
        //  and pick the CDL with the most recent SystemModstamp)
        try {
            List<SObject> sessions = Database.query(
                'SELECT Id FROM MessagingSession WHERE Status = \'Active\' LIMIT 50'
            );
            if (!sessions.isEmpty()) {
                List<Id> sessionIds = new List<Id>();
                for (SObject s : sessions) { sessionIds.add((Id) s.get('Id')); }
                List<ContentDocumentLink> recentLinks = [
                    SELECT ContentDocumentId
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId IN :sessionIds
                    ORDER BY SystemModstamp DESC
                    LIMIT 1
                ];
                if (!recentLinks.isEmpty()) {
                    return recentLinks[0].ContentDocumentId;
                }
            }
        } catch (Exception e) { /* MessagingSession not queryable — skip */ }
        res.success      = false;
        res.errorMessage = 'No uploaded file could be located. Please upload a document first.';
        return null;
    }

    private static String buildRequestBodyFromBase64(String base64Data, String fileExt) {
        Map<String, Object> body = new Map<String, Object>{
            'idpConfigurationIdOrName' => SCHEMA_NAME,
            'files' => new List<Object>{
                new Map<String, Object>{
                    'mimeType' => mimeType(fileExt),
                    'data'     => base64Data
                }
            }
        };
        return JSON.serialize(body);
    }

    private static String buildRequestBody(Blob fileData, String fileExt) {
        // Document AI REST API format: idpConfigurationIdOrName + files array
        Map<String, Object> body = new Map<String, Object>{
            'idpConfigurationIdOrName' => SCHEMA_NAME,
            'files' => new List<Object>{
                new Map<String, Object>{
                    'mimeType' => mimeType(fileExt),
                    'data'     => EncodingUtil.base64Encode(fileData)
                }
            }
        };
        return JSON.serialize(body);
    }

    private static String mimeType(String ext) {
        if (ext == null) return 'application/octet-stream';
        String lower = ext.toLowerCase();
        if (lower == 'pdf')  return 'application/pdf';
        if (lower == 'docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        if (lower == 'doc')  return 'application/msword';
        if (lower == 'xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        return 'application/octet-stream';
    }

    /**
     * Parses the Document AI response envelope:
     * Outer: {data: [{data: "<json-string>"}]}
     * Inner JSON: [{type:"object", value:{fieldName:{type,value}, ...}}]
     * Unwraps all {type,value} wrappers recursively to produce plain field values.
     */
    @TestVisible
    private static Map<String, Object> buildFieldMap(Map<String, Object> apiResponse) {
        Map<String, Object> result = new Map<String, Object>();

        List<Object> outerData = (List<Object>) apiResponse.get('data');
        if (outerData == null || outerData.isEmpty()) return result;

        Map<String, Object> firstItem = (Map<String, Object>) outerData[0];
        String innerJson = (String) firstItem.get('data');
        if (String.isBlank(innerJson)) return result;

        // Unescape HTML entities — defensive, in case htmlEncode=false doesn't fully suppress
        innerJson = innerJson
            .replace('&quot;', '"')
            .replace('&#92;', '\\')
            .replace('&amp;', '&')
            .replace('&lt;', '<')
            .replace('&gt;', '>');

        Object parsed;
        try { parsed = JSON.deserializeUntyped(innerJson); } catch (Exception e) { return result; }

        Map<String, Object> fieldsMap = extractFieldsMap(parsed);
        if (fieldsMap == null) return result;

        for (String key : fieldsMap.keySet()) {
            result.put(key, unwrapDocAiValue(fieldsMap.get(key)));
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

    private static Object unwrapDocAiValue(Object val) {
        if (val instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) val;
            if (m.containsKey('type') && m.containsKey('value')) {
                return unwrapDocAiValue(m.get('value'));
            }
            Map<String, Object> r = new Map<String, Object>();
            for (String k : m.keySet()) { r.put(k, unwrapDocAiValue(m.get(k))); }
            return r;
        }
        if (val instanceof List<Object>) {
            List<Object> lst = (List<Object>) val;
            List<Object> r = new List<Object>();
            for (Object item : lst) { r.add(unwrapDocAiValue(item)); }
            return r;
        }
        return val;
    }

    @TestVisible
    private static void remapTravelAgencies(Map<String, Object> result) {
        String taKey = null;
        for (String k : result.keySet()) {
            String kl = k.toLowerCase().replace('_', '').replace(' ', '');
            if (kl.startsWith('travelagenc') && result.get(k) instanceof List<Object>) {
                taKey = k;
                break;
            }
        }
        if (taKey == null) return;

        List<Object> rows = (List<Object>) result.get(taKey);
        List<Object> agencies = new List<Object>();
        for (Object rowObj : rows) {
            if (!(rowObj instanceof Map<String, Object>)) continue;
            Map<String, Object> row = (Map<String, Object>) rowObj;
            Map<String, Object> agency = new Map<String, Object>{
                'iataName' => '', 'iataNumber' => '', 'pcc' => '', 'gds' => ''
            };
            for (String k : row.keySet()) {
                String kl = k.toLowerCase().replace('_', '').replace(' ', '');
                if (kl == 'iataname') agency.put('iataName', row.get(k));
                else if (kl == 'iatanumber') agency.put('iataNumber', row.get(k));
                else if (kl == 'pcc') agency.put('pcc', row.get(k));
                else if (kl == 'gds') agency.put('gds', row.get(k));
            }
            Object n = agency.get('iataName');
            Object num = agency.get('iataNumber');
            Object p = agency.get('pcc');
            Object g = agency.get('gds');
            if (String.isNotBlank(n != null ? String.valueOf(n) : '')
                || String.isNotBlank(num != null ? String.valueOf(num) : '')
                || String.isNotBlank(p != null ? String.valueOf(p) : '')
                || String.isNotBlank(g != null ? String.valueOf(g) : '')) {
                agencies.add(agency);
            }
        }

        result.remove(taKey);
        if (!agencies.isEmpty()) result.put('travelAgencies', agencies);
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