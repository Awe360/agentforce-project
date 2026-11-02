import { LightningElement, api, track } from 'lwc';
import uploadAndExtract from '@salesforce/apex/RfpUploadController.uploadAndExtract';

const APEX_ENVELOPE_FIELD = 'rfpUploadCltJSON';
const BUILDER_FALLBACK = {
    title: 'Upload RFP Document',
    subtitle: 'Select your Request for Proposal document to extract application details automatically.',
    submitLabel: 'Upload & Extract'
};

function unwrapApexEnvelope(raw) {
    if (raw == null) return raw;
    if (typeof raw !== 'object') return raw;
    if (!(APEX_ENVELOPE_FIELD in raw)) {
        const keys = Object.keys(raw);
        if (keys.length === 1 && keys[0] === 'value' && raw.value && typeof raw.value === 'object') {
            return raw.value;
        }
        return raw;
    }
    const field = raw[APEX_ENVELOPE_FIELD];
    if (typeof field === 'string' && field.trim()) {
        try { return JSON.parse(field); } catch (_e) { return null; }
    }
    return null;
}

function sendUtterance(message) {
    try {
        if (typeof embeddedservice_configuration !== 'undefined'
                && embeddedservice_configuration?.util?.sendTextMessage) {
            embeddedservice_configuration.util.sendTextMessage(message).catch((err) => {
                console.error('sendUtterance failed:', err);
            });
        } else {
            console.log('sendUtterance (preview):', message);
        }
    } catch (err) {
        console.error('sendUtterance threw:', err);
    }
}

const STATE_IDLE       = 'idle';
const STATE_PROCESSING = 'processing';
const STATE_SUCCESS    = 'success';
const STATE_ERROR      = 'error';

export default class RfpUploadClt extends LightningElement {
    _value;
    @api
    get value() { return this._value != null ? this._value : BUILDER_FALLBACK; }
    set value(v) { this._value = unwrapApexEnvelope(v); }

    @track _state = STATE_IDLE;
    @track _selectedFile = null;
    @track _isDragOver = false;
    @track _errorMessage = '';
    @track _processingMessage = 'Uploading and extracting…';
    @track _successMessage = '';
    @track _errorStateMessage = '';

    get showIdle()       { return this._state === STATE_IDLE; }
    get showProcessing() { return this._state === STATE_PROCESSING; }
    get showSuccess()    { return this._state === STATE_SUCCESS; }
    get showErrorState() { return this._state === STATE_ERROR; }

    get hasFile()           { return this._selectedFile != null; }
    get submitDisabled()    { return this._selectedFile == null; }
    get selectedFileName()  { return this._selectedFile ? this._selectedFile.name : ''; }
    get selectedFileSize() {
        if (!this._selectedFile) return '';
        const b = this._selectedFile.size;
        if (b < 1024)        return b + ' B';
        if (b < 1048576)     return (b / 1024).toFixed(1) + ' KB';
        return (b / 1048576).toFixed(1) + ' MB';
    }
    get dropZoneClass() {
        return this._isDragOver ? 'ruc-dropzone ruc-dropzone--active' : 'ruc-dropzone';
    }
    get errorMessage()      { return this._errorMessage; }
    get processingMessage() { return this._processingMessage; }
    get successMessage()    { return this._successMessage; }
    get errorStateMessage() { return this._errorStateMessage; }

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
        this._errorMessage = '';
        const name = file.name.toLowerCase();
        if (!name.endsWith('.pdf') && !name.endsWith('.doc') && !name.endsWith('.docx')) {
            this._errorMessage = 'Accepted formats: PDF, DOC, DOCX';
            return;
        }
        if (file.size > 5242880) {
            this._errorMessage = 'File too large (max 5 MB). Please use a smaller document or choose the form path.';
            return;
        }
        this._selectedFile = file;
    }
    handleRemoveFile() {
        this._selectedFile = null;
        this._errorMessage = '';
    }

    _successUtterance() {
        const ctx = this.value && this.value.context;
        return ctx === 'business_licence'
            ? 'Business licence uploaded'
            : 'RFP document uploaded and processed';
    }

    handleSubmit() {
        if (!this._selectedFile) return;
        this._state = STATE_PROCESSING;
        this._processingMessage = 'Uploading and extracting…';

        const reader = new FileReader();
        reader.onload = (e) => {
            const dataUrl = e.target.result;
            const base64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
            uploadAndExtract({ base64Data: base64, filename: this._selectedFile.name })
                .then((result) => {
                    if (result.success) {
                        this._successMessage = 'Document uploaded successfully.';
                        this._state = STATE_SUCCESS;
                        sendUtterance(this._successUtterance());
                    } else {
                        this._errorStateMessage = result.errorMessage
                            || 'Upload failed. Please try again or choose the form path.';
                        this._state = STATE_ERROR;
                        sendUtterance('RFP document upload failed: ' + (result.errorMessage || 'unknown error'));
                    }
                })
                .catch((err) => {
                    this._errorStateMessage = (err && err.body && err.body.message)
                        || 'An unexpected error occurred. Please try again.';
                    this._state = STATE_ERROR;
                    sendUtterance('RFP document upload failed: ' + this._errorStateMessage);
                });
        };
        reader.onerror = () => {
            this._errorStateMessage = 'Could not read the selected file.';
            this._state = STATE_ERROR;
        };
        reader.readAsDataURL(this._selectedFile);
    }

    handleRetry() {
        this._state = STATE_IDLE;
        this._selectedFile = null;
        this._errorMessage = '';
        this._errorStateMessage = '';
    }
}