@JsonAccess(serializable='always' deserializable='always')
global with sharing class BusinessLicenceUploadCltData {

    @AuraEnabled
    global String businessLicenceUploadCltJSON;

    global BusinessLicenceUploadCltData(String json) {
        this.businessLicenceUploadCltJSON = json;
    }

    global BusinessLicenceUploadCltData() {
        this.businessLicenceUploadCltJSON = '';
    }
}