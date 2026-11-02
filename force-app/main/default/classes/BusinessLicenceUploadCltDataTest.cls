@IsTest
private class BusinessLicenceUploadCltDataTest {

    @IsTest
    static void testDefaultConstructor() {
        BusinessLicenceUploadCltData d = new BusinessLicenceUploadCltData();
        System.assertEquals('', d.businessLicenceUploadCltJSON,
            'Default constructor should set JSON to empty string');
    }

    @IsTest
    static void testJsonConstructor() {
        String payload = '{"key":"value","number":42}';
        BusinessLicenceUploadCltData d = new BusinessLicenceUploadCltData(payload);
        System.assertEquals(payload, d.businessLicenceUploadCltJSON,
            'Constructor should store the provided JSON string');
    }

    @IsTest
    static void testJsonConstructorWithNull() {
        BusinessLicenceUploadCltData d = new BusinessLicenceUploadCltData(null);
        System.assertEquals(null, d.businessLicenceUploadCltJSON,
            'Constructor with null should store null');
    }

    @IsTest
    static void testMutability() {
        BusinessLicenceUploadCltData d = new BusinessLicenceUploadCltData();
        d.businessLicenceUploadCltJSON = '{"updated":true}';
        System.assertEquals('{"updated":true}', d.businessLicenceUploadCltJSON);
    }
}