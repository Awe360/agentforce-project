import { LightningElement, api, track } from 'lwc';
import uploadFileOnly from '@salesforce/apex/RfpUploadController.uploadFileOnly';
import saveRfpFromLwc from '@salesforce/apex/CorporateTravelRfpSave.saveRfpFromLwc';
import uploadDocumentOnly from '@salesforce/apex/RfpUploadController.uploadDocumentOnly';

const ENVELOPE_FIELD = 'wizardJSON';

// Wizard config baked in for Agent Builder preview. The agent always passes
// the same JSON via the Flow Details variable at runtime.
const BUILDER_FALLBACK_JSON = '{"title":"Ethiopian Airlines Corporate Travel RFP","submitButtonLabel":"Submit Application","previousButtonLabel":"Previous","nextButtonLabel":"Next","confirmationTitle":"Application Submitted","confirmationMessage":"Thank you for submitting your Corporate Travel RFP. Our Global Corporate Sales team will be in touch within 2 working days.","steps":[{"title":"Company Profile","fields":[{"name":"companyName","label":"Company Name","type":"text","required":true,"width":"full","placeholder":"e.g., Acme Corporation Ltd"},{"name":"address","label":"Address","type":"text","required":true,"width":"full","placeholder":"Street, City, Country"},{"name":"website","label":"Website","type":"url","required":true,"width":"half","placeholder":"https://www.example.com"},{"name":"primaryLineOfBusiness","label":"Primary Line of Business","type":"text","required":true,"width":"half","placeholder":"e.g., Financial Services"},{"name":"numberOfTravellingStaff","label":"Number of Travelling Staff","type":"number","required":false,"width":"half","placeholder":"e.g., 50"},{"name":"annualTravelBudget","label":"Annual Travel Budget (USD)","type":"number","required":true,"width":"half","placeholder":"e.g., 100000"}]},{"title":"Contact & Request","fields":[{"name":"contactName","label":"Contact Name","type":"text","required":true,"width":"full","placeholder":"Full name"},{"name":"contactEmail","label":"Contact Email","type":"email","required":true,"width":"half","placeholder":"name@company.com"},{"name":"contactPhone","label":"Contact Phone","type":"tel","required":true,"width":"half","placeholder":"+1 (555) 123-4567"},{"name":"requestType","label":"Request Type","type":"select","required":true,"width":"full","placeholder":"Select...","options":[{"label":"New Application","value":"New"},{"label":"Renewal","value":"Renewal"}]},{"name":"corporateId","label":"Corporate ID","type":"text","required":false,"width":"half","placeholder":"Existing corporate ID","showIf":{"field":"requestType","value":"Renewal"}},{"name":"nfrJustification","label":"NFR Justification","type":"text","required":false,"width":"full","placeholder":"Explain if previous NFR was below target","showIf":{"field":"requestType","value":"Renewal"}}]},{"title":"Proposal Details","hasRoutes":true,"fields":[{"name":"annualNfrTarget","label":"Annual NFR Target (USD)","type":"number","required":true,"width":"full","placeholder":"Minimum USD 50,000"},{"name":"economyDiscount","label":"Economy Discount % (incl. RBD restriction if any)","type":"text","required":true,"width":"half","placeholder":""},{"name":"businessDiscount","label":"Business Class Discount % (incl. RBD restriction if any)","type":"text","required":true,"width":"half","placeholder":""},{"name":"additionalBenefits","label":"Additional Benefits Requested","type":"text","required":false,"width":"full","placeholder":""}]},{"title":"Ticket Issuance & Declaration","hasTravelAgencies":true,"fields":[{"name":"ticketIssuanceEtOffice","label":"ET Office","type":"checkbox","required":false,"width":"full","checkboxLabel":"Tickets issued via Ethiopian Airlines ET Office"},{"name":"ticketIssuanceGsaOffice","label":"GSA Office","type":"checkbox","required":false,"width":"full","checkboxLabel":"Tickets issued via GSA Office"},{"name":"ticketIssuanceTravelAgency","label":"Travel Agency","type":"checkbox","required":false,"width":"full","checkboxLabel":"Tickets issued via Travel Agency"},{"name":"requestedBy","label":"Requested By (Name & Position)","type":"text","required":true,"width":"full","placeholder":"e.g., Jane Smith, Head of Travel","afterAgencies":true}]},{"title":"Business Licence","type":"fileupload","description":"Please upload your current Business Licence or Certificate of Incorporation (PDF, DOC or DOCX, max 5 MB).","required":true},{"title":"Review & Submit","fields":[]}]}';

function peelValueWrapper(parsed) {
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const keys = Object.keys(parsed);
        if (keys.length === 1 && keys[0] === 'value' && parsed.value && typeof parsed.value === 'object') {
            return parsed.value;
        }
    }
    return parsed;
}

function unwrapApexEnvelope(raw) {
    if (raw == null || typeof raw !== 'object') return raw;
    if (!(ENVELOPE_FIELD in raw)) return peelValueWrapper(raw);
    const field = raw[ENVELOPE_FIELD];
    if (typeof field === 'string' && field.trim()) {
        try { return peelValueWrapper(JSON.parse(field.replace(/\\'/g, "'"))); } catch (_e) { return null; }
    }
    return null;
}

let _fallbackParsed;
function getBuilderFallback() {
    if (_fallbackParsed !== undefined) return _fallbackParsed;
    try { _fallbackParsed = JSON.parse(BUILDER_FALLBACK_JSON); } catch (_e) { _fallbackParsed = null; }
    return _fallbackParsed;
}

function sendUploadUtterance(message) {
    try {
        if (typeof embeddedservice_configuration !== 'undefined'
                && embeddedservice_configuration?.util?.sendTextMessage) {
            embeddedservice_configuration.util.sendTextMessage(message).catch((err) => {
                console.error('sendUploadUtterance failed:', err);
            });
        } else {
            console.log('sendUploadUtterance (preview):', message);
        }
    } catch (err) {
        console.error('sendUploadUtterance threw:', err);
    }
}

const UPL_IDLE       = 'idle';
const UPL_PROCESSING = 'processing';
const UPL_SUCCESS    = 'success';
const UPL_ERROR      = 'error';

export default class CorporateTravelRfpWizard extends LightningElement {
    _value;

    @api
    get value() {
        return this._value != null ? this._value : getBuilderFallback();
    }
    set value(v) {
        console.log('#### CorporateTravelRfpWizard input:', v);
        const parsed = unwrapApexEnvelope(v);
        const isUploadConfig = parsed && (parsed.mode === 'rfp_upload' || parsed.mode === 'business_licence_upload');
        this._value = (isUploadConfig || (parsed && parsed.steps && parsed.steps.length > 0)) ? parsed : null;
        if (parsed && typeof parsed === 'object') {
            this._prefillValuesJSON = parsed.prefillValuesJSON || null;
            this._rfpDocumentId     = parsed.rfpDocumentId     || null;
        }
    }

    // ── Form wizard state ──────────────────────────────────────────────────────
    @track currentIndex = 0;
    @track formValues = {};
    @track routes = [{ key: 'r0', origin: '', destination: '' }];
    @track travelAgencies = [{ key: 'ta0', iataName: '', iataNumber: '', pcc: '', gds: '' }];
    @track errorMessage = '';
    @track isSuccess = false;
    @track _isSaving = false;
    @track _saveError = '';
    _recordId = null;
    _prefillValuesJSON = null;
    _rfpDocumentId = null;

    // ── Business licence file upload (fileupload wizard step) ──────────────────
    _businessLicenceFile = null;
    @track _bizLicIsDragOver = false;
    @track _bizLicErrorMessage = '';

    // ── Upload widget state ────────────────────────────────────────────────────
    @track _uploadState = UPL_IDLE;
    @track _selectedFile = null;
    @track _isDragOver = false;
    @track _uploadErrorMessage = '';
    @track _processingMessage = 'Uploading…';
    @track _successMessage = '';
    @track _errorStateMessage = '';

    // ── Mode detection ─────────────────────────────────────────────────────────
    get config() { return this.value || {}; }

    get isUploadMode() {
        const m = this.config.mode;
        return m === 'rfp_upload' || m === 'business_licence_upload';
    }
    get isFormMode() { return !this.isUploadMode; }

    connectedCallback() {
        if (!this._prefillValuesJSON || this.isUploadMode) return;
        try {
            const prefill = JSON.parse(this._prefillValuesJSON);
            const { routes: extractedRoutes, travelAgencies: extractedAgencies, ...fields } = prefill;
            this.formValues = { ...fields };
            // Re-add https:// for url-type fields — protocol is stripped in the extractor
            // to prevent Agentforce guardrails from redacting URL values in action outputs.
            const allFields = (this.config.steps || []).flatMap(s => s.fields || []);
            for (const field of allFields) {
                if (field.type === 'url') {
                    const v = this.formValues[field.name];
                    if (v && !v.startsWith('http')) {
                        this.formValues = { ...this.formValues, [field.name]: 'https://' + v };
                    }
                }
            }
            if (extractedRoutes && extractedRoutes.length > 0) {
                this.routes = extractedRoutes.map((r, i) => ({
                    key: `r${i}`,
                    origin:      r.origin      || '',
                    destination: r.destination || ''
                }));
            }
            if (extractedAgencies && extractedAgencies.length > 0) {
                this.travelAgencies = extractedAgencies.map((a, i) => ({
                    key:        `ta${i}`,
                    iataName:   a.iataName   || '',
                    iataNumber: a.iataNumber || '',
                    pcc:        a.pcc        || '',
                    gds:        a.gds        || ''
                }));
            }
        } catch (_e) { /* silent: fall back to empty form */ }
    }

    // ── Upload widget getters ──────────────────────────────────────────────────
    get uploadShowIdle()       { return this._uploadState === UPL_IDLE; }
    get uploadShowProcessing() { return this._uploadState === UPL_PROCESSING; }
    get uploadShowSuccess()    { return this._uploadState === UPL_SUCCESS; }
    get uploadShowErrorState() { return this._uploadState === UPL_ERROR; }
    get hasFile()          { return this._selectedFile != null; }
    get submitDisabled()   { return this._selectedFile == null; }
    get selectedFileName() { return this._selectedFile ? this._selectedFile.name : ''; }
    get selectedFileSize() {
        if (!this._selectedFile) return '';
        const b = this._selectedFile.size;
        if (b < 1024)    return b + ' B';
        if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
        return (b / 1048576).toFixed(1) + ' MB';
    }
    get dropZoneClass() {
        return this._isDragOver ? 'ruc-dropzone ruc-dropzone--active' : 'ruc-dropzone';
    }
    get uploadErrorMessage() { return this._uploadErrorMessage; }
    get processingMessage()  { return this._processingMessage; }
    get successMessage()     { return this._successMessage; }
    get errorStateMessage()  { return this._errorStateMessage; }
    get uploadTitle()        { return this.config.title || 'Upload Document'; }
    get uploadSubtitle()     { return this.config.subtitle || ''; }
    get uploadSubmitLabel()  { return this.config.submitLabel || 'Upload'; }

    // ── Upload handlers ────────────────────────────────────────────────────────
    handleDragOver(event) {
        event.preventDefault();
        this._isDragOver = true;
    }
    handleDragLeave() { this._isDragOver = false; }
    handleDrop(event) {
        event.preventDefault();
        this._isDragOver = false;
        const files = event.dataTransfer && event.dataTransfer.files;
        if (files && files.length > 0) this._applyFile(files[0]);
    }
    handleFileChange(event) {
        const files = event.target.files;
        if (files && files.length > 0) this._applyFile(files[0]);
    }
    _applyFile(file) {
        this._uploadErrorMessage = '';
        const name = file.name.toLowerCase();
        if (!name.endsWith('.pdf') && !name.endsWith('.doc') && !name.endsWith('.docx') && !name.endsWith('.xls') && !name.endsWith('.xlsx')) {
            this._uploadErrorMessage = 'Accepted formats: PDF, DOC, DOCX, XLS, XLSX';
            return;
        }
        if (file.size > 5242880) {
            this._uploadErrorMessage = 'File too large (max 5 MB). Please use a smaller document or choose the form path.';
            return;
        }
        this._selectedFile = file;
    }
    handleRemoveFile() {
        this._selectedFile = null;
        this._uploadErrorMessage = '';
    }
    _uploadSuccessUtterance() {
        return this.config.mode === 'business_licence_upload'
            ? 'Business licence uploaded'
            : 'RFP document uploaded. Starting data extraction — this may take a moment.';
    }
    handleUploadSubmit() {
        if (!this._selectedFile) return;
        this._uploadState = UPL_PROCESSING;
        this._processingMessage = 'Uploading…';
        const reader = new FileReader();
        reader.onload = (e) => {
            const dataUrl = e.target.result;
            const base64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
            uploadFileOnly({ base64Data: base64, filename: this._selectedFile.name })
                .then((result) => {
                    if (result.success) {
                        this._successMessage = 'Document uploaded successfully.';
                        this._uploadState = UPL_SUCCESS;
                        sendUploadUtterance(this._uploadSuccessUtterance());
                    } else {
                        this._errorStateMessage = result.errorMessage
                            || 'Upload failed. Please try again or choose the form path.';
                        this._uploadState = UPL_ERROR;
                        sendUploadUtterance('Upload failed: ' + (result.errorMessage || 'unknown error'));
                    }
                })
                .catch((err) => {
                    this._errorStateMessage = (err && err.body && err.body.message)
                        || 'An unexpected error occurred. Please try again.';
                    this._uploadState = UPL_ERROR;
                    sendUploadUtterance('Upload failed: ' + this._errorStateMessage);
                });
        };
        reader.onerror = () => {
            this._errorStateMessage = 'Could not read the selected file.';
            this._uploadState = UPL_ERROR;
        };
        reader.readAsDataURL(this._selectedFile);
    }
    handleRetry() {
        this._uploadState = UPL_IDLE;
        this._selectedFile = null;
        this._uploadErrorMessage = '';
        this._errorStateMessage = '';
    }

    // ── Form wizard getters ────────────────────────────────────────────────────
    get wizardTitle() { return this.config.title || ''; }
    get submitButtonLabel() { return this.config.submitButtonLabel || 'Submit'; }
    get nextButtonLabel() { return this.config.nextButtonLabel || 'Next'; }
    get previousButtonLabel() { return this.config.previousButtonLabel || 'Previous'; }
    get confirmationTitle() { return this.config.confirmationTitle || 'Submitted'; }
    get confirmationMessage() { return this.config.confirmationMessage || ''; }

    get steps() {
        return (this.config.steps || []).map((s, i) => ({ ...s, key: `step-${i}` }));
    }
    get totalSteps() { return this.steps.length; }
    get currentStepNumber() { return this.currentIndex + 1; }
    get isFirstStep() { return this.currentIndex === 0; }
    get isLastStep() { return this.totalSteps > 0 && this.currentIndex === this.totalSteps - 1; }
    get isReviewStep() { return this.isLastStep; }
    get isFileUploadStep() { return !this.isReviewStep && this.currentStep.type === 'fileupload'; }
    get isSubmitDisabled() { return this._isSaving; }
    get recordIdForDisplay() { return this._recordId; }

    get bizLicDropZoneClass() {
        return this._bizLicIsDragOver ? 'ruc-dropzone ruc-dropzone--active' : 'ruc-dropzone';
    }
    get bizLicHasFile()       { return this._businessLicenceFile != null; }
    get bizLicFileName()      { return this._businessLicenceFile ? this._businessLicenceFile.name : ''; }
    get bizLicFileSize() {
        if (!this._businessLicenceFile) return '';
        const b = this._businessLicenceFile.size;
        if (b < 1024)    return b + ' B';
        if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
        return (b / 1048576).toFixed(1) + ' MB';
    }
    get bizLicStepDescription() { return this.currentStep.description || ''; }
    get bizLicErrorMessage()    { return this._bizLicErrorMessage; }
    get currentStep() { return this.steps[this.currentIndex] || { title: '', fields: [] }; }
    get currentStepHasRoutes() { return !this.isReviewStep && !!this.currentStep.hasRoutes; }
    get isSingleRoute() { return this.routes.length <= 1; }
    get currentStepHasTravelAgencies() { return !this.isReviewStep && !!this.currentStep.hasTravelAgencies; }
    get showTravelAgencies() { return this.currentStepHasTravelAgencies && !!this.formValues.ticketIssuanceTravelAgency; }
    get isSingleTravelAgency() { return this.travelAgencies.length <= 1; }

    get hasRoutes() {
        return this.routes && this.routes.length > 0;
    }

    _mapField(f) {
        return {
            ...f,
            className: `form-field ${f.width === 'half' ? 'half-width' : 'full-width'}`,
            isSelect: f.type === 'select',
            isCheckbox: f.type === 'checkbox',
            isInput: !['select', 'checkbox'].includes(f.type),
            currentValue: this.formValues[f.name] || '',
            checkedValue: !!this.formValues[f.name],
            options: (f.options || []).map(o => ({
                ...o,
                selected: this.formValues[f.name] === o.value
            }))
        };
    }

    _passesShowIf(f) {
        if (!f.showIf) return true;
        return this.formValues[f.showIf.field] === f.showIf.value;
    }

    get visibleFields() {
        return (this.currentStep.fields || [])
            .filter(f => {
                if (this.currentStepHasTravelAgencies && f.afterAgencies) return false;
                return this._passesShowIf(f);
            })
            .map(f => ({
                ...f,
                className: `form-field ${f.width === 'half' ? 'half-width' : 'full-width'}`,
                isSelect: f.type === 'select',
                isCheckbox: f.type === 'checkbox',
                isInput: !['select', 'checkbox'].includes(f.type),
                currentValue: this.formValues[f.name] || '',
                checkedValue: !!this.formValues[f.name],
                options: (f.options || []).map(o => ({
                    ...o,
                    selected: this.formValues[f.name] === o.value
                }))
            }));
    }

    get visibleFieldsAfterAgencies() {
        if (!this.currentStepHasTravelAgencies) return [];
        return (this.currentStep.fields || [])
            .filter(f => !!f.afterAgencies && this._passesShowIf(f))
            .map(f => this._mapField(f));
    }

    get hasVisibleFieldsAfterAgencies() { return this.visibleFieldsAfterAgencies.length > 0; }

    get reviewSections() {
        if (!this.isReviewStep) return [];
        return this.steps.slice(0, this.steps.length - 1).map(step => {
            if (step.type === 'fileupload') {
                return this._businessLicenceFile
                    ? { title: step.title, fields: [{ label: 'Document', value: this._businessLicenceFile.name }] }
                    : null;
            }
            const fields = (step.fields || [])
                .filter(f => {
                    const v = this.formValues[f.name];
                    return v !== undefined && v !== '' && v !== null;
                })
                .map(f => {
                    let v = this.formValues[f.name];
                    if (f.type === 'checkbox') v = v ? 'Yes' : 'No';
                    return { label: f.label, value: String(v) };
                });
            return fields.length ? { title: step.title, fields } : null;
        }).filter(Boolean);
    }

    get reviewTravelAgencies() {
        if (!this.isReviewStep || !this.formValues.ticketIssuanceTravelAgency) return [];
        return this.travelAgencies.filter(a =>
            a.iataName || a.iataNumber || a.pcc || a.gds
        );
    }

    get hasReviewTravelAgencies() { return this.reviewTravelAgencies.length > 0; }

    // ── Business licence handlers ──────────────────────────────────────────────
    handleBizLicDragOver(event) { event.preventDefault(); this._bizLicIsDragOver = true; }
    handleBizLicDragLeave()     { this._bizLicIsDragOver = false; }
    handleBizLicDrop(event) {
        event.preventDefault();
        this._bizLicIsDragOver = false;
        const files = event.dataTransfer && event.dataTransfer.files;
        if (files && files.length > 0) this._applyBizLicFile(files[0]);
    }
    handleBizLicFileChange(event) {
        const files = event.target.files;
        if (files && files.length > 0) this._applyBizLicFile(files[0]);
    }
    _applyBizLicFile(file) {
        this._bizLicErrorMessage = '';
        const name = file.name.toLowerCase();
        if (!name.endsWith('.pdf') && !name.endsWith('.doc') && !name.endsWith('.docx')) {
            this._bizLicErrorMessage = 'Accepted formats: PDF, DOC, DOCX';
            return;
        }
        if (file.size > 5242880) {
            this._bizLicErrorMessage = 'File too large (max 5 MB).';
            return;
        }
        this._businessLicenceFile = file;
    }
    handleRemoveBizLicFile() {
        this._businessLicenceFile = null;
        this._bizLicErrorMessage = '';
    }

    // ── Form event handlers ────────────────────────────────────────────────────
    handleInputChange(event) {
        const name = event.target.dataset.name;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.formValues = { ...this.formValues, [name]: value };
        if (this.errorMessage) this.errorMessage = '';
    }

    handleRouteChange(event) {
        const { key, field } = event.target.dataset;
        const value = event.target.value.trim();
        this.routes = this.routes.map(r =>
            r.key === key ? { ...r, [field]: value } : r
        );
    }

    handleAddRoute() {
        const key = `r${Date.now()}`;
        this.routes = [...this.routes, { key, origin: '', destination: '' }];
    }

    handleRemoveRoute(event) {
        const key = event.currentTarget.dataset.key;
        if (this.routes.length > 1) {
            this.routes = this.routes.filter(r => r.key !== key);
        }
    }

    handleTravelAgencyChange(event) {
        const { key, field } = event.target.dataset;
        this.travelAgencies = this.travelAgencies.map(a =>
            a.key === key ? { ...a, [field]: event.target.value } : a
        );
    }

    handleAddTravelAgency() {
        const key = `ta${Date.now()}`;
        this.travelAgencies = [...this.travelAgencies, { key, iataName: '', iataNumber: '', pcc: '', gds: '' }];
    }

    handleRemoveTravelAgency(event) {
        const key = event.currentTarget.dataset.key;
        if (this.travelAgencies.length > 1) {
            this.travelAgencies = this.travelAgencies.filter(a => a.key !== key);
        }
    }

    handlePrevious() {
        if (!this.isFirstStep) { this.currentIndex--; this.errorMessage = ''; }
    }

    handleNext() {
        if (this.validateCurrentStep()) { this.errorMessage = ''; this.currentIndex++; }
    }

    handleSubmit() {
        if (!this._isSaving && this.validateCurrentStep()) { this.errorMessage = ''; this.submitForm(); }
    }

    validateCurrentStep() {
        if (this.isFileUploadStep) {
            if (this.currentStep.required !== false && !this._businessLicenceFile) {
                this.errorMessage = `Please upload your ${this.currentStep.title || 'document'} to continue.`;
                return false;
            }
            return true;
        }
        for (const field of this.visibleFields) {
            if (!field.required) continue;
            const v = this.formValues[field.name];
            if (field.type === 'checkbox') {
                if (!v) { this.errorMessage = `Please tick "${field.checkboxLabel || field.label}".`; return false; }
            } else {
                if (!v || String(v).trim() === '') { this.errorMessage = `"${field.label}" is required.`; return false; }
            }
        }
        for (const field of this.visibleFields) {
            if (field.type !== 'email') continue;
            const v = this.formValues[field.name];
            if (!v || !String(v).trim()) continue;
            if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(v).trim())) {
                this.errorMessage = `"${field.label}" must be a valid email address.`;
                return false;
            }
        }
        const nfrVal = this.formValues['annualNfrTarget'];
        if (nfrVal !== undefined && nfrVal !== '' && nfrVal !== null && Number(nfrVal) < 50000) {
            this.errorMessage = '"Annual NFR Target (USD)" must be at least USD 50,000.';
            return false;
        }
        if (this.currentStepHasRoutes) {
            if (this.routes.length === 0) { this.errorMessage = 'Please add at least one travel route.'; return false; }
            for (const r of this.routes) {
                if (!r.origin || !r.destination) { this.errorMessage = 'All routes must have both an origin and destination.'; return false; }
            }
        }
        return true;
    }

    submitForm() {
        if (this._isSaving) return;
        this._isSaving = true;
        this._saveError = '';

        if (this._businessLicenceFile) {
            const reader = new FileReader();
            reader.onload = (e) => {
                const dataUrl = e.target.result;
                const base64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
                uploadDocumentOnly({ base64Data: base64, filename: this._businessLicenceFile.name })
                    .then(result => {
                        if (result.success) {
                            this._doSaveRecord(result.contentDocumentId);
                        } else {
                            this._isSaving = false;
                            this._saveError = result.errorMessage || 'Business licence upload failed. Please try again.';
                        }
                    })
                    .catch(err => {
                        this._isSaving = false;
                        this._saveError = (err && err.body && err.body.message) || 'Business licence upload failed. Please try again.';
                    });
            };
            reader.onerror = () => {
                this._isSaving = false;
                this._saveError = 'Could not read the selected file. Please try again.';
            };
            reader.readAsDataURL(this._businessLicenceFile);
        } else {
            this._doSaveRecord(null);
        }
    }

    _doSaveRecord(bizLicDocId) {
        const payload = JSON.stringify({
            ...this.formValues,
            routes: this.routes.map(r => ({ origin: r.origin, destination: r.destination })),
            travelAgencies: this.travelAgencies.map(a => ({
                iataName: a.iataName, iataNumber: a.iataNumber, pcc: a.pcc, gds: a.gds
            })),
            contentDocumentIds: bizLicDocId || '',
            rfpDocumentId: this._rfpDocumentId || ''
        });
        saveRfpFromLwc({ submissionJSON: payload })
            .then(result => {
                this._isSaving = false;
                this._recordId = result.recordId;
                this.isSuccess = true;
                sendUploadUtterance('Application submitted');
            })
            .catch(err => {
                this._isSaving = false;
                this._saveError = (err && err.body && err.body.message)
                    || 'An error occurred. Please try again or contact GlobalCorporateSales@ethiopianairlines.com.';
            });
    }
}