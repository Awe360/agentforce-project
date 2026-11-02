@IsTest
private class RfpUploadCltDataTest {

    @IsTest
    static void testDefaultConstructor() {
        RfpUploadCltData data = new RfpUploadCltData();
        System.assertEquals('', data.rfpUploadCltJSON, 'Default constructor should set empty string');
    }

    @IsTest
    static void testParameterizedConstructor() {
        String json = '{"title":"Test"}';
        RfpUploadCltData data = new RfpUploadCltData(json);
        System.assertEquals(json, data.rfpUploadCltJSON, 'Constructor should store provided JSON');
    }
}