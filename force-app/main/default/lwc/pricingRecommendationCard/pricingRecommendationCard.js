import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getOfferData from '@salesforce/apex/GetRfpOfferData.getOfferData';

export default class PricingRecommendationCard extends LightningElement {
    @api recordId;

    _wiredResult;

    @wire(getOfferData, { recordId: '$recordId' })
    wiredOfferData(result) {
        this._wiredResult = result;
    }

    // ── Data accessors ───────────────────────────────────────────
    get offerData()   { return this._wiredResult?.data  || {}; }
    get isLoading()   { return !this._wiredResult; }
    get hasError()    { return !!this._wiredResult?.error; }
    get errorMessage(){ return this._wiredResult?.error?.body?.message || 'Unable to load pricing data.'; }
    get showEmpty()   { return this._wiredResult?.data && !this._wiredResult.data.offerSet; }
    get showOffer()   { return this._wiredResult?.data?.offerSet === true; }

    // ── Row badge ────────────────────────────────────────────────
    get rowBadgeLabel() {
        const row = this.offerData.matrixRow;
        if (!row) return '';
        return row === 1 ? 'Discount Offer 1 — Default' : `Discount Offer ${row} — Escalated`;
    }

    get rowBadgeClass() {
        return this.offerData.isDefaultRow ? 'badge badge-default' : 'badge badge-escalated';
    }

    // ── Approval badge ───────────────────────────────────────────
    get approvalBadgeClass() {
        const s = (this.offerData.approvalStatus || '').toLowerCase();
        if (s === 'approved') return 'badge badge-approved';
        if (s === 'rejected') return 'badge badge-rejected';
        return 'badge badge-pending';
    }

    // ── Approval banner ──────────────────────────────────────────
    get showApprovalBanner() {
        return this.offerData.escalationRequired || !!this.offerData.approvalStatus;
    }

    get approvalBannerClass() {
        const s = (this.offerData.approvalStatus || '').toLowerCase();
        if (s === 'approved') return 'approval-banner banner-approved';
        if (s === 'rejected') return 'approval-banner banner-rejected';
        return 'approval-banner banner-pending';
    }

    get bannerTitle() {
        const s = (this.offerData.approvalStatus || '').toLowerCase();
        if (s === 'approved') return 'Offer Approved';
        if (s === 'rejected') return 'Offer Rejected — Requires Revision';
        return 'Approval Pending';
    }

    get bannerIcon() {
        const s = (this.offerData.approvalStatus || '').toLowerCase();
        if (s === 'approved') return '✓';
        if (s === 'rejected') return '✕';
        return '⏳';
    }

    // ── Offer tier pill ──────────────────────────────────────────
    get _approvalStatus() {
        return (this.offerData.approvalStatus || '').toLowerCase();
    }

    get _tierApproved() {
        return this.offerData.isDefaultRow || this._approvalStatus === 'approved';
    }

    get _tierRejected() {
        return !this.offerData.isDefaultRow && this._approvalStatus === 'rejected';
    }

    get offerTierClass() {
        if (this._tierApproved) return 'offer-tier offer-tier-approved';
        if (this._tierRejected) return 'offer-tier offer-tier-rejected';
        return 'offer-tier offer-tier-escalated';
    }

    get offerTierLabelClass() {
        if (this._tierApproved) return 'tier-label tier-label-approved';
        if (this._tierRejected) return 'tier-label tier-label-rejected';
        return 'tier-label tier-label-escalated';
    }

    get offerTierLabel() {
        if (this.offerData.isDefaultRow) return 'Pre-approved Offer';
        if (this._approvalStatus === 'approved') return 'Offer Approved';
        if (this._approvalStatus === 'rejected') return 'Offer Rejected';
        return 'Additional Approval Required';
    }

    get offerTierIcon() {
        if (this._tierApproved) return '✓';
        if (this._tierRejected) return '✕';
        return '⚠';
    }

    // ── Rate display helpers ─────────────────────────────────────
    _pct(val) {
        return val != null ? `${Number(val).toFixed(2)}%` : '—';
    }

    get economyLowerDisplay()  { return this._pct(this.offerData.economyLowerPct); }
    get economyHigherDisplay() { return this._pct(this.offerData.economyHigherPct); }
    get dClassDisplay()        { return this._pct(this.offerData.dClassPct); }
    get jClassDisplay()        { return this._pct(this.offerData.jClassPct); }
    get cClassDisplay()        { return this._pct(this.offerData.cClassPct); }
    get rule2PctDisplay()      { return this._pct(this.offerData.rule2Pct); }

    get softOptionsDisplay() {
        const n = this.offerData.softOptionsCount;
        return n != null ? `${n} option${n !== 1 ? 's' : ''}` : '—';
    }

    // ── Benefits ─────────────────────────────────────────────────
    get hasBenefits() {
        return (this.offerData.softBenefits || []).length > 0;
    }

    get computedBenefits() {
        return (this.offerData.softBenefits || []).map(b => ({
            ...b,
            itemClass : b.active ? 'benefit-item benefit-active' : 'benefit-item benefit-inactive',
            iconClass : b.active ? 'benefit-icon icon-active' : 'benefit-icon icon-inactive',
            icon      : b.active ? '✓' : '○'
        }));
    }

    // ── Refresh ──────────────────────────────────────────────────
    handleRefresh() {
        refreshApex(this._wiredResult);
    }
}