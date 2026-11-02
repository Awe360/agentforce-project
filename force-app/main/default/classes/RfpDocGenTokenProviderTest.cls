@IsTest
private class RfpDocGenTokenProviderTest {

    @IsTest
    static void testTransformTokenData_passesThrough() {
        RfpDocGenTokenProvider provider = new RfpDocGenTokenProvider();
        Map<String, Object> inputMap = new Map<String, Object>{
            'TokenData' => '{"CompanyName":"Acme","CorporateId":"ETA001"}'
        };
        Map<String, Object> outMap = new Map<String, Object>();

        Test.startTest();
        Boolean result = provider.invokeMethod('transformTokenData', inputMap, outMap);
        Test.stopTest();

        System.assertEquals(true, result, 'transformTokenData should return true');
        System.assertEquals(inputMap.get('TokenData'), outMap.get('TokenData'),
            'TokenData should be passed through unchanged');
    }

    @IsTest
    static void testTransformTokenData_nullTokenData() {
        RfpDocGenTokenProvider provider = new RfpDocGenTokenProvider();
        Map<String, Object> inputMap = new Map<String, Object>();
        Map<String, Object> outMap = new Map<String, Object>();

        Test.startTest();
        Boolean result = provider.invokeMethod('transformTokenData', inputMap, outMap);
        Test.stopTest();

        System.assertEquals(true, result, 'Should return true even with null TokenData');
        System.assertEquals(false, outMap.containsKey('TokenData'),
            'outMap should not have TokenData key when input is null');
    }

    @IsTest
    static void testUnknownMethodReturnsFalse() {
        RfpDocGenTokenProvider provider = new RfpDocGenTokenProvider();
        Map<String, Object> inputMap = new Map<String, Object>();
        Map<String, Object> outMap = new Map<String, Object>();

        Test.startTest();
        Boolean result = provider.invokeMethod('unknownMethod', inputMap, outMap);
        Test.stopTest();

        System.assertEquals(false, result, 'Unknown method should return false');
    }
}