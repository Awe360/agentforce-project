@IsTest
private class LicenceValidationParserTest {

    @IsTest
    static void testHappyPath() {
        String json = '{'
            + '"confidenceLevel":"High",'
            + '"officialMarkersObserved":true,'
            + '"sealCharacteristics":"Physical",'
            + '"statedCapital":5000000,'
            + '"capitalCurrency":"ETB",'
            + '"registeredEntityName":"Acme Global Logistics PLC",'
            + '"companyNameMatch":"MATCH",'
            + '"analystNotes":"Physical stamp observed.",'
            + '"renewalOrExpiryDate":"31 December 2027",'
            + '"dateType":"ExpiryDate",'
            + '"issuingCountry":"Ethiopia"'
            + '}';

        LicenceValidationParser.Request req = new LicenceValidationParser.Request();
        req.responseJson = json;

        List<LicenceValidationParser.Result> results =
            LicenceValidationParser.parse(new List<LicenceValidationParser.Request>{ req });

        System.assertEquals(1, results.size());
        LicenceValidationParser.Result r = results[0];
        System.assertEquals('High', r.confidenceLevel);
        System.assertEquals(true, r.officialMarkersObserved);
        System.assertEquals('Physical', r.sealCharacteristics);
        System.assertEquals(5000000, r.statedCapital);
        System.assertEquals('ETB', r.capitalCurrency);
        System.assertEquals('MATCH', r.companyNameMatch);
        System.assertEquals('Ethiopia', r.issuingCountry);
        System.assertEquals(null, r.parseError);
    }

    @IsTest
    static void testMarkdownStripAndNullCapital() {
        String json = '```json\n'
            + '{"confidenceLevel":"Medium","officialMarkersObserved":false,'
            + '"sealCharacteristics":"Digital","statedCapital":null,'
            + '"capitalCurrency":null,"registeredEntityName":"Test Co",'
            + '"companyNameMatch":"MATCH","analystNotes":"Digital seal.",'
            + '"renewalOrExpiryDate":null,"dateType":"Unknown","issuingCountry":"UK"}'
            + '\n```';

        LicenceValidationParser.Request req = new LicenceValidationParser.Request();
        req.responseJson = json;
        List<LicenceValidationParser.Result> results =
            LicenceValidationParser.parse(new List<LicenceValidationParser.Request>{ req });

        System.assertEquals('Medium', results[0].confidenceLevel);
        System.assertEquals(null, results[0].statedCapital);
        System.assertEquals(null, results[0].parseError);
    }

    @IsTest
    static void testMalformedJson() {
        LicenceValidationParser.Request req = new LicenceValidationParser.Request();
        req.responseJson = 'not valid json';
        List<LicenceValidationParser.Result> results =
            LicenceValidationParser.parse(new List<LicenceValidationParser.Request>{ req });

        System.assertNotEquals(null, results[0].parseError);
    }
}