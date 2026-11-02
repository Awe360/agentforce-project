public without sharing class CorporateTravelRfpSave {

    public class Request {
        @InvocableVariable(label='Submission JSON' required=true
            description='The complete JSON payload from the RFP wizard form submission')
        public String submissionJSON;
    }

    public class Response {
        @InvocableVariable(label='Record ID')
        public String recordId;

        @InvocableVariable(label='Confirmation Message')
        public String confirmationMessage;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, String> saveRfpFromLwc(String submissionJSON) {
        Request req = new Request();
        req.submissionJSON = submissionJSON;
        Response res = processRequest(req);
        return new Map<String, String>{
            'recordId' => res.recordId,
            'confirmationMessage' => res.confirmationMessage
        };
    }

    @InvocableMethod(
        label='Save RFP Submission'
        description='Saves the completed Corporate Travel RFP form data and returns a confirmation reference.'
        category='Corporate Travel'
    )
    public static List<Response> saveRfpSubmission(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            responses.add(processRequest(req));
        }
        return responses;
    }

    private static Response processRequest(Request req) {
        Response res = new Response();
        try {
            Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(req.submissionJSON);

            // Extract document IDs — business licence and uploaded RFP source document are tracked separately
            String docIds    = str(d, 'contentDocumentIds');
            String rfpDocId  = str(d, 'rfpDocumentId');
            String firstLicenceDocId = null;
            if (String.isNotBlank(docIds)) {
                List<String> parts = docIds.split(',');
                if (!parts.isEmpty()) firstLicenceDocId = parts[0].trim();
            }

            // ── 1. Account ─────────────────────────────────────────────────
            String websiteRaw   = str(d, 'website');
            String websiteDomain = extractDomain(websiteRaw);

            Account acct;
            if (String.isNotBlank(websiteDomain)) {
                String domainPattern = '%' + websiteDomain + '%';
                List<Account> existing = [SELECT Id FROM Account WHERE Website LIKE :domainPattern LIMIT 1];
                if (!existing.isEmpty()) acct = existing[0];
            }
            if (acct == null) {
                acct = new Account(
                    Name          = str(d, 'companyName'),
                    Website       = websiteRaw,
                    BillingStreet    = str(d, 'street'),
                    BillingCity      = str(d, 'city'),
                    BillingState     = str(d, 'state'),
                    BillingPostalCode = str(d, 'postalCode'),
                    BillingCountry   = str(d, 'country'),
                    Description   = str(d, 'primaryLineOfBusiness')
                );
                insert acct;
            }

            // ── 2. Contact ─────────────────────────────────────────────────
            String contactEmail    = str(d, 'contactEmail');
            String contactFullName = str(d, 'contactName');

            Contact con;
            if (String.isNotBlank(contactEmail)) {
                List<Contact> byAcct = [SELECT Id FROM Contact WHERE Email = :contactEmail AND AccountId = :acct.Id LIMIT 1];
                if (!byAcct.isEmpty()) {
                    con = byAcct[0];
                } else {
                    List<Contact> byEmail = [SELECT Id FROM Contact WHERE Email = :contactEmail LIMIT 1];
                    if (!byEmail.isEmpty()) con = byEmail[0];
                }
            }
            if (con == null) {
                String firstName = '';
                String lastName  = String.isNotBlank(contactFullName) ? contactFullName : 'Unknown';
                if (String.isNotBlank(contactFullName)) {
                    Integer spaceIdx = contactFullName.indexOf(' ');
                    if (spaceIdx > 0) {
                        firstName = contactFullName.substring(0, spaceIdx);
                        lastName  = contactFullName.substring(spaceIdx + 1);
                    }
                }
                con = new Contact(
                    FirstName = firstName,
                    LastName  = String.isNotBlank(lastName) ? lastName : contactFullName,
                    Email     = contactEmail,
                    Phone     = str(d, 'contactPhone'),
                    AccountId = acct.Id
                );
                insert con;
            }

            // ── 3. Opportunity ─────────────────────────────────────────────
            String requestType = str(d, 'requestType');
            String stageName   = 'Renewal'.equalsIgnoreCase(requestType) ? 'Qualification' : 'Prospecting';

            Opportunity opp = new Opportunity(
                Name        = str(d, 'companyName') + ' — Corporate Travel RFP',
                AccountId   = acct.Id,
                StageName   = stageName,
                CloseDate   = Date.today().addDays(90),
                Amount      = dec(d, 'annualNfrTarget'),
                Description = str(d, 'nfrJustification')
            );
            insert opp;

            // ── 4. OpportunityContactRole ──────────────────────────────────
            try {
                insert new OpportunityContactRole(
                    OpportunityId = opp.Id,
                    ContactId     = con.Id,
                    Role          = 'Decision Maker',
                    IsPrimary     = true
                );
            } catch (Exception e) { /* OCR failure never blocks save */ }

            // ── 5. Corporate Travel RFP ────────────────────────────────────
            Corporate_Travel_RFP__c rfp = new Corporate_Travel_RFP__c(
                Opportunity__c                   = opp.Id,
                Company_Name__c                  = str(d, 'companyName'),
                Address__c                       = str(d, 'street'),
                City__c                          = str(d, 'city'),
                State__c                         = str(d, 'state'),
                PostalCode__c                    = str(d, 'postalCode'),
                Country__c                       = str(d, 'country'),
                Website__c                       = websiteRaw,
                Primary_Line_of_Business__c      = str(d, 'primaryLineOfBusiness'),
                Annual_Travel_Budget_USD__c       = dec(d, 'annualTravelBudget'),
                Contact_Name__c                  = contactFullName,
                Contact_Email__c                 = contactEmail,
                Contact_Phone__c                 = str(d, 'contactPhone'),
                Request_Type__c                  = requestType,
                Corporate_ID__c                  = str(d, 'corporateId'),
                NFR_Justification__c             = str(d, 'nfrJustification'),
                Annual_NFR_Target_USD__c          = dec(d, 'annualNfrTarget'),
                Economy_Discount_Pct__c          = str(d, 'economyDiscount'),
                Business_Discount_Pct__c         = str(d, 'businessDiscount'),
                Additional_Benefits__c           = str(d, 'additionalBenefits'),
                Ticket_Issuance_ET_Office__c     = bool(d, 'ticketIssuanceEtOffice'),
                Ticket_Issuance_GSA_Office__c    = bool(d, 'ticketIssuanceGsaOffice'),
                Ticket_Issuance_Travel_Agency__c = bool(d, 'ticketIssuanceTravelAgency'),
                Requested_By__c                  = str(d, 'requestedBy'),
                Submission_Date__c               = Date.today(),
                Status__c                        = 'New'
            );

            Object staffRaw = d.get('numberOfTravellingStaff');
            if (staffRaw != null && String.valueOf(staffRaw).trim() != '') {
                try { rfp.Number_of_Travelling_Staff__c = Integer.valueOf(String.valueOf(staffRaw)); } catch (Exception e) {}
            }
            if (String.isNotBlank(firstLicenceDocId)) {
                rfp.Licence_Document_Id__c = firstLicenceDocId;
            }
            if (String.isNotBlank(rfpDocId)) {
                rfp.RFP_Document_Id__c = rfpDocId;
            }

            insert rfp;

            // ── 6. Confirmation email ──────────────────────────────────────
            try {
                if (String.isNotBlank(contactEmail)) {
                    // In sandbox, only send to @salesforce.com or @ethiopianairlines.com
                    // to prevent accidental emails to live customer addresses.
                    // This check is skipped automatically in production.
                    Organization sandboxOrg = [SELECT IsSandbox FROM Organization LIMIT 1];
                    Boolean domainAllowed = true;
                    if (sandboxOrg.IsSandbox) {
                        String domain = contactEmail.contains('@')
                            ? contactEmail.substringAfterLast('@').toLowerCase() : '';
                        domainAllowed = new Set<String>{'salesforce.com', 'ethiopianairlines.com'}.contains(domain);
                    }

                    if (domainAllowed) {
                        String salutation = String.isNotBlank(contactFullName)
                            ? 'Dear ' + contactFullName + ','
                            : 'Dear Applicant,';
                        String companyNameStr = str(d, 'companyName');
                        String orgDomain = URL.getOrgDomainUrl().toExternalForm();
                        String siteDomain = orgDomain.replace('.my.salesforce.com', '.my.site.com');
                        String logoUrl = siteDomain
                            + '/etcorporatetravelvforcesitevforcesite/resource/etAirlineImages/logo.png';

                        String htmlBody =
                        '<!DOCTYPE html><html><body style="margin:0;padding:0;background-color:#f4f4f4;font-family:Arial,Helvetica,sans-serif;">'
                        + '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f4;">'
                        + '<tr><td align="center" style="padding:32px 16px;">'
                        + '<table width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;overflow:hidden;">'
                        // Header
                        + '<tr><td style="background-color:#1a5c38;padding:20px 32px;">'
                        + '<img src="' + logoUrl + '" alt="Ethiopian Airlines" height="44" style="display:block;" /></td></tr>'
                        // Gold accent strip
                        + '<tr><td style="background-color:#c8a951;height:4px;font-size:0;line-height:0;padding:0;">&#160;</td></tr>'
                        // Body
                        + '<tr><td style="padding:36px 32px;">'
                        + '<h2 style="margin:0 0 20px 0;color:#1a1a1a;font-size:20px;font-weight:bold;">Application Received</h2>'
                        + '<p style="margin:0 0 14px 0;color:#333333;font-size:15px;line-height:1.6;">' + salutation + '</p>'
                        + '<p style="margin:0 0 14px 0;color:#333333;font-size:15px;line-height:1.6;">'
                        + 'Thank you for submitting a Corporate Travel Request for Proposal to Ethiopian Airlines on behalf of '
                        + '<strong>' + companyNameStr + '</strong>.</p>'
                        + '<p style="margin:0 0 16px 0;color:#333333;font-size:15px;line-height:1.6;">Your application has been received. Your reference number is:</p>'
                        // Reference box
                        + '<table cellpadding="0" cellspacing="0" style="margin:0 0 24px 0;">'
                        + '<tr><td style="background-color:#f0f9f4;border:2px solid #00843D;border-radius:6px;padding:12px 24px;'
                        + 'font-family:monospace;font-size:14px;color:#00843D;font-weight:bold;">' + rfp.Id + '</td></tr></table>'
                        + '<p style="margin:0 0 14px 0;color:#333333;font-size:15px;line-height:1.6;">'
                        + 'Our Global Corporate Sales team will review your application and be in touch within <strong>2 working days</strong>.</p>'
                        + '<p style="margin:0;color:#333333;font-size:15px;line-height:1.6;">'
                        + 'If you have any questions, please contact us at '
                        + '<a href="mailto:GlobalCorporateSales@ethiopianairlines.com" style="color:#00843D;">'
                        + 'GlobalCorporateSales@ethiopianairlines.com</a>.</p>'
                        + '</td></tr>'
                        // Divider
                        + '<tr><td style="padding:0 32px;"><table width="100%" cellpadding="0" cellspacing="0">'
                        + '<tr><td style="border-top:1px solid #e5e5e5;font-size:0;">&nbsp;</td></tr></table></td></tr>'
                        // Footer
                        + '<tr><td style="padding:20px 32px;background-color:#f9f9f9;">'
                        + '<p style="margin:0;color:#999999;font-size:12px;line-height:1.8;">'
                        + 'Ethiopian Airlines Global Corporate Sales Team<br/>'
                        + '<a href="mailto:GlobalCorporateSales@ethiopianairlines.com" style="color:#999999;">'
                        + 'GlobalCorporateSales@ethiopianairlines.com</a></p></td></tr>'
                        + '</table></td></tr></table></body></html>';

                    String plainBody =
                        salutation + '\n\n'
                        + 'Thank you for submitting a Corporate Travel Request for Proposal to Ethiopian Airlines on behalf of '
                        + companyNameStr + '.\n\n'
                        + 'Your application has been received and assigned reference number: ' + rfp.Id + '\n\n'
                        + 'Our Global Corporate Sales team will review your application and be in touch within 2 working days.\n\n'
                        + 'If you have any questions, please contact us at GlobalCorporateSales@ethiopianairlines.com.\n\n'
                        + 'Best regards,\nEthiopian Airlines Global Corporate Sales Team';

                    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                    mail.setToAddresses(new String[]{ contactEmail });
                    mail.setSubject('Ethiopian Airlines Corporate Travel — Application Received');
                    List<OrgWideEmailAddress> owea = [SELECT Id FROM OrgWideEmailAddress
                        WHERE DisplayName = 'Ethiopian Airlines Global Corporate Sales'
                           OR DisplayName = 'ET No Reply Email Address'
                        ORDER BY DisplayName DESC LIMIT 1];
                    if (!owea.isEmpty()) mail.setOrgWideEmailAddressId(owea[0].Id);
                    mail.setHtmlBody(htmlBody);
                    mail.setPlainTextBody(plainBody);
                    mail.setTargetObjectId(con.Id);
                    mail.setWhatId(rfp.Id);
                    mail.setSaveAsActivity(true);
                    Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
                    } // end domainAllowed
                }
            } catch (Exception e) { /* email failure never blocks save */ }

            // ── 7. Travel Routes ──────────────────────────────────────────
            List<Object> routesRaw = (List<Object>) d.get('routes');
            if (routesRaw != null && !routesRaw.isEmpty()) {
                List<Travel_Route__c> routes = new List<Travel_Route__c>();
                for (Object ro : routesRaw) {
                    Map<String, Object> r = (Map<String, Object>) ro;
                    String origin = String.valueOf(r.get('origin')).toUpperCase().trim();
                    String dest   = String.valueOf(r.get('destination')).toUpperCase().trim();
                    if (String.isNotBlank(origin) && String.isNotBlank(dest)) {
                        routes.add(new Travel_Route__c(
                            Corporate_Travel_RFP__c = rfp.Id,
                            Origin__c               = origin,
                            Destination__c          = dest
                        ));
                    }
                }
                if (!routes.isEmpty()) insert routes;
            }

            // ── 8. Travel Agencies ────────────────────────────────────────
            List<Object> agenciesRaw = (List<Object>) d.get('travelAgencies');
            if (agenciesRaw != null && !agenciesRaw.isEmpty()) {
                List<Travel_Agency__c> agencies = new List<Travel_Agency__c>();
                for (Object ao : agenciesRaw) {
                    Map<String, Object> a = (Map<String, Object>) ao;
                    String iataName   = a.get('iataName')   != null ? String.valueOf(a.get('iataName')).trim()   : '';
                    String iataNumber = a.get('iataNumber') != null ? String.valueOf(a.get('iataNumber')).trim() : '';
                    String pcc        = a.get('pcc')        != null ? String.valueOf(a.get('pcc')).trim()        : '';
                    String gds        = a.get('gds')        != null ? String.valueOf(a.get('gds')).trim()        : '';
                    if (String.isBlank(iataName) && String.isBlank(iataNumber) && String.isBlank(pcc) && String.isBlank(gds)) continue;
                    agencies.add(new Travel_Agency__c(
                        Corporate_Travel_RFP__c = rfp.Id,
                        IATA_Name__c            = iataName,
                        IATA_Number__c          = iataNumber,
                        PCC__c                  = pcc,
                        GDS__c                  = gds
                    ));
                }
                if (!agencies.isEmpty()) insert agencies;
            }

            // ── 9. Document links (business licence + RFP source → record + opportunity) ─────
            try {
                List<ContentDocumentLink> links = new List<ContentDocumentLink>();
                for (String docId : new List<String>{ docIds, rfpDocId }) {
                    if (String.isBlank(docId)) continue;
                    for (String part : docId.split(',')) {
                        String trimmed = part.trim();
                        if (String.isBlank(trimmed)) continue;
                        links.add(new ContentDocumentLink(ContentDocumentId = trimmed, LinkedEntityId = rfp.Id, ShareType = 'V', Visibility = 'AllUsers'));
                        links.add(new ContentDocumentLink(ContentDocumentId = trimmed, LinkedEntityId = opp.Id, ShareType = 'V', Visibility = 'AllUsers'));
                    }
                }
                if (!links.isEmpty()) insert links;
            } catch (Exception e) { /* file link failure never blocks save */ }

            res.recordId = rfp.Id;
            res.confirmationMessage = 'Your proposal has been received. Reference: ' + rfp.Id
                + '. Our Global Corporate Sales team will be in touch within 2 working days.';

        } catch (Exception e) {
            res.recordId = null;
            res.confirmationMessage = 'Sorry, there was an error saving your submission: '
                + e.getMessage() + '. Please contact GlobalCorporateSales@ethiopianairlines.com.';
        }
        return res;
    }

    private static String extractDomain(String url) {
        if (String.isBlank(url)) return null;
        String d = url.toLowerCase().trim();
        d = d.removeStart('https://');
        d = d.removeStart('http://');
        d = d.removeStart('www.');
        Integer slashIdx = d.indexOf('/');
        if (slashIdx > 0) d = d.substring(0, slashIdx);
        return d.trim();
    }

    private static String str(Map<String, Object> d, String key) {
        Object v = d.get(key);
        return v != null ? String.valueOf(v) : null;
    }

    private static Decimal dec(Map<String, Object> d, String key) {
        Object v = d.get(key);
        if (v == null) return null;
        try { return Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { return null; }
    }

    private static Boolean bool(Map<String, Object> d, String key) {
        Object v = d.get(key);
        if (v == null) return false;
        if (v instanceof Boolean) return (Boolean) v;
        return String.valueOf(v).toLowerCase() == 'true';
    }
}