@IsTest
private class AutoDetectRfpContextTest {

    @IsTest
    static void testExecuteReturnsResult() {
        // RecentlyViewed is framework-populated; in test context it will be empty,
        // so the fallback path runs and returns an empty string.
        AutoDetectRfpContext.Request req = new AutoDetectRfpContext.Request();
        req.placeholder = 'ignored';

        Test.startTest();
        List<AutoDetectRfpContext.Result> results =
            AutoDetectRfpContext.execute(new List<AutoDetectRfpContext.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertNotEquals(null, results[0].recordId,
            'recordId should be non-null (empty string when nothing recently viewed)');
    }

    @IsTest
    static void testExecuteWithNullPlaceholder() {
        AutoDetectRfpContext.Request req = new AutoDetectRfpContext.Request();
        req.placeholder = null;

        Test.startTest();
        List<AutoDetectRfpContext.Result> results =
            AutoDetectRfpContext.execute(new List<AutoDetectRfpContext.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        // recordId is either an ID from RecentlyViewed or empty string; just verify non-null
        System.assertNotEquals(null, results[0].recordId,
            'recordId should be non-null (empty string or an ID from RecentlyViewed)');
    }

    @IsTest
    static void testExecuteMultipleRequests() {
        // The method always returns a single result regardless of input batch size —
        // it resolves one "most recently viewed" record for the current user.
        List<AutoDetectRfpContext.Request> requests = new List<AutoDetectRfpContext.Request>();
        for (Integer i = 0; i < 3; i++) {
            AutoDetectRfpContext.Request req = new AutoDetectRfpContext.Request();
            requests.add(req);
        }

        Test.startTest();
        List<AutoDetectRfpContext.Result> results = AutoDetectRfpContext.execute(requests);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Method always returns one result regardless of batch size');
        System.assertNotEquals(null, results[0].recordId, 'recordId should be non-null');
    }
}