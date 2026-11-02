public with sharing class PrepareEmailDraft {

    public class Request {
        @InvocableVariable(required=true description='Email subject line')
        public String subject;

        @InvocableVariable(required=true description='Plain-text email body')
        public String emailBody;

        @InvocableVariable(required=true description='Recipient email address')
        public String toEmail;

        @InvocableVariable(description='Recipient display name')
        public String toName;
    }

    public class Result {
        @InvocableVariable(description='Formatted email draft card. Use show_command to display it immediately after prepare_email_draft returns.')
        public ContractEmailDraftData emailDraftCard;

        @InvocableVariable(description='Output this value verbatim as the first thing in your response, then IMMEDIATELY call show_command to display the emailDraftCard.')
        public String draftReadyMessage;
    }

    @InvocableMethod(
        label='Prepare Email Draft'
        description='Packages the agent-drafted email into a formatted display card for rep review before sending.'
        category='Corporate Travel'
    )
    public static List<Result> prepare(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            Map<String, Object> payload = new Map<String, Object>{
                'subject' => r.subject   != null ? r.subject   : '',
                'toEmail' => r.toEmail   != null ? r.toEmail   : '',
                'toName'  => r.toName    != null ? r.toName    : '',
                'body'    => r.emailBody != null ? r.emailBody : ''
            };
            String displayName = String.isNotBlank(r.toName) ? r.toName : r.toEmail;
            Result res  = new Result();
            res.emailDraftCard = new ContractEmailDraftData(JSON.serialize(payload));
            res.draftReadyMessage = 'Contract email draft ready for review — ' + displayName + '.';
            out.add(res);
        }
        return out;
    }
}