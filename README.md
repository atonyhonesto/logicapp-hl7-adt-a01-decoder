# Azure Logic Apps Standard – HL7 v2 ADT (A01) → HL7 XML → JSON (VS Code + Azurite)

This repository contains a **Logic App Standard** workflow that:
1. Receives an HL7 v2.x message via **HTTP request**  
2. Uses the **HL7 built-in connector – Decode HL7** action to convert HL7 v2 (flat file) → **HL7 XML** (no manual string parsing)  
3. Extracts required fields using **XPath** (against the decoded HL7 XML)  
4. Validates mandatory fields and returns **400** on validation failure  
5. Returns the required **structured JSON** payload

> **Important (Preview capability):** The HL7 built-in connector for Standard workflows is currently in preview and requires an Integration Account with uploaded HL7 schemas.

---

## Repo layout

```
LogicAppStandard_HL7_ADT_A01/
  host.json
  local.settings.json
  connections.json
  workflows/
    Hl7AdtA01ToJson/
      workflow.json
  README.md
```

---

## Prerequisites (local development)

### Tools
- VS Code + **Azure Logic Apps (Standard)** extension  
- Azure Functions Core Tools v4  
- Node.js 18+  
- Azurite

### Azure prerequisites
- An **Integration Account** in the same subscription/region as the Logic App  
- Uploaded HL7 schemas (example: `ADT_A01_231_GLO_DEF.xsd` + dependencies such as `datatypes_21.xsd`, `segments_21.xsd`, etc.)   
- Logic App Standard linked to the Integration Account  

---

## Running locally (AzURITE + Logic App)

### 1) Start Azurite
**Option A (VS Code extension):** Start Azurite from the Azurite extension.  
**Option B (CLI):**
```bash
azurite --silent --location .azurite --debug .azurite/debug.log
```

### 2) Configure local settings
`local.settings.json` already contains:
- `AzureWebJobsStorage = UseDevelopmentStorage=true` (AzURITE)
- Node runtime defaults

> If you already have your own storage connection string, replace that value.

### 3) Open the folder in VS Code and start the Logic App
- Press **F5** (Run → Start Debugging)  
- Or run:
```bash
func start
```

### 4) Find the local callback URL
When the host starts, the **Request trigger** prints a local URL in the terminal (it can take ~10–20 seconds on first start).

---

## Workflow – high level design

### Trigger
- **When a HTTP request is received**
- Request body schema expects:
```json
{ "hl7": "MSH|...\nPID|...\nPV1|..." }
```

### Decode step (no manual parsing)
- Action: **Decode HL7** (HL7 built-in connector)
- Input: `triggerBody().hl7`
- Output: decoded XML message (and possibly header)

**Implementation note:** the workflow references:
- `body('Decode_HL7')?['message']` as the decoded HL7 XML payload.

Because HL7 Decode returns both XML message and header, the output object shape may differ slightly by environment/version. If your output uses different property names, adjust **Compose_HL7_Xml** accordingly.

---

## XPath extraction (required fields)

All extraction is performed with Logic Apps expression functions:
- `xml()` to cast string → XML
- `xpath()` to extract values

Use **namespace-agnostic XPath** via `local-name()` to avoid surprises from schema namespaces.

> **XML root varies by schema** (often `ADT_A01_231` or similar), so all paths are anchored with `//*[local-name()='SEG']`.

### MSH
| Field | JSON path | XPath used |
|---|---|---|
| MSH.9 Message Type | `messageHeader.messageType` | `string(//*[local-name()="MSH"]/*[local-name()="MSH.9"])` |
| MSH.10 Control ID | `messageHeader.messageControlId` | `string(//*[local-name()="MSH"]/*[local-name()="MSH.10"])` |
| MSH.12 HL7 Version | `messageHeader.hl7Version` | `string(//*[local-name()="MSH"]/*[local-name()="MSH.12"])` |

### PID
| Field | JSON path | XPath used |
|---|---|---|
| PID.3 Patient ID | `patient.patientId` | `string(//*[local-name()="PID"]/*[local-name()="PID.3"]/*[local-name()="CX.1"][1])` |
| PID.5.1 Last Name | `patient.lastName` | `string(//*[local-name()="PID"]/*[local-name()="PID.5"]/*[local-name()="XPN.1"]/*[local-name()="FN.1"][1])` |
| PID.5.2 First Name | `patient.firstName` | `string(//*[local-name()="PID"]/*[local-name()="PID.5"]/*[local-name()="XPN.2"][1])` |
| PID.7 DOB | `patient.dateOfBirth` | `string(//*[local-name()="PID"]/*[local-name()="PID.7"][1])` |
| PID.8 Gender | `patient.gender` | `string(//*[local-name()="PID"]/*[local-name()="PID.8"][1])` |
| PID.13 Phone | `patient.phoneNumber` | `string(//*[local-name()="PID"]/*[local-name()="PID.13"]/*[local-name()="XTN.1"][1])` |

### PV1
| Field | JSON path | XPath used |
|---|---|---|
| PV1.2 Patient Class | `visit.patientClass` | `string(//*[local-name()="PV1"]/*[local-name()="PV1.2"][1])` |
| PV1.3 Assigned Location | `visit.location` | `string(//*[local-name()="PV1"]/*[local-name()="PV1.3"][1])` |
| PV1.7.1 Doctor ID | `visit.attendingDoctor.doctorId` | `string(//*[local-name()="PV1"]/*[local-name()="PV1.7"]/*[local-name()="XCN.1"][1])` |
| PV1.7.2 Doctor Last | `visit.attendingDoctor.lastName` | `string(//*[local-name()="PV1"]/*[local-name()="PV1.7"]/*[local-name()="XCN.2"][1])` |
| PV1.7.3 Doctor First | `visit.attendingDoctor.firstName` | `string(//*[local-name()="PV1"]/*[local-name()="PV1.7"]/*[local-name()="XCN.3"][1])` |

---

## Validation behavior

Validate mandatory fields by appending readable messages into an `errors` array:
- `MSH.9`, `MSH.10`, `MSH.12`
- `PID.3`, `PID.5.1`, `PID.5.2`, `PID.7`, `PID.8`
- `PV1.2`

If `errors` is non-empty, return HTTP 400:
```json
{
  "status": "ValidationFailed",
  "errors": ["Missing required field: ..."]
}
```

---

## Sample request + response

### Sample HL7 input (ADT^A01)
```
MSH|^~\&|ADT1|GOOD HEALTH HOSPITAL|EHR|HOSPITAL|202401011200||ADT^A01|MSG00001|P|2.5
PID|1||123456^^^HOSPITAL^MR||Doe^John||19800101|M|||123 Main St^^Metropolis^NY^10001||555-123-4567
PV1|1|I|2000-2012-01||||1234^Smith^Adam
```

### HTTP request
```bash
curl -X POST "http://localhost:7071/api/Hl7AdtA01ToJson/triggers/When_a_HTTP_request_is_received/invoke?api-version=2016-06-01" \
  -H "Content-Type: application/json" \
  -d @./test-data/request.sample.json
```

### Example 200 response
```json
{
  "messageHeader": {
    "messageType": "ADT^A01",
    "messageControlId": "MSG00001",
    "hl7Version": "2.5"
  },
  "patient": {
    "patientId": "123456",
    "firstName": "John",
    "lastName": "Doe",
    "dateOfBirth": "1980-01-01",
    "gender": "M",
    "phoneNumber": "555-123-4567"
  },
  "visit": {
    "patientClass": "I",
    "location": "2000-2012-01",
    "attendingDoctor": {
      "doctorId": "1234",
      "firstName": "Adam",
      "lastName": "Smith"
    }
  },
  "status": "Decoded to HL7 XML Successfully"
}
```

---

## Obstacles encountered + technical fixes

These are the most common “gotchas” I ran into (and how to fix them):

### 1) “Create New Logic App (Standard)” missing in VS Code
**Why it happens:** the Logic Apps (Standard) extension isn’t installed, is disabled, or you only have the Consumption workflow tooling.  
**Fix:**
- Install/update **Azure Logic Apps (Standard)** extension
- Ensure **Azure Functions Core Tools v4** is installed and on PATH
- Ensure Node 18+ is installed (Logic App Standard uses Functions runtime underneath)

### 2) Callback URL is empty in designer / can’t find trigger URL locally
**Why it happens:** the host isn’t running, the workflow hasn’t been saved, or the debugger is attached to the wrong project root.  
**Fix:**
- Start Azurite first
- Verify `AzureWebJobsStorage=UseDevelopmentStorage=true`
- Start with F5 / `func start`
- Watch the terminal output for the Request trigger URL

---

## Assumptions

1. HL7 Decode output shape may vary slightly; this repo assumes decoded XML is in `body('Decode_HL7')['message']`.  
2. You will link an Integration Account and upload schemas required by the HL7 connector.
3. For local runs, you have the Standard workflow tooling + Functions runtime installed.

---

## Notes for reviewers
- No manual “split('|')” parsing exists anywhere — all field extraction is XPath against decoded XML.
- XPath expressions are explicit, documented, and namespace-agnostic.
