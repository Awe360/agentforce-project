import { LightningElement, wire, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import updateLeadProposal from '@salesforce/apex/LeadContractProposalController.updateLeadProposal';
import generateToken from '@salesforce/apex/FileSecurityService.generateUploadToken';
import { CurrentPageReference } from 'lightning/navigation';
import getSingleLead from '@salesforce/apex/LeadContractProposalController.getSingleLead';
export default class CorporateContractProposalForm extends LightningElement {
    // Get the Lead ID from the Lightning Record Page
 
    // Object to store all form data
    @track leadData = {};
    
    @track encryptedToken; // Variable to hold the token
    @track isSubmitted = false; 
    @track isUpdateEnabled = false; // Variable to track if update is enabled
    @track isFetching = true; // To show loading spinner while fetching lead data
     // Call Apex imperatively when the component loads
    connectedCallback() {
        if (this.recordId) {
            this.getUploadToken();
        }
    }

    checkedTicketIssuanceOptions = [];
    isSubmitting = false; // To disable button on click
     recordId;
   
     goToHomePage() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: ''
            },
        });
    }
   
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId =currentPageReference?.state?.leadId;//"00QQ100000HD0A5MAL";// 
            console.log('Record ID:', this.recordId);
        }
    }
    // Renamed from leadData to leadStatus
    @wire(getSingleLead, { leadId: '$recordId' })
wiredLead(result) {
        this.leadStatus = result; // Store the result (data and error)
        this.isFetching = false; // Data fetching is complete
        if (result.data) {
            console.log(result.data); 
            console.log('Lead Data Fetched Successfully:');
            console.log(JSON.parse(JSON.stringify(result.data))); 
            // Accessing specific field:
            console.log('Enable Update Value:', result.data.Enable_Update__c);
            this.isUpdateEnabled = result.data.Enable_Update__c;
        } else if (result.error) {
            console.error('Error fetching lead:', result.error);
        }
    }
 
    get hasError() {
        return this.leadStatus?.error;
    }
    // File Upload accepted formats
    get acceptedFormats() {
        return ['.pdf', '.png', '.jpg', '.jpeg', '.doc', '.docx'];
    }

    // Options for the "Place of Ticket Issuance" checkbox group
    // This matches the field 'Place_of_Ticket_Issuance__c' (Multi-Select Picklist)
    get ticketIssuanceOptions() {
        return [
            { label: 'GSA Office', value: 'GSA Office' },
            { label: 'Travel Agency', value: 'Travel Agency' },
            { label: 'ET Website', value: 'ET Website' },
            { label: 'Mobile App', value: 'Mobile App' },
            { label: 'ET Ticket Office', value: 'ET Ticket Office' },
        ];
    }


    
    getUploadToken() {
        generateToken({ targetRecordId: this.recordId })
            .then(token => {
                this.encryptedToken = token;
            })
            .catch(error => {
                console.error('Error generating token:', error);
                // Handle error: e.g., show a toast or disable the upload button
            });
    }

    // This getter will now return the token fetched from Apex
    get tokenValue() {
        return this.encryptedToken;
    }




    /**
     * Generic change handler for all standard inputs (text, number, textarea, etc.)
     */
    handleChange(event) {
        // Dynamically set the property on leadData object
        // e.g., this.leadData['Company'] = 'Acme Inc.';
        this.leadData[event.target.name] = event.target.value;
    }

        handleCheckboxChange(event) {
        // This maps the checkbox name (e.g., 'isGsaOffice') to its checked state (true/false)
        // this.leadData[event.target.name] = event.target.checked;
        // this.leadData.Place_of_Ticket_Issuance__c = event.target.name;
        if(event.target.checked){
            this.checkedTicketIssuanceOptions.push(event.target.name);
        }else{
            const index = this.checkedTicketIssuanceOptions.indexOf(event.target.name);
            if (index > -1) {
                this.checkedTicketIssuanceOptions.splice(index, 1);
            }
        }
        console.log('Checked Options:', this.checkedTicketIssuanceOptions);

    }


    /**
     * Specific change handler for the 'Place of Ticket Issuance' checkbox group.
     * Multi-select picklist values must be joined by a semicolon.
     */
    handleCheckboxGroupChange(event) {
        // event.detail.value is an array of selected values, e.g., ['GSA Office', 'ET Website']
        // We join them into a single string to store in the multi-select picklist field
        this.leadData.Place_of_Ticket_Issuance__c = event.detail.value.join(';');
    }

    /**
     * Handles the 'Submit Proposal' button click.
     */
    async handleSubmit() {
        this.isSubmitting = true;
        // this.leadData.RFP_Submission_Date__c = new Date().toISOString(); // Set submission date to today  
        this.leadData.Place_of_Ticket_Issuance__c = this.checkedTicketIssuanceOptions.join(';');
        // 1. Basic Validation
        if (!this.validateFields()) {
            this.showToast('Error', 'Please fill in all required fields.', 'error');
            this.isSubmitting = false;
            return;
        }

        // 2. Call Apex to update the Lead
        try {
            console.log('Lead Data to submit:', this.leadData);
            // Pass the record ID and the JSON string of our form data
            await updateLeadProposal({ 
                leadId: this.recordId, 
                leadWrapperJson: JSON.stringify(this.leadData) 
            });

            // 3. Show success
            this.showToast('Success', 'Proposal submitted successfully.', 'success');
            // Optionally, you can navigate away or refresh the page here
            this.isSubmitted = true;

        } catch (error) {
            // 4. Show error
            this.showToast('Error Submitting', error.body.message, 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    /**
     * Handles successful file upload.
     */
    handleUploadFinished(event) {
        // Get the list of uploaded files
        const uploadedFiles = event.detail.files.length;
        this.showToast('Files Uploaded', `${uploadedFiles} file(s) uploaded successfully.`, 'success');
    }

    /**
     * Helper function to check validity of all required fields.
     */
    validateFields() {
        let isValid = true;
        // Check all inputs/textareas with 'required' attribute
        this.template.querySelectorAll('lightning-input[required], lightning-textarea[required], lightning-checkbox-group[required]')
            .forEach(input => {
                if (!input.reportValidity()) {
                    isValid = false;
                }
            });
        return isValid;
    }
    

    /**
     * Helper function to show toast messages.
     */
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }
}