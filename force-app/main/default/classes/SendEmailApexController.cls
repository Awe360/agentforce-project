public with sharing class SendEmailApexController {

    @AuraEnabled
    public static void sendEmail(String caseId, String subject, String body, String fromAddress, List<String> contentDocumentIds) {
        try {
            Case caseRecord = [SELECT Id, SuppliedEmail FROM Case WHERE Id = :caseId LIMIT 1];
            
            if (caseRecord.SuppliedEmail == null) {
                throw new AuraHandledException('Case does not have a valid email address');
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ caseRecord.SuppliedEmail });
            mail.setSubject(subject);
            mail.setHtmlBody(body);
            mail.setReplyTo(fromAddress);
            mail.setSaveAsActivity(true);
            mail.setWhatId(caseRecord.Id);
           
            
            if (contentDocumentIds != null && !contentDocumentIds.isEmpty()) {
                List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

                List<ContentVersion> contentVersions = [
                    SELECT Id, Title, VersionData, FileType, PathOnClient 
                    FROM ContentVersion 
                    WHERE ContentDocumentId IN :contentDocumentIds AND IsLatest = true
                ];

                for (ContentVersion cv : contentVersions) {
                    Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                    attachment.setFileName(cv.PathOnClient != null ? cv.PathOnClient : cv.Title);
                    attachment.setBody(cv.VersionData);
                    attachments.add(attachment);
                }

                mail.setFileAttachments(attachments);
            }

            Messaging.sendEmail(new List<Messaging.Email>{ mail });

        } catch (Exception e) {
            throw new AuraHandledException('Failed to send email: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<EmailWrapper> getEmailHistory(String caseId) {
        List<EmailWrapper> emails = new List<EmailWrapper>();

        for (EmailMessage em : [
            SELECT Id, Subject, TextBody, HtmlBody, FromAddress, ToAddress, MessageDate, 
                   (SELECT Id, Name FROM Attachments)
            FROM EmailMessage 
            WHERE ParentId = :caseId 
            ORDER BY MessageDate DESC
        ]) {
            emails.add(new EmailWrapper(em));
        }

        return emails;
    }

    public class EmailWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String fromAddress;
        @AuraEnabled public String toAddress;
        @AuraEnabled public Datetime messageDate;
        @AuraEnabled public Boolean hasAttachments;
        @AuraEnabled public String formattedDate;
        @AuraEnabled public List<AttachmentWrapper> attachments;

        public EmailWrapper(EmailMessage em) {
            this.id = em.Id;
            this.subject = em.Subject;
            this.body = em.HtmlBody != null ? em.HtmlBody : em.TextBody;
            this.fromAddress = em.FromAddress;
            this.toAddress = em.ToAddress;
            this.messageDate = em.MessageDate;
            this.formattedDate = em.MessageDate.format('MMM d, yyyy h:mm a');
            this.hasAttachments = !em.Attachments.isEmpty();
            this.attachments = new List<AttachmentWrapper>();

            for (Attachment att : em.Attachments) {
                this.attachments.add(new AttachmentWrapper(att));
            }
        }
    }

    public class AttachmentWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;

        public AttachmentWrapper(Attachment att) {
            this.id = att.Id;
            this.name = att.Name;
        }
    }
}