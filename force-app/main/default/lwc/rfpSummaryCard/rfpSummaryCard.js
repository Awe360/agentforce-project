import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import COMPANY_NAME      from '@salesforce/schema/Corporate_Travel_RFP__c.Company_Name__c';
import STATUS            from '@salesforce/schema/Corporate_Travel_RFP__c.Status__c';
import REQUEST_TYPE      from '@salesforce/schema/Corporate_Travel_RFP__c.Request_Type__c';
import SUBMISSION_DATE   from '@salesforce/schema/Corporate_Travel_RFP__c.Submission_Date__c';
import BUDGET            from '@salesforce/schema/Corporate_Travel_RFP__c.Annual_Travel_Budget_USD__c';
import NFR_TARGET        from '@salesforce/schema/Corporate_Travel_RFP__c.Annual_NFR_Target_USD__c';
import STAFF             from '@salesforce/schema/Corporate_Travel_RFP__c.Number_of_Travelling_Staff__c';
import ECONOMY_DISC      from '@salesforce/schema/Corporate_Travel_RFP__c.Economy_Discount_Pct__c';
import BUSINESS_DISC     from '@salesforce/schema/Corporate_Travel_RFP__c.Business_Discount_Pct__c';
import LIC_CONFIDENCE    from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Confidence_Level__c';
import LIC_NAME_MATCH    from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Company_Name_Match__c';
import LIC_EXPIRY        from '@salesforce/schema/Corporate_Travel_RFP__c.Licence_Renewal_Expiry_Date__c';

const FIELDS = [
    COMPANY_NAME, STATUS, REQUEST_TYPE, SUBMISSION_DATE,
    BUDGET, NFR_TARGET, STAFF, ECONOMY_DISC, BUSINESS_DISC,
    LIC_CONFIDENCE, LIC_NAME_MATCH, LIC_EXPIRY
];

export default class RfpSummaryCard extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    record;

    // ── Field accessors ──────────────────────────────────────
    get companyName()             { return getFieldValue(this.record?.data, COMPANY_NAME)   || 'Loading…'; }
    get status()                  { return getFieldValue(this.record?.data, STATUS)          || ''; }
    get requestType()             { return getFieldValue(this.record?.data, REQUEST_TYPE)    || ''; }
    get annualTravelBudget()      { return getFieldValue(this.record?.data, BUDGET)          || 0; }
    get annualNfrTarget()         { return getFieldValue(this.record?.data, NFR_TARGET)      || 0; }
    get travellingStaffRaw()      { return getFieldValue(this.record?.data, STAFF)           || null; }
    get economyDiscountRaw()      { return getFieldValue(this.record?.data, ECONOMY_DISC)    || null; }
    get businessDiscountRaw()     { return getFieldValue(this.record?.data, BUSINESS_DISC)   || null; }
    get licenceConfidenceLevel()  { return getFieldValue(this.record?.data, LIC_CONFIDENCE)  || ''; }
    get licenceCompanyNameMatch() { return getFieldValue(this.record?.data, LIC_NAME_MATCH)  || ''; }
    get licenceRenewalExpiryDate(){ return getFieldValue(this.record?.data, LIC_EXPIRY)      || null; }

    // ── Formatted display values ─────────────────────────────
    get submissionDate() {
        const raw = getFieldValue(this.record?.data, SUBMISSION_DATE);
        if (!raw) return '—';
        return new Date(raw).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    }

    get formattedBudget() {
        const b = this.annualTravelBudget;
        if (!b) return '—';
        if (b >= 1000000) return `$${(b / 1000000).toFixed(1)}M`;
        if (b >= 1000)    return `$${Math.round(b / 1000)}K`;
        return `$${b}`;
    }

    get formattedNfrTarget() {
        const n = this.annualNfrTarget;
        if (!n) return '—';
        if (n >= 1000000) return `$${(n / 1000000).toFixed(1)}M`;
        if (n >= 1000)    return `$${Math.round(n / 1000)}K`;
        return `$${n}`;
    }

    get travellingStaff() {
        return this.travellingStaffRaw != null ? String(this.travellingStaffRaw) : '—';
    }

    get economyDiscount() {
        if (this.economyDiscountRaw == null) return '—';
        const match = String(this.economyDiscountRaw).match(/(\d+(?:\.\d+)?)/);
        return match ? `${match[1]}%` : String(this.economyDiscountRaw);
    }

    get businessDiscount() {
        if (this.businessDiscountRaw == null) return '—';
        const match = String(this.businessDiscountRaw).match(/(\d+(?:\.\d+)?)/);
        return match ? `${match[1]}%` : String(this.businessDiscountRaw);
    }

    // ── Request type badge ───────────────────────────────────
    get statusLabel() {
        return this.requestType ? `Request Type: ${this.requestType}` : 'Request Type: —';
    }

    get statusBadgeClass() {
        return 'badge badge-status-new';
    }

    // ── Licence confidence badge ─────────────────────────────
    get licenceHealthLabel() {
        const conf = (this.licenceConfidenceLevel || '').toLowerCase();
        if (!conf) return 'Licence Confidence: Unknown';
        const label = this.licenceConfidenceLevel.charAt(0).toUpperCase() + this.licenceConfidenceLevel.slice(1).toLowerCase();
        return `Licence Confidence: ${label}`;
    }

    get licenceBadgeClass() {
        const conf = (this.licenceConfidenceLevel || '').toLowerCase();
        if (conf === 'high')   return 'badge badge-confidence-high';
        if (conf === 'medium') return 'badge badge-confidence-medium';
        if (conf === 'low')    return 'badge badge-confidence-low';
        return 'badge badge-licence-unknown';
    }

    // ── Expiry helper (used by score only) ──────────────────
    get monthsToExpiry() {
        if (!this.licenceRenewalExpiryDate) return null;
        const expiry = new Date(this.licenceRenewalExpiryDate);
        return (expiry - new Date()) / (1000 * 60 * 60 * 24 * 30.44);
    }

    // ── Value score ──────────────────────────────────────────
    get valueScore() {
        let score = 0;

        // NFR tier: 0–40 pts (uses ET-specific spend, not total budget)
        const nfr = this.annualNfrTarget;
        if (nfr >= 1000000)     score += 40;
        else if (nfr >= 500000) score += 32;
        else if (nfr >= 200000) score += 22;
        else if (nfr >= 50000)  score += 12;

        // Licence confidence: 0–25 pts
        const conf = (this.licenceConfidenceLevel || '').toLowerCase();
        if (conf === 'high')        score += 25;
        else if (conf === 'medium') score += 16;
        else if (conf === 'low')    score += 6;

        // Name match: 0–20 pts
        const match = (this.licenceCompanyNameMatch || '').toLowerCase();
        if (match === 'match')      score += 20;
        else if (match === 'partial') score += 10;

        // Licence validity: 0–15 pts
        const months = this.monthsToExpiry;
        if (months !== null) {
            if (months > 12)      score += 15;
            else if (months > 6)  score += 10;
            else if (months > 0)  score += 5;
        }

        return Math.min(score, 100);
    }

    get scoreRating() {
        const s = this.valueScore;
        if (s >= 80) return 'High Value';
        if (s >= 60) return 'Good Prospect';
        if (s >= 40) return 'Moderate';
        return 'Needs Review';
    }

    get scoreRatingClass() {
        const s = this.valueScore;
        if (s >= 80) return 'score-rating-high';
        if (s >= 60) return 'score-rating-good';
        if (s >= 40) return 'score-rating-mod';
        return 'score-rating-review';
    }

    get scoreBarStyle() {
        return `width: ${this.valueScore}%`;
    }

    get scoreBreakdown() {
        const parts = [];
        const conf  = this.licenceConfidenceLevel;
        const match = this.licenceCompanyNameMatch;
        if (conf)   parts.push(`Licence: ${conf}`);
        if (match)  parts.push(`Name: ${match}`);
        const months = this.monthsToExpiry;
        if (months !== null && months > 0) {
            parts.push(`Expires: ${Math.round(months)}mo`);
        }
        return parts.join('  ·  ');
    }
}