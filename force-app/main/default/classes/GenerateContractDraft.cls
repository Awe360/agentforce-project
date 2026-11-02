public with sharing class GenerateContractDraft {

    public class Request {
        @InvocableVariable(required=true description='Corporate_Travel_RFP__c record Id')
        public Id rfpId;
        @InvocableVariable(description='Include free date changes clause in Annex I section 2.2')
        public Boolean includeFreeDateChanges;
        @InvocableVariable(description='Include free tickets at end of term clause in Annex I section 2.3')
        public Boolean includeFreeTickets;
        @InvocableVariable(description='Include Skylight Hotel discount in Annex I section 2.2')
        public Boolean includeHotelDiscount;
        @InvocableVariable(description='Full name of the Ethiopian Airlines signatory (e.g. Yohannes Tefera)')
        public String etSignatoryName;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;
        @InvocableVariable public Integer contractVersion;
        @InvocableVariable public String contentDocumentId;
    }

    @InvocableMethod(
        label='Generate Contract Draft'
        description='Generates a Word contract draft from the approved offer and stores it as a Salesforce File on the RFP record.'
        category='Corporate Travel'
    )
    public static List<Result> generate(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) out.add(process(r));
        return out;
    }

    private static Result process(Request req) {
        Result res = new Result();
        try {
            Corporate_Travel_RFP__c rfp = [
                SELECT Offer_Matrix_Row__c, Pricing_Approval_Status__c,
                       Offer_Contract_Version__c, Offer_Contract_Template__c,
                       Company_Name__c, Address__c, City__c, Country__c, Website__c,
                       Contact_Email__c, Contact_Name__c, Corporate_ID__c,
                       Annual_NFR_Target_USD__c, Annual_NFR_Target_Quarterly__c,
                       Offer_Economy_Lower_Pct__c, Offer_Economy_Higher_Pct__c,
                       Offer_D_Class_Pct__c, Offer_J_Class_Pct__c, Offer_C_Class_Pct__c,
                       Offer_Routing_Scope__c
                FROM Corporate_Travel_RFP__c WHERE Id = :req.rfpId LIMIT 1
            ];

            // Gate: row 1 always passes; row 2+ requires Approved status
            Integer row = rfp.Offer_Matrix_Row__c != null ? rfp.Offer_Matrix_Row__c.intValue() : 0;
            String status = rfp.Pricing_Approval_Status__c;
            if (row != 1 && !'Approved'.equalsIgnoreCase(status)) {
                res.success = false;
                res.errorMessage = 'Offer must be approved before generating a contract. Current status: '
                    + (status != null ? status : 'Not submitted for approval');
                return res;
            }

            // Soft benefit count gate — enforce tier entitlement before touching DGP
            if (rfp.Offer_Matrix_Row__c != null) {
                Decimal nfrForQuery = rfp.Annual_NFR_Target_USD__c != null ? rfp.Annual_NFR_Target_USD__c : 0;
                List<ET_Discount_Tier__c> dRows = [
                    SELECT Soft_Options_Count__c FROM ET_Discount_Tier__c
                    WHERE Row_Number__c = :rfp.Offer_Matrix_Row__c
                    AND NFR_Lower_USD__c <= :nfrForQuery
                    AND (NFR_Upper_USD__c >= :nfrForQuery OR NFR_Upper_USD__c = null)
                    LIMIT 1
                ];
                Integer maxSoft = (!dRows.isEmpty() && dRows[0].Soft_Options_Count__c != null)
                    ? dRows[0].Soft_Options_Count__c.intValue() : 0;
                Integer selectedCount = 0;
                if (req.includeFreeDateChanges == true) selectedCount++;
                if (req.includeFreeTickets    == true) selectedCount++;
                if (req.includeHotelDiscount  == true) selectedCount++;
                if (selectedCount > maxSoft) {
                    res.success = false;
                    res.errorMessage = 'Soft benefit limit: the accepted offer allows '
                        + maxSoft + ' soft benefit' + (maxSoft == 1 ? '' : 's')
                        + ', but ' + selectedCount + ' were selected.'
                        + ' Ask the rep to choose within the limit and try again.';
                    return res;
                }
            }

            // Version overflow guard — field is Number(3,0)
            Integer currentVersion = rfp.Offer_Contract_Version__c != null
                ? rfp.Offer_Contract_Version__c.intValue() : 0;
            if (currentVersion >= 999) {
                res.success = false;
                res.errorMessage = 'Contract version limit reached (999). Contact your system administrator to reset.';
                return res;
            }
            Integer nextVersion = currentVersion + 1;

            // Template check
            String picklistValue = rfp.Offer_Contract_Template__c;
            if (String.isBlank(picklistValue)) {
                res.success = false;
                res.errorMessage = 'No DocumentTemplate configured. Set Offer_Contract_Template__c on this RFP to proceed.';
                return res;
            }

            // Resolve ContentVersionId from DocumentTemplate
            String contentVersionId = resolveContentVersionId(picklistValue);
            if (String.isBlank(contentVersionId)) {
                res.success = false;
                res.errorMessage = 'DocumentTemplate not found for template selection: ' + picklistValue;
                return res;
            }

            // Query Travel Agencies, Routes, and matching Soft Benefit Tier
            List<Travel_Agency__c> agencies = [
                SELECT IATA_Name__c, IATA_Number__c, PCC__c, GDS__c
                FROM Travel_Agency__c
                WHERE Corporate_Travel_RFP__c = :req.rfpId
                ORDER BY IATA_Name__c
            ];

            List<Travel_Route__c> routes = [
                SELECT Origin__c, Destination__c
                FROM Travel_Route__c
                WHERE Corporate_Travel_RFP__c = :req.rfpId
                ORDER BY Origin__c, Destination__c
            ];

            Decimal nfr = rfp.Annual_NFR_Target_USD__c != null ? rfp.Annual_NFR_Target_USD__c : 0;
            List<ET_Soft_Benefit_Tier__c> tiers = [
                SELECT NFR_Lower_USD__c, NFR_Upper_USD__c, Free_Tickets__c
                FROM ET_Soft_Benefit_Tier__c
                WHERE NFR_Lower_USD__c <= :nfr
                AND (NFR_Upper_USD__c >= :nfr OR NFR_Upper_USD__c = null)
                ORDER BY NFR_Lower_USD__c DESC LIMIT 1
            ];

            // Auto-generate Corporate ID before building token data so {{CorporateId}} renders correctly
            if (String.isBlank(rfp.Corporate_ID__c)) {
                rfp.Corporate_ID__c = generateCorporateId(req.rfpId);
            }

            String safeCompanyName = String.isNotBlank(rfp.Company_Name__c)
                ? rfp.Company_Name__c.replaceAll('[^a-zA-Z0-9]', '') : 'Unknown';
            String contractTitle = rfp.Corporate_ID__c
                + '_' + safeCompanyName
                + '_' + DateTime.now().format('yyyyMMddHHmmss');

            String tokenDataJson = JSON.serialize(
                buildTokenData(rfp, agencies, routes, tiers.isEmpty() ? null : tiers[0], req)
            );

            // Write version, date, corporate ID, and status synchronously
            Corporate_Travel_RFP__c versionUpdate = new Corporate_Travel_RFP__c(
                Id                               = req.rfpId,
                Offer_Contract_Generated_Date__c = Date.today(),
                Offer_Contract_Version__c        = nextVersion,
                Corporate_ID__c                  = rfp.Corporate_ID__c,
                Status__c                        = 'Contract Draft'
            );
            update versionUpdate;

            // Start async DGP pipeline via Queueable
            System.enqueueJob(new ContractGenPoller(req.rfpId, contentVersionId, tokenDataJson, contractTitle));

            res.success         = true;
            res.contractVersion = nextVersion;

        } catch (Exception e) {
            res.success      = false;
            res.errorMessage = e.getMessage();
        }
        return res;
    }

    @TestVisible
    private static String resolveContentVersionId(String picklistValue) {
        if (Test.isRunningTest()) return 'TEST_MOCK_CV_ID';

        String templateName = 'Main'.equalsIgnoreCase(picklistValue)
            ? 'ET Standard Corporate Agreement'
            : picklistValue;

        List<DocumentTemplate> templates = [
            SELECT Id FROM DocumentTemplate
            WHERE Name = :templateName LIMIT 1
        ];
        if (templates.isEmpty()) return null;

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :templates[0].Id
            ORDER BY ContentDocument.CreatedDate DESC LIMIT 1
        ];
        if (links.isEmpty()) return null;

        return links[0].ContentDocument.LatestPublishedVersionId;
    }

    private static Map<String, Object> buildTokenData(
        Corporate_Travel_RFP__c rfp,
        List<Travel_Agency__c> agencies,
        List<Travel_Route__c> routes,
        ET_Soft_Benefit_Tier__c tier,
        Request req
    ) {
        String etOfficeCity = 'Requesting Station Only'.equalsIgnoreCase(rfp.Offer_Routing_Scope__c)
            ? (rfp.City__c != null ? rfp.City__c : (rfp.Address__c != null ? rfp.Address__c : ''))
            : 'all ET online stations';

        // Corporate_ID__c is guaranteed non-blank here (auto-generated in process() if needed)
        String corpIdDisplay = String.isNotBlank(rfp.Corporate_ID__c)
            ? rfp.Corporate_ID__c
            : 'To be assigned on contract execution';

        String nfrRange = '';
        String freeTickets = '0';
        if (tier != null) {
            Decimal lower = tier.NFR_Lower_USD__c != null ? tier.NFR_Lower_USD__c : 0;
            Decimal upper = tier.NFR_Upper_USD__c;
            nfrRange = (upper != null && upper > 0)
                ? formatCurrency(lower) + ' – ' + formatCurrency(upper)
                : formatCurrency(lower) + '+';
            freeTickets = String.valueOf(tier.Free_Tickets__c != null ? tier.Free_Tickets__c.intValue() : 0);
        }

        Boolean incDateChanges  = req.includeFreeDateChanges == true;
        Boolean incFreeTickets  = req.includeFreeTickets == true;
        Boolean incHotel        = req.includeHotelDiscount == true;

        List<Map<String, String>> agencyRows = new List<Map<String, String>>();
        for (Travel_Agency__c a : agencies) {
            agencyRows.add(new Map<String, String>{
                'IATAName'   => a.IATA_Name__c != null ? a.IATA_Name__c : '',
                'IATANumber' => a.IATA_Number__c != null ? a.IATA_Number__c : '',
                'PCC'        => a.PCC__c != null ? a.PCC__c : '',
                'GDS'        => a.GDS__c != null ? a.GDS__c : ''
            });
        }

        // Build one row per route; each row carries all discount values so the loop renders correctly
        String ecoLower  = formatPct(rfp.Offer_Economy_Lower_Pct__c);
        String ecoHigher = formatPct(rfp.Offer_Economy_Higher_Pct__c);
        String dClass    = formatPct(rfp.Offer_D_Class_Pct__c);
        String jClass    = formatPct(rfp.Offer_J_Class_Pct__c);
        String cClass    = formatPct(rfp.Offer_C_Class_Pct__c);
        List<Map<String, String>> discountRouteRows = new List<Map<String, String>>();
        for (Travel_Route__c r : routes) {
            String routeLabel = (r.Origin__c != null ? r.Origin__c : '')
                + ' – ' + (r.Destination__c != null ? r.Destination__c : '');
            discountRouteRows.add(new Map<String, String>{
                'RouteLabel'      => routeLabel,
                'RouteSalesChannel' => 'Direct and indirect',
                'RouteEcoLower'   => ecoLower,
                'RouteEcoHigher'  => ecoHigher,
                'RouteD'          => dClass,
                'RouteJ'          => jClass,
                'RouteC'          => cClass
            });
        }
        if (discountRouteRows.isEmpty()) {
            discountRouteRows.add(new Map<String, String>{
                'RouteLabel'      => rfp.Offer_Routing_Scope__c != null ? rfp.Offer_Routing_Scope__c : '',
                'RouteSalesChannel' => 'Direct and indirect',
                'RouteEcoLower'   => ecoLower,
                'RouteEcoHigher'  => ecoHigher,
                'RouteD'          => dClass,
                'RouteJ'          => jClass,
                'RouteC'          => cClass
            });
        }

        String sigName = String.isNotBlank(req.etSignatoryName) ? req.etSignatoryName : '';

        return new Map<String, Object>{
            'CompanyName'           => rfp.Company_Name__c != null ? rfp.Company_Name__c : '',
            'Address'               => rfp.Address__c != null ? rfp.Address__c : '',
            'City'                  => rfp.City__c != null ? rfp.City__c : '',
            'Country'               => rfp.Country__c != null ? rfp.Country__c : '',
            'Website'               => rfp.Website__c != null ? rfp.Website__c : '',
            'ContactEmail'          => rfp.Contact_Email__c != null ? rfp.Contact_Email__c : '',
            'ContactName'           => rfp.Contact_Name__c != null ? rfp.Contact_Name__c : '',
            'CorporateId'           => corpIdDisplay,
            'SigningDate'           => DateTime.newInstance(Date.today(), Time.newInstance(0,0,0,0))
                                           .format('d MMMM yyyy'),
            // Template already prefixes "USD " before these tokens; return number only to avoid "USD USD"
            'AnnualNFRTarget'       => formatCurrencyAmount(rfp.Annual_NFR_Target_USD__c),
            'AnnualNFRQuarterly'    => formatCurrencyAmount(rfp.Annual_NFR_Target_Quarterly__c),
            'ETOfficeCity'          => etOfficeCity,
            'FreeDateChangeRBD'     => 'T/K',
            'NFRRange'              => nfrRange,
            'DiscountRoutes'        => discountRouteRows,
            'TravelAgencies'        => agencyRows,
            // Soft benefit conditional flags
            'IncludeSection22'      => incDateChanges || incHotel,
            'IncludeFreeDateChanges'=> incDateChanges,
            'IncludeHotelDiscount'  => incHotel,
            'IncludeFreeTickets'    => incFreeTickets,
            // Top-level token for the free tickets table cell (template uses bare {{FreeTickets}})
            'FreeTickets'           => freeTickets,
            // Clause number for the free tickets section: 2.2 if §2.2 block is skipped, else 2.3
            'FreeTicketsSectionRef' => (incDateChanges || incHotel) ? '2.3.' : '2.2.',
            // Free tickets table — one row for this client's tier (consumed by {{#SoftBenefitTiers}} loop)
            'SoftBenefitTiers'      => new List<Map<String, String>>{
                new Map<String, String>{ 'NFRRange' => nfrRange, 'FreeTickets' => freeTickets }
            },
            // ET signatory name — captured from rep during contract draft conversation
            'ETSignatoryName'       => sigName
        };
    }

    private static String formatCurrencyAmount(Decimal amount) {
        if (amount == null) return '0';
        Long v = amount.setScale(0).longValue();
        String s = String.valueOf(v);
        String result = '';
        Integer len = s.length();
        for (Integer i = 0; i < len; i++) {
            if (i > 0 && Math.mod(len - i, 3) == 0) result += ',';
            result += s.substring(i, i + 1);
        }
        return result;
    }

    private static String formatCurrency(Decimal amount) {
        if (amount == null) return 'USD 0';
        return 'USD ' + formatCurrencyAmount(amount);
    }

    private static String generateCorporateId(Id rfpId) {
        List<Corporate_Travel_RFP__c> existing = [
            SELECT Corporate_ID__c FROM Corporate_Travel_RFP__c
            WHERE Corporate_ID__c LIKE 'ETA%' AND Id != :rfpId
            ORDER BY Corporate_ID__c DESC LIMIT 1
        ];
        Integer num = 0;
        if (!existing.isEmpty()) {
            try {
                num = Integer.valueOf(existing[0].Corporate_ID__c.removeStart('ETA'));
            } catch (Exception e) {}
        }
        String numStr = String.valueOf(num + 1);
        while (numStr.length() < 3) numStr = '0' + numStr;
        return 'ETA' + numStr;
    }

    private static String formatPct(Decimal pct) {
        if (pct == null) return '0';
        return String.valueOf(pct.setScale(0).intValue());
    }

    public class ContractGenPoller implements Queueable {
        private final Id rfpId;
        private final String contentVersionId;
        private final String tokenDataJson;
        private final String contractTitle;
        private final Id dgpId;
        private final Integer attempt;
        private final Integer MAX_ATTEMPTS = 10;

        public ContractGenPoller(Id rfpId, String cvId, String tdJson, String title) {
            this(rfpId, cvId, tdJson, title, null, 0);
        }

        public ContractGenPoller(Id rfpId, String cvId, String tdJson, String title, Id dgpId, Integer attempt) {
            this.rfpId            = rfpId;
            this.contentVersionId = cvId;
            this.tokenDataJson    = tdJson;
            this.contractTitle    = title;
            this.dgpId            = dgpId;
            this.attempt          = attempt;
        }

        public void execute(QueueableContext ctx) {
            if (Test.isRunningTest()) {
                ContentVersion cv = new ContentVersion(
                    Title        = 'Test Contract Draft',
                    PathOnClient = 'test_contract.docx',
                    VersionData  = Blob.valueOf('test')
                );
                insert cv;
                Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
                writeBack(rfpId, docId);
                return;
            }

            if (dgpId == null) {
                // First execution: insert DGP
                DocumentGenerationProcess dgp = new DocumentGenerationProcess();
                dgp.Type           = 'Generate';
                dgp.RequestText    = JSON.serialize(new Map<String, Object>{
                    'templateContentVersionId' => contentVersionId,
                    'title'                    => contractTitle,
                    'keepIntermediate'         => false
                });
                dgp.TokenData          = tokenDataJson;
                dgp.DocGenApiVersionType = 'Basic';
                dgp.ReferenceObject    = String.valueOf(rfpId);
                insert dgp;
                if (attempt < MAX_ATTEMPTS) {
                    System.enqueueJob(new ContractGenPoller(rfpId, contentVersionId, tokenDataJson, contractTitle, dgp.Id, attempt + 1));
                }
                return;
            }

            // Polling: check DGP status
            DocumentGenerationProcess dgp = [
                SELECT Status, ResponseText FROM DocumentGenerationProcess WHERE Id = :dgpId
            ];
            if (dgp.Status == 'InProgress') {
                if (attempt < MAX_ATTEMPTS) {
                    System.enqueueJob(new ContractGenPoller(rfpId, contentVersionId, tokenDataJson, contractTitle, dgpId, attempt + 1));
                }
                return;
            }
            if (dgp.Status == 'Success' && String.isNotBlank(dgp.ResponseText)) {
                ContentVersion cv = [
                    SELECT ContentDocumentId FROM ContentVersion WHERE Id = :dgp.ResponseText LIMIT 1
                ];
                writeBack(rfpId, cv.ContentDocumentId);
            }
        }

        private void writeBack(Id rfpId, Id contentDocId) {
            List<ContentDocumentLink> existing = [
                SELECT Id FROM ContentDocumentLink
                WHERE ContentDocumentId = :contentDocId AND LinkedEntityId = :rfpId LIMIT 1
            ];
            if (existing.isEmpty()) {
                insert new ContentDocumentLink(
                    ContentDocumentId = contentDocId,
                    LinkedEntityId    = rfpId,
                    ShareType         = 'V'
                );
            }
            update new Corporate_Travel_RFP__c(
                Id                           = rfpId,
                Offer_Contract_Content_Id__c = contentDocId
            );
        }
    }
}