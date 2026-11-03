# Customer-Facing Agent Deep Dive
## Ethiopian Airlines Corporate Travel RFP Agent — Step-by-Step Implementation

---

## 0. Big Picture: What is This?

The **Corporate Travel RFP Agent** is an **external Agentforce (Einstein Service) Agent** embedded in a **Messaging for In-App and Web (MIAW)** chat window on the Ethiopian Airlines website. It is not a simple chatbot — it is an AI agent driven by a large language model (Claude Sonnet, specifically `sfdc_ai__DefaultBedrockAnthropicClaude5Sonnet`) that:

1. Converses with a corporate travel buyer
2. Presents interactive UI widgets (LWCs) inside the chat bubble
3. Accepts uploaded documents, extracts fields via Document AI, and pre-fills a multi-step form
4. Saves the completed RFP as Salesforce records and sends a confirmation email

---

## 1. Entry Point: The Chat Window (MIAW)

### What it is
**Messaging for In-App and Web (MIAW)** is Salesforce's successor to Live Agent/Chat. It embeds a floating chat button on the airline's website using an Embedded Service deployment. When the customer clicks it, a WebSocket-based messaging session (`MessagingSession` SObject) is created.

### How the Agent is Attached
The `aiAgentDefinition` metadata file
[`Corporate_Travel_RFP_Agent.aiAgentDefinition-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/aiAgents/Corporate_Travel_RFP_Agent.aiAgentDefinition-meta.xml)
declares:
- `type = EinsteinServiceAgent` — this is a customer-facing service agent
- `subtype = ExternalCopilot` — runs in the external (public) channel
- Linked to the MIAW channel via `connection customer_web_client`

> [!IMPORTANT]
> The **Welcome Message** `"Welcome to Ethiopian Airlines Corporate Travel Services. How can I assist you today?"` is displayed automatically when the chat window opens. This is configured in the agent's `messages.welcome` field — it is sent by the platform, not the LLM.

---

## 2. Agent Builder Configuration: The Brain

The agent's behaviour is defined through **Topics** and **Actions** configured in Agent Builder (Salesforce's low-code agent canvas). Here is how the configuration from your YAML maps to Salesforce concepts:

### 2a. The Router Topic (`start_agent topic_selector`)
```
topic_selector — routes every message → go_to_rfp_intake → Corporate_Travel_RFP_Intake subagent
```
- This is a **Topic** in Agentforce.
- Its entire purpose is routing: instructions say `"Call go_to_rfp_intake for every user message without exception."`
- `go_to_rfp_intake` is an **Agent Action of type Transition** — it hands control to the `Corporate_Travel_RFP_Intake` subagent.
- Why have a separate router? It's a guard rail: even if the LLM decides the user message is off-topic, the router forces the handoff.

### 2b. The Main Subagent (`Corporate_Travel_RFP_Intake`)
This is where all the conversation intelligence lives. It has:

| Config Key | Salesforce Concept | Purpose |
|---|---|---|
| `label` | Topic Label | Human-readable name in Agent Builder |
| `description` | Topic Description | Tells the LLM when to use this topic |
| `reasoning.instructions` | Topic Instructions | The "system prompt" given to the LLM for this topic |
| `actions.show_form` | Agent Action (Flow) | Invokes `corporateTravelRfpWizard_Output` flow |
| `actions.get_extract` | Agent Action (Flow) | Invokes `getLatestRfpExtract_Output` flow |
| `model_config.model` | Model Configuration | Claude Sonnet (Bedrock) |

### 2c. The Off-Topic Subagent (`off_topic`)
A simple catch-all that responds with a redirect message. The topic `description` tells the LLM to match it when the user asks about non-RFP topics (flights, baggage, loyalty, etc.).

---

## 3. The Two Intake Paths: How the Agent Decides What to Show

The agent instructions define two paths explicitly. The LLM follows them strictly:

```
PATH A (user has RFP document to upload)
  Step 1 → call show_form(Details="upload")        → renders rfpUploadClt upload widget
  Step 2 → call __show_tool_results__              → platform renders the LWC in chat
  Step 3 → wait for "RFP document uploaded and processed" utterance
  Step 4 → call get_rfp_extract                   → retrieves extracted JSON from ET_RFP_Extract__c
  Step 5 → call show_form(Details="form", PrefillValuesJSON=..., ContentDocumentIds=...)
  Step 6 → call __show_tool_results__              → platform renders the pre-filled wizard

PATH B (user fills manually)
  Step 1 → call show_form(Details="form", PrefillValuesJSON="", ContentDocumentIds="")
  Step 2 → call __show_tool_results__              → platform renders empty wizard
```

> [!NOTE]
> `__show_tool_results__` is a **special built-in Agentforce instruction** that tells the platform to render the structured output (an LWC) of the previous action call inline in the chat window. Without it, the action result would only be sent as text.

---

## 4. The Flow Adapter Layer (CLT Output Flows)

This is the key architectural insight — **Flows act as the bridge between Agent Actions and LWCs**.

### How it works

```
Agent Action (show_form)
    ↓ calls
AutoLaunched Flow: corporateTravelRfpWizard_Output
    ↓ produces
Apex class output variable (CorporateTravelRfpWizardData)
    ↓ rendered as
LWC: corporateTravelRfpWizard (Chat Lightning Template)
```

### `corporateTravelRfpWizard_Output` Flow
**File:** [`flows/corporateTravelRfpWizard_Output.flow-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flows/corporateTravelRfpWizard_Output.flow-meta.xml)

**Type:** `AutoLaunchedFlow` — has no screens, runs completely in the background

**Input Variables:**
| Variable | Type | Purpose |
|---|---|---|
| `Details` | String | `"upload"` or `"form"` — tells the LWC which mode to show |
| `PrefillValuesJSON` | String | JSON of AI-extracted field values for auto-fill |
| `ContentDocumentIds` | String | ID of the uploaded RFP source document |

**What it does (only 2 steps):**
1. **Formula: `MergedWizardJSON`** — builds the final JSON by choosing either `StandardFormJSON` (full wizard) or `UploadJSON` (upload widget) based on `Details`, then appends `prefillValuesJSON` and `rfpDocumentId` to it.
2. **Assignment: `Assign_Details_To_Options`** — puts the merged JSON string into `Options.wizardJSON` (the output variable).

**Output Variable: `Options`**
- Type: `Apex` class `CorporateTravelRfpWizardData`
- This is the **Apex data contract** that tells Agentforce which LWC to render

### `CorporateTravelRfpWizardData` Apex Class
**File:** [`classes/CorporateTravelRfpWizardData.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/CorporateTravelRfpWizardData.cls)

```java
// This is the "envelope" that binds the Flow output to the LWC
public class CorporateTravelRfpWizardData {
    @AuraEnabled public String wizardJSON;  // The JSON config string
}
```

This class is marked with Agentforce's `@AuraEnabled` rendering annotation. The platform uses the class name to look up the corresponding LWC component by convention.

### The Same Pattern for Upload CLT
**File:** [`flows/rfpUploadClt_Output.flow-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flows/rfpUploadClt_Output.flow-meta.xml)

- Input: `Details` (JSON string)
- Assigns it to `Options.rfpUploadCltJSON`
- Output type: `RfpUploadCltData` → renders `rfpUploadClt` LWC

---

## 5. LWC: `rfpUploadClt` — The Document Upload Widget

**Files:** [`lwc/rfpUploadClt/`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lwc/rfpUploadClt/)

This LWC renders **inside the chat bubble** as a Chat Lightning Template (CLT). It is a self-contained file upload UI.

### Meta Config (`rfpUploadClt.js-meta.xml`)
The metadata marks this component as a CLT — it is exposed to Messaging (MIAW) channels.

### State Machine (4 states)
```
IDLE → (user picks/drags file) → IDLE with file preview
     → (user clicks Upload & Extract) → PROCESSING
PROCESSING → (Apex success) → SUCCESS
           → (Apex fail) → ERROR
ERROR → (user clicks Try Again) → IDLE
```

### `@api value` Property
```js
@api
get value() { return this._value != null ? this._value : BUILDER_FALLBACK; }
set value(v) { this._value = unwrapApexEnvelope(v); }
```
- This is how the Flow passes configuration **into** the LWC
- The `value` property receives the output of the Flow's `Options` variable
- `unwrapApexEnvelope()` peels off the Apex wrapper layer that Agentforce adds: `{rfpUploadCltJSON: "..."}` → parsed JSON
- The `BUILDER_FALLBACK` object is used when previewing in Agent Builder (no real Flow data)

### File Validation Logic
```js
_applyFile(file) {
    // 1. Extension check: only PDF, DOC, DOCX accepted
    if (!name.endsWith('.pdf') && !name.endsWith('.doc') && !name.endsWith('.docx')) {
        this._errorMessage = 'Accepted formats: PDF, DOC, DOCX';
        return;
    }
    // 2. Size check: max 5 MB (5 * 1024 * 1024 bytes)
    if (file.size > 5242880) { ... return; }
    this._selectedFile = file;
}
```

### The Upload & Extract Flow
```js
handleSubmit() {
    // 1. Read file as base64 Data URL using FileReader API
    const reader = new FileReader();
    reader.onload = (e) => {
        const base64 = dataUrl.substring(dataUrl.indexOf(',') + 1); // strip "data:...;base64,"
        
        // 2. Call Apex: RfpUploadController.uploadAndExtract
        uploadAndExtract({ base64Data: base64, filename: this._selectedFile.name })
            .then((result) => {
                if (result.success) {
                    // 3. Transition to SUCCESS state
                    // 4. Send utterance back into chat
                    sendUtterance('RFP document uploaded and processed');
                }
            });
    };
}
```

### The Critical `sendUtterance()` Function
```js
function sendUtterance(message) {
    // embeddedservice_configuration is the global Embedded Service JS object
    embeddedservice_configuration.util.sendTextMessage(message)
}
```
This is **how the LWC talks back to the Agent**. After a successful upload, it programmatically sends the text `"RFP document uploaded and processed"` as a chat message. The agent's instructions say: *"Wait for user message 'RFP document uploaded and processed'. When received, call get_rfp_extract."* So the LWC triggers the next step in the agent's workflow automatically.

---

## 6. Apex: `RfpUploadController` — File Storage + Document AI

**File:** [`classes/RfpUploadController.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/RfpUploadController.cls)

This is a `public without sharing` class (guest user context — no record security enforced).

### Three Methods with Different Responsibilities

#### `uploadDocumentOnly(base64Data, filename)`
- Called by the **wizard LWC** for the business licence file
- Creates a `ContentVersion` (Salesforce File), queries back `ContentDocumentId`
- **No callout** — just stores the file
- Returns `UploadResult { success, contentDocumentId }`

#### `uploadFileOnly(base64Data, filename)`
- Called by the **rfpUploadClt LWC** 
- Creates `ContentVersion` → gets `ContentDocumentId`
- Also inserts `ET_RFP_Extract__c` staging row (with `ContentDocumentId__c` and `FileExt__c` only, no extracted JSON yet)
- The extraction is done later by the **agent action** (`DocumentAiRfpExtractor`)
- Why? The agent user (not the guest user) has Named Credential access for the callout

#### `uploadAndExtract(base64Data, filename)` ← The Important One
```
Step 1: HTTP callout to Document AI (MUST be before any DML — Apex rule)
    → POST to callout:DocumentAI_NC/services/data/v65.0/ssot/document-processing/actions/extract-data
    → Body: { idpConfigurationIdOrName: "ET_Corporate_RFP", files: [{mimeType, data: base64}] }

Step 2: Parse Document AI response
    → Unwrap nested {data: [{data: "<json-string>"}]} envelope
    → Extract field values (each field is {type, value} wrapper)
    → Build human-readable summary ("Extracted 12 of 14 required fields. Missing: ...")

Step 3: DML (after callout — Apex rule)
    → INSERT ContentVersion (the file)
    → INSERT ET_RFP_Extract__c {
        ContentDocumentId__c, ExtractedJSON__c, ExtractionSummary__c, Success__c
      }
```

> [!IMPORTANT]
> **Apex Callout Rule**: You cannot do DML (INSERT/UPDATE) before a callout in the same transaction. This is why the `uploadAndExtract` method does the HTTP call first, then DML. `uploadFileOnly` avoids this by skipping the callout entirely.

### Document AI Request Format
```json
{
  "idpConfigurationIdOrName": "ET_Corporate_RFP",
  "files": [{
    "mimeType": "application/pdf",
    "data": "<base64-encoded-file-content>"
  }]
}
```
- `ET_Corporate_RFP` is a **Document AI configuration** (IDP = Intelligent Document Processing) set up in Setup → Document AI
- It defines which fields to extract and how (field names, types, labels)
- `callout:DocumentAI_NC` is a **Named Credential** — stores the endpoint URL and OAuth credentials without hardcoding them

---

## 7. Apex: `DocumentAiRfpExtractor` — Agent-Side Extraction Action

**File:** [`classes/DocumentAiRfpExtractor.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/DocumentAiRfpExtractor.cls)

This class is an **`@InvocableMethod`** — it is called by the `getLatestRfpExtract_Output` Flow, which is called by the agent's `get_extract` action.

### Input Flexibility (3 resolution strategies for the document)
```
Priority 1: contentDocumentId provided directly → use it
Priority 2: messagingSessionId provided → lookup ContentDocumentLink WHERE LinkedEntityId = sessionId
Priority 3: Fallback → query all active MessagingSessions, find most recent CDL
```

### Cache Hit (Avoiding Duplicate Callout)
```java
// Check if uploadAndExtract already ran and cached the result
List<ET_RFP_Extract__c> cached = [
    SELECT ExtractedJSON__c, ExtractionSummary__c
    FROM ET_RFP_Extract__c
    WHERE ContentDocumentId__c = :docId AND Success__c = true
    ORDER BY CreatedDate DESC LIMIT 1
];
if (!cached.isEmpty()) {
    // Return cached result — skip the Document AI callout
    return cached result;
}
```

This is the **two-path convergence**: if `uploadAndExtract` already ran (Path A via rfpUploadClt), the cache hit skips the second callout. If `uploadFileOnly` ran instead, the cache row has no JSON, so the extractor makes a fresh callout.

### URL Protocol Stripping
```java
// Strip "https://" prefix from website fields
// Agentforce guardrails intercept and redact URLs in action outputs
// The wizard LWC re-adds "https://" when it populates url-type fields
if (sv.startsWith('https://')) urlFixes.put(k, sv.substring(8));
```
This is an important workaround: Agentforce's built-in content safety guardrails (`#DisableURLRedaction#` in the agent config is an attempt to disable this) can redact URL values passing through action outputs. The solution is to strip the protocol server-side and re-add it client-side.

### Travel Agency Remapping
```java
// Document AI returns: { "travelAgencies": [{iata_name, iata_number, pcc, gds}] }
// LWC expects: { "travelAgencies": [{iataName, iataNumber, pcc, gds}] }
remapTravelAgencies(extracted);
```
Normalises the field names from Document AI's snake_case/underscore format to the camelCase the form LWC expects.

---

## 8. LWC: `corporateTravelRfpWizard` — The Multi-Step Form

**Files:** [`lwc/corporateTravelRfpWizard/`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lwc/corporateTravelRfpWizard/)

This is the central UX component — a data-driven, 6-step wizard rendered in the chat window.

### Dual-Mode Architecture (Upload vs Form)
```js
get isUploadMode() {
    const m = this.config.mode;
    return m === 'rfp_upload' || m === 'business_licence_upload';
}
get isFormMode() { return !this.isUploadMode; }
```
The same LWC handles BOTH the upload widget and the full wizard. The Flow sets `mode` in the JSON config to determine which mode to show. This eliminates the need for two separate LWC deployments.

### Data-Driven Steps Configuration
The wizard's steps, fields, labels, types, and validation rules are all defined in a **JSON object** passed from the Flow (not hardcoded in the LWC). This means the agent can theoretically change the form shape without a code deployment — just by changing the Flow variable.

The 6 steps are:
| Step # | Title | Special Features |
|---|---|---|
| 1 | Company Profile | Company name, address, website, budget |
| 2 | Contact & Request | Contact info, New vs Renewal toggle (conditional fields) |
| 3 | Proposal Details | NFR target (min $50K enforced), discount %, **hasRoutes** — dynamic route rows |
| 4 | Ticket Issuance & Declaration | Checkboxes + **hasTravelAgencies** — conditional travel agency rows |
| 5 | Business Licence | **type: fileupload** — special drag-and-drop file step |
| 6 | Review & Submit | Auto-generated summary of all entered values |

### Pre-fill Logic (`connectedCallback`)
```js
connectedCallback() {
    if (!this._prefillValuesJSON || this.isUploadMode) return;
    const prefill = JSON.parse(this._prefillValuesJSON);
    const { routes: extractedRoutes, travelAgencies: extractedAgencies, ...fields } = prefill;
    
    // 1. Set simple field values
    this.formValues = { ...fields };
    
    // 2. Re-add https:// to URL fields (stripped by extractor)
    for (const field of allFields) {
        if (field.type === 'url') {
            const v = this.formValues[field.name];
            if (v && !v.startsWith('http')) {
                this.formValues = { ...this.formValues, [field.name]: 'https://' + v };
            }
        }
    }
    
    // 3. Re-hydrate routes array
    if (extractedRoutes?.length > 0) { this.routes = extractedRoutes.map(...); }
    
    // 4. Re-hydrate travel agencies array
    if (extractedAgencies?.length > 0) { this.travelAgencies = extractedAgencies.map(...); }
}
```
This runs immediately when the LWC is inserted into the DOM (after `show_form` with Path A data). It pre-populates all form fields from the AI extraction result.

### Dynamic Field Visibility
```js
_passesShowIf(f) {
    if (!f.showIf) return true;
    return this.formValues[f.showIf.field] === f.showIf.value;
}
```
Fields like `corporateId` and `nfrJustification` are conditionally shown only when `requestType === "Renewal"`. This is driven by the `showIf` property in the JSON config.

### Client-Side Validation
```js
validateCurrentStep() {
    // Required field check
    for (const field of this.visibleFields) {
        if (!field.required) continue;
        if (!v || String(v).trim() === '') {
            this.errorMessage = `"${field.label}" is required.`; 
            return false;
        }
    }
    // Email format check
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { ... }
    
    // NFR minimum check ($50,000)
    if (Number(nfrVal) < 50000) {
        this.errorMessage = '"Annual NFR Target (USD)" must be at least USD 50,000.';
        return false;
    }
    
    // Route completeness check
    for (const r of this.routes) {
        if (!r.origin || !r.destination) { ... return false; }
    }
}
```

### Submit Flow
```
1. User clicks "Submit Application" on Review step
2. validateCurrentStep() passes
3. submitForm() called:
   a. If business licence file selected:
      → FileReader reads file as base64
      → uploadDocumentOnly(base64, filename) [Apex]
      → on success: _doSaveRecord(contentDocumentId)
   b. If no licence file:
      → _doSaveRecord(null)

4. _doSaveRecord(bizLicDocId):
   → Build JSON payload: { ...formValues, routes, travelAgencies, 
                            contentDocumentIds, rfpDocumentId }
   → saveRfpFromLwc(submissionJSON) [Apex]
   → on success: isSuccess = true, sendUploadUtterance("Application submitted")
```

The final `sendUploadUtterance('Application submitted')` triggers the agent's post-submission response: *"Your Corporate Travel RFP application has been submitted successfully!"*

---

## 9. Apex: `CorporateTravelRfpSave` — Record Creation

**File:** [`classes/CorporateTravelRfpSave.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/CorporateTravelRfpSave.cls)

This class is **both** `@AuraEnabled` (called by LWC) **and** `@InvocableMethod` (called by Flow/Agent). Both surfaces call the same `processRequest()` private method.

### What it Creates (9 Steps)

```
Step 1: Account
   → Deduplicate by website domain
   → If no match, INSERT new Account

Step 2: Contact  
   → Deduplicate by email + AccountId, then email alone
   → If no match, INSERT new Contact (parse first/last name)

Step 3: Opportunity
   → INSERT Opportunity linked to Account
   → StageName = "Prospecting" (New) or "Qualification" (Renewal)
   → CloseDate = today + 90 days
   → Amount = annualNfrTarget

Step 4: OpportunityContactRole
   → INSERT OCR (Decision Maker, Primary=true)
   → Failure is silently swallowed

Step 5: Corporate_Travel_RFP__c
   → INSERT the main RFP record with all form fields mapped
   → Status__c = 'New'
   → Stores both licenceDocumentId and rfpDocumentId

Step 6: Confirmation Email
   → Build branded HTML email (ET green/gold colour scheme)
   → Sandbox check: only send to @salesforce.com or @ethiopianairlines.com
   → Messaging.sendEmail() with OrgWideEmailAddress lookup
   → Failure is silently swallowed

Step 7: Travel_Route__c records
   → For each route in the JSON: INSERT Travel_Route__c linked to RFP

Step 8: Travel_Agency__c records
   → For each agency: INSERT Travel_Agency__c linked to RFP

Step 9: ContentDocumentLink
   → Link the uploaded files to both the RFP record and the Opportunity
   → ShareType='V', Visibility='AllUsers' (accessible by guest)
```

> [!WARNING]
> This class is `without sharing` — it runs without record-level security. This is necessary because the guest/agent user may not have normal record access, but it means all input must be carefully validated before trusting it.

---

## 10. Record-Triggered Flows: Post-Save Automation

### `corporateTravelRfpNewSubmission` Flow
**File:** [`flows/corporateTravelRfpNewSubmission.flow-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flows/corporateTravelRfpNewSubmission.flow-meta.xml)

- **Trigger:** `Corporate_Travel_RFP__c` → After Create (After Save)
- **Action:** Creates a `Task` record
  - Subject: `"Review RFP: {Company_Name__c}"`
  - Due Date: Today + 2 days
  - Priority: High
  - WhatId: the RFP record
  - Owner: the RFP owner
- **Purpose:** Notifies the Global Corporate Sales Desk to manually review the submission

### `Business_Licence_Validation_on_RFP_Create` Flow
**File:** [`flows/Business_Licence_Validation_on_RFP_Create.flow-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flows/Business_Licence_Validation_on_RFP_Create.flow-meta.xml)

- **Trigger:** `Corporate_Travel_RFP__c` → After Create (Async After Commit)
- **Filter:** Only runs if `Licence_Document_Id__c IS NOT NULL`
- **Action:** Publishes a Platform Event: `RFP_Licence_Validation_Request__e { RFP_Id__c: recordId }`
- **Why Async?** The guest user cannot mint the JWT token required to invoke prompt template callouts. By publishing a Platform Event, the worker runs as **Automated Process** user who can.

### `Licence_Validation_Worker` Flow (Event-Triggered)
- **Trigger:** `RFP_Licence_Validation_Request__e` platform event
- **Process:**
  1. Query `Corporate_Travel_RFP__c` to get the licence document
  2. Invoke the **Prompt Builder template** (calls an LLM with the licence document)
  3. Parse the JSON response via `LicenceValidationParser` Apex class
  4. Update licence validation fields on the RFP record

---

## 11. End-to-End Flow Summary

```
[Customer opens chat on airline website]
    ↓
MIAW session opens → Welcome message displayed
    ↓
Agent's topic_selector routes to Corporate_Travel_RFP_Intake
    ↓
LLM reads system prompt + knowledge (USD 50K minimum, benefits, etc.)
    ↓
Customer expresses interest in RFP
    ↓
LLM sends requirements briefing (bold headers, bullet points)
LLM asks: "Do you have an RFP document to upload?"
    ↓
    ├─ PATH A: "Yes, I have a document"
    │   ↓
    │   Agent calls show_form(Details="upload")
    │       ↓ invokes corporateTravelRfpWizard_Output flow
    │       ↓ Flow merges UploadJSON + empty prefill
    │       ↓ Returns CorporateTravelRfpWizardData to agent
    │   Agent calls __show_tool_results__
    │       ↓ corporateTravelRfpWizard LWC renders in upload mode
    │   Customer drags file → clicks Upload
    │       ↓ LWC FileReader reads as base64
    │       ↓ RfpUploadController.uploadFileOnly() [Apex]
    │           → INSERT ContentVersion (file stored)
    │           → INSERT ET_RFP_Extract__c (staging, no JSON yet)
    │       ↓ LWC sendUtterance("RFP document uploaded and processed")
    │   Agent receives utterance → calls get_rfp_extract
    │       ↓ getLatestRfpExtract_Output flow → DocumentAiRfpExtractor [Apex]
    │           → resolves ContentDocumentId (from ET_RFP_Extract__c)
    │           → cache miss: POST to Document AI endpoint
    │           → parse {type, value} field wrappers
    │           → strip URL protocols
    │           → remap travelAgencies keys
    │           → return ExtractedFieldsJSON + RfpContentDocumentId
    │   Agent calls show_form(Details="form", PrefillValuesJSON=..., ContentDocumentIds=...)
    │       ↓ Flow merges StandardFormJSON + prefill JSON
    │   Agent calls __show_tool_results__
    │       ↓ corporateTravelRfpWizard LWC renders in form mode (pre-filled)
    │
    └─ PATH B: "I'll fill manually"
        ↓
        Agent calls show_form(Details="form", empty prefill)
            ↓ Flow merges StandardFormJSON + empty prefill
        Agent calls __show_tool_results__
            ↓ corporateTravelRfpWizard LWC renders in form mode (empty)

Customer fills 6-step form → clicks Submit
    ↓
1. uploadDocumentOnly() [Apex] — uploads business licence file
2. saveRfpFromLwc() [Apex]:
    → INSERT Account (deduplicated)
    → INSERT Contact (deduplicated)
    → INSERT Opportunity
    → INSERT OpportunityContactRole
    → INSERT Corporate_Travel_RFP__c (all fields)
    → Messaging.sendEmail() — confirmation to customer
    → INSERT Travel_Route__c records
    → INSERT Travel_Agency__c records
    → INSERT ContentDocumentLink (files linked to RFP + Opp)
    ↓
LWC sendUtterance("Application submitted")
    ↓
Agent responds: "Your application has been submitted! 
                Our team will be in touch within 2 working days."
    ↓
AFTER-SAVE FLOWS fire on Corporate_Travel_RFP__c:
    → corporateTravelRfpNewSubmission: Task created for sales desk (due +2 days)
    → Business_Licence_Validation_on_RFP_Create: Publishes platform event
        → Licence_Validation_Worker: LLM validates the business licence async
```

---

## 12. Component Dependency Map (For Replication)

```
Agentforce Agent Definition
├── Topic: Corporate_Travel_RFP_Intake
│   ├── Action: show_form
│   │   └── Flow: corporateTravelRfpWizard_Output   ← AutoLaunched, must be Active
│   │       ├── Apex Data Class: CorporateTravelRfpWizardData
│   │       └── LWC: corporateTravelRfpWizard        ← CLT, deployed to MIAW channel
│   │           ├── Apex: RfpUploadController.uploadFileOnly()
│   │           ├── Apex: RfpUploadController.uploadDocumentOnly()
│   │           └── Apex: CorporateTravelRfpSave.saveRfpFromLwc()
│   │               ├── SObject: Corporate_Travel_RFP__c
│   │               ├── SObject: Travel_Route__c
│   │               ├── SObject: Travel_Agency__c
│   │               ├── SObject: Account
│   │               ├── SObject: Contact
│   │               └── SObject: Opportunity
│   └── Action: get_extract
│       └── Flow: getLatestRfpExtract_Output        ← must be Active
│           └── Apex: DocumentAiRfpExtractor (@InvocableMethod)
│               ├── Named Credential: DocumentAI_NC
│               ├── Document AI Config: ET_Corporate_RFP
│               └── SObject: ET_RFP_Extract__c
│
└── Post-Save Automation
    ├── Flow: corporateTravelRfpNewSubmission (Record-Triggered, Active)
    ├── Flow: Business_Licence_Validation_on_RFP_Create (Record-Triggered, Active)
    │   └── Platform Event: RFP_Licence_Validation_Request__e
    └── Flow: Licence_Validation_Worker (Event-Triggered, Active)
        ├── Prompt Builder Template (external to source)
        └── Apex: LicenceValidationParser
```

---

## 13. Key Design Patterns to Replicate

| Pattern | Implementation | Why |
|---|---|---|
| **Flow as CLT adapter** | AutoLaunched Flow → Apex data class → LWC | Agentforce needs an Apex output class to bind a Flow action to an LWC |
| **sendUtterance()** | `embeddedservice_configuration.util.sendTextMessage()` | LWC triggers the next agent step programmatically |
| **`__show_tool_results__`** | Agent instruction after every show_form call | Renders the structured LWC output in the chat bubble |
| **JSON-driven form** | Wizard config embedded in Flow variables | Decouples form schema from LWC code |
| **URL protocol stripping** | Apex strips `https://`, LWC re-adds it | Works around Agentforce URL redaction guardrails |
| **Async validation** | Platform Event → Licence_Validation_Worker | Guest users can't call prompt templates directly |
| **Callout-before-DML** | `uploadAndExtract` calls HTTP, then INSERTs | Required by Apex transaction rules |
| **Cache layer** | `ET_RFP_Extract__c.Success__c = true` check | Avoids duplicate Document AI calls |
| **Silent failure** | Email, OCR, file links wrapped in try/catch | Core record save never blocked by secondary operations |

---

## 14. Deep Dive: Flow Variables, `show_form`, and the LWC/CLT Bridge

### 14.1 The Core Problem This Solves
The Agentforce Agent (the LLM) lives in a chat interface. It can reason, produce text, and call backend actions. However, an LLM cannot render interactive HTML/CSS UI components (like a multi-step form or a file uploader with drag-and-drop) on its own.

To display a custom interactive widget in the chat window, Salesforce uses this bridge:

```
[User Chat]
    ↓ (User asks to submit an RFP)
[Agentforce Agent]
    ↓ (Decides to invoke action: show_form)
[Autolaunched Flow: corporateTravelRfpWizard_Output]
    ↓ (Takes inputs, picks JSON template, injects data into MergedWizardJSON)
[Apex Output Variable: Options (Type: CorporateTravelWizardData)]
    ↓ (Flow assigns jsonString = MergedWizardJSON)
[Lightning Custom Type (CLT): corporateTravelRfpWizard]
    ↓ (renderer.json maps CorporateTravelWizardData → c/corporateTravelRfpWizard)
[LWC Component: corporateTravelRfpWizard]
    ↓ (Renders interactive form or upload widget directly in the chat bubble)
```

---

### 14.2 What is `show_form`?
`show_form` is an **Agent Action** configured in Agent Builder:
* **Type:** Flow Action
* **Underlying Implementation:** Autolaunched Flow [`corporateTravelRfpWizard_Output`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flows/corporateTravelRfpWizard_Output.flow-meta.xml)
* **Purpose:** Instructs the chat UI to display the interactive wizard widget (either in "upload" mode or "form" mode).
* **Companion Instruction:** The agent is instructed to output `__show_tool_results__` immediately after invoking `show_form` so the platform renders the LWC response widget instead of standard text.

---

### 14.3 Breakdown of Flow Variables

| Variable | Flow Type | In / Out | Purpose |
|---|---|---|---|
| **`Details`** | String | **Input** (`isInput: true`) | Specifies the display mode: `"form"` for the multi-step form, or `"upload"` for the file upload widget. |
| **`PrefillValuesJSON`** | String | **Input** (`isInput: true`) | JSON string containing extracted data (from Document AI via `getLatestRfpExtract_Output`) to pre-populate fields. |
| **`ContentDocumentIds`** | String | **Input** (`isInput: true`) | Salesforce File ID (`ContentDocumentId`) of the uploaded RFP document, passed forward so the form links to the file. |
| **`StandardFormJSON`** | Text Template | Internal | Raw JSON template defining form fields, steps, picklist values, labels, and validation rules. |
| **`UploadJSON`** | Text Template | Internal | Raw JSON template configuring the file upload widget view. |
| **`MergedWizardJSON`** | Formula (String) | Internal | Injects runtime inputs into the selected JSON template (see formula below). |
| **`Options`** | Apex-Defined (`CorporateTravelWizardData`) | **Output** (`isOutput: true`) | The structured object returned to Agentforce. The platform detects this Apex type and matches it to the CLT renderer. |

#### The `MergedWizardJSON` Formula Explained:
```javascript
IF({!Details} = 'form', 
   LEFT({!StandardFormJSON}, LEN({!StandardFormJSON}) - 1), 
   LEFT({!UploadJSON}, LEN({!UploadJSON}) - 1)
) 
& ',"prefillValuesJSON":"' & JSENCODE({!PrefillValuesJSON}) 
& '","rfpDocumentId":"' & JSENCODE({!ContentDocumentIds}) 
& '"}'
```
1. **Selects the Template:** If `Details` equals `'form'`, it takes `StandardFormJSON`; otherwise it takes `UploadJSON`.
2. **Strips the Closing Bracket:** `LEFT(..., LEN(...) - 1)` removes the trailing `}` from the template string.
3. **Appends Runtime State:** Adds `"prefillValuesJSON": "..."` and `"rfpDocumentId": "..."` using `JSENCODE` to escape special characters.
4. **Closes the JSON:** Adds the closing `"}"` to complete the valid JSON payload.

---

### 14.4 How the Output Connects to the LWC
1. **The Flow Assignment Element:**
   ```xml
   <assignments>
       <name>Assign_Wizard_Output</name>
       <assignmentItems>
           <assignToReference>Options.jsonString</assignToReference>
           <operator>Assign</operator>
           <value>
               <elementReference>MergedWizardJSON</elementReference>
           </value>
       </assignmentItems>
   </assignments>
   ```
2. **The Apex Class [`CorporateTravelWizardData.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/CorporateTravelWizardData.cls):**
   ```apex
   public class CorporateTravelWizardData {
       @AuraEnabled public String jsonString;
   }
   ```
3. **The Custom Lightning Type (CLT) [`renderer.json`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lightningTypes/corporateTravelRfpWizard/lightningDesktopGenAi/renderer.json):**
   ```json
   {
     "renderer": {
       "componentOverrides": {
         "$": {
           "definition": "c/corporateTravelRfpWizard"
         }
       }
     }
   }
   ```
4. **The LWC [`corporateTravelRfpWizard`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lwc/corporateTravelRfpWizard/corporateTravelRfpWizard.js):**
   * Receives `@api value` (which contains `jsonString`).
   * Parses the JSON and renders the appropriate mode (`isUploadMode` or multi-step wizard form).
   * When user submits, dispatches an event / calls MIAW `sendTextMessage()` to trigger the next agent topic action.

---

*Generated from source code analysis of `d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/`*
