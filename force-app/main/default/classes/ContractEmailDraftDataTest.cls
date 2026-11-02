@IsTest
private class ContractEmailDraftDataTest {

    @IsTest
    static void testDefaultConstructor() {
        ContractEmailDraftData d = new ContractEmailDraftData();
        System.assertEquals('', d.contractEmailDraftJSON,
            'Default constructor should set JSON to empty string');
    }

    @IsTest
    static void testJsonConstructor() {
        String payload = '{"subject":"Test","body":"Hello"}';
        ContractEmailDraftData d = new ContractEmailDraftData(payload);
        System.assertEquals(payload, d.contractEmailDraftJSON,
            'Constructor should store the provided JSON string');
    }

    @IsTest
    static void testJsonConstructorWithNull() {
        ContractEmailDraftData d = new ContractEmailDraftData(null);
        System.assertEquals(null, d.contractEmailDraftJSON);
    }

    @IsTest
    static void testMutability() {
        ContractEmailDraftData d = new ContractEmailDraftData();
        d.contractEmailDraftJSON = '{"subject":"Updated"}';
        System.assertEquals('{"subject":"Updated"}', d.contractEmailDraftJSON);
    }
}