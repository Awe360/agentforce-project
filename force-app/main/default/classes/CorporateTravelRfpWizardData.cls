@JsonAccess(serializable='always' deserializable='always')
global with sharing class CorporateTravelRfpWizardData {

    @AuraEnabled
    global String wizardJSON;

    global CorporateTravelRfpWizardData(String wizardJSON) {
        this.wizardJSON = wizardJSON;
    }

    global CorporateTravelRfpWizardData() {
        this.wizardJSON = '';
    }
}