import { LightningElement, api } from 'lwc';

const __APEX_ENVELOPE_FIELD = "contractEmailDraftJSON";

function __peelValueWrapper(parsed) {
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const keys = Object.keys(parsed);
        if (keys.length === 1 && keys[0] === 'value' && parsed.value && typeof parsed.value === 'object') {
            return parsed.value;
        }
    }
    return parsed;
}

function __unwrapApexEnvelope(raw) {
    if (raw == null) return raw;
    if (typeof raw !== 'object') return raw;
    if (!(__APEX_ENVELOPE_FIELD in raw)) return __peelValueWrapper(raw);
    const field = raw[__APEX_ENVELOPE_FIELD];
    if (typeof field === 'string' && field.trim()) {
        try { return __peelValueWrapper(JSON.parse(field)); }
        catch (_e) { return null; }
    }
    return null;
}

const BUILDER_FALLBACK_JSON = '{"subject":"Ethiopian Airlines Corporate Agreement — Nordic Cargo Solutions Ltd","toEmail":"contact@nordiccargo.com","toName":"Mrs. Fatima Al-Hussein","body":"Dear Mrs. Al-Hussein,\\n\\nThank you for your continued partnership with Ethiopian Airlines. Please find attached the corporate rate agreement reflecting the approved discount terms for Nordic Cargo Solutions Ltd.\\n\\nShould you have any questions regarding the terms or require any clarification, please do not hesitate to contact us.\\n\\nWe look forward to a successful partnership.\\n\\nBest regards,\\nEthiopian Airlines Global Corporate Sales"}';

let _fallback;
function getBuilderFallback() {
    if (_fallback !== undefined) return _fallback;
    try { _fallback = JSON.parse(BUILDER_FALLBACK_JSON); }
    catch (_e) { _fallback = null; }
    return _fallback;
}

export default class ContractEmailDraftCard extends LightningElement {
    _value;

    @api
    get value() { return this._value != null ? this._value : getBuilderFallback(); }
    set value(v) { this._value = __unwrapApexEnvelope(v); }

    get hasData()  { return !!(this.value && (this.value.subject || this.value.body)); }
    get subject()  { return this.value ? (this.value.subject || '') : ''; }

    get toLine() {
        if (!this.value) return '';
        const name  = this.value.toName  || '';
        const email = this.value.toEmail || '';
        if (name && email) return name + ' — ' + email;
        return name || email;
    }

    get bodyParagraphs() {
        const raw = this.value ? (this.value.body || '') : '';
        return raw
            .split(/\n+/)
            .map(l => l.trim())
            .filter(l => l.length > 0)
            .map((text, i) => ({ id: i, text }));
    }
}