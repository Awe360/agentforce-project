@JsonAccess(serializable='always' deserializable='always')
global class ContractEmailDraftData {

    @AuraEnabled
    global String contractEmailDraftJSON;

    global ContractEmailDraftData(String json) {
        this.contractEmailDraftJSON = json;
    }

    global ContractEmailDraftData() {
        this.contractEmailDraftJSON = '';
    }
}