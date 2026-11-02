@JsonAccess(serializable='always' deserializable='always')
global with sharing class RfpUploadCltData {

    @AuraEnabled
    global String rfpUploadCltJSON;

    global RfpUploadCltData(String rfpUploadCltJSON) {
        this.rfpUploadCltJSON = rfpUploadCltJSON;
    }

    global RfpUploadCltData() {
        this.rfpUploadCltJSON = '';
    }
}