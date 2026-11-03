# Internal Agent Deep Dive
## Ethiopian Airlines Corporate Rate & Contract Generation Agent — Step-by-Step Implementation

---

## 0. Big Picture: What Is This?

The **Corporate Rate & Contract Generation Agent** is an **internal Agentforce Employee Agent** (a.k.a. `InternalCopilot`) that runs inside the Salesforce desktop UI — NOT in a public-facing chat window. It assists **Ethiopian Airlines sales reps** in:

1. Reviewing incoming Corporate Travel RFP submissions
2. Looking up the qualifying discount tier and pricing matrix
3. Presenting a negotiation brief with rate assessment
4. Accepting a pricing offer (with optional escalation and approval)
5. Generating a Word contract draft via Document Generation Package (DGP)
6. Drafting and sending the contract email to the prospect

> [!IMPORTANT]
> The **customer-facing agent** (External Copilot) _collects_ the RFP. This **internal agent** _processes_ it — pricing, contract, and delivery. They are two completely separate agents that operate on the same `Corporate_Travel_RFP__c` record.

---

## 1. Entry Point: The Agent Definition

### Source File
[`Corporate_Rate_Contract_Generation.aiAgentDefinition-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/aiAgents/Corporate_Rate_Contract_Generation.aiAgentDefinition-meta.xml)

### Key Properties
```xml
<AiAgentDefinition>
    <agentDSLEnabled>true</agentDSLEnabled>
    <agentDescription>Corporate Rate &amp; Contract Generation</agentDescription>
    <agentType>AgentforceEmployeeAgent</agentType>
    <logPrivateConversationData>false</logPrivateConversationData>
    <richContentEnabled>true</richContentEnabled>
    <type>InternalCopilot</type>
</AiAgentDefinition>
```

| Property | Value | What it Means |
|---|---|---|
| `agentType` | `AgentforceEmployeeAgent` | This is an **employee-facing** agent (not a service agent for customers) |
| `type` | `InternalCopilot` | It appears inside the Salesforce desktop copilot panel, not in a MIAW chat window |
| `richContentEnabled` | `true` | The agent can render Custom Lightning Types (CLTs) — rich UI cards inside the copilot panel |
| `agentDSLEnabled` | `true` | The agent supports the declarative DSL (domain-specific language) for topic/action configuration |
| `logPrivateConversationData` | `false` | Conversation data is not logged to Data Cloud for privacy |

### How an Employee Accesses It
The rep opens the **Agentforce Copilot panel** (the floating assistant icon) while on a `Corporate_Travel_RFP__c` record page. The agent appears in the right sidebar. The rep can type natural language instructions like:
- "Show me the negotiation brief for this RFP"
- "Accept discount row 2 with a Rule 2 uplift of 3%"
- "Generate the contract and email it"

---

## 2. Where the Agent Lives: The Record Page

### Source File
[`Corporate_Travel_RFP_Record_Page.flexipage-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flexipages/Corporate_Travel_RFP_Record_Page.flexipage-meta.xml)

This is the Lightning Record Page layout for `Corporate_Travel_RFP__c`. It includes:

| Region | Component | Purpose |
|---|---|---|
| Header | `force:highlightsPanel` | Standard record highlights (Name, Owner, etc.) |
| Header | `c:rfpSummaryCard` | Custom LWC showing company name, NFR target, licence confidence, and a computed value score |
| Body | Standard record detail fields | Status, submission date, company info, contact, budget, discount requests |
| Body | `c:pricingRecommendationCard` | Current offer details — tier, row, rates, approval status, soft benefits |
| Body | `c:businessLicenceViewer` | Preview of the uploaded business licence document |
| Body | `c:licenceAnalystNotes` | AI-generated validation notes from the licence analysis |
| Sidebar | Agentforce Copilot Panel | Where the internal agent chat appears |

> [!NOTE]
> The rep sees the RFP data, licence health, and pricing card **on the same page** where they chat with the agent. The agent can modify the record fields in real-time, and the LWC components auto-refresh via `@wire` reactivity.

---

## 3. Agent Topics and Actions (Configured in Agent Builder)

The agent definition XML file is a "shell" — it does not contain topics or action bindings. Those are configured in **Agent Builder** (Setup → Agentforce → Agent Builder) in the Salesforce org. Based on the Apex `@InvocableMethod` classes and their `category='Corporate Travel'` labels, the internal agent's actions are:

### Topic: Pricing & Negotiation

| Action Name (Likely) | Apex Class | Purpose |
|---|---|---|
| `auto_detect_rfp_context` | [`AutoDetectRfpContext`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/AutoDetectRfpContext.cls) | Identifies which RFP the rep is looking at |
| `get_rfp_with_matrix_data` | [`GetRfpWithMatrixData`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/GetRfpWithMatrixData.cls) | Loads the RFP, qualifying tier, all discount rows, and negotiation brief |
| `get_pricing_recommendation` | [`PricingRecommendationService`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/PricingRecommendationService.cls) | Returns all available discount rows with a human-readable summary |
| `accept_pricing_row` | [`AcceptPricingRow`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/AcceptPricingRow.cls) | Writes the selected row to the RFP `Offer_*` fields |
| `show_negotiation_brief` | Flow → CLT | Renders the negotiation brief card in the copilot panel |

### Topic: Contract Generation & Email

| Action Name (Likely) | Apex Class | Purpose |
|---|---|---|
| `generate_contract_draft` | [`GenerateContractDraft`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/GenerateContractDraft.cls) | Creates a Word contract using Document Generation Package |
| `prepare_email_draft` | [`PrepareEmailDraft`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/PrepareEmailDraft.cls) | Packages the email draft into a CLT display card |
| `send_contract_email` | [`SendContractEmail`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/SendContractEmail.cls) | Sends the actual email with contract attachment |
| `show_email_draft` | Flow → CLT | Renders the email draft card for rep review |

### Topic: Business Licence Upload

| Action Name (Likely) | Flow | Purpose |
|---|---|---|
| `show_licence_upload` | [`businessLicenceUploadClt_Output`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flows/businessLicenceUploadClt_Output.flow-meta.xml) | Shows the licence upload widget in copilot |

---

## 4. Step 1: Auto-Detecting the RFP Context

### The Problem
When the rep opens the copilot and says "Show me the pricing options", the agent needs to know _which_ RFP they're referring to.

### The Solution: `AutoDetectRfpContext`
[`AutoDetectRfpContext.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/AutoDetectRfpContext.cls)

```
Rep opens RFP record page
    → (Salesforce adds to RecentlyViewed)
Rep opens copilot and asks a question
    → (Agent calls auto_detect_rfp_context)
AutoDetectRfpContext queries RecentlyViewed
    → (Returns the most recent Corporate_Travel_RFP__c or Opportunity Id)
Agent now has the recordId for all subsequent actions
```

**How it works:**
1. Queries `RecentlyViewed WHERE Type = 'Corporate_Travel_RFP__c'` — checks for the most recent RFP
2. If no RFP found, falls back to `RecentlyViewed WHERE Type = 'Opportunity'` — because the rep might be on the linked Opportunity
3. Returns an empty string if nothing is found

**Input:** Nothing meaningful (a `placeholder` variable exists but is unused)

**Output:** `recordId` (String) — the Id of the most recently viewed RFP or Opportunity

> [!TIP]
> `GetRfpWithMatrixData` accepts **both** RFP IDs and Opportunity IDs. If it gets an Opportunity ID (starts with `006`), it queries the linked RFP via `WHERE Opportunity__c = :recordId`. This is why the context auto-detect can return either type.

---

## 5. Step 2: Loading the Pricing Matrix — `GetRfpWithMatrixData`

This is the **central data-loading action** for the internal agent. It produces everything the agent needs to guide the pricing conversation.

### Source File
[`GetRfpWithMatrixData.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/GetRfpWithMatrixData.cls)

### What It Does (Step by Step)

```
Agent calls get_rfp_with_matrix_data(recordId)

1. fetchRfp(recordId)
   → If starts with '006': query RFP WHERE Opportunity__c = :recordId
   → Otherwise: query RFP WHERE Id = :recordId

2. fetchTierRows(nfr)
   → SELECT FROM ET_Discount_Tier__c
     WHERE NFR_Lower_USD__c <= nfr
     AND (NFR_Upper_USD__c >= nfr OR NFR_Upper_USD__c = null)
   → Returns up to 5 discount rows, ordered by Row_Number__c ASC

3. fetchSoftBenefit(nfr)
   → SELECT FROM ET_Soft_Benefit_Tier__c using same NFR range match
   → Returns 1 soft benefit row

4. buildRateAssessment(rfp, tierRows)
   → Compares prospect's requested rates vs Row 1 maximums
   → Returns text like: "Economy discount 11% EXCEEDS the pre-approved
     Row 1 maximum (7.00%)"

5. buildSummary(rfp, tierRows, softTier)
   → Generates a human-readable markdown negotiation brief

6. buildBriefDisplay(rfp, tierRows, softTier)
   → Returns a RfpNegotiationBriefData object containing JSON
     for the CLT rendering

7. buildSoftBenefitQuestion(acceptedRowSoftOptionsCount, softTier)
   → Pre-builds the exact question the agent should ask about
     soft benefits

Returns all 20+ output fields to the agent
```

### Understanding the Discount Tier Data Model

The pricing matrix lives in two Custom Objects:

#### `ET_Discount_Tier__c` — Discount Rows
Each NFR tier has multiple rows (1–5), ordered from lowest discount to highest:

| Field | Example | Purpose |
|---|---|---|
| `Tier_Label__c` | "$100K–$299,999" | Human-readable tier name |
| `Row_Number__c` | 1, 2, 3, 4, 5 | Row 1 = default (pre-approved). Row 2+ = requires manager approval |
| `NFR_Lower_USD__c` | 100000 | Minimum Annual NFR to qualify |
| `NFR_Upper_USD__c` | 299999 (or null for top tier) | Maximum Annual NFR |
| `Economy_Lower_Pct__c` | 4.00 | Economy T–K fare class discount |
| `Economy_Higher_Pct__c` | 5.00 | Economy M–Y fare class discount |
| `D_Class_Pct__c` | 9.00 | Business D fare class discount |
| `J_Class_Pct__c` | 10.00 | Business J fare class discount |
| `C_Class_Pct__c` | 11.00 | Business C fare class discount |
| `Soft_Options_Count__c` | 4 | How many soft benefits the client can pick at this row |
| `Routing_Scope__c` | "Requesting Station Only" | Geographic scope of the discount |

**Key Rule:** Row 1 = highest soft benefit count, lowest discount. Row 5 = lowest soft benefit count, highest discount. There is a **trade-off** the rep negotiates.

#### `ET_Soft_Benefit_Tier__c` — Soft Benefits
One row per tier, defining available extras:

| Field | Purpose |
|---|---|
| `Free_Tickets__c` / `Free_Tickets_Active__c` | Complimentary tickets per year |
| `Free_Date_Changes__c` / `Free_Date_Changes_Active__c` | Free date change allowance |
| `Baggage_Uplift_Kg__c` / `Baggage_Active__c` | Extra baggage in kg |
| `Upgrades__c` / `Upgrades_Active__c` | Upgrade vouchers |
| `Lounge_At_Origin__c` / `Lounge_Active__c` | Lounge access at departure |
| `Skylight_Hotel_Active__c` | 20% hotel discount eligibility |

### Output Fields Returned to the Agent

| Field | Type | Purpose |
|---|---|---|
| `rfpId` | String | The RFP record Id |
| `companyName` | String | Company name from the RFP |
| `annualNfrTargetUsd` | String | Formatted NFR e.g. "$118K" |
| `corporateId` | String | Corporate ID (blank if not yet assigned) |
| `requestedEconomy` | String | What discount the prospect asked for |
| `requestedBusiness` | String | What business class discount the prospect asked for |
| `qualifyingTierLabel` | String | e.g. "$100K–$299,999" |
| `tierRowsJson` | String | JSON array of all 5 discount rows |
| `softBenefitJson` | String | JSON of the soft benefit tier |
| `negotiationSummary` | String | Markdown-formatted brief for the agent to present |
| `rateAssessmentSummary` | String | Pre-computed assessment: within limits or exceeds |
| `softBenefitQuestion` | String | Pre-built question about soft benefit selection |
| `offerMatrixRow` | Integer | Currently accepted row (null = no offer yet) |
| `pricingApprovalStatus` | String | "Pending", "Approved", or null |
| `contractContentId` | String | ContentDocument Id of existing contract draft |
| `contactName` / `contactEmail` | String | Contact info for the email step |
| `maxAvailableRowNumber` | Integer | Highest row available in this tier |
| `negotiationBriefDisplay` | `RfpNegotiationBriefData` | **CLT output** — renders the visual negotiation brief card |
| `errorMessage` | String | Non-null if something went wrong |

> [!IMPORTANT]
> The `negotiationBriefDisplay` field is the CLT bridge. It is an Apex-Defined output of type `RfpNegotiationBriefData`, which maps to the `rfpNegotiationBriefRenderer` LWC via the CLT `renderer.json`. When the agent returns this field, the copilot panel renders the interactive card.

---

## 6. Step 2b: Alternative Pricing Lookup — `PricingRecommendationService`

### Source File
[`PricingRecommendationService.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/PricingRecommendationService.cls)

This is a **simpler, read-only** pricing lookup compared to `GetRfpWithMatrixData`. It focuses on the discount options without the negotiation brief context.

### Output
| Field | Purpose |
|---|---|
| `tierLabel` | Qualifying tier name |
| `routingScope` | Geographic scope |
| `offerOptionsSummary` | ASCII table of all rows with discount rates |
| `allRowsJson` | JSON array for programmatic consumption |
| `row1EconomyLowerPct` ... `row1CClassPct` | Individual Row 1 rate fields |
| `row1SoftOptionsCount` | How many soft benefits at Row 1 |
| `availableBenefitsSummary` | Human-readable list of active benefits |

### Difference from `GetRfpWithMatrixData`
| Feature | `GetRfpWithMatrixData` | `PricingRecommendationService` |
|---|---|---|
| Loads the full RFP context | Yes | No (only needs rfpId) |
| Rate assessment vs. prospect request | Yes | No |
| Generates CLT display card | Yes (via `negotiationBriefDisplay`) | No |
| Pre-builds soft benefit question | Yes | No |
| Returns all rows as JSON | Yes | Yes |
| Read-only (no DML) | Yes | Yes |

---

## 7. The Negotiation Brief CLT — Visual Output in the Copilot

### Architecture

```
GetRfpWithMatrixData.buildBriefDisplay()
    Returns RfpNegotiationBriefData(jsonString)
        Platform detects the Apex type

CLT: lightningTypes/RfpNegotiationBrief/
    schema.json   → links to @apexClassType/c__RfpNegotiationBriefData
    lightningDesktopGenAi/renderer.json → maps to c/rfpNegotiationBriefRenderer
        Renders the LWC

LWC: rfpNegotiationBriefRenderer
    Parses JSON and displays:
    - Company header (name, NFR target, qualifying tier)
    - Rate assessment callout (green = within limits, amber = exceeds)
    - Discount rows table (each row with approval status pill)
    - Soft benefits summary
    - Rule 2 uplift note
```

### The CLT Files

**[`schema.json`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lightningTypes/RfpNegotiationBrief/schema.json):**
```json
{
  "title": "RFP Negotiation Brief",
  "description": "Displays the qualifying NFR tier, available discount rows, soft benefits, and rule 2 note.",
  "lightning:type": "@apexClassType/c__RfpNegotiationBriefData"
}
```

**[`renderer.json`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lightningTypes/RfpNegotiationBrief/lightningDesktopGenAi/renderer.json):**
```json
{
  "renderer": {
    "componentOverrides": {
      "$": {
        "definition": "c/rfpNegotiationBriefRenderer"
      }
    }
  }
}
```

### The Apex Data Envelope
[`RfpNegotiationBriefData.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/RfpNegotiationBriefData.cls):
```apex
@JsonAccess(serializable='always' deserializable='always')
global class RfpNegotiationBriefData {
    @AuraEnabled
    global String rfpNegotiationBriefJSON;  // The payload
}
```

### The LWC Renderer
[`rfpNegotiationBriefRenderer.js`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lwc/rfpNegotiationBriefRenderer/rfpNegotiationBriefRenderer.js):

**Key implementation details:**
1. **Unwraps the Apex envelope:** `__unwrapApexEnvelope()` extracts the `rfpNegotiationBriefJSON` field and parses it
2. **Builder fallback:** Includes a hardcoded `BUILDER_FALLBACK_JSON` constant — this lets the component preview in Agent Builder without live data
3. **`@api value`** setter uses `__unwrapApexEnvelope(v)` to handle the platform's wrapper format
4. **Computed getters:** `discountRowsWithLabel`, `assessmentSummary`, `hasSoftBenefits`, etc. transform the JSON data into display-ready properties

> [!TIP]
> **Pattern for the internal agent CLT:** Unlike the external agent (which uses `__show_tool_results__` in a chat window), the internal agent renders CLTs directly in the **copilot side panel**. The renderer directory name `lightningDesktopGenAi` tells the platform this CLT renders in the desktop copilot context (not in an Enhanced Web Chat context).

---

## 8. Step 3: Accepting a Pricing Row — `AcceptPricingRow`

### Source File
[`AcceptPricingRow.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/AcceptPricingRow.cls)

### What the Rep Tells the Agent
- "Accept row 1 for this RFP" → default, pre-approved
- "Accept row 3, justify: long-term partnership" → escalation
- "Accept row 2 with a Rule 2 uplift of 3%" → escalation + non-commissionable uplift

### Input Parameters

| Parameter | Type | Required | Purpose |
|---|---|---|---|
| `rfpId` | Id | Yes | Which RFP to update |
| `rowNumber` | Integer | Yes | 1 = default, 2+ = higher discount (needs approval) |
| `escalationJustification` | String | When row > 1 | Business reason for the higher row |
| `applyRule2Uplift` | Boolean | No | Whether to add Rule 2 uplift |
| `rule2UpliftPct` | Decimal | When Rule 2 = true | 1–4% additional across all fare classes |
| `negotiationBrief` | String | No | Free-text negotiation context |

### What It Does (Step by Step)

```
1. Query the RFP to get Annual_NFR_Target_USD__c and current contract version

2. Look up the specific ET_Discount_Tier__c row matching
   the NFR range + rowNumber

3. Calculate whether escalation is needed:
   - Row > 1 → needs escalation
   - Rule 2 uplift applied → needs escalation

4. Write Offer_* fields on the RFP:
   - Offer_Matrix_Tier__c, Offer_Matrix_Row__c
   - Offer_Economy_Lower_Pct__c = row rate + Rule 2 uplift
   - (same for all 5 fare classes)
   - Offer_Soft_Options_Count__c, Offer_Routing_Scope__c
   - Offer_Rule2_Uplift_Applied__c, Offer_Rule2_Uplift_Pct__c
   - Offer_Contract_Version__c = next version
   - Status__c = 'Offer Prepared'

5. If escalation needed:
   - Escalation_Type__c = 'Rule 2 Uplift' or 'In-Tier Row Increase'
   - Pricing_Approval_Status__c = 'Pending'
   - Submit to Salesforce Approval Process
   (approval submission failure is caught and logged, not returned as error)

6. Return success, escalation status, and tier label
```

### Output

| Field | Purpose |
|---|---|
| `success` | Boolean — whether the write succeeded |
| `errorMessage` | Error details if failed |
| `updatedVersion` | New contract version number |
| `escalationRequired` | True if manager approval is needed |
| `approvalStatus` | "Pending" if escalation, null if default row |
| `tierLabel` | The tier name for confirmation |

> [!WARNING]
> **Silent approval failure:** If the Approval Process submission fails (no matching process, record already in approval, etc.), the exception is caught and only debug-logged. The `Pricing_Approval_Status__c` will still show "Pending" even though no approval was actually submitted. This should be validated in your Salesforce org.

---

## 9. Step 4: Generating the Contract — `GenerateContractDraft`

### Source File
[`GenerateContractDraft.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/GenerateContractDraft.cls)

### Input Parameters

| Parameter | Type | Required | Purpose |
|---|---|---|---|
| `rfpId` | Id | Yes | Which RFP to generate the contract for |
| `includeFreeDateChanges` | Boolean | No | Include Annex I section 2.2 free date change clause |
| `includeFreeTickets` | Boolean | No | Include Annex I section 2.3 free tickets clause |
| `includeHotelDiscount` | Boolean | No | Include Skylight Hotel discount clause |
| `etSignatoryName` | String | No | ET signatory name for the contract |

### Gate Checks Before Generation

```
1. APPROVAL GATE:
   - Row 1 → always passes (pre-approved)
   - Row 2+ → requires Pricing_Approval_Status__c = 'Approved'
   - If not approved → return error, block generation

2. SOFT BENEFIT LIMIT GATE:
   - Count selected benefits (freeDateChanges + freeTickets + hotelDiscount)
   - Compare against Offer_Soft_Options_Count__c from the tier row
   - If exceeds limit → return error

3. VERSION OVERFLOW GUARD:
   - Contract version field is Number(3,0), max 999
   - If >= 999 → return error

4. TEMPLATE CHECK:
   - Offer_Contract_Template__c must be set (defaults to 'Main')
   - Resolves to DocumentTemplate named 'ET Standard Corporate Agreement'
   - Gets the LatestPublishedVersionId from ContentDocumentLink
```

### Contract Generation Pipeline

```
1. Resolve ContentVersionId from DocumentTemplate

2. Query Travel_Agency__c and Travel_Route__c related to the RFP

3. Query ET_Soft_Benefit_Tier__c for free ticket count

4. Auto-generate Corporate ID if blank (format: ETA001, ETA002, ...)

5. Build token data map (30+ template merge fields):
   - CompanyName, Address, City, Country, Website
   - ContactEmail, ContactName, CorporateId
   - SigningDate (formatted: "3 November 2026")
   - AnnualNFRTarget, AnnualNFRQuarterly
   - DiscountRoutes (per-route rates table)
   - TravelAgencies (IATA name, number, PCC, GDS)
   - IncludeFreeDateChanges, IncludeFreeTickets, IncludeHotelDiscount
   - ETSignatoryName

6. Update RFP record:
   - Offer_Contract_Generated_Date__c = today
   - Offer_Contract_Version__c = next version
   - Corporate_ID__c = auto-generated
   - Status__c = 'Contract Draft'

7. Enqueue ContractGenPoller (Queueable):
   First execution: INSERT DocumentGenerationProcess
   Subsequent executions: POLL until DGP status = 'Success'
   On success: Link ContentDocument to RFP,
               update Offer_Contract_Content_Id__c
```

### The Document Generation Package (DGP) Integration

The contract is generated by Salesforce's managed package `ind_docgen_api`. The pipeline is:

```
GenerateContractDraft (your code)
    Creates DocumentGenerationProcess record
DocumentGenerationProcess (managed package DML)
    Uses the Word template with {{Mustache}} tokens
RfpDocGenTokenProvider (your code, implements ind_docgen_api.OpenInterface)
    Passes token data through unchanged
Managed Package Engine
    Merges tokens into the Word template
    Returns ContentVersionId of the generated document
ContractGenPoller (your code, Queueable)
    Polls DGP status up to 10 times
    On success: links ContentDocument to RFP
```

### `RfpDocGenTokenProvider`
[`RfpDocGenTokenProvider.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/RfpDocGenTokenProvider.cls):
```apex
global class RfpDocGenTokenProvider implements ind_docgen_api.OpenInterface {
    global Boolean invokeMethod(String methodName,
            Map<String, Object> inputMap, Map<String, Object> outMap) {
        if (methodName == 'transformTokenData') {
            String tokenData = (String) inputMap.get('TokenData');
            if (tokenData != null) {
                outMap.put('TokenData', tokenData);
            }
            return true;
        }
        return false;
    }
}
```
This is a **pass-through** — `GenerateContractDraft` pre-builds all token data, so the provider just forwards it unchanged to the DGP engine.

---

## 10. Step 5: Preparing the Email Draft — `PrepareEmailDraft`

### Source File
[`PrepareEmailDraft.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/PrepareEmailDraft.cls)

### What It Does
The agent drafts the email text (subject + body) using its LLM capabilities, then calls `prepare_email_draft` to package it into a visual card for the rep to review.

### Input Parameters
| Parameter | Type | Purpose |
|---|---|---|
| `subject` | String | Email subject line |
| `emailBody` | String | Plain-text email body |
| `toEmail` | String | Recipient email |
| `toName` | String | Recipient name |

### Output
| Field | Type | Purpose |
|---|---|---|
| `emailDraftCard` | `ContractEmailDraftData` | **CLT output** — renders the email preview card |
| `draftReadyMessage` | String | "Contract email draft ready for review — Mrs. Al-Hussein." |

### The Email Draft CLT

```
PrepareEmailDraft.prepare()
    Returns ContractEmailDraftData(jsonString)

CLT: lightningTypes/ContractEmailDraft/
    schema.json   → @apexClassType/c__ContractEmailDraftData
    lightningDesktopGenAi/renderer.json → c/contractEmailDraftCard

LWC: contractEmailDraftCard
    Displays:
    - Subject line
    - Recipient (name — email)
    - Body paragraphs
```

[`ContractEmailDraftData.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/ContractEmailDraftData.cls):
```apex
@JsonAccess(serializable='always' deserializable='always')
global class ContractEmailDraftData {
    @AuraEnabled
    global String contractEmailDraftJSON;
}
```

[`contractEmailDraftCard.js`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lwc/contractEmailDraftCard/contractEmailDraftCard.js):
- Same `__unwrapApexEnvelope` pattern as the negotiation brief
- Includes `BUILDER_FALLBACK_JSON` for Agent Builder preview
- Parses `body` into paragraphs by splitting on `\n`

---

## 11. Step 6: Sending the Contract Email — `SendContractEmail`

### Source File
[`SendContractEmail.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/SendContractEmail.cls)

### Gate Checks

```
1. Contact email must exist on the RFP

2. Contract document must exist (Offer_Contract_Content_Id__c)

3. Org-wide email address must be configured:
   - "Ethiopian Airlines Global Corporate Sales"
   - OR "ET No Reply Email Address"

4. Sandbox safety: only allows @salesforce.com or
   @ethiopianairlines.com domains
```

### Email Construction

```
1. Retrieve contract file blob from ContentVersion (latest version)

2. Build EmailFileAttachment from VersionData

3. Build HTML email body using buildHtmlBody():
   - Ethiopian Airlines branded header (green #1a5c38)
   - Gold accent strip (#c8a951)
   - Body paragraphs from agent-drafted text
   - Footer with GlobalCorporateSales@ethiopianairlines.com

4. Set org-wide email address as sender

5. If Contact record found → link as Activity

6. Send via Messaging.sendEmail()

7. Update RFP Status__c = 'Contract Sent'
```

> [!NOTE]
> The logo URL is constructed dynamically from the org domain: `{siteDomain}/etcorporatetravelvforcesitevforcesite/resource/etAirlineImages/logo.png`. This requires the VF Site and static resources to be deployed.

---

## 12. The Record Page LWC Components

### `rfpSummaryCard` — RFP Overview with Value Score
[`rfpSummaryCard.js`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lwc/rfpSummaryCard/rfpSummaryCard.js)

**Uses:** `@wire(getRecord)` with 12 fields from `Corporate_Travel_RFP__c`

**Features:**
- Displays company name, status, request type, submission date
- Formatted budget and NFR target (e.g. "$1.2M", "$118K")
- **Value Score** (0–100): a composite score from:
  - NFR tier (0–40 pts)
  - Licence confidence (0–25 pts: High/Medium/Low)
  - Company name match (0–20 pts: Match/Partial/None)
  - Licence validity (0–15 pts based on months to expiry)
- Colour-coded badges for licence confidence and value rating

### `pricingRecommendationCard` — Current Offer Display
[`pricingRecommendationCard.js`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lwc/pricingRecommendationCard/pricingRecommendationCard.js)

**Uses:** `@wire(getOfferData)` from [`GetRfpOfferData.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/GetRfpOfferData.cls)

**Features:**
- Shows the current offer: tier, row number, all 5 fare class rates
- Approval status banner (Pending/Approved/Rejected with icons)
- "Discount Offer 1 — Default" vs "Discount Offer 3 — Escalated" badges
- Rule 2 uplift percentage if applied
- Soft benefits list with active/inactive indicators
- Refresh button to re-query after agent updates the record

### `GetRfpOfferData` — Offer Data Provider
[`GetRfpOfferData.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/GetRfpOfferData.cls)

**Cacheable:** Yes (`@AuraEnabled(cacheable=true)`)

Returns the `Offer_*` fields from the RFP plus the matching soft benefits from `ET_Soft_Benefit_Tier__c`, packaged into an `OfferData` wrapper with nested `BenefitItem` objects.

---

## 13. Business Licence Upload CLT (Internal Agent)

The internal agent can also prompt the rep to upload a business licence:

### Flow
[`businessLicenceUploadClt_Output.flow-meta.xml`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/flows/businessLicenceUploadClt_Output.flow-meta.xml)

This is a simple adapter Flow:
- **Input:** `Details` (String) — JSON configuration for the upload widget
- **Output:** `Options` (Apex: `BusinessLicenceUploadCltData`) — wrapped JSON for CLT rendering

### CLT
[`businessLicenceUploadClt/schema.json`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/lightningTypes/businessLicenceUploadClt/schema.json):
```json
{
  "title": "Business Licence Upload CLT",
  "description": "Document upload widget for business licence intake.",
  "lightning:type": "@apexClassType/c__BusinessLicenceUploadCltData"
}
```

Note: This CLT has **two renderer directories**:
- `enhancedWebChat/` — for the external agent (MIAW chat window)
- `lightningDesktopGenAi/` — for the internal agent (copilot panel)

This means the **same** CLT can render in both agent contexts.

### Business Licence Viewer
[`BusinessLicencePreviewController.cls`](file:///d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/classes/BusinessLicencePreviewController.cls) — A Visualforce controller that renders the uploaded licence as an inline PDF preview or Word doc rendition.

---

## 14. End-to-End Conversation Flow

Here is what a complete internal agent interaction looks like:

```
Rep opens Corporate_Travel_RFP__c record page
  → rfpSummaryCard shows company info + value score
  → pricingRecommendationCard shows "No offer set"
  → businessLicenceViewer shows uploaded licence
  → licenceAnalystNotes shows AI validation results
                       |
                       v
Rep opens copilot: "Show me the negotiation brief"
  Agent calls: auto_detect_rfp_context → gets recordId
  Agent calls: get_rfp_with_matrix_data(recordId)
  Agent returns: negotiationBriefDisplay (CLT)

  → Copilot renders rfpNegotiationBriefRenderer:
    - Header: "Pinnacle Aviation, $118K, Tier 2"
    - Assessment: "Economy 11% EXCEEDS Row 1 max (7%)"
    - Discount rows table (Row 1–4 with approval pills)
    - Soft benefits: 2 tickets, 1 date change, 5kg bag
    - Rule 2 note: "Not applied"
                       |
                       v
Rep: "Accept row 3, justify: long-term partnership"
  Agent calls: accept_pricing_row(
    rfpId, rowNumber=3,
    escalationJustification="long-term partnership"
  )
  → RFP updated: Offer_Matrix_Row__c = 3
    Escalation_Required__c = true
    Pricing_Approval_Status__c = 'Pending'
    Approval submitted to manager

  → pricingRecommendationCard auto-refreshes:
    Shows "Discount Offer 3 — Escalated, Pending"
                       |
                       v
[Manager approves → Pricing_Approval_Status__c = Approved]
  → pricingRecommendationCard: "Offer Approved"
                       |
                       v
Rep: "Generate the contract with free date changes
      and free tickets. Signatory: Yohannes Tefera"
  Agent calls: generate_contract_draft(
    rfpId,
    includeFreeDateChanges=true,
    includeFreeTickets=true,
    includeHotelDiscount=false,
    etSignatoryName="Yohannes Tefera"
  )
  → Approval gate: Row 3 + Approved (pass)
  → Soft benefit gate: 2 selected <= 2 allowed at Row 3 (pass)
  → Corporate ID auto-generated: ETA042
  → DGP Queueable enqueued → polls until document ready
  → RFP Status = 'Contract Draft'
                       |
                       v
Rep: "Draft an email to the prospect"
  Agent drafts email text using LLM, then calls:
  prepare_email_draft(
    subject="Ethiopian Airlines Corporate Agreement...",
    emailBody="Dear Mrs. Al-Hussein, ...",
    toEmail="contact@pinnacle.com",
    toName="Mrs. Fatima Al-Hussein"
  )
  → Copilot renders contractEmailDraftCard:
    Subject, recipient, and formatted body preview

  Rep reviews: "Looks good, send it"

  Agent calls: send_contract_email(
    rfpId, emailSubject, emailBody
  )
  → Gate checks pass
  → Contract file attached
  → Branded HTML email sent from ET Global Corporate Sales
  → RFP Status = 'Contract Sent'
  → Activity logged on Contact record
```

---

## 15. Full Component Dependency Tree

```
Corporate_Rate_Contract_Generation (InternalCopilot)
|
+-- Topic: Pricing & Negotiation
|   +-- Action: auto_detect_rfp_context
|   |   +-- Apex: AutoDetectRfpContext (@InvocableMethod)
|   |       +-- SObject: RecentlyViewed
|   |
|   +-- Action: get_rfp_with_matrix_data
|   |   +-- Apex: GetRfpWithMatrixData (@InvocableMethod)
|   |       +-- SObject: Corporate_Travel_RFP__c
|   |       +-- SObject: ET_Discount_Tier__c
|   |       +-- SObject: ET_Soft_Benefit_Tier__c
|   |       +-- Apex: RfpNegotiationBriefData
|   |           +-- CLT: RfpNegotiationBrief
|   |               +-- LWC: rfpNegotiationBriefRenderer
|   |
|   +-- Action: get_pricing_recommendation
|   |   +-- Apex: PricingRecommendationService (@InvocableMethod)
|   |       +-- SObject: Corporate_Travel_RFP__c
|   |       +-- SObject: ET_Discount_Tier__c
|   |       +-- SObject: ET_Soft_Benefit_Tier__c
|   |
|   +-- Action: accept_pricing_row
|       +-- Apex: AcceptPricingRow (@InvocableMethod)
|           +-- SObject: Corporate_Travel_RFP__c
|           +-- SObject: ET_Discount_Tier__c
|           +-- Salesforce Approval Process
|
+-- Topic: Contract Generation & Email
|   +-- Action: generate_contract_draft
|   |   +-- Apex: GenerateContractDraft (@InvocableMethod)
|   |       +-- SObject: Corporate_Travel_RFP__c
|   |       +-- SObject: Travel_Agency__c
|   |       +-- SObject: Travel_Route__c
|   |       +-- SObject: ET_Soft_Benefit_Tier__c
|   |       +-- SObject: DocumentTemplate
|   |       +-- SObject: ContentVersion / ContentDocumentLink
|   |       +-- Queueable: ContractGenPoller
|   |       |   +-- SObject: DocumentGenerationProcess (managed pkg)
|   |       +-- Apex: RfpDocGenTokenProvider (ind_docgen_api)
|   |
|   +-- Action: prepare_email_draft
|   |   +-- Apex: PrepareEmailDraft (@InvocableMethod)
|   |       +-- Apex: ContractEmailDraftData
|   |           +-- CLT: ContractEmailDraft
|   |               +-- LWC: contractEmailDraftCard
|   |
|   +-- Action: send_contract_email
|       +-- Apex: SendContractEmail (@InvocableMethod)
|           +-- SObject: Corporate_Travel_RFP__c
|           +-- SObject: ContentVersion
|           +-- SObject: OrgWideEmailAddress
|           +-- SObject: Contact (for Activity)
|           +-- Messaging.sendEmail()
|
+-- Topic: Business Licence Upload
|   +-- Action: show_licence_upload
|       +-- Flow: businessLicenceUploadClt_Output
|           +-- Apex: BusinessLicenceUploadCltData
|               +-- CLT: businessLicenceUploadClt
|                   +-- LWC: businessLicenceUploadClt
|
+-- Record Page Components (not agent actions, on same page)
    +-- LWC: rfpSummaryCard
    |   +-- @wire(getRecord) → Corporate_Travel_RFP__c (12 fields)
    +-- LWC: pricingRecommendationCard
    |   +-- @wire(getOfferData) → GetRfpOfferData.cls
    |       +-- SObject: Corporate_Travel_RFP__c
    |       +-- SObject: ET_Soft_Benefit_Tier__c
    +-- LWC: businessLicenceViewer
    |   +-- Apex: BusinessLicencePreviewController (VF)
    +-- LWC: licenceAnalystNotes
```

---

## 16. Key Design Patterns to Replicate

| Pattern | Implementation | Why |
|---|---|---|
| **InternalCopilot + `lightningDesktopGenAi`** | Agent type `InternalCopilot`, CLT renderer dir `lightningDesktopGenAi` | Renders rich cards in the desktop copilot panel (not MIAW chat) |
| **CLT as agent-to-LWC bridge** | Apex data class → CLT `schema.json` + `renderer.json` → LWC | Standard Agentforce pattern to display structured UI from an agent action |
| **`@InvocableMethod` as agent actions** | All business logic uses `@InvocableMethod(category='Corporate Travel')` | Agent Builder discovers invocable methods by category |
| **Record context auto-detection** | `AutoDetectRfpContext` queries `RecentlyViewed` | Agent knows which record the rep is looking at without being told |
| **Opportunity/RFP ID resolution** | `fetchRfp()` checks if ID starts with '006' (Opportunity key prefix) | Rep can launch the agent from either the RFP or Opportunity page |
| **Pre-computed agent text** | `rateAssessmentSummary`, `softBenefitQuestion`, `negotiationSummary` | Heavy formatting done in Apex, agent outputs verbatim — avoids LLM hallucination on numbers |
| **Builder fallback JSON** | `BUILDER_FALLBACK_JSON` constant in LWC | Enables visual preview in Agent Builder without live data |
| **Approval gate before contract** | `GenerateContractDraft` checks `Pricing_Approval_Status__c` | Row 2+ offers must be approved before a contract can be generated |
| **Soft benefit count gate** | Selected count vs. `Offer_Soft_Options_Count__c` | Prevents selecting more benefits than the row allows |
| **Async document generation** | `ContractGenPoller` Queueable polls DGP up to 10 times | DGP is asynchronous; Queueable chains handle the polling |
| **Auto-generated Corporate ID** | `generateCorporateId()` queries existing IDs and increments | Deterministic sequence: ETA001, ETA002, ... |
| **Branded HTML email** | `buildHtmlBody()` in `SendContractEmail` | Ethiopian Airlines green/gold branded email template |
| **Sandbox email safety** | Domain whitelist: `@salesforce.com` and `@ethiopianairlines.com` | Prevents accidental external emails in sandbox |
| **Value score composite** | `rfpSummaryCard.valueScore` combines NFR, licence confidence, name match, expiry | Visual lead qualification metric for rep decision-making |
| **`@wire` reactivity on record page** | `pricingRecommendationCard` and `rfpSummaryCard` use `@wire` | Components auto-update when the agent modifies the RFP record |
| **Dual-context CLT** | `businessLicenceUploadClt` has both `enhancedWebChat` and `lightningDesktopGenAi` renderers | Same CLT works in both external chat and internal copilot |

---

## 17. Key Differences: Internal vs. External Agent

| Dimension | External (Customer-Facing) | Internal (Employee-Facing) |
|---|---|---|
| **Agent Type** | `EinsteinServiceAgent` / `ExternalCopilot` | `AgentforceEmployeeAgent` / `InternalCopilot` |
| **Channel** | MIAW (Messaging for In-App and Web) | Salesforce Desktop Copilot Panel |
| **User** | Guest / Unauthenticated visitor | Logged-in Salesforce employee |
| **CLT Renderer Directory** | `enhancedWebChat` | `lightningDesktopGenAi` |
| **UI Pattern** | Chat bubbles with embedded LWC widgets | Copilot side panel with rich cards |
| **Trigger** | `sendTextMessage()` / `sendUtterance()` | Natural language typed into copilot |
| **`__show_tool_results__`** | Required (tells platform to render CLT in chat) | Not needed (copilot auto-renders CLT outputs) |
| **Data Access** | `without sharing` (guest user) | `with sharing` (respects user's permissions) |
| **Primary Purpose** | Collect RFP data from prospect | Process RFP: pricing, contract, email |
| **Record Interaction** | Creates `Corporate_Travel_RFP__c` | Reads/updates `Corporate_Travel_RFP__c` |
| **Document Flow** | Upload (RFP doc, business licence) | Generate (contract Word doc) |

---

*Generated from source code analysis of `d:/Dev/14_Salesforce/agentforce/agentforce-project/force-app/main/default/`*
