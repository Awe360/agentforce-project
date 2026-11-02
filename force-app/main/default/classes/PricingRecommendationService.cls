public with sharing class PricingRecommendationService {

    public class Input {
        @InvocableVariable(required=true label='RFP Id')
        public Id rfpId;
    }

    public class Output {
        @InvocableVariable public Boolean tierFound;
        @InvocableVariable public String errorMessage;

        // Tier-level context
        @InvocableVariable public String tierLabel;
        @InvocableVariable public String routingScope;
        @InvocableVariable public String availableBenefitsSummary;

        // Human-readable multi-row table for agent to present to the rep
        @InvocableVariable public String offerOptionsSummary;

        // All rows as JSON so the agent has numeric values when calling WriteApprovedRates
        // Format: [{"row":1,"economyLower":5.0,"economyHigher":6.0,"dClass":6.0,"jClass":7.0,"cClass":8.0,"softOptions":3}, ...]
        @InvocableVariable public String allRowsJson;

        // Row 1 (default offer) fields surfaced individually for convenience
        @InvocableVariable public Decimal row1EconomyLowerPct;
        @InvocableVariable public Decimal row1EconomyHigherPct;
        @InvocableVariable public Decimal row1DClassPct;
        @InvocableVariable public Decimal row1JClassPct;
        @InvocableVariable public Decimal row1CClassPct;
        @InvocableVariable public Integer row1SoftOptionsCount;
    }

    @InvocableMethod(
        label='Get Pricing Recommendation'
        description='Returns all pricing rows for the qualifying tier and available soft benefits. Read-only — does not modify the RFP. Call WriteApprovedRates to commit the rep\'s chosen offer.'
        category='Corporate Travel'
    )
    public static List<Output> calculate(List<Input> inputs) {
        List<Output> outputs = new List<Output>();
        for (Input inp : inputs) {
            outputs.add(run(inp.rfpId));
        }
        return outputs;
    }

    @TestVisible
    static Output run(Id rfpId) {
        Output out = new Output();

        Corporate_Travel_RFP__c rfp = [
            SELECT Annual_NFR_Target_USD__c
            FROM Corporate_Travel_RFP__c
            WHERE Id = :rfpId
            LIMIT 1
        ];

        Decimal nfr = rfp.Annual_NFR_Target_USD__c;
        if (nfr == null || nfr <= 0) {
            out.tierFound = false;
            out.errorMessage = 'Annual NFR Target is not set on this RFP';
            return out;
        }

        // Retrieve all rows for the qualifying tier, ordered Row 1 first
        List<ET_Discount_Tier__c> allRows = [
            SELECT Tier_Label__c, Row_Number__c, Soft_Options_Count__c,
                   Economy_Lower_Pct__c, Economy_Higher_Pct__c,
                   D_Class_Pct__c, J_Class_Pct__c, C_Class_Pct__c,
                   Routing_Scope__c
            FROM ET_Discount_Tier__c
            WHERE NFR_Lower_USD__c <= :nfr
            AND (NFR_Upper_USD__c >= :nfr OR NFR_Upper_USD__c = null)
            ORDER BY Row_Number__c ASC
        ];

        if (allRows.isEmpty()) {
            out.tierFound = false;
            out.errorMessage = 'No pricing tier found for NFR target $' + nfr.setScale(0).toPlainString();
            return out;
        }

        ET_Discount_Tier__c row1 = allRows[0];
        out.tierFound = true;
        out.tierLabel = row1.Tier_Label__c;
        out.routingScope = row1.Routing_Scope__c;

        // Row 1 individual fields for easy WriteApprovedRates consumption
        out.row1EconomyLowerPct  = row1.Economy_Lower_Pct__c;
        out.row1EconomyHigherPct = row1.Economy_Higher_Pct__c;
        out.row1DClassPct        = row1.D_Class_Pct__c;
        out.row1JClassPct        = row1.J_Class_Pct__c;
        out.row1CClassPct        = row1.C_Class_Pct__c;
        out.row1SoftOptionsCount = row1.Soft_Options_Count__c != null ? Integer.valueOf(row1.Soft_Options_Count__c) : 0;

        // Build JSON for all rows (agent uses this when calling WriteApprovedRates for any row)
        List<Map<String, Object>> rowsList = new List<Map<String, Object>>();
        for (ET_Discount_Tier__c r : allRows) {
            rowsList.add(new Map<String, Object>{
                'row'          => Integer.valueOf(r.Row_Number__c),
                'economyLower' => r.Economy_Lower_Pct__c,
                'economyHigher'=> r.Economy_Higher_Pct__c,
                'dClass'       => r.D_Class_Pct__c,
                'jClass'       => r.J_Class_Pct__c,
                'cClass'       => r.C_Class_Pct__c,
                'softOptions'  => r.Soft_Options_Count__c != null ? Integer.valueOf(r.Soft_Options_Count__c) : 0
            });
        }
        out.allRowsJson = JSON.serialize(rowsList);

        // Human-readable summary for agent presentation
        out.offerOptionsSummary = buildOptionsSummary(row1.Tier_Label__c, row1.Routing_Scope__c, allRows);

        // Soft benefits for this tier
        List<ET_Soft_Benefit_Tier__c> benefits = [
            SELECT Free_Tickets__c, Free_Tickets_Active__c,
                   Free_Date_Changes__c, Free_Date_Changes_Active__c,
                   Baggage_Uplift_Kg__c, Baggage_Active__c,
                   Upgrades__c, Upgrades_Active__c,
                   Lounge_At_Origin__c, Lounge_Active__c,
                   Skylight_Hotel_Active__c
            FROM ET_Soft_Benefit_Tier__c
            WHERE NFR_Lower_USD__c <= :nfr
            AND (NFR_Upper_USD__c >= :nfr OR NFR_Upper_USD__c = null)
            ORDER BY NFR_Lower_USD__c DESC
            LIMIT 1
        ];
        out.availableBenefitsSummary = buildBenefitSummary(benefits.isEmpty() ? null : benefits[0]);

        return out;
    }

    private static String buildOptionsSummary(String tierLabel, String routing, List<ET_Discount_Tier__c> rows) {
        List<String> lines = new List<String>();
        lines.add('Qualifying tier: ' + tierLabel + ' | Routing scope: ' + routing);
        lines.add('Row 1 is the default (minimum discount / maximum soft benefits). Rows 2+ require manager approval.');
        lines.add('');
        lines.add('     | Economy T–K | Economy M–Y | Business D | Business J | Business C | Soft Options');
        lines.add('-----+-------------+-------------+------------+------------+------------+-------------');
        for (ET_Discount_Tier__c r : rows) {
            Integer row = Integer.valueOf(r.Row_Number__c);
            Integer soft = r.Soft_Options_Count__c != null ? Integer.valueOf(r.Soft_Options_Count__c) : 0;
            String defaultTag = (row == 1) ? ' (default)' : '';
            lines.add(
                'Row ' + row + defaultTag + ' | ' +
                pct(r.Economy_Lower_Pct__c)  + ' | ' +
                pct(r.Economy_Higher_Pct__c) + ' | ' +
                pct(r.D_Class_Pct__c)        + ' | ' +
                pct(r.J_Class_Pct__c)        + ' | ' +
                pct(r.C_Class_Pct__c)        + ' | ' +
                soft
            );
        }
        return String.join(lines, '\n');
    }

    private static String pct(Decimal val) {
        return val != null ? val.setScale(2).toPlainString() + '%' : 'N/A';
    }

    private static String buildBenefitSummary(ET_Soft_Benefit_Tier__c b) {
        if (b == null) return 'No soft benefits data found for this tier';

        List<String> parts = new List<String>();

        Integer tickets = b.Free_Tickets__c != null ? Integer.valueOf(b.Free_Tickets__c) : 0;
        if (b.Free_Tickets_Active__c && tickets > 0) {
            parts.add(tickets + ' free ticket' + (tickets > 1 ? 's' : '') + ' (awarded on annual target achievement)');
        }

        Integer changes = b.Free_Date_Changes__c != null ? Integer.valueOf(b.Free_Date_Changes__c) : 0;
        if (b.Free_Date_Changes_Active__c && changes > 0) {
            parts.add(changes + ' free date change' + (changes > 1 ? 's' : ''));
        }

        Integer baggage = b.Baggage_Uplift_Kg__c != null ? Integer.valueOf(b.Baggage_Uplift_Kg__c) : 0;
        if (b.Baggage_Active__c && baggage > 0) {
            parts.add(baggage + 'kg extra baggage allowance');
        }

        Integer upgrades = b.Upgrades__c != null ? Integer.valueOf(b.Upgrades__c) : 0;
        if (b.Upgrades_Active__c && upgrades > 0) {
            parts.add(upgrades + ' upgrade voucher' + (upgrades > 1 ? 's' : ''));
        }

        if (b.Lounge_Active__c && b.Lounge_At_Origin__c) {
            parts.add('lounge access at origin');
        }

        if (b.Skylight_Hotel_Active__c) {
            parts.add('20% Skylight Hotel discount');
        }

        return parts.isEmpty() ? 'No soft benefits currently available for this tier' : String.join(parts, '; ');
    }
}