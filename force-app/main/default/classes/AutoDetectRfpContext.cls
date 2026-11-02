public with sharing class AutoDetectRfpContext {

    public class Request {
        @InvocableVariable(label='Placeholder' description='Unused')
        public String placeholder;
    }

    public class Result {
        @InvocableVariable(label='Record ID' description='Most recently viewed Corporate_Travel_RFP__c or Opportunity ID; empty string if none found')
        public String recordId;
    }

    @InvocableMethod(
        label='Auto-Detect RFP Context'
        description='Returns the most recently viewed Corporate Travel RFP or Opportunity ID for the current user.'
        category='Corporate Travel'
    )
    public static List<Result> execute(List<Request> requests) {
        Result res = new Result();

        // Check for RFP first — preferred context
        List<RecentlyViewed> recentRfps = [
            SELECT Id FROM RecentlyViewed
            WHERE Type = 'Corporate_Travel_RFP__c'
            ORDER BY LastViewedDate DESC LIMIT 1
        ];

        if (!recentRfps.isEmpty()) {
            res.recordId = recentRfps[0].Id;
        } else {
            // Fall back to Opportunity — GetRfpWithMatrixData handles the lookup
            List<RecentlyViewed> recentOpps = [
                SELECT Id FROM RecentlyViewed
                WHERE Type = 'Opportunity'
                ORDER BY LastViewedDate DESC LIMIT 1
            ];
            res.recordId = recentOpps.isEmpty() ? '' : recentOpps[0].Id;
        }

        return new List<Result>{ res };
    }
}