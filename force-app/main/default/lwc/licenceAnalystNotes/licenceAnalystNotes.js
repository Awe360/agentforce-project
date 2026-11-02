import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import ANALYST_NOTES    from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Analyst_Notes__c';
import CONFIDENCE_LEVEL from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Confidence_Level__c';
import REGISTERED_NAME  from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Registered_Name__c';
import NAME_MATCH       from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Company_Name_Match__c';
import EXPIRY_DATE      from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Renewal_Expiry_Date__c';

const FIELDS = [ANALYST_NOTES, CONFIDENCE_LEVEL, REGISTERED_NAME, NAME_MATCH, EXPIRY_DATE];

const CONFIDENCE_CLASS = { High: 'la-badge la-badge-high', Medium: 'la-badge la-badge-medium', Low: 'la-badge la-badge-low' };
const NAME_MATCH_CLASS  = { Match: 'la-badge la-badge-high', Partial: 'la-badge la-badge-medium', Mismatch: 'la-badge la-badge-low' };

export default class LicenceAnalystNotes extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    record;

    get isLoading()       { return !this.record.data && !this.record.error; }
    get analystNotes()    { return getFieldValue(this.record?.data, ANALYST_NOTES); }
    get confidenceLevel() { return getFieldValue(this.record?.data, CONFIDENCE_LEVEL); }
    get registeredName()  { return getFieldValue(this.record?.data, REGISTERED_NAME) || '—'; }
    get nameMatch()       { return getFieldValue(this.record?.data, NAME_MATCH); }
    get expiryDate()      { return getFieldValue(this.record?.data, EXPIRY_DATE) || '—'; }
    get hasData()         { return !!this.analystNotes; }

    get confidenceBadgeClass() { return CONFIDENCE_CLASS[this.confidenceLevel] || 'la-badge'; }
    get nameMatchBadgeClass()  { return NAME_MATCH_CLASS[this.nameMatch]  || 'la-badge'; }

    get formattedNotes() {
        const raw = this.analystNotes;
        if (!raw) return [];
        return raw.split('\n').map((line, idx) => {
            if (!line.trim()) {
                return { id: String(idx), isLabelled: false, isEmpty: true, text: '' };
            }
            const match = line.match(/^([A-Za-z][^:]{0,30}):\s*(.*)$/);
            if (match) {
                return { id: String(idx), isLabelled: true, isEmpty: false, label: match[1], value: match[2] };
            }
            return { id: String(idx), isLabelled: false, isEmpty: false, text: line };
        });
    }
}