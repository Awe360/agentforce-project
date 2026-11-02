public without sharing class rfpProposalAndRequest {

    @AuraEnabled(cacheable=true)
    public static Proposal_Version__c getRecordDetails(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('No Record ID provided in the page request.');
        }

        String trimmedId = recordId.trim();
        if ((trimmedId.length() != 15 && trimmedId.length() != 18) || !trimmedId.isAlphanumeric()) {
            throw new AuraHandledException('Invalid Record ID format: ' + trimmedId);
        }

        try {
            Id validId = (Id) trimmedId;

            List<Proposal_Version__c> records = [
                SELECT Id, 
                       Name, 
                       Business_Discount__c, 
                       Customer_Feedback_Request__c, 
                       Economy_Discount__c, 
                       Min_Target_per_Year_USD__c, 
                       Opportunity__c, 
                       Routing__c, 
                       Soft_Benefits__c, 
                       Status__c, 
                       Ticket_Issuance_Location__c, 
                       Type__c, 
                       Version_Number__c
                FROM Proposal_Version__c
                WHERE Id = :validId
                LIMIT 1
            ];

            if (records.isEmpty()) {
                throw new AuraHandledException('Record not found or access denied for ID: ' + validId);
            }

            return records[0];

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error in getRecordDetails: ' + e.getMessage());
            throw new AuraHandledException('An error occurred while fetching proposal details: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Proposal_Version__c getLatestProposalByOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID cannot be null.');
        }

        try {
            List<Proposal_Version__c> records = [
                SELECT Id, 
                       Name, 
                       Business_Discount__c, 
                       Customer_Feedback_Request__c, 
                       Economy_Discount__c, 
                       Min_Target_per_Year_USD__c, 
                       Opportunity__c, 
                       Routing__c, 
                       Soft_Benefits__c, 
                       Status__c, 
                       Ticket_Issuance_Location__c, 
                       Type__c, 
                       Version_Number__c,
                       CreatedDate
                FROM Proposal_Version__c
                WHERE Opportunity__c = :opportunityId
                ORDER BY Version_Number__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 1
            ];

            if (records.isEmpty()) {
                return null;
            }

            return records[0];

        } catch (Exception e) {
            System.debug('Error in getLatestProposalByOpportunity: ' + e.getMessage());
            throw new AuraHandledException('Error fetching latest proposal version: ' + e.getMessage());
        }
    }

   @AuraEnabled
public static void acceptProposal(Id recordId) {
    if (recordId == null) {
        throw new AuraHandledException('Record ID cannot be null.');
    }

    try {
        // 1. Query ALL required proposal fields
        Proposal_Version__c currentProposal = [
            SELECT Id, 
                   Opportunity__c,
                   Business_Discount__c,
                   Economy_Discount__c,
                   Ticket_Issuance_Location__c,
                   Min_Target_per_Year_USD__c,
                   Soft_Benefits__c,
                   Origin__c,
                   Destination__c
            FROM Proposal_Version__c 
            WHERE Id = :recordId 
            LIMIT 1
        ];

        // 2. Update Proposal Status
        Proposal_Version__c proposalToUpdate = new Proposal_Version__c(
            Id = recordId,
            Status__c = 'Accepted'
        );
        update proposalToUpdate;

        // 3. Update Opportunity Fields using values from currentProposal
        if (currentProposal.Opportunity__c != null) {
            Opportunity oppToUpdate = new Opportunity(
                Id = currentProposal.Opportunity__c,
                StageName = 'Accepted',
                
                Proposed_Discount_for_Business__c = currentProposal.Business_Discount__c,
                Proposed_Discount_for_Economy__c  = currentProposal.Economy_Discount__c, 
                Place_of_Ticket_Issuance__c       = currentProposal.Ticket_Issuance_Location__c,
                Minimum_Annual_TS__c              = currentProposal.Min_Target_per_Year_USD__c,
                Special_services__c               = currentProposal.Soft_Benefits__c,
                Origin__c                         = currentProposal.Origin__c,
                Destination__c                    = currentProposal.Destination__c
            );
            update oppToUpdate;
        }

    } catch (Exception e) {
        System.debug('Error in acceptProposal: ' + e.getMessage());
        throw new AuraHandledException('Failed to accept proposal: ' + e.getMessage());
    }
}

    /**
     * Creates a NEW proposal version by copying base details from old proposal 
     * and merging the updated form values. Updates related Opportunity StageName to "Negotiation".
     */
    @AuraEnabled
    public static Proposal_Version__c createNewVersion(String oldRecordId, Proposal_Version__c updatedFields) {
        if (String.isBlank(oldRecordId)) {
            throw new AuraHandledException('Original record ID is required to create a new version.');
        }

        try {
            // Fetch original record - ADDED Origin__c and Destination__c to SELECT
            Proposal_Version__c oldRecord = [
                SELECT Id, 
                       Opportunity__c, 
                       Routing__c, 
                       Origin__c,
                       Destination__c,
                       Ticket_Issuance_Location__c, 
                       Type__c, 
                       Version_Number__c
                FROM Proposal_Version__c 
                WHERE Id = :oldRecordId 
                LIMIT 1
            ];

            // Calculate next version increment
            Decimal currentVer = oldRecord.Version_Number__c != null ? oldRecord.Version_Number__c : 1;
            Decimal nextVer = currentVer + 1;

            // Construct new instance combining old values and new form inputs
            Proposal_Version__c newProposal = new Proposal_Version__c(
                Opportunity__c               = oldRecord.Opportunity__c,
                Origin__c                   = oldRecord.Origin__c,
                Destination__c              = oldRecord.Destination__c,
                Ticket_Issuance_Location__c  = oldRecord.Ticket_Issuance_Location__c,
                Type__c                      = 'Customer Counter Proposal',
                
                Business_Discount__c         = updatedFields.Business_Discount__c,
                Economy_Discount__c          = updatedFields.Economy_Discount__c,
                Min_Target_per_Year_USD__c   = updatedFields.Min_Target_per_Year_USD__c,
                Soft_Benefits__c             = updatedFields.Soft_Benefits__c,
                Customer_Feedback_Request__c = updatedFields.Customer_Feedback_Request__c,
                
                Version_Number__c            = nextVer,
                Status__c                    = 'Change Requested'
            );

            insert newProposal;

            // Update Opportunity Stage to "Negotiation"
            if (oldRecord.Opportunity__c != null) {
                Opportunity oppToUpdate = new Opportunity(
                    Id = oldRecord.Opportunity__c,
                    StageName = 'Negotiation'
                );
                update oppToUpdate;
            }

            return newProposal;

        } catch (Exception e) {
            System.debug('Error in createNewVersion: ' + e.getMessage());
            throw new AuraHandledException('Failed to create new proposal version: ' + e.getMessage());
        }
    }
}