@JsonAccess(serializable='always' deserializable='always')
global class RfpNegotiationBriefData {

    @AuraEnabled
    global String rfpNegotiationBriefJSON;

    global RfpNegotiationBriefData(String json) {
        this.rfpNegotiationBriefJSON = json;
    }

    global RfpNegotiationBriefData() {
        this.rfpNegotiationBriefJSON = '';
    }
}