import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import LICENCE_DOC_ID from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Document_Id__c';

const FIELDS = [LICENCE_DOC_ID];

export default class BusinessLicenceViewer extends NavigationMixin(LightningElement) {
    @api recordId;

    _frameLoaded = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    record;

    get isLoading() {
        return !this.record.data && !this.record.error;
    }

    get licenceDocId() {
        return getFieldValue(this.record?.data, LICENCE_DOC_ID);
    }

    get hasDocument() {
        return !!this.licenceDocId;
    }

    get documentUrl() {
        return `/apex/BusinessLicencePreview?docId=${this.licenceDocId}`;
    }

    handleFrameLoad() {
        this._frameLoaded = true;
    }

    handleOpenPreview() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: this.licenceDocId }
        });
    }
}