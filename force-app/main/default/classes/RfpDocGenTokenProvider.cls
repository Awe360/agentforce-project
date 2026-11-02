global class RfpDocGenTokenProvider implements ind_docgen_api.OpenInterface {
    global Boolean invokeMethod(String methodName, Map<String, Object> inputMap, Map<String, Object> outMap) {
        if (methodName == 'transformTokenData') {
            // Pass token data through unchanged — data is built by GenerateContractDraft Apex
            String tokenData = (String) inputMap.get('TokenData');
            if (tokenData != null) {
                outMap.put('TokenData', tokenData);
            }
            return true;
        }
        return false;
    }
}