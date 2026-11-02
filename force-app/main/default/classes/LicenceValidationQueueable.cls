public without sharing class LicenceValidationQueueable implements Queueable, Database.AllowsCallouts {

    private List<String> rfpIds;

    public LicenceValidationQueueable(List<String> rfpIds) {
        this.rfpIds = rfpIds;
    }

    public void execute(QueueableContext ctx) {
        for (String rfpId : rfpIds) {
            Map<String, Object> inputs = new Map<String, Object>{ 'rfpId' => rfpId };
            Flow.Interview interview = Flow.Interview.createInterview('Licence_Validation_Worker', inputs);
            interview.start();
        }
    }
}