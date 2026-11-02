public with sharing class GetRfpOfferData {

    public class OfferData {
        @AuraEnabled public Boolean offerSet;
        @AuraEnabled public String  tierLabel;
        @AuraEnabled public Integer matrixRow;
        @AuraEnabled public Boolean isDefaultRow;
        @AuraEnabled public String  routingScope;
        @AuraEnabled public Decimal economyLowerPct;
        @AuraEnabled public Decimal economyHigherPct;
        @AuraEnabled public Decimal dClassPct;
        @AuraEnabled public Decimal jClassPct;
        @AuraEnabled public Decimal cClassPct;
        @AuraEnabled public Integer softOptionsCount;
        @AuraEnabled public Boolean rule2Applied;
        @AuraEnabled public Decimal rule2Pct;
        @AuraEnabled public Boolean escalationRequired;
        @AuraEnabled public String  escalationType;
        @AuraEnabled public String  escalationJustification;
        @AuraEnabled public String  approvalStatus;
        @AuraEnabled public List<BenefitItem> softBenefits;
    }

    public class BenefitItem {
        @AuraEnabled public String  label;
        @AuraEnabled public String  detail;
        @AuraEnabled public Boolean active;

        BenefitItem(String label, String detail, Boolean active) {
            this.label  = label;
            this.detail = detail;
            this.active = active;
        }
    }

    @AuraEnabled(cacheable=true)
    public static OfferData getOfferData(Id recordId) {
        Corporate_Travel_RFP__c rfp = [
            SELECT Annual_NFR_Target_USD__c,
                   Offer_Matrix_Tier__c, Offer_Matrix_Row__c, Offer_Routing_Scope__c,
                   Offer_Economy_Lower_Pct__c, Offer_Economy_Higher_Pct__c,
                   Offer_D_Class_Pct__c, Offer_J_Class_Pct__c, Offer_C_Class_Pct__c,
                   Offer_Soft_Options_Count__c,
                   Offer_Rule2_Uplift_Applied__c, Offer_Rule2_Uplift_Pct__c,
                   Escalation_Required__c, Escalation_Type__c, Escalation_Justification__c,
                   Pricing_Approval_Status__c
            FROM Corporate_Travel_RFP__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        OfferData d = new OfferData();
        d.offerSet           = rfp.Offer_Matrix_Tier__c != null;
        d.tierLabel          = rfp.Offer_Matrix_Tier__c;
        d.matrixRow          = rfp.Offer_Matrix_Row__c != null ? Integer.valueOf(rfp.Offer_Matrix_Row__c) : null;
        d.isDefaultRow       = d.matrixRow != null && d.matrixRow == 1;
        d.routingScope       = rfp.Offer_Routing_Scope__c;
        d.economyLowerPct    = rfp.Offer_Economy_Lower_Pct__c;
        d.economyHigherPct   = rfp.Offer_Economy_Higher_Pct__c;
        d.dClassPct          = rfp.Offer_D_Class_Pct__c;
        d.jClassPct          = rfp.Offer_J_Class_Pct__c;
        d.cClassPct          = rfp.Offer_C_Class_Pct__c;
        d.softOptionsCount   = rfp.Offer_Soft_Options_Count__c != null ? Integer.valueOf(rfp.Offer_Soft_Options_Count__c) : null;
        d.rule2Applied       = rfp.Offer_Rule2_Uplift_Applied__c;
        d.rule2Pct           = rfp.Offer_Rule2_Uplift_Pct__c;
        d.escalationRequired = rfp.Escalation_Required__c;
        d.escalationType     = rfp.Escalation_Type__c;
        d.escalationJustification = rfp.Escalation_Justification__c;
        d.approvalStatus     = rfp.Pricing_Approval_Status__c;
        d.softBenefits       = new List<BenefitItem>();

        if (rfp.Annual_NFR_Target_USD__c != null && rfp.Offer_Matrix_Tier__c != null) {
            Decimal nfr = rfp.Annual_NFR_Target_USD__c;
            List<ET_Soft_Benefit_Tier__c> rows = [
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

            if (!rows.isEmpty()) {
                ET_Soft_Benefit_Tier__c b = rows[0];

                Integer tickets = b.Free_Tickets__c != null ? Integer.valueOf(b.Free_Tickets__c) : 0;
                if (b.Free_Tickets_Active__c && tickets > 0) {
                    d.softBenefits.add(new BenefitItem('Free Tickets',
                        tickets + ' per year (awarded on target achievement)', true));
                }

                Integer changes = b.Free_Date_Changes__c != null ? Integer.valueOf(b.Free_Date_Changes__c) : 0;
                if (b.Free_Date_Changes_Active__c && changes > 0) {
                    d.softBenefits.add(new BenefitItem('Free Date Changes',
                        changes + ' per year', true));
                }

                Integer baggage = b.Baggage_Uplift_Kg__c != null ? Integer.valueOf(b.Baggage_Uplift_Kg__c) : 0;
                if (b.Baggage_Active__c && baggage > 0) {
                    d.softBenefits.add(new BenefitItem('Extra Baggage',
                        baggage + 'kg uplift allowance', true));
                }

                Integer upgrades = b.Upgrades__c != null ? Integer.valueOf(b.Upgrades__c) : 0;
                if (b.Upgrades_Active__c && upgrades > 0) {
                    d.softBenefits.add(new BenefitItem('Upgrade Vouchers',
                        upgrades + ' per year', true));
                }

                if (b.Lounge_Active__c && b.Lounge_At_Origin__c) {
                    d.softBenefits.add(new BenefitItem('Lounge Access',
                        'Origin airport', true));
                }

                if (b.Skylight_Hotel_Active__c) {
                    d.softBenefits.add(new BenefitItem('Skylight Hotel Discount',
                        '20% off for eligible clients', true));
                }
            }
        }

        return d;
    }
}