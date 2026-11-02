import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLatestProposalByOpportunity from '@salesforce/apex/rfpProposalAndRequest.getLatestProposalByOpportunity';
import acceptProposal from '@salesforce/apex/rfpProposalAndRequest.acceptProposal';
import createNewVersion from '@salesforce/apex/rfpProposalAndRequest.createNewVersion';

export default class RfpProposalAndRequest extends LightningElement {
    opportunityId; 
    record;        
    @track formData = {};
    
    isEditMode = false;
    isLoading = true;
    errorMessage;

    // States for Thank You screen
    isSubmitted = false;
    submissionType = ''; // 'accepted' or 'requested_change'

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference && currentPageReference.state) {
            const stateParams = currentPageReference.state;
            
            // Case-insensitive key check for 'recordid'
            const recordIdKey = Object.keys(stateParams).find(
                (key) => key.toLowerCase() === 'recordid'
            );

            this.opportunityId = recordIdKey ? stateParams[recordIdKey] : null;

            if (this.opportunityId) {
                this.loadRecord();
            } else {
                this.isLoading = false;
                this.errorMessage = 'No recordId parameter found in page URL.';
            }
        }
    }

    loadRecord() {
        this.isLoading = true;
        getLatestProposalByOpportunity({ opportunityId: this.opportunityId })
            .then((result) => {
                if (result) {
                    this.record = result;
                    this.formData = { ...result };
                    this.errorMessage = null;
                } else {
                    this.errorMessage = 'No proposals found for this Opportunity.';
                }
            })
            .catch((error) => {
                this.errorMessage = error.body ? error.body.message : 'Error fetching proposal details.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Dynamic visibility check: Buttons only show if status is strictly 'Sent'
    get canTakeAction() {
        return this.record?.Status__c?.toLowerCase() === 'sent';
    }

    get statusBadgeClass() {
        const status = this.record?.Status__c ? this.record.Status__c.toLowerCase() : '';
        if (status.includes('accept') || status.includes('approved')) {
            return 'badge badge-success';
        } else if (status.includes('draft') || status.includes('pending') || status.includes('change') || status.includes('review')) {
            return 'badge badge-warning';
        } else if (status === 'sent') {
            return 'badge badge-info';
        }
        return 'badge badge-neutral';
    }

    get isAcceptedSubmission() {
        return this.submissionType === 'accepted';
    }

    get thankYouTitle() {
        return this.isAcceptedSubmission 
            ? 'Thank You for Accepting!' 
            : 'Change Request Submitted!';
    }

    get thankYouSubtitle() {
        return this.isAcceptedSubmission 
            ? 'We are excited to work with you. Your acceptance has been logged and sent to our team.' 
            : 'Your proposed updates have been registered as a new proposal version for review.';
    }

    get thankYouIcon() {
        return this.isAcceptedSubmission ? 'action:approval' : 'action:update_status';
    }

    handleAccept() {
        if (!this.record?.Id) return;
        
        this.isLoading = true;
        acceptProposal({ recordId: this.record.Id })
            .then(() => {
                this.showToast('Success', 'Proposal Accepted Successfully!', 'success');
                this.submissionType = 'accepted';
                this.isSubmitted = true;
                this.loadRecord();
            })
            .catch((error) => {
                this.showToast('Error', error.body ? error.body.message : 'Failed to accept proposal.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleEnableUpdate() {
        this.isEditMode = true;
    }

    handleCancelUpdate() {
        this.isEditMode = false;
        this.formData = { ...this.record };
    }

    handleInputChange(event) {
        const field = event.target.name;
        this.formData[field] = event.target.value;
    }

    handleSubmitUpdate() {
        if (!this.record?.Id) return;

        this.isLoading = true;
        
        createNewVersion({ 
            oldRecordId: this.record.Id, 
            updatedFields: this.formData 
        })
            .then((newRecord) => {
                this.showToast(
                    'Success', 
                    `New Proposal Version ${newRecord.Version_Number__c} created!`, 
                    'success'
                );
                this.isEditMode = false;
                this.submissionType = 'requested_change';
                this.isSubmitted = true;
                
                this.loadRecord();
            })
            .catch((error) => {
                this.showToast(
                    'Error', 
                    error.body ? error.body.message : 'Failed to create new proposal version.', 
                    'error'
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleResetView() {
        this.isSubmitted = false;
        this.loadRecord();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}