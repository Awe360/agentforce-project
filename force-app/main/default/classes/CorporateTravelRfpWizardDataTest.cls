@isTest
private class CorporateTravelRfpWizardDataTest {

    @isTest
    static void testDefaultConstructor() {
        CorporateTravelRfpWizardData data = new CorporateTravelRfpWizardData();
        Assert.areEqual('', data.wizardJSON, 'Default ctor must set wizardJSON to empty string');
    }

    @isTest
    static void testJsonConstructor() {
        String json = '{"title":"Test Wizard"}';
        CorporateTravelRfpWizardData data = new CorporateTravelRfpWizardData(json);
        Assert.areEqual(json, data.wizardJSON, 'JSON ctor must store the string verbatim');
    }
}