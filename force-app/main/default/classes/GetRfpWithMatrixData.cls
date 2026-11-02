public with sharing class GetRfpWithMatrixData {

    public class Request {
        @InvocableVariable(required=true description='RFP record Id or Opportunity Id')
        public String recordId;
    }

    public class Result {
        @InvocableVariable(description='RFP record Id')
        public String rfpId;
        @InvocableVariable(description='Company name from RFP')
        public String companyName;
        @InvocableVariable(description='Annual NFR target, formatted as currency string')
        public String annualNfrTargetUsd;
        @InvocableVariable(description='Corporate ID — blank means not yet assigned')
        public String corporateId;
        @InvocableVariable(description='Requested economy discount (raw field value)')
        public String requestedEconomy;
        @InvocableVariable(description='Requested business discount (raw field value)')
        public String requestedBusiness;
        @InvocableVariable(description='Matrix tier label matching prospect NFR')
        public String qualifyingTierLabel;
        @InvocableVariable(description='JSON array of all 5 ET_Discount_Tier__c rows for qualifying tier')
        public String tierRowsJson;
        @InvocableVariable(description='JSON object of ET_Soft_Benefit_Tier__c row for qualifying tier')
        public String softBenefitJson;
        @InvocableVariable(description='Formatted negotiation brief for rep review')
        public String negotiationSummary;
        @InvocableVariable(description='Non-null if lookup failed')
        public String errorMessage;
        @InvocableVariable(description='Structured CLT display object for the negotiation brief')
        public RfpNegotiationBriefData negotiationBriefDisplay;
        @InvocableVariable(description='The accepted pricing row number (1 = default approved; 2+ = escalation; null = no offer yet)')
        public Integer offerMatrixRow;
        @InvocableVariable(description='Pricing approval status (null = not submitted; Pending = awaiting approval; Approved = approved)')
        public String pricingApprovalStatus;
        @InvocableVariable(description='Soft benefit options count for the accepted pricing row. 0 = no soft benefits at this discount level. Null = no offer accepted yet.')
        public Integer acceptedRowSoftOptionsCount;
        @InvocableVariable(description='Pre-computed rate assessment: whether the prospect requested rates are within or above the pre-approved Row 1 matrix maximums, and whether escalation is needed.')
        public String rateAssessmentSummary;
        @InvocableVariable(description='Pre-built soft benefit selection question using the actual free ticket count from the tier data. Output verbatim — do not rephrase.')
        public String softBenefitQuestion;
        @InvocableVariable(description='ContentDocument Id of the most recently generated contract draft. Non-blank means a contract already exists on this RFP.')
        public String contractContentId;
        @InvocableVariable(description='Contact name from the RFP (Contact_Name__c)')
        public String contactName;
        @InvocableVariable(description='Contact email address from the RFP (Contact_Email__c)')
        public String contactEmail;
        @InvocableVariable(description='True if Rule 2 non-commissionable uplift has been applied to this offer')
        public Boolean offerRule2UpliftApplied;
        @InvocableVariable(description='Rule 2 uplift percentage applied. Null if not applied.')
        public Decimal offerRule2UpliftPct;
        @InvocableVariable(description='The highest row number available for this NFR tier. Use as the base rowNumber for Rule 2 uplift when no row has been accepted yet (offerMatrixRow is null).')
        public Integer maxAvailableRowNumber;
    }

    @InvocableMethod(
        label='Get RFP With Matrix Data'
        description='Reads a Corporate Travel RFP and the matching incentive scheme matrix rows. Accepts either an RFP Id or an Opportunity Id.'
        category='Corporate Travel'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(lookup(req.recordId));
        }
        return results;
    }

    private static Result lookup(String recordId) {
        Result res = new Result();
        try {
            Corporate_Travel_RFP__c rfp = fetchRfp(recordId);
            res.rfpId = rfp.Id;
            res.companyName = rfp.Company_Name__c;
            res.corporateId = rfp.Corporate_ID__c != null ? rfp.Corporate_ID__c : '';
            res.requestedEconomy = rfp.Economy_Discount_Pct__c != null ? rfp.Economy_Discount_Pct__c : '';
            res.requestedBusiness = rfp.Business_Discount_Pct__c != null ? rfp.Business_Discount_Pct__c : '';
            res.offerMatrixRow = rfp.Offer_Matrix_Row__c != null ? rfp.Offer_Matrix_Row__c.intValue() : null;
            res.pricingApprovalStatus = rfp.Pricing_Approval_Status__c;
            Decimal nfr = rfp.Annual_NFR_Target_USD__c != null ? rfp.Annual_NFR_Target_USD__c : 0;
            res.annualNfrTargetUsd = formatCurrency(nfr);

            List<ET_Discount_Tier__c> tierRows = fetchTierRows(nfr);
            if (tierRows.isEmpty()) {
                res.errorMessage = 'No qualifying matrix tier found for NFR target ' + res.annualNfrTargetUsd + '. Minimum threshold is $50,000.';
                return res;
            }
            res.qualifyingTierLabel = tierRows[0].Tier_Label__c;
            res.tierRowsJson = JSON.serialize(tierRows);
            res.rateAssessmentSummary = buildRateAssessment(rfp, tierRows);

            if (res.offerMatrixRow != null) {
                for (ET_Discount_Tier__c r : tierRows) {
                    if (r.Row_Number__c != null && r.Row_Number__c.intValue() == res.offerMatrixRow) {
                        res.acceptedRowSoftOptionsCount = r.Soft_Options_Count__c != null
                            ? r.Soft_Options_Count__c.intValue() : 0;
                        break;
                    }
                }
            }

            List<ET_Soft_Benefit_Tier__c> softRows = fetchSoftBenefit(nfr);
            ET_Soft_Benefit_Tier__c softTier = softRows.isEmpty() ? null : softRows[0];
            res.softBenefitJson = softTier == null ? '{}' : JSON.serialize(softTier);
            res.negotiationSummary = buildSummary(rfp, tierRows, softTier);
            res.negotiationBriefDisplay = buildBriefDisplay(rfp, tierRows, softTier);
            res.softBenefitQuestion = buildSoftBenefitQuestion(res.acceptedRowSoftOptionsCount, softTier);
            res.contractContentId        = rfp.Offer_Contract_Content_Id__c;
            res.contactName              = rfp.Contact_Name__c;
            res.contactEmail             = rfp.Contact_Email__c;
            res.offerRule2UpliftApplied  = rfp.Offer_Rule2_Uplift_Applied__c;
            res.offerRule2UpliftPct      = rfp.Offer_Rule2_Uplift_Pct__c;
            res.maxAvailableRowNumber    = tierRows.size();
        } catch (Exception e) {
            res.errorMessage = e.getMessage();
        }
        return res;
    }

    private static Corporate_Travel_RFP__c fetchRfp(String recordId) {
        // Opportunity IDs always start with '006'
        if (recordId.startsWith('006')) {
            List<Corporate_Travel_RFP__c> rfps = [
                SELECT Id, Company_Name__c, Annual_NFR_Target_USD__c,
                       Economy_Discount_Pct__c, Business_Discount_Pct__c,
                       Corporate_ID__c, Status__c,
                       Offer_Matrix_Row__c, Pricing_Approval_Status__c,
                       Offer_Contract_Content_Id__c,
                       Offer_Rule2_Uplift_Applied__c, Offer_Rule2_Uplift_Pct__c,
                       Contact_Name__c, Contact_Email__c
                FROM Corporate_Travel_RFP__c
                WHERE Opportunity__c = :recordId
                LIMIT 1
            ];
            if (rfps.isEmpty()) {
                throw new QueryException('No Corporate Travel RFP found linked to this Opportunity. Please launch the agent from the RFP record directly.');
            }
            return rfps[0];
        }
        return [
            SELECT Id, Company_Name__c, Annual_NFR_Target_USD__c,
                   Economy_Discount_Pct__c, Business_Discount_Pct__c,
                   Corporate_ID__c, Status__c,
                   Offer_Matrix_Row__c, Pricing_Approval_Status__c,
                   Offer_Contract_Content_Id__c,
                   Offer_Rule2_Uplift_Applied__c, Offer_Rule2_Uplift_Pct__c,
                   Contact_Name__c, Contact_Email__c
            FROM Corporate_Travel_RFP__c
            WHERE Id = :recordId
            LIMIT 1
        ];
    }

    private static List<ET_Discount_Tier__c> fetchTierRows(Decimal nfr) {
        // Rows where NFR falls within [Lower, Upper) or >= Lower for top tier (null Upper)
        return [
            SELECT Tier_Label__c, Row_Number__c, NFR_Lower_USD__c, NFR_Upper_USD__c,
                   Economy_Lower_Pct__c, Economy_Higher_Pct__c,
                   D_Class_Pct__c, J_Class_Pct__c, C_Class_Pct__c,
                   Soft_Options_Count__c, Routing_Scope__c
            FROM ET_Discount_Tier__c
            WHERE NFR_Lower_USD__c <= :nfr
              AND (NFR_Upper_USD__c >= :nfr OR NFR_Upper_USD__c = null)
            ORDER BY Row_Number__c ASC
            LIMIT 5
        ];
    }

    private static List<ET_Soft_Benefit_Tier__c> fetchSoftBenefit(Decimal nfr) {
        return [
            SELECT Tier_Label__c, NFR_Lower_USD__c, NFR_Upper_USD__c,
                   Free_Tickets__c, Free_Tickets_Active__c,
                   Free_Date_Changes__c, Free_Date_Changes_Active__c,
                   Baggage_Uplift_Kg__c, Baggage_Active__c,
                   Upgrades__c, Upgrades_Active__c,
                   Lounge_At_Origin__c, Lounge_Active__c
            FROM ET_Soft_Benefit_Tier__c
            WHERE NFR_Lower_USD__c <= :nfr
              AND (NFR_Upper_USD__c >= :nfr OR NFR_Upper_USD__c = null)
            LIMIT 1
        ];
    }

    private static String buildSummary(
        Corporate_Travel_RFP__c rfp,
        List<ET_Discount_Tier__c> rows,
        ET_Soft_Benefit_Tier__c soft
    ) {
        ET_Discount_Tier__c row1 = rows[0];
        String s = '## Negotiation Brief\n\n';
        s += '**Company:** ' + rfp.Company_Name__c + '\n';
        s += '**NFR Target:** ' + formatCurrency(rfp.Annual_NFR_Target_USD__c) + '\n';
        s += '**Qualifying Tier:** ' + row1.Tier_Label__c + '\n\n';
        s += '### Requested vs. Entitled Rates\n\n';
        s += '| Rate Type | Prospect Requested | Matrix Maximum (Row 1) |\n';
        s += '|---|---|---|\n';
        s += '| Economy Lower (T–K) | ' + (String.isBlank(rfp.Economy_Discount_Pct__c) ? '—' : rfp.Economy_Discount_Pct__c) + ' | ' + formatPct(row1.Economy_Lower_Pct__c) + ' |\n';
        s += '| Economy Higher (M–Y) | — | ' + formatPct(row1.Economy_Higher_Pct__c) + ' |\n';
        s += '| D Class | — | ' + formatPct(row1.D_Class_Pct__c) + ' |\n';
        s += '| J Class | — | ' + formatPct(row1.J_Class_Pct__c) + ' |\n';
        s += '| C Class | ' + (String.isBlank(rfp.Business_Discount_Pct__c) ? '—' : rfp.Business_Discount_Pct__c) + ' | ' + formatPct(row1.C_Class_Pct__c) + ' |\n\n';
        s += '### Tier Rate Options (Rows 1–' + rows.size() + ')\n\n';
        s += '| Row | Eco Lower | Eco Higher | D | J | C | Soft Options | Routing |\n';
        s += '|---|---|---|---|---|---|---|---|\n';
        for (ET_Discount_Tier__c r : rows) {
            s += '| ' + r.Row_Number__c + ' | ' + formatPct(r.Economy_Lower_Pct__c) +
                 ' | ' + formatPct(r.Economy_Higher_Pct__c) +
                 ' | ' + formatPct(r.D_Class_Pct__c) +
                 ' | ' + formatPct(r.J_Class_Pct__c) +
                 ' | ' + formatPct(r.C_Class_Pct__c) +
                 ' | ' + (r.Soft_Options_Count__c != null ? String.valueOf(r.Soft_Options_Count__c.intValue()) : '—') +
                 ' | ' + (r.Routing_Scope__c != null ? r.Routing_Scope__c : '—') + ' |\n';
        }
        if (soft != null) {
            s += '\n### Soft Benefits Allocation (active only)\n\n';
            if (soft.Free_Tickets_Active__c && soft.Free_Tickets__c != null && soft.Free_Tickets__c > 0)
                s += '- Free tickets: ' + soft.Free_Tickets__c.intValue() + '\n';
            if (soft.Free_Date_Changes_Active__c && soft.Free_Date_Changes__c != null && soft.Free_Date_Changes__c > 0)
                s += '- Free date changes: ' + soft.Free_Date_Changes__c.intValue() + '\n';
            if (soft.Baggage_Active__c && soft.Baggage_Uplift_Kg__c != null && soft.Baggage_Uplift_Kg__c > 0)
                s += '- Baggage uplift: ' + soft.Baggage_Uplift_Kg__c.intValue() + ' kg\n';
            if (soft.Upgrades_Active__c && soft.Upgrades__c != null && soft.Upgrades__c > 0)
                s += '- Upgrades: ' + soft.Upgrades__c.intValue() + '\n';
            if (soft.Lounge_Active__c && soft.Lounge_At_Origin__c)
                s += '- Lounge at origin: Yes\n';
        }
        s += '\n### Rule 2 — Non-Commissionable Uplift\n\n';
        s += '**Eligibility:** Non-commissionable agreements only (requires manager confirmation).\n';
        s += '**Range:** 1–4% additional discount across all fare classes.\n';
        if (rfp.Offer_Rule2_Uplift_Applied__c) {
            s += '**Status:** Uplift of ' + formatPct(rfp.Offer_Rule2_Uplift_Pct__c)
                + ' applied — awaiting manager approval.\n';
        } else {
            s += '**Status:** Not applied. Tell the agent you want a Rule 2 uplift if eligible.\n';
        }
        return s;
    }

    private static RfpNegotiationBriefData buildBriefDisplay(
        Corporate_Travel_RFP__c rfp,
        List<ET_Discount_Tier__c> rows,
        ET_Soft_Benefit_Tier__c soft
    ) {
        Map<String, Object> data = new Map<String, Object>();

        data.put('header', new Map<String, Object>{
            'companyName' => rfp.Company_Name__c,
            'nfrTarget' => formatCurrency(rfp.Annual_NFR_Target_USD__c),
            'qualifyingTier' => rows.isEmpty() ? '—' : rows[0].Tier_Label__c,
            'requestedEconomy' => String.isBlank(rfp.Economy_Discount_Pct__c) ? '—' : rfp.Economy_Discount_Pct__c,
            'requestedBusiness' => String.isBlank(rfp.Business_Discount_Pct__c) ? '—' : rfp.Business_Discount_Pct__c
        });

        List<Map<String, Object>> rowList = new List<Map<String, Object>>();
        for (ET_Discount_Tier__c r : rows) {
            rowList.add(new Map<String, Object>{
                'rowNumber' => r.Row_Number__c != null ? r.Row_Number__c.intValue() : 0,
                'ecoLower' => formatPct(r.Economy_Lower_Pct__c),
                'ecoHigher' => formatPct(r.Economy_Higher_Pct__c),
                'dClass' => formatPct(r.D_Class_Pct__c),
                'jClass' => formatPct(r.J_Class_Pct__c),
                'cClass' => formatPct(r.C_Class_Pct__c),
                'softOptions' => r.Soft_Options_Count__c != null ? r.Soft_Options_Count__c.intValue() : 0,
                'routing' => r.Routing_Scope__c != null ? r.Routing_Scope__c : '—'
            });
        }
        data.put('discountRows', rowList);

        if (soft != null) {
            data.put('softBenefits', new Map<String, Object>{
                'freeTickets'    => (soft.Free_Tickets_Active__c    && soft.Free_Tickets__c    != null) ? soft.Free_Tickets__c.intValue()    : 0,
                'freeDateChanges'=> (soft.Free_Date_Changes_Active__c && soft.Free_Date_Changes__c != null) ? soft.Free_Date_Changes__c.intValue() : 0,
                'baggageUpliftKg'=> (soft.Baggage_Active__c         && soft.Baggage_Uplift_Kg__c != null) ? soft.Baggage_Uplift_Kg__c.intValue() : 0,
                'upgrades'       => (soft.Upgrades_Active__c        && soft.Upgrades__c        != null) ? soft.Upgrades__c.intValue()        : 0,
                'loungeAtOrigin' => soft.Lounge_Active__c && soft.Lounge_At_Origin__c
            });
        }

        // Assessment: compare prospect's requested rates vs all available rows at this tier
        if (!rows.isEmpty()) {
            ET_Discount_Tier__c maxRow = rows[rows.size() - 1];
            Integer maxRowNum = rows.size();
            Decimal reqEco = parseReqPct(rfp.Economy_Discount_Pct__c);
            Decimal reqBus = parseReqPct(rfp.Business_Discount_Pct__c);

            // Find minimum row number that covers each requested rate
            Integer rowReqEco = null;
            Integer rowReqBus = null;
            for (ET_Discount_Tier__c r : rows) {
                Integer rn = r.Row_Number__c != null ? r.Row_Number__c.intValue() : 0;
                if (reqEco != null && rowReqEco == null && r.Economy_Lower_Pct__c != null && reqEco <= r.Economy_Lower_Pct__c) {
                    rowReqEco = rn;
                }
                if (reqBus != null && rowReqBus == null && r.C_Class_Pct__c != null && reqBus <= r.C_Class_Pct__c) {
                    rowReqBus = rn;
                }
            }

            List<Map<String, Object>> comparisons = new List<Map<String, Object>>();
            if (reqEco != null) {
                comparisons.add(new Map<String, Object>{
                    'label' => 'Economy Lower (T-K)',
                    'requested' => rfp.Economy_Discount_Pct__c,
                    'matrixMax' => formatPct(maxRow.Economy_Lower_Pct__c),
                    'exceeds' => reqEco > maxRow.Economy_Lower_Pct__c,
                    'rowRequired' => rowReqEco,
                    'maxRowNumber' => maxRowNum
                });
            }
            if (reqBus != null) {
                comparisons.add(new Map<String, Object>{
                    'label' => 'C Class (Business)',
                    'requested' => rfp.Business_Discount_Pct__c,
                    'matrixMax' => formatPct(maxRow.C_Class_Pct__c),
                    'exceeds' => reqBus > maxRow.C_Class_Pct__c,
                    'rowRequired' => rowReqBus,
                    'maxRowNumber' => maxRowNum
                });
            }
            if (!comparisons.isEmpty()) {
                Boolean anyExceeds = false;
                Boolean requiresEscalation = false;
                for (Map<String, Object> c : comparisons) {
                    if ((Boolean)c.get('exceeds')) { anyExceeds = true; requiresEscalation = true; }
                    Integer rr = (Integer)c.get('rowRequired');
                    if (rr != null && rr > 1) requiresEscalation = true;
                }
                data.put('assessment', new Map<String, Object>{
                    'comparisons' => comparisons,
                    'anyExceeds' => anyExceeds,
                    'requiresEscalation' => requiresEscalation
                });
            }
        }

        String rule2Status = rfp.Offer_Rule2_Uplift_Applied__c
            ? 'Applied — ' + formatPct(rfp.Offer_Rule2_Uplift_Pct__c) + ' uplift pending approval'
            : 'Not applied. Eligible for non-commissionable agreements (1–4%). Request conversationally.';
        data.put('rule2Note', rule2Status);

        return new RfpNegotiationBriefData(JSON.serialize(data));
    }

    private static String buildSoftBenefitQuestion(Integer optionCount, ET_Soft_Benefit_Tier__c soft) {
        if (optionCount == null || optionCount == 0) return '';
        Integer ticketCount = (soft != null && soft.Free_Tickets__c != null)
            ? soft.Free_Tickets__c.intValue() : 1;
        String ticketLabel = ticketCount == 1 ? 'complimentary ticket' : 'complimentary tickets';
        String ticketLine = '2. Free ticket at end of term (§2.3) — ' + ticketCount + ' '
            + ticketLabel + ' awarded at the end of the contract term per the incentive tier table';
        String intro;
        if (optionCount == 1) {
            intro = 'Your selected discount offer includes 1 soft benefit option. Choose 1 from the following — or none if you prefer:';
        } else if (optionCount == 2) {
            intro = 'Your selected discount offer includes 2 soft benefit options. Choose up to 2 from the following — or none if you prefer:';
        } else {
            intro = 'Which soft benefits would you like to include in this contract? Choose any combination — or none if you prefer:';
        }
        return intro + '\n'
            + '1. Free date change (§2.2) — one free date change per year for bookings on restricted booking days (RBD) above the qualifying threshold\n'
            + ticketLine + '\n'
            + '3. Skylight Hotel 20% discount (§2.2) — 20% off the best available daily room rate at Skylight Hotel';
    }

    private static String buildRateAssessment(Corporate_Travel_RFP__c rfp, List<ET_Discount_Tier__c> rows) {
        ET_Discount_Tier__c row1 = rows[0];
        Decimal reqEco = parseReqPct(rfp.Economy_Discount_Pct__c);
        Decimal reqBus = parseReqPct(rfp.Business_Discount_Pct__c);

        if (reqEco == null && reqBus == null) {
            return 'No specific discount rates requested — present the full matrix for the rep to evaluate.';
        }

        List<String> findings = new List<String>();
        Boolean anyExceeds = false;

        if (reqEco != null && row1.Economy_Lower_Pct__c != null) {
            Boolean exceeds = reqEco > row1.Economy_Lower_Pct__c;
            if (exceeds) anyExceeds = true;
            findings.add('Economy discount ' + formatPct(reqEco)
                + (exceeds ? ' EXCEEDS' : ' is within')
                + ' the pre-approved Row 1 maximum (' + formatPct(row1.Economy_Lower_Pct__c) + ').');
        }
        if (reqBus != null && row1.C_Class_Pct__c != null) {
            Boolean exceeds = reqBus > row1.C_Class_Pct__c;
            if (exceeds) anyExceeds = true;
            findings.add('Business class (C/J) discount ' + formatPct(reqBus)
                + (exceeds ? ' EXCEEDS' : ' is within')
                + ' the pre-approved Row 1 maximum (' + formatPct(row1.C_Class_Pct__c) + ').');
        }

        String conclusion = anyExceeds
            ? 'One or more rates EXCEED the pre-approved Row 1 maximum — manager escalation and approval will be required before a contract can be generated.'
            : 'All requested rates are within the pre-approved Row 1 matrix — can proceed to contract generation without approval.';
        findings.add(conclusion);

        return String.join(findings, ' ');
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) return '—';
        if (amount >= 1000000) {
            return '$' + (amount / 1000000).setScale(0) + 'M';
        }
        if (amount >= 1000) {
            return '$' + (amount / 1000).setScale(0) + 'K';
        }
        return '$' + amount.setScale(0);
    }

    private static String formatPct(Decimal pct) {
        return pct != null ? pct.setScale(2) + '%' : '—';
    }

    private static Decimal parseReqPct(String s) {
        if (String.isBlank(s)) return null;
        try {
            String clean = s.trim();
            Integer pctPos = clean.indexOf('%');
            if (pctPos > 0) clean = clean.substring(0, pctPos);
            return Decimal.valueOf(clean.trim());
        } catch (Exception e) {
            return null;
        }
    }
}