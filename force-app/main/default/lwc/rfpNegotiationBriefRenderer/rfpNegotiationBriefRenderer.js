import { LightningElement, api } from 'lwc';

const __APEX_ENVELOPE_FIELD = "rfpNegotiationBriefJSON";
function __peelValueWrapper(parsed) {
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
    var __keys = Object.keys(parsed);
    if (__keys.length === 1 && __keys[0] === 'value' && parsed.value && typeof parsed.value === 'object') {
      return parsed.value;
    }
  }
  return parsed;
}
function __unwrapApexEnvelope(raw) {
  if (raw == null) return raw;
  if (typeof raw !== 'object') return raw;
  if (!(__APEX_ENVELOPE_FIELD in raw)) return __peelValueWrapper(raw);
  var __field = raw[__APEX_ENVELOPE_FIELD];
  if (typeof __field === 'string' && __field.trim()) {
    try { return __peelValueWrapper(JSON.parse(__field)); }
    catch (_err) { return null; }
  }
  return null;
}

const BUILDER_FALLBACK_JSON = "{\"header\":{\"companyName\":\"Pinnacle Aviation Services\",\"nfrTarget\":\"$118K\",\"qualifyingTier\":\"$100K\\u2013$299,999\",\"requestedEconomy\":\"11%\",\"requestedBusiness\":\"17%\"},\"assessment\":{\"anyExceeds\":true,\"comparisons\":[{\"label\":\"Economy Lower (T-K)\",\"requested\":\"11%\",\"matrixMax\":\"7.00%\",\"exceeds\":true},{\"label\":\"C Class (Business)\",\"requested\":\"17%\",\"matrixMax\":\"14.00%\",\"exceeds\":true}]},\"discountRows\":[{\"rowNumber\":1,\"ecoLower\":\"4.00%\",\"ecoHigher\":\"5.00%\",\"dClass\":\"9.00%\",\"jClass\":\"10.00%\",\"cClass\":\"11.00%\",\"softOptions\":4,\"routing\":\"Requesting Station Only\"},{\"rowNumber\":2,\"ecoLower\":\"5.00%\",\"ecoHigher\":\"6.00%\",\"dClass\":\"10.00%\",\"jClass\":\"11.00%\",\"cClass\":\"12.00%\",\"softOptions\":3,\"routing\":\"Requesting Station Only\"},{\"rowNumber\":3,\"ecoLower\":\"6.00%\",\"ecoHigher\":\"7.00%\",\"dClass\":\"11.00%\",\"jClass\":\"12.00%\",\"cClass\":\"13.00%\",\"softOptions\":2,\"routing\":\"Requesting Station Only\"},{\"rowNumber\":4,\"ecoLower\":\"7.00%\",\"ecoHigher\":\"8.00%\",\"dClass\":\"12.00%\",\"jClass\":\"13.00%\",\"cClass\":\"14.00%\",\"softOptions\":1,\"routing\":\"Requesting Station Only\"}],\"softBenefits\":{\"freeTickets\":2,\"freeDateChanges\":1,\"baggageUpliftKg\":5,\"upgrades\":2,\"loungeAtOrigin\":true},\"rule2Note\":\"Rule 2 direct-booking uplift is pending ET clarification (Q4, Q5, Q9). Will be applied in Stream B once answers are received.\"}";

let __builderFallbackParsed;
function __getBuilderFallback() {
  if (__builderFallbackParsed !== undefined) return __builderFallbackParsed;
  if (BUILDER_FALLBACK_JSON && BUILDER_FALLBACK_JSON !== '__BUILDER_FALLBACK_PAYLOAD__') {
    try { __builderFallbackParsed = JSON.parse(BUILDER_FALLBACK_JSON); }
    catch (_err) { __builderFallbackParsed = null; }
  } else {
    __builderFallbackParsed = null;
  }
  return __builderFallbackParsed;
}

export default class RfpNegotiationBriefRenderer extends LightningElement {
    _value;
    @api
    get value() { return this._value != null ? this._value : __getBuilderFallback(); }
    set value(v) { this._value = __unwrapApexEnvelope(v); }

    get hasData() { return !!(this.value && this.value.header); }
    get header() { return (this.value && this.value.header) ? this.value.header : {}; }
    get rule2Note() { return (this.value && this.value.rule2Note) ? this.value.rule2Note : ''; }
    get softBenefits() { return (this.value && this.value.softBenefits) ? this.value.softBenefits : {}; }

    get showFreeTickets()    { return this.softBenefits.freeTickets    > 0; }
    get showFreeDateChanges(){ return this.softBenefits.freeDateChanges > 0; }
    get showBaggage()        { return this.softBenefits.baggageUpliftKg > 0; }
    get showUpgrades()       { return this.softBenefits.upgrades        > 0; }
    get showLounge()         { return this.softBenefits.loungeAtOrigin === true; }

    get hasSoftBenefits() {
        return this.showFreeTickets || this.showFreeDateChanges || this.showBaggage || this.showUpgrades || this.showLounge;
    }
    get loungeAtOriginText() {
        return (this.value && this.value.softBenefits && this.value.softBenefits.loungeAtOrigin) ? 'Yes' : 'No';
    }

    get discountRowsWithLabel() {
        const rows = (this.value && this.value.discountRows) ? this.value.discountRows : [];
        return rows.map(r => ({
            ...r,
            softOptionsLabel: r.softOptions + ' benefit option' + (r.softOptions !== 1 ? 's' : ''),
            softOptionsPillClass: r.softOptions >= 4 ? 'status-pill high-options' :
                                  r.softOptions >= 2 ? 'status-pill mid-options' : 'status-pill low-options',
            isDefaultRow: r.rowNumber === 1,
            rowClass: r.rowNumber === 1 ? 'review-item review-item-approved' : 'review-item review-item-escalated',
            approvalLabel: r.rowNumber === 1 ? '✓ Pre-approved' : '⚠ Approval Required',
            approvalLabelClass: r.rowNumber === 1 ? 'approval-pill approval-approved' : 'approval-pill approval-escalated'
        }));
    }

    get hasAssessment() {
        return !!(this.value && this.value.assessment && this.value.assessment.comparisons && this.value.assessment.comparisons.length > 0);
    }

    get assessmentCalloutClass() {
        const a = this.value && this.value.assessment;
        const warn = a && (a.anyExceeds || a.requiresEscalation);
        return warn ? 'assessment-callout assessment-callout-warning' : 'assessment-callout assessment-callout-ok';
    }

    get assessmentSummary() {
        const a = this.value && this.value.assessment;
        if (!a || !a.comparisons || a.comparisons.length === 0) return '';

        const lines = a.comparisons.map(c => {
            const maxRow = c.maxRowNumber;
            const rowReq = c.rowRequired;
            if (c.exceeds) {
                return c.label + ' at ' + c.requested + ' exceeds the highest rate available in this tier (' + c.matrixMax + ' at Discount Offer ' + maxRow + '). This rate cannot be offered under standard terms — the prospect will need to reduce their request.';
            }
            if (rowReq != null && rowReq === maxRow) {
                return c.label + ' at ' + c.requested + ' is at the Discount Offer ' + maxRow + ' maximum (' + c.matrixMax + '). This is the highest escalation level available — full manager approval will be required.';
            }
            if (rowReq != null && rowReq > 1) {
                return c.label + ' at ' + c.requested + ' falls within Discount Offer ' + rowReq + ' (' + c.matrixMax + ' available at Offer ' + maxRow + '). Manager approval required for Offer ' + rowReq + '+.';
            }
            return c.label + ' at ' + c.requested + ' is within the pre-approved Discount Offer 1 rate (max ' + c.matrixMax + '). No escalation needed.';
        });

        return lines.join(' ');
    }
}