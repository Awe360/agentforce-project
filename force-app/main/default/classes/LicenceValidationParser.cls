public without sharing class LicenceValidationParser {

    public class Request {
        @InvocableVariable(label='Prompt Response JSON' required=true)
        public String responseJson;
    }

    public class Result {
        @InvocableVariable(label='Confidence Level')
        public String confidenceLevel;

        @InvocableVariable(label='Official Markers Observed')
        public Boolean officialMarkersObserved;

        @InvocableVariable(label='Seal Characteristics')
        public String sealCharacteristics;

        @InvocableVariable(label='Stated Capital')
        public Decimal statedCapital;

        @InvocableVariable(label='Capital Currency')
        public String capitalCurrency;

        @InvocableVariable(label='Registered Entity Name')
        public String registeredEntityName;

        @InvocableVariable(label='Company Name Match')
        public String companyNameMatch;

        @InvocableVariable(label='Analyst Notes')
        public String analystNotes;

        @InvocableVariable(label='Renewal Or Expiry Date')
        public String renewalOrExpiryDate;

        @InvocableVariable(label='Date Type')
        public String dateType;

        @InvocableVariable(label='Issuing Country')
        public String issuingCountry;

        @InvocableVariable(label='Parse Error')
        public String parseError;
    }

    @InvocableMethod(label='Parse Licence Validation Response' category='Corporate Travel')
    public static List<Result> parse(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(parseOne(req.responseJson));
        }
        return results;
    }

    private static Result parseOne(String rawJson) {
        Result r = new Result();
        try {
            String cleaned = rawJson == null ? '' : rawJson.trim();
            // Strip markdown code fence if present
            if (cleaned.startsWith('```')) {
                Integer nl = cleaned.indexOf('\n');
                if (nl > -1) cleaned = cleaned.substring(nl + 1).trim();
                if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length() - 3).trim();
            }

            Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(cleaned);

            r.confidenceLevel        = str(d, 'confidenceLevel');
            r.officialMarkersObserved = bool(d, 'officialMarkersObserved');
            r.sealCharacteristics    = str(d, 'sealCharacteristics');
            r.capitalCurrency        = str(d, 'capitalCurrency');
            r.registeredEntityName   = str(d, 'registeredEntityName');
            r.companyNameMatch       = str(d, 'companyNameMatch');
            r.analystNotes           = str(d, 'analystNotes');
            r.renewalOrExpiryDate    = str(d, 'renewalOrExpiryDate');
            r.dateType               = str(d, 'dateType');
            r.issuingCountry         = str(d, 'issuingCountry');

            Object capRaw = d.get('statedCapital');
            if (capRaw != null && capRaw != (Object) 'null') {
                try { r.statedCapital = Decimal.valueOf(String.valueOf(capRaw)); } catch (Exception e) {}
            }
        } catch (Exception e) {
            r.parseError = e.getMessage() + ' | input: ' + (rawJson != null ? rawJson.left(300) : 'null');
        }
        return r;
    }

    private static String str(Map<String, Object> d, String key) {
        Object v = d.get(key);
        return (v != null && v != (Object) 'null') ? String.valueOf(v) : null;
    }

    private static Boolean bool(Map<String, Object> d, String key) {
        Object v = d.get(key);
        if (v == null) return false;
        if (v instanceof Boolean) return (Boolean) v;
        return String.valueOf(v).toLowerCase() == 'true';
    }
}