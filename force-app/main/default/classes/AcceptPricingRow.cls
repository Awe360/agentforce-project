public with sharing class AcceptPricingRow {

    public class Request {
        @InvocableVariable(required=true description='Corporate_Travel_RFP__c record Id')
        public Id rfpId;

        @InvocableVariable(required=true description='Matrix row to offer: 1 = default (no escalation), 2+ = flags for manager approval')
        public Integer rowNumber;

        @InvocableVariable(description='Business reason for offering above the default row. Required when row > 1.')
        public String escalationJustification;

        @InvocableVariable(description='Set true to apply Rule 2 non-commissionable uplift to all fare class rates.')
        public Boolean applyRule2Uplift;

        @InvocableVariable(description='Uplift percentage to add to all fare class rates (1–4%). Used when applyRule2Uplift = true.')
        public Decimal rule2UpliftPct;

        @InvocableVariable(description='Free-text negotiation context to store on the record.')
        public String negotiationBrief;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;
        @InvocableVariable public Integer updatedVersion;
        @InvocableVariable public Boolean escalationRequired;
        @InvocableVariable public String approvalStatus;
        @InvocableVariable public String tierLabel;
    }

    @InvocableMethod(
        label='Accept Pricing Row'
        description='Writes the selected discount tier row to Offer_* fields on Corporate_Travel_RFP__c. Row 1 = default offer, row 2+ = flags escalation and submits for manager approval.'
        category='Corporate Travel'
    )
    public static List<Result> accept(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) out.add(process(r));
        return out;
    }

    private static Result process(Request req) {
        Result res = new Result();
        try {
            Corporate_Travel_RFP__c rfp = [
                SELECT Annual_NFR_Target_USD__c, Offer_Contract_Version__c
                FROM Corporate_Travel_RFP__c WHERE Id = :req.rfpId LIMIT 1
            ];

            Decimal nfr = rfp.Annual_NFR_Target_USD__c;
            if (nfr == null) {
                res.success = false;
                res.errorMessage = 'Annual NFR Target is not set — cannot look up a pricing row.';
                return res;
            }

            List<ET_Discount_Tier__c> rows = [
                SELECT Tier_Label__c, Row_Number__c,
                       Economy_Lower_Pct__c, Economy_Higher_Pct__c,
                       D_Class_Pct__c, J_Class_Pct__c, C_Class_Pct__c,
                       Soft_Options_Count__c, Routing_Scope__c
                FROM ET_Discount_Tier__c
                WHERE NFR_Lower_USD__c <= :nfr
                  AND (NFR_Upper_USD__c >= :nfr OR NFR_Upper_USD__c = null)
                  AND Row_Number__c = :req.rowNumber
                ORDER BY NFR_Lower_USD__c DESC
                LIMIT 1
            ];

            if (rows.isEmpty()) {
                res.success = false;
                res.errorMessage = 'Row ' + req.rowNumber + ' not found in the pricing matrix for NFR $' + nfr.format();
                return res;
            }

            ET_Discount_Tier__c row = rows[0];
            Boolean rule2      = req.applyRule2Uplift != null && req.applyRule2Uplift;
            Decimal uplift     = (rule2 && req.rule2UpliftPct != null) ? req.rule2UpliftPct : 0;
            Boolean needsEscalation = (req.rowNumber > 1) || rule2;
            Integer nextVersion = rfp.Offer_Contract_Version__c != null
                ? rfp.Offer_Contract_Version__c.intValue() + 1 : 1;

            Corporate_Travel_RFP__c upd = new Corporate_Travel_RFP__c(Id = req.rfpId);
            upd.Offer_Matrix_Tier__c        = row.Tier_Label__c;
            upd.Offer_Matrix_Row__c         = req.rowNumber;
            upd.Offer_Economy_Lower_Pct__c  = (row.Economy_Lower_Pct__c  != null ? row.Economy_Lower_Pct__c  : 0) + uplift;
            upd.Offer_Economy_Higher_Pct__c = (row.Economy_Higher_Pct__c != null ? row.Economy_Higher_Pct__c : 0) + uplift;
            upd.Offer_D_Class_Pct__c        = (row.D_Class_Pct__c        != null ? row.D_Class_Pct__c        : 0) + uplift;
            upd.Offer_J_Class_Pct__c        = (row.J_Class_Pct__c        != null ? row.J_Class_Pct__c        : 0) + uplift;
            upd.Offer_C_Class_Pct__c        = (row.C_Class_Pct__c        != null ? row.C_Class_Pct__c        : 0) + uplift;
            upd.Offer_Soft_Options_Count__c = row.Soft_Options_Count__c != null
                ? Integer.valueOf(row.Soft_Options_Count__c) : 0;
            upd.Offer_Routing_Scope__c      = row.Routing_Scope__c;
            upd.Offer_Rule2_Uplift_Applied__c = rule2;
            upd.Offer_Rule2_Uplift_Pct__c   = rule2 ? req.rule2UpliftPct : null;
            upd.Offer_Contract_Version__c   = nextVersion;
            upd.Offer_Contract_Template__c  = 'Main';
            upd.Offer_Negotiation_Brief__c  = req.negotiationBrief;
            upd.Status__c                   = 'Offer Prepared';
            upd.Escalation_Required__c      = needsEscalation;

            if (needsEscalation) {
                upd.Escalation_Type__c = rule2 ? 'Rule 2 Uplift' : 'In-Tier Row Increase';
                upd.Escalation_Justification__c = req.escalationJustification;
                upd.Pricing_Approval_Status__c  = 'Pending';
            } else {
                upd.Escalation_Type__c          = null;
                upd.Escalation_Justification__c = null;
                upd.Pricing_Approval_Status__c  = null;
            }

            update upd;

            if (needsEscalation) {
                try {
                    Approval.ProcessSubmitRequest aReq = new Approval.ProcessSubmitRequest();
                    aReq.setObjectId(req.rfpId);
                    aReq.setSkipEntryCriteria(false);
                    Approval.process(aReq);
                } catch (Exception approvalEx) {
                    // Non-fatal: escalation fields are already set. Approval submission can fail
                    // if no process matches or the record is already in an approval workflow.
                    System.debug('AcceptPricingRow: approval submission skipped — ' + approvalEx.getMessage());
                }
            }

            res.success            = true;
            res.updatedVersion     = nextVersion;
            res.escalationRequired = needsEscalation;
            res.approvalStatus     = needsEscalation ? 'Pending' : null;
            res.tierLabel          = row.Tier_Label__c;
        } catch (Exception e) {
            res.success       = false;
            res.errorMessage  = e.getMessage();
        }
        return res;
    }
}