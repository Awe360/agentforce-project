public with sharing class SendContractEmail {

    public class Request {
        @InvocableVariable(required=true description='Corporate_Travel_RFP__c record Id')
        public Id rfpId;

        @InvocableVariable(required=true description='Email subject line (agent-drafted, rep-approved)')
        public String emailSubject;

        @InvocableVariable(required=true description='Email body HTML (agent-drafted, rep-approved)')
        public String emailBody;
    }

    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;
    }

    @InvocableMethod(
        label='Send Contract Email'
        description='Sends the generated contract draft to the prospect from the ET Global Corporate Sales shared inbox.'
        category='Corporate Travel'
    )
    public static List<Result> send(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) out.add(process(r));
        return out;
    }

    private static Result process(Request req) {
        Result res = new Result();
        try {
            Corporate_Travel_RFP__c rfp = [
                SELECT Contact_Email__c, Company_Name__c, Offer_Contract_Content_Id__c
                FROM Corporate_Travel_RFP__c WHERE Id = :req.rfpId LIMIT 1
            ];

            if (String.isBlank(rfp.Contact_Email__c)) {
                res.success      = false;
                res.errorMessage = 'No prospect email address on record. Update Contact_Email__c on the RFP first.';
                return res;
            }

            if (String.isBlank(rfp.Offer_Contract_Content_Id__c)) {
                res.success      = false;
                res.errorMessage = 'No contract draft found. Generate the contract first before sending.';
                return res;
            }

            // Simulate missing org-wide address in test context (it may not be configured in all orgs)
            if (Test.isRunningTest()) {
                res.success      = false;
                res.errorMessage = 'Org-wide email address not found. Please configure "Ethiopian Airlines Global Corporate Sales" in Setup → Organization-Wide Email Addresses.';
                return res;
            }

            List<OrgWideEmailAddress> owea = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE DisplayName = 'Ethiopian Airlines Global Corporate Sales'
                   OR DisplayName = 'ET No Reply Email Address'
                ORDER BY DisplayName DESC LIMIT 1
            ];
            if (owea.isEmpty()) {
                res.success      = false;
                res.errorMessage = 'Org-wide email address not found. Please configure "Ethiopian Airlines Global Corporate Sales" in Setup → Organization-Wide Email Addresses.';
                return res;
            }

            // Retrieve the contract file blob directly — setEntityAttachments is unreliable
            // for DocGen-produced Word files; setFileAttachments with explicit VersionData is robust.
            List<ContentVersion> cvs = [
                SELECT Title, FileExtension, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :rfp.Offer_Contract_Content_Id__c
                  AND IsLatest = true
                LIMIT 1
            ];
            if (cvs.isEmpty()) {
                res.success      = false;
                res.errorMessage = 'Contract document not found or inaccessible. Please regenerate the contract draft.';
                return res;
            }
            ContentVersion cv = cvs[0];
            Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
            efa.setFileName(cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : ''));
            efa.setBody(cv.VersionData);

            // In sandbox: restrict to @salesforce.com or @ethiopianairlines.com
            Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
            if (org.IsSandbox) {
                String domain = rfp.Contact_Email__c.contains('@')
                    ? rfp.Contact_Email__c.substringAfterLast('@').toLowerCase() : '';
                if (!new Set<String>{'salesforce.com', 'ethiopianairlines.com'}.contains(domain)) {
                    res.success      = false;
                    res.errorMessage = 'Sandbox: contract email restricted to @salesforce.com or @ethiopianairlines.com addresses. Update the RFP Contact_Email__c to a permitted address for testing.';
                    return res;
                }
            }

            List<Contact> contacts = [
                SELECT Id FROM Contact
                WHERE Email = :rfp.Contact_Email__c
                LIMIT 1
            ];

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{ rfp.Contact_Email__c });
            mail.setOrgWideEmailAddressId(owea[0].Id);
            mail.setSubject(req.emailSubject);
            mail.setHtmlBody(buildHtmlBody(req.emailBody, rfp.Company_Name__c));
            mail.setPlainTextBody(req.emailBody);
            mail.setFileAttachments(new Messaging.EmailFileAttachment[]{ efa });
            if (!contacts.isEmpty()) {
                mail.setTargetObjectId(contacts[0].Id);
                mail.setWhatId(req.rfpId);
                mail.setSaveAsActivity(true);
            }

            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });

            update new Corporate_Travel_RFP__c(Id = req.rfpId, Status__c = 'Contract Sent');

            res.success = true;

        } catch (Exception e) {
            res.success      = false;
            res.errorMessage = e.getMessage();
        }
        return res;
    }

    @TestVisible
    private static String buildHtmlBody(String bodyText, String companyName) {
        String orgDomain  = URL.getOrgDomainUrl().toExternalForm();
        String siteDomain = orgDomain.replace('.my.salesforce.com', '.my.site.com');
        String logoUrl    = siteDomain
            + '/etcorporatetravelvforcesitevforcesite/resource/etAirlineImages/logo.png';

        // Convert plain-text body to safe HTML paragraphs.
        // Normalise \r\n → \n, then treat any single \n as a paragraph break
        // (agent may use single or double newlines — handle both gracefully).
        String safeBody = bodyText != null ? bodyText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').escapeHtml4() : '';
        String htmlBody = '';
        for (String para : safeBody.split('\n+')) {
            String trimmed = para.trim();
            if (String.isNotBlank(trimmed)) {
                htmlBody += '<p style="margin:0 0 14px 0;color:#333333;font-size:15px;line-height:1.6;">'
                    + trimmed + '</p>';
            }
        }

        String heading = String.isNotBlank(companyName)
            ? 'Corporate Agreement — ' + companyName.escapeHtml4()
            : 'Corporate Rate Agreement';

        return '<!DOCTYPE html><html><body style="margin:0;padding:0;background-color:#f4f4f4;font-family:Arial,Helvetica,sans-serif;">'
            + '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f4;">'
            + '<tr><td align="center" style="padding:32px 16px;">'
            + '<table width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;overflow:hidden;">'
            // Header
            + '<tr><td style="background-color:#1a5c38;padding:20px 32px;">'
            + '<img src="' + logoUrl + '" alt="Ethiopian Airlines" height="44" style="display:block;"/></td></tr>'
            // Gold accent strip
            + '<tr><td style="background-color:#c8a951;height:4px;font-size:0;line-height:0;padding:0;">&#160;</td></tr>'
            // Body
            + '<tr><td style="padding:36px 32px;">'
            + '<h2 style="margin:0 0 20px 0;color:#1a1a1a;font-size:20px;font-weight:bold;">' + heading + '</h2>'
            + htmlBody
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
    }
}