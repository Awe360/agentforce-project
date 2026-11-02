@IsTest
private class RfpNegotiationBriefDataTest {

    @IsTest
    static void testDefaultConstructor() {
        RfpNegotiationBriefData d = new RfpNegotiationBriefData();
        System.assertEquals('', d.rfpNegotiationBriefJSON,
            'Default constructor should set JSON to empty string');
    }

    @IsTest
    static void testJsonConstructor() {
        String payload = '{"clientName":"Acme","nfr":500000}';
        RfpNegotiationBriefData d = new RfpNegotiationBriefData(payload);
        System.assertEquals(payload, d.rfpNegotiationBriefJSON,
            'Constructor should store the provided JSON string');
    }

    @IsTest
    static void testJsonConstructorWithNull() {
        RfpNegotiationBriefData d = new RfpNegotiationBriefData(null);
        System.assertEquals(null, d.rfpNegotiationBriefJSON);
    }

    @IsTest
    static void testMutability() {
        RfpNegotiationBriefData d = new RfpNegotiationBriefData();
        d.rfpNegotiationBriefJSON = '{"updated":true}';
        System.assertEquals('{"updated":true}', d.rfpNegotiationBriefJSON);
    }
}