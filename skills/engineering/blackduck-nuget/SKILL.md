---
name: blackduck-nuget
description: "Fix Black Duck NuGet — Analyze Black Duck scan results for .NET Framework (4.x) NuGet projects, compare against a baseline version, identify NEW risk items (Operational/Security/License), upgrade packages, and generate waive reports (Excel). Trigger on /blackduck-nuget, or when user reports Black Duck operational/security/license risk items, asks to fix/waive Black Duck scan results, says 'fix blackduck', or says 'waive blackduck'."
---

# Fix Black Duck NuGet — Scan, Compare, and Upgrade .NET Framework packages

Analyze Black Duck scan results for .NET Framework (4.x) NuGet projects, compare against a baseline version, identify NEW risk items (Operational/Security/License), and upgrade packages to resolve them while respecting .NET Framework compatibility constraints. Learned from PTTGC.KBS project (85 operational risk items reduced to 54, 27 resolved, 0 new).

## Usage
```
/blackduck-nuget <black-duck-url> <api-token> <project-name>   # Full workflow
/blackduck-nuget compare <baseline> <current>                   # Compare two versions
/blackduck-nuget upgrade <package-name> <target-version>        # Upgrade specific package
/blackduck-nuget report                                         # Generate remediation report
/blackduck-nuget waive <before-dir> <after-dir> <output.xlsx>   # Generate waive report from PDF exports
```

## Instructions

### Phase 1: Authenticate & Discover Versions

```
1. Authenticate with Black Duck API:
   POST {server}/api/tokens/authenticate
   Header: Authorization: token {api-token}
   → Returns bearerToken for subsequent calls

2. Find project ID:
   GET /api/projects?q=name:{project-name}
   Header: Accept: application/json
   → Extract project._meta.href → project ID from URL

3. List all versions:
   GET /api/projects/{projectId}/versions?limit=20
   → Note version names and IDs
   → Identify baseline version and current scan version

4. If baseline has 0 components in API (common for old scans):
   → Use CSV export from Black Duck UI instead
   → CSV path typically: {export-dir}/csv/{project-name}/components_*.csv
   → CSV columns: [3]=Component name, [4]=Version, [13]=Operational Risk,
     [26]=License Risk, [31-34]=Vulnerability counts (Crit/High/Med/Low)
```

### Phase 2: Compare Versions & Identify NEW Risk Items

```
1. Get current version components:
   GET /api/projects/{projectId}/versions/{versionId}/components?limit=500
   Header: Accept: application/json
   → Save response for analysis

2. For each component, extract risk profiles:
   - operationalRiskProfile.counts[] → find highest non-OK countType
   - securityRiskProfile.counts[] → find highest non-OK countType
   - licenseRiskProfile.counts[] → find highest non-OK countType

3. Compare with baseline:
   - Match components by name (case-insensitive, fuzzy match)
   - Identify NEW items: in current but NOT in baseline
   - Identify RESOLVED items: in baseline but NOT in current
   - Group by risk category (Operational, Security, License)

4. Goal: NEW items count must be 0 or items must be fixable
   - Only fix packages that introduce NEW risk
   - Pre-existing risk items are acceptable (already in baseline)
```

### Phase 3: Verify .NET Framework Compatibility

**CRITICAL: Before upgrading any package, verify it supports .NET Framework 4.x**

```
1. Check NuGet package page or nuspec for Target Framework Monikers (TFMs):
   - COMPATIBLE: net462, net472, net48, netstandard2.0, netstandard2.1
   - INCOMPATIBLE: net6.0, net7.0, net8.0, net9.0 (without netstandard2.0)

2. Check HintPath in .csproj for actual DLL location:
   - Example: packages\Package.1.0.0\lib\net462\Package.dll
   - The lib subfolder indicates target framework

3. Common compatibility limits (.NET Framework 4.8):
   - Microsoft.Extensions.* → Max 10.0.8 (has net462 TFM)
   - System.Text.Json → Max 10.0.0 (has net462 TFM)
   - Microsoft.IdentityModel.* → Max 8.18.0 (has net462/net472 TFM)
   - Newtonsoft.Json → 13.0.4 is latest stable
   - System.ComponentModel.Annotations → 5.0.0 is max for .NET Framework
   - System.IO.FileSystem.AccessControl → 5.0.0 is max
   - System.Security.Principal.Windows → 5.0.0 is max

4. Watch for package structure changes between major versions:
   - DotNetCompilerPlatform 2.0.1: build/net46/*.props, lib/net45/
   - DotNetCompilerPlatform 4.1.0: build/net472/*.targets, lib/net472/
   - Always verify actual package folder contents after install
```

### Phase 4: Upgrade Packages (Three-File Update)

For each package upgrade, update THREE file types in EVERY project that references it:

#### 4A. packages.config
```xml
<!-- Change version attribute -->
<package id="Microsoft.Extensions.Logging" version="8.0.0" targetFramework="net48" />
<!-- becomes -->
<package id="Microsoft.Extensions.Logging" version="10.0.8" targetFramework="net48" />
```

#### 4B. .csproj (Assembly Version + HintPath)
```xml
<!-- TWO things to update: -->

<!-- 1. Reference Include — assembly version -->
<Reference Include="Package.Name, Version=8.0.0.0, Culture=neutral, PublicKeyToken=xxx">
<!-- becomes -->
<Reference Include="Package.Name, Version=10.0.0.8, Culture=neutral, PublicKeyToken=xxx">

<!-- 2. HintPath — package folder version -->
<HintPath>..\packages\Package.Name.8.0.0\lib\net462\Package.Name.dll</HintPath>
<!-- becomes -->
<HintPath>..\packages\Package.Name.10.0.8\lib\net462\Package.Name.dll</HintPath>

<!-- 3. Import/Error conditions (if package has build targets) -->
<Import Project="..\packages\Pkg.2.0.1\build\net46\Pkg.props" ... />
<!-- becomes -->
<Import Project="..\packages\Pkg.4.1.0\build\net472\Pkg.targets" ... />
<!-- ALSO update matching <Error Condition="!Exists(..." /> -->
```

**Assembly Version Mapping (NuGet version → Assembly version):**

| NuGet Package Version | Assembly Version | Notes |
|---|---|---|
| 10.0.8 | 10.0.0.8 | Microsoft.Extensions.*, System.* |
| 8.18.0 | 8.18.0.0 | Microsoft.IdentityModel.* |
| 3.1.1 | 3.1.1.0 | Microsoft.ApplicationInsights |
| 13.0.4 | 13.0.0.0 | Newtonsoft.Json |
| 4.1.0 | 4.1.0.0 | DotNetCompilerPlatform |

#### 4C. app.config / Web.config (Binding Redirects)
```xml
<!-- Update BOTH oldVersion range AND newVersion -->
<dependentAssembly>
  <assemblyIdentity name="Package.Name" publicKeyToken="xxx" culture="neutral" />
  <bindingRedirect oldVersion="0.0.0.0-8.0.0.0" newVersion="8.0.0.0" />
</dependentAssembly>
<!-- becomes -->
<dependentAssembly>
  <assemblyIdentity name="Package.Name" publicKeyToken="xxx" culture="neutral" />
  <bindingRedirect oldVersion="0.0.0.0-10.0.0.8" newVersion="10.0.0.8" />
</dependentAssembly>
```

**Common publicKeyToken values:**

| Token | Packages |
|---|---|
| `adb9793829ddae60` | Microsoft.Extensions.* |
| `cc7b13ffcd2ddd51` | System.Diagnostics.*, System.Text.*, System.Buffers, System.Memory, Microsoft.Bcl.* |
| `b03f5f7f11d50a3a` | System.Security.*, System.Configuration.*, System.Text.Encoding.CodePages, System.IO.Packaging |
| `31bf3856ad364e35` | Microsoft.IdentityModel.*, Microsoft.ApplicationInsights, Microsoft.Graph.* |
| `30ad4fe6b2a6aeed` | Newtonsoft.Json |
| `0a613f4dd989e8ae` | Microsoft.Identity.Client.* |

### Phase 5: Apply to Multiple Directories

```
1. Source directory — for build verification
   - Update packages.config, .csproj, app.config/Web.config
   - Rebuild solution to verify no errors
   - Fix any build errors (path changes, version conflicts)

2. Scan directory — for Black Duck re-scan
   - Apply identical changes
   - This is the directory Black Duck will scan
   - Must be an exact copy of source changes

3. Both directories must have:
   - Same packages.config versions
   - Same .csproj assembly versions and HintPaths
   - Same binding redirects in config files
```

### Phase 6: Build & Fix Errors

Common build errors and fixes:

```
1. MSB3277 — Assembly version conflict (e.g., Bcl.AsyncInterfaces 10.0.0 vs 10.0.0.8)
   → Upgrade the lower version package to match
   → Update binding redirect to higher version

2. Missing .props/.targets file
   → Package structure changed between versions
   → Check actual package folder: packages/{pkg}/build/ and packages/{pkg}/lib/
   → Update Import path and Error condition in .csproj
   → Example: DotNetCompilerPlatform 2.0.1→4.1.0:
     build/net46/*.props → build/net472/*.targets
     lib/net45/ → lib/net472/

3. Missing package folder
   → Run NuGet Package Restore
   → Or manually download package to packages/ folder

4. TFM mismatch warnings
   → Package may target different framework
   → Verify DLL exists in expected lib/ subfolder
```

### Phase 7: Verify with Black Duck Re-scan

```
1. Upload scan directory to Black Duck (new version)
2. Wait for scan to complete
3. Compare new scan vs baseline:
   - NEW operational risk items = 0
   - NEW security risk items = 0
   - NEW license risk items = 0 (or justified)
4. If new items appear:
   - Check if package was newly detected (not from our changes)
   - Check if risk rating changed (Black Duck reclassification)
   - If genuinely new, fix or document with justification
```

### Phase 8: Generate Report & Commit

```
1. Create BLACK_DUCK_REMEDIATION_REPORT.md with:
   - Executive summary table (baseline vs after, by risk category)
   - All package upgrades performed
   - Resolved items list
   - New items with justification
   - Items that cannot be upgraded (at latest version, legacy deps)
   - Recommendations for team

2. Commit format:
   fix(security): upgrade NuGet packages to resolve N Black Duck {Risk} items

   List all upgraded packages and version changes.

3. Push to repository
```

### Phase 9: Generate Waive Report (Excel) from PDF Exports

When BD API is unavailable or user provides PDF exports from the BD web UI.

```
Two modes:

Mode A — Compare (มี baseline):
  /blackduck-nuget waive
  /blackduck-nuget waive <before-dir> <after-dir> <output.xlsx>

Mode B — Initial (ไม่มี baseline, scan ครั้งแรก):
  /blackduck-nuget waive --initial
  /blackduck-nuget waive --initial <scan-dir> <output.xlsx>
```

#### 9-PREREQ. Gather Inputs (Interactive)

```
If paths are not provided as arguments, ASK the user:

Step 0: "มี baseline (Before) สำหรับเปรียบเทียบมั้ยครับ?"
  → YES → Mode A (Compare): proceed to Step 1
  → NO  → Mode B (Initial): skip to Step 2
         Set HAS_BASELINE = False

--- Mode A only ---
Step 1: "Before (baseline) PDF folder อยู่ที่ไหนครับ?"
  → User provides path to folder containing baseline PDFs
  → Auto-discover PDFs: ls the folder, find *operationalrisk*.pdf, *licenserisk*.pdf, *securityrisk*.pdf
  → If any PDF missing, ask: "ไม่พบไฟล์ {type} risk PDF — มีไฟล์ชื่ออื่นมั้ยครับ?"

--- Both modes ---
Step 2: "PDF folder ของ scan {ปัจจุบัน/ที่ต้องการ waive} อยู่ที่ไหนครับ?"
  → Auto-discover: *operationalrisk*.pdf, *licenserisk*.pdf, *securityrisk*.pdf

Step 3: "ต้องการบันทึกไฟล์ waive report (.xlsx) ไว้ที่ไหนครับ?"
  → Default suggestion: same directory as scan folder

Step 4: "มีไฟล์ waive report เก่าที่ต้องการ copy รูปมาด้วยมั้ยครับ? (optional)"
  → If yes: load old xlsx for image copying
  → If no: skip image copying

Step 5: Confirm project details:
  Mode A: "Project: {name}, Baseline: {version}, Current: {version} — ถูกต้องมั้ยครับ?"
  Mode B: "Project: {name}, Version: {version} (initial scan, ไม่มี baseline) — ถูกต้องมั้ยครับ?"
  → Extract project name and version from PDF headers automatically
```

#### 9A. Extract Data from PDFs

```
1. Read each PDF with the Read tool (Claude reads PDFs natively as images)
2. For each page, extract the component table rows:
   - Component: full name including version (e.g., "jQuery 3.3.1")
   - Operational Risk: HIGH / MEDIUM / LOW / None
   - Security Risk: vuln count numbers (e.g., "2 1 1" = 2H 1M 1L)
   - License: license name and severity marker (H/M)
3. Build Python lists from extracted data (see template below)
4. Cross-check: count HIGH items vs header summary — BD PDFs sometimes
   miss 1-2 items at page boundaries. Document any discrepancy.

CRITICAL PITFALLS:
- BD shows ALL versions of a component separately (e.g., Json.NET 10.0.3 AND 13.0.4)
  → List EVERY version as a separate row. Do NOT merge or deduplicate.
- BD Op Risk PDF may show items with both Sec Risk AND Op Risk columns
  → Extract Op Risk severity from the LAST column (rightmost)
- The same component may appear in multiple risk PDFs with different data
  → Op Risk PDF is the master for operational risk items
  → Sec Risk PDF is the master for security risk items
  → Lic Risk PDF is the master for license risk items
```

#### 9B. Compare or Catalog

```
=== Mode A (Compare — HAS_BASELINE = True) ===

1. Build lookup sets from Before data:
   before_op  = {("Component Name Version", "SEVERITY"), ...}
   before_sec = {("Component Name Version", "Severity"), ...}
   before_lic = {("Component Name Version", "SEVERITY"), ...}

2. For each After item, classify:
   - EXISTING: exact name+version match in Before → Remark=""
   - NEW: name+version NOT in Before → Remark="NEW"
   - VERSION_CHANGED: same component name but different version → note in Remark

3. Count REMOVED items (in Before but not in After) for the summary

4. Calculate deltas for Overview:
   Category    | Baseline (from Before header) | Current (COUNTIF from sheet) | Delta
   Sec HIGH    | {N}                          | =COUNTIF(...)                | =C-B
   ...

=== Mode B (Initial — HAS_BASELINE = False) ===

1. No comparison — all items are documented as-is
2. Remark column: leave blank (no "NEW" marking needed — everything is initial)
3. Overview: show only "Risk | Count" (2 columns, no Baseline/Delta)
4. Skip creating _Baseline_* hidden sheets
5. Key Changes text: "Initial scan — ไม่มี baseline สำหรับเปรียบเทียบ"
```

#### 9C. Excel Structure

```
=== Mode A (Compare) — Sheet order ===
1. Overview            — Summary: Risk | Baseline | Current | Delta (COUNTIF formulas)
2. SecurityRisk        — All current Sec HIGH+MED items with waive justification
3. LicenseRisk         — All current Lic HIGH+MED items with waive justification
4. OperationRisk       — All current Op HIGH+MED items with waive justification
5. L1..LN              — 1 detail sheet per License Risk item (title, severity, URL, screenshot area)
6. _Baseline_SecRisk   — Before Sec Risk data (sheet_state="hidden")
7. _Baseline_LicRisk   — Before Lic Risk data (sheet_state="hidden")
8. _Baseline_OpRisk    — Before Op Risk data (sheet_state="hidden")
9. .net48              — Optional: .NET FW compatibility screenshots

=== Mode B (Initial) — Sheet order ===
1. Overview            — Summary: Risk | Count (2 columns only, no baseline/delta)
2. SecurityRisk        — same schema as Mode A
3. LicenseRisk         — same schema as Mode A
4. OperationRisk       — same schema as Mode A (Remark column left empty)
5. L1..LN              — same as Mode A
   (NO _Baseline_* sheets — nothing to compare against)

=== Column schemas (both modes) ===
SecurityRisk:
  No. | Component | Severity | Fix | Impact | Mitigation | Reference | TC Result(Agree/Disagree)

LicenseRisk:
  No. | Component | Severity | Commercial Impact(Yes/No) | Fix | Lib URLs |
  Link Image | Impact | Migration | Dependency/Reason | Reference | TC Result(Agree/Disagree)

OperationRisk:
  No. | Component | Search Name | Severity | Fix | Impact | Mitigation |
  Reference | Remark | TC Result(Agree/Disagree)

Baseline hidden sheets (Mode A only):
  No. | Component | Severity | (extra columns vary)

Severity casing convention:
  - SecurityRisk uses "High"/"Medium" (title case) ← matches BD web UI
  - LicenseRisk uses "HIGH"/"MEDIUM" (uppercase)
  - OperationRisk uses "HIGH"/"MEDIUM" (uppercase)
  - COUNTIF formulas must match the exact casing used in each sheet
```

#### 9D. Python Script Template (openpyxl)

Write a Python script to `/tmp/create_waive.py` and execute it. Adapt the data arrays to match the specific project.

```python
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

OUT = "<output.xlsx path>"
OLD = "<old.xlsx path or None>"  # for image copying
HAS_BASELINE = True  # False for initial scan (no baseline to compare)

# ─── Styles ───
HEADER_FILL = PatternFill("solid", fgColor="4472C4")
HEADER_FONT = Font(bold=True, size=11, color="FFFFFF")
RED_FILL    = PatternFill("solid", fgColor="FFC7CE")
YELLOW_FILL = PatternFill("solid", fgColor="FFEB9C")
NEW_FILL    = PatternFill("solid", fgColor="DDEBF7")
WRAP        = Alignment(wrap_text=True, vertical="top")
WRAP_CENTER = Alignment(wrap_text=True, vertical="top", horizontal="center")
THIN_BORDER = Border(*(Side(style="thin"),)*4)

def style_header(ws, row, ncols):
    for c in range(1, ncols+1):
        cell = ws.cell(row=row, column=c)
        cell.font, cell.fill, cell.alignment, cell.border = HEADER_FONT, HEADER_FILL, WRAP_CENTER, THIN_BORDER

def style_data(ws, row, ncols):
    for c in range(1, ncols+1):
        cell = ws.cell(row=row, column=c)
        cell.alignment, cell.border = WRAP, THIN_BORDER

# ════════════════════════════════════════════
# DATA — Populate these arrays from PDF extraction
# ════════════════════════════════════════════

# Security Risk — After (current scan)
# (Component, Severity, Fix, Impact_TH, Mitigation_TH, Reference)
SEC_RISK = [
    # ... extract from After security risk PDF
]

# License Risk — After
# (Component, Severity, CommercialImpact, Fix, LibURL, Impact_TH, Migration_TH, Dependency_TH, Reference)
LIC_RISK = [
    # ... extract from After license risk PDF
]

# Operational Risk — After
# (Component, SearchName, Severity, Fix, Impact_TH, Mitigation_TH, Remark)
# Remark: Mode A → "NEW" if not in baseline, "" if existed
#         Mode B → always "" (no baseline to compare)
OP_RISK = [
    # ... extract from operational risk PDF
]

# ── Baseline data (Mode A only — skip if HAS_BASELINE=False) ──
BASELINE_SEC = [  # (Component, Severity, VulnCount)
]
BASELINE_LIC = [  # (Component, Severity, License)
]
BASELINE_OP  = [  # (Component, Severity)
]
BEFORE_COUNTS = {  # Header counts from Before PDF
    "sec_high": 0, "sec_med": 0,
    "op_high": 0, "op_med": 0,
    "lic_high": 0, "lic_med": 0,
}

PROJECT_NAME = "gc-kbs-backend"
BASELINE_VERSION = "20260515 1042"
CURRENT_VERSION = "4"
REPORT_DATE = "2026-05-27"

# ════════════════════════════════════════════
# CREATE WORKBOOK
# ════════════════════════════════════════════
wb = openpyxl.Workbook()

# ── Overview ──
ws = wb.active
ws.title = "Overview"
ws.sheet_properties.tabColor = "4472C4"
ws["A1"] = "Black Duck Waive Report"
ws["A1"].font = Font(bold=True, size=14)
ws["A3"] = f"Project: {PROJECT_NAME}"
if HAS_BASELINE:
    ws["A4"] = f"Baseline: {BASELINE_VERSION}"
    ws["A5"] = f"Current: Version {CURRENT_VERSION}"
else:
    ws["A4"] = f"Version: {CURRENT_VERSION} (initial scan)"
ws["A6"] = "Package versions: Visual Studio packages.config (actual installed)"
ws["A7"] = f"Report date: {REPORT_DATE}"

# Summary table
countif_rows = [
    ("Sec HIGH",  '=COUNTIF(SecurityRisk!C:C,"High")'),
    ("Sec MED",   '=COUNTIF(SecurityRisk!C:C,"Medium")'),
    ("Op HIGH",   '=COUNTIF(OperationRisk!D:D,"HIGH")'),
    ("Op MED",    '=COUNTIF(OperationRisk!D:D,"MEDIUM")'),
    ("Lic HIGH",  '=COUNTIF(LicenseRisk!C:C,"HIGH")'),
    ("Lic MED",   '=COUNTIF(LicenseRisk!C:C,"MEDIUM")'),
]

if HAS_BASELINE:
    # Mode A: Risk | Baseline | Current | Delta
    for i, h in enumerate(["Risk", "Baseline", "Current", "Delta"], 1):
        c = ws.cell(row=9, column=i, value=h)
        c.font, c.fill, c.alignment, c.border = HEADER_FONT, HEADER_FILL, WRAP_CENTER, THIN_BORDER
    before_vals = [BEFORE_COUNTS["sec_high"], BEFORE_COUNTS["sec_med"],
                   BEFORE_COUNTS["op_high"], BEFORE_COUNTS["op_med"],
                   BEFORE_COUNTS["lic_high"], BEFORE_COUNTS["lic_med"]]
    for i, ((label, formula), base) in enumerate(zip(countif_rows, before_vals), 10):
        ws.cell(row=i, column=1, value=label).font = Font(bold=True)
        ws.cell(row=i, column=2, value=base)
        ws.cell(row=i, column=3, value=formula)
        ws.cell(row=i, column=4, value=f"=C{i}-B{i}")
        for c in range(1,5): ws.cell(row=i, column=c).border = THIN_BORDER
    ws["A17"] = "Key Changes (Before -> After):"
    ws["A17"].font = Font(bold=True)
    ws.column_dimensions["D"].width = 12
else:
    # Mode B: Risk | Count (simpler — no comparison)
    for i, h in enumerate(["Risk", "Count"], 1):
        c = ws.cell(row=9, column=i, value=h)
        c.font, c.fill, c.alignment, c.border = HEADER_FONT, HEADER_FILL, WRAP_CENTER, THIN_BORDER
    for i, (label, formula) in enumerate(countif_rows, 10):
        ws.cell(row=i, column=1, value=label).font = Font(bold=True)
        ws.cell(row=i, column=2, value=formula)
        for c in range(1,3): ws.cell(row=i, column=c).border = THIN_BORDER
    ws["A17"] = "Initial scan — no baseline for comparison"
    ws["A17"].font = Font(bold=True, color="808080")

ws.column_dimensions["A"].width = 22
ws.column_dimensions["B"].width = 14
ws.column_dimensions["C"].width = 14

# ── SecurityRisk ──
ws_sec = wb.create_sheet("SecurityRisk")
ws_sec.sheet_properties.tabColor = "FF0000"
sec_h = ["No.", "Component", "Severity", "Fix", "Impact", "Mitigation", "Reference", "TC Result\n(Agree/Disagree)"]
for i, h in enumerate(sec_h, 1): ws_sec.cell(row=1, column=i, value=h)
style_header(ws_sec, 1, len(sec_h))
for idx, (comp, sev, fix, impact, mit, ref) in enumerate(SEC_RISK, 1):
    r = idx + 1
    for c, v in enumerate([idx, comp, sev, fix, impact, mit, ref, ""], 1):
        ws_sec.cell(row=r, column=c, value=v)
    style_data(ws_sec, r, len(sec_h))
    sev_cell = ws_sec.cell(row=r, column=3)
    sev_cell.fill = RED_FILL if sev == "High" else YELLOW_FILL if sev == "Medium" else PatternFill()
ws_sec.column_dimensions["B"].width = 45
ws_sec.column_dimensions["E"].width = 55
ws_sec.column_dimensions["F"].width = 55

# ── LicenseRisk ──
ws_lic = wb.create_sheet("LicenseRisk")
ws_lic.sheet_properties.tabColor = "FF6600"
lic_h = ["No.", "Component", "Severity", "Commercial Impact\n(Yes/No)", "Fix", "Lib URLs",
         "Link Image", "Impact", "Migration", "Dependency / Reason", "Reference", "TC Result\n(Agree/Disagree)"]
for i, h in enumerate(lic_h, 1): ws_lic.cell(row=1, column=i, value=h)
style_header(ws_lic, 1, len(lic_h))
for idx, (comp, sev, comm, fix, url, impact, mig, dep, ref) in enumerate(LIC_RISK, 1):
    r = idx + 1
    for c, v in enumerate([idx, comp, sev, comm, fix, url,
                           f"=HYPERLINK(\"#'L{idx}'!A1\",\"-> L{idx}\")",
                           impact, mig, dep, ref, ""], 1):
        ws_lic.cell(row=r, column=c, value=v)
    style_data(ws_lic, r, len(lic_h))
    sev_cell = ws_lic.cell(row=r, column=3)
    sev_cell.fill = RED_FILL if sev == "HIGH" else YELLOW_FILL if sev == "MEDIUM" else PatternFill()
ws_lic.column_dimensions["B"].width = 45
ws_lic.column_dimensions["F"].width = 50
ws_lic.column_dimensions["I"].width = 45
ws_lic.column_dimensions["J"].width = 45

# ── OperationRisk ──
# NOTE: Row heights and col H width are sized for BD web screenshots (~900x550px)
ws_op = wb.create_sheet("OperationRisk")
ws_op.sheet_properties.tabColor = "FFC000"
op_h = ["No.", "Component", "Search Name", "Severity", "Fix", "Impact", "Mitigation", "Reference", "Remark", "TC Result\n(Agree/Disagree)"]
for i, h in enumerate(op_h, 1): ws_op.cell(row=1, column=i, value=h)
style_header(ws_op, 1, len(op_h))
ws_op.row_dimensions[1].height = 32  # header row
for idx, (comp, search, sev, fix, impact, mit, remark) in enumerate(OP_RISK, 1):
    r = idx + 1
    for c, v in enumerate([idx, comp, search, sev, fix, impact, mit, "", remark, ""], 1):
        ws_op.cell(row=r, column=c, value=v)
    style_data(ws_op, r, len(op_h))
    ws_op.cell(row=r, column=4).fill = RED_FILL if sev == "HIGH" else YELLOW_FILL if sev == "MEDIUM" else PatternFill()
    if remark == "NEW":
        ws_op.cell(row=r, column=9).fill = NEW_FILL
    ws_op.row_dimensions[r].height = 209  # tall rows for screenshot placement
ws_op.column_dimensions["A"].width = 5
ws_op.column_dimensions["B"].width = 50
ws_op.column_dimensions["C"].width = 40
ws_op.column_dimensions["D"].width = 12
ws_op.column_dimensions["E"].width = 8
ws_op.column_dimensions["F"].width = 45
ws_op.column_dimensions["G"].width = 55
ws_op.column_dimensions["H"].width = 66   # wide column for BD screenshots
ws_op.column_dimensions["I"].width = 12
ws_op.column_dimensions["J"].width = 18

# ── L1..LN detail sheets (sized for BD web screenshots) ──
for idx, (comp, sev, comm, fix, url, impact, mig, dep, ref) in enumerate(LIC_RISK, 1):
    ws_l = wb.create_sheet(f"L{idx}")
    ws_l.cell(row=1, column=1, value=f"L{idx}: {comp}").font = Font(bold=True, size=12)
    ws_l.cell(row=2, column=1, value=f"Severity: {sev}").font = Font(bold=True, size=11,
        color="FF0000" if sev == "HIGH" else "FF8C00")
    ws_l.cell(row=3, column=1, value=f"License Issue: {mig}")
    ws_l.cell(row=4, column=1, value=f"Dependency: {dep}")
    ws_l.cell(row=6, column=1, value="URL:")
    ws_l.cell(row=6, column=2, value=url)
    ws_l.cell(row=8, column=1, value="Screenshot:").font = Font(bold=True, size=11, color="4472C4")
    # Rows 9-10: tall rows for pasting BD web screenshots (~2400x1500px)
    ws_l.row_dimensions[9].height = 400
    ws_l.row_dimensions[10].height = 400
    ws_l.column_dimensions["A"].width = 22
    ws_l.column_dimensions["B"].width = 90   # wide for screenshots
    ws_l.column_dimensions["C"].width = 50   # overflow area

# ── Baseline hidden sheets (Mode A only) ──
if HAS_BASELINE:
    for name, data, cols in [
        ("_Baseline_SecRisk", BASELINE_SEC, ["No.", "Component", "Severity", "Vuln Count"]),
        ("_Baseline_LicRisk", BASELINE_LIC, ["No.", "Component", "Severity", "License"]),
        ("_Baseline_OpRisk",  BASELINE_OP,  ["No.", "Component", "Severity"]),
    ]:
        ws_b = wb.create_sheet(name)
        for i, h in enumerate(cols, 1): ws_b.cell(row=1, column=i, value=h)
        style_header(ws_b, 1, len(cols))
        for i, row_data in enumerate(data, 1):
            ws_b.cell(row=i+1, column=1, value=i)
            for c, v in enumerate(row_data, 2): ws_b.cell(row=i+1, column=c, value=v)
            style_data(ws_b, i+1, len(cols))
        ws_b.column_dimensions["B"].width = 55
        ws_b.sheet_state = "hidden"

# ── Copy images from old workbook (if available) ──
if OLD:
    try:
        old_wb = openpyxl.load_workbook(OLD)
        for old_name in old_wb.sheetnames:
            if old_name in wb.sheetnames:
                for img in old_wb[old_name]._images:
                    wb[old_name].add_image(img)
            elif old_name == ".net48":
                ws_net = wb.create_sheet(".net48")
                for img in old_wb[old_name]._images:
                    ws_net.add_image(img)
    except Exception as e:
        print(f"Warning: image copy failed: {e}")

wb.save(OUT)
print(f"Saved: {OUT}")
print(f"Sheets: {wb.sheetnames}")
```

#### 9E. Waive Text Patterns (Thai)

Use these patterns for the Impact and Mitigation columns. Replace `{parent}`, `{version}`, `{replacement}` with actual values.

```
OPERATIONAL RISK — Mitigation patterns:
  asp_framework:     "เป็น Core Framework ของ Project"
  asp_dependency:    "เป็น Dependency ของ ASP.NET Web API"
  asp_mvc_dep:       "เป็น ASP.NET MVC dependency"
  frontend:          "เป็น Frontend Library ใช้ใน SharePoint SitePages"
  frontend_dep:      "เป็น Frontend dependency ของ {parent}"
  project_dep:       "เป็น Dependency Library ของ Project"
  project_main_dep:  "เป็น Dependency หลักของ Project"
  locked:            "Locked โดย {parent} ไม่สามารถ upgrade ได้"
  transitive:        "เป็น Transitive Dependency"
  transitive_deep:   "เป็น Transitive Dependency — ถูก detect จาก deeper scan"
  deprecated:        "เป็น Deprecated library แนะนำย้ายเป็น {replacement} แต่ยังจำเป็นสำหรับ legacy code"
  at_max:            "Max version สำหรับ .NET Framework 4.8 ({version}) — .NET 6+ only สำหรับ version ใหม่กว่า"
  latest:            "Update เป็น version ล่าสุดแล้ว"
  system_lib:        "เป็น .NET Framework system library — ได้รับ patch ผ่าน Windows Update"

OPERATIONAL RISK — Impact patterns:
  auth:              "Library ในการ Authentication ผ่าน Azure AD ({lib_name})"
  html_parse:        "Library ในการ Parse HTML"
  expr_parser:       "Expression Parser"
  ui_framework:      "Library ในการทำ UI/CSS Framework ของ Frontend"
  excel_io:          "Library ในการอ่าน/เขียนไฟล์ Excel"
  auth_token:        "Library ในการจัดการ Authentication Token"
  dom_event:         "Library ในการจัดการ DOM / Event ของ Frontend"
  form_validation:   "Library ในการตรวจสอบ Form Validation ของ Frontend"
  jwt:               "Library ในการจัดการ JWT Token"
  json:              "Library ในการ Serialize/Deserialize JSON"
  cors:              "CORS Support"
  framework:         "ASP.NET {name} Framework"
  graph_api:         "Microsoft Graph API / Azure AD Graph API"
  key_vault:         "Library เชื่อมต่อ Azure Key Vault"
  reporting:         "Library ในการทำ Reporting (RDL)"
  odata:             "OData protocol library"
  tooltip:           "Library ในการทำ Tooltip/Popover ของ Bootstrap"
  razor:             "Razor View Engine"
  swagger:           "API Documentation (Swagger)"
  data_annotation:   "Library ในการทำ Data Annotation / Validation"
  file_acl:          "Library ในการจัดการ File System ACL"
  http_req:          "Library ในการเรียก HTTP Request"
  win_identity:      "Library ในการจัดการ Windows Identity"
  css_minify:        "CSS/JS Minification"
  blob_storage:      "Azure Blob/Table Storage"

SECURITY RISK — Mitigation patterns:
  locked_parent:     "เป็น Dependency ที่ถูก Lock ผ่าน {parent} ไม่สามารถอัปเกรดได้อิสระ ใช้งานภายใน Intranet เท่านั้น"
  frontend_only:     "เป็น Frontend Library ใช้ใน SharePoint SitePages เท่านั้น ไม่ได้ใช้ประมวลผลข้อมูลที่ sensitive"
  client_validate:   "เป็น Frontend Library ใช้ใน SharePoint SitePages เท่านั้น การ Validate ฝั่ง Client เป็นส่วนเสริม มี Server-side validation เป็นหลัก"
  controlled_input:  "ใช้ deserialize JSON จากแหล่งที่ระบบควบคุมเองเท่านั้น (Configuration, Internal API) ไม่รับ JSON จาก external untrusted source โดยตรง"
  windows_update:    "เป็น .NET Framework System Library จะได้รับ Security Patch ผ่าน Windows Update ของ Server โดยตรง"

LICENSE RISK — Migration (license issue description) patterns:
  unknown_false:     "BD จัดเป็น Unknown License — match score ต่ำ {N}% (false positive เป็น {actual_lang} library)"
  mit_misclass:      "MIT License จริง (GitHub) — BD จัดเป็น Unknown เพราะไม่พบ license file ใน NuGet package"
  ms_proprietary:    "Microsoft proprietary license — BD ไม่รู้จัก แต่เป็น official Microsoft package"
  ms_standard:       "Microsoft license เป็น standard .NET license"
  internal:          "License Not Found — Internal library ไม่มี license บน registry"
  ms_license_terms:  "Microsoft License Terms — Product or Version Unspecified"
```

#### 9F. Lessons Learned (Waive Report Pitfalls)

```
1. EXTRACT EVERY ITEM from every PDF page — do NOT skip items at page boundaries.
   The most common error is missing items. Count your extracted items and compare
   with the PDF header summary counts.

2. BD shows MULTIPLE VERSIONS of the same component separately.
   e.g., "Microsoft ASP.NET Web API Client Libraries" may appear as 5.2.3, 5.2.7, AND 5.2.8.
   Each is a separate row. Missing one = wrong count.

3. Version numbers in BD ≠ NuGet package versions.
   e.g., BD shows "Json.NET 10.0.3" but NuGet package is "Newtonsoft.Json 10.0.3".
   Always use the BD display name in the waive report.

4. When comparing Before→After, match by EXACT "Component Name Version" string.
   "odata.net 5.8.4" (Before) ≠ "odata.net 5.8.5" (After) — treat as version changed.

5. "NEW" items are NOT always regressions. Common causes:
   - Deeper scan detection (scanner found more transitive deps)
   - Version upgrade caused BD to re-analyze
   - BD reclassification of existing risk
   Document the actual cause in the Remark column.

6. Image handling with openpyxl:
   - Load old workbook → access ws._images list → add_image() to new sheet
   - Images have anchor positions that persist
   - If sheet row count changed, images may not align to correct rows
   - Cannot create new BD screenshots from code — these must come from old file or manual capture

7. Severity casing MUST be consistent within each sheet:
   - SecurityRisk: "High"/"Medium" (title case) — this is how BD displays it
   - LicenseRisk/OperationRisk: "HIGH"/"MEDIUM" (uppercase)
   - COUNTIF formulas must match exact casing or they return 0

8. Always backup the old file before overwriting:
   mv old.xlsx old-BACKUP.xlsx
```

## Black Duck API Reference

### Authentication
```bash
# Get bearer token (valid ~2 hours)
curl -k -X POST "{server}/api/tokens/authenticate" \
  -H "Authorization: token {api-token}"
# Response: { "bearerToken": "eyJ..." }
```

### Project & Version Discovery
```bash
# Search projects
GET /api/projects?q=name:{name}
Accept: application/json

# List versions
GET /api/projects/{id}/versions?limit=20
Accept: application/json

# Get version details
GET /api/projects/{id}/versions/{vid}
Accept: application/json
```

### Component Analysis
```bash
# Get all components with risk profiles
GET /api/projects/{id}/versions/{vid}/components?limit=500
Accept: application/json

# Response includes per-component:
# - operationalRiskProfile.counts[]: {countType, count}
# - securityRiskProfile.counts[]: {countType, count}
# - licenseRiskProfile.counts[]: {countType, count}
# - licenses[]: {licenseDisplay, licenseFamilyName}
# - activityData: {lastCommitDate, newerReleases}

# countType values: UNKNOWN, OK, LOW, MEDIUM, HIGH, CRITICAL
```

### CSV Export Columns (for baseline without API data)
```
[0]  Used by
[1]  Component id
[2]  Version id
[3]  Component name
[4]  Component version name
[13] Operational Risk (OK/LOW/MEDIUM/HIGH/CRITICAL)
[26] License Risk (OK/LOW/MEDIUM/HIGH/CRITICAL)
[31] Critical Vulnerability Count
[32] High Vulnerability Count
[33] Medium Vulnerability Count
[34] Low Vulnerability Count
```

## .NET Framework 4.8 Compatibility Matrix

### Safe to Upgrade (confirmed net462/netstandard2.0 TFMs)

| Package Family | Max Version | Assembly Version |
|---|---|---|
| Microsoft.Extensions.* | 10.0.8 | 10.0.0.8 |
| Microsoft.IdentityModel.* | 8.18.0 | 8.18.0.0 |
| System.IdentityModel.Tokens.Jwt | 8.18.0 | 8.18.0.0 |
| Microsoft.ApplicationInsights | 3.1.1 | 3.1.1.0 |
| System.Configuration.ConfigurationManager | 10.0.8 | 10.0.0.8 |
| System.Diagnostics.DiagnosticSource | 10.0.8 | 10.0.0.8 |
| System.DirectoryServices | 10.0.8 | 10.0.0.8 |
| System.Security.Cryptography.ProtectedData | 10.0.8 | 10.0.0.8 |
| System.Security.Permissions | 10.0.8 | 10.0.0.8 |
| Microsoft.Bcl.AsyncInterfaces | 10.0.8 | 10.0.0.8 |
| Microsoft.Bcl.TimeProvider | 10.0.8 | 10.0.0.8 |
| Microsoft.CodeDom.Providers.DotNetCompilerPlatform | 4.1.0 | 4.1.0.0 |
| Newtonsoft.Json | 13.0.4 | 13.0.0.0 |

### At Maximum Version (cannot upgrade further on .NET Framework)

| Package | Current Max | Reason |
|---|---|---|
| AngleSharp / AngleSharp.Css | 0.17.0 | Latest stable release |
| System.ComponentModel.Annotations | 5.0.0 | Newer versions target .NET 5+ only |
| System.IO.FileSystem.AccessControl | 5.0.0 | Newer versions target .NET 5+ only |
| System.Security.Principal.Windows | 5.0.0 | Newer versions target .NET 5+ only |
| System.Security.AccessControl | 6.0.1 | Latest with netstandard2.0 |

### Legacy Dependencies (cannot remove without major refactoring)

| Package | Locks | Impact |
|---|---|---|
| SharePointPnPCoreOnline 3.8.1904 | IdentityModel 5.2.4, JWT 5.2.4 | Security risk (MEDIUM) |
| MapSuiteDependency-NewtonsoftJson 10.3.0 | Json.NET 10.0.3 | Security risk (MEDIUM) |
| Microsoft.Azure.ActiveDirectory.GraphClient | Various | License risk (HIGH) |

## Troubleshooting

### Windows path issues with Node.js
```bash
# /tmp/ maps to C:\tmp\ on Windows, not $USERPROFILE
# Always use $USERPROFILE/tmp/ for temp files
node -e "require(process.env.USERPROFILE + '/tmp/file.json')"
```

### Node.js inline escaping
```bash
# Avoid \! in node -e on bash (causes "Expected unicode escape")
# Write scripts to files instead of inline:
node script.js  # preferred over node -e "..."

# Avoid !== in node -e (bash escapes \!)
# Use: val != 'x'  or write to file
```

### Black Duck API Accept headers
```bash
# Some endpoints require specific Accept headers:
# Projects/Versions: application/json (NOT vnd.blackducksoftware.user-4+json)
# Components: application/json
# Authentication: no Accept header needed
```

### sed on Windows (Git Bash)
```bash
# Backslashes in paths need escaping in sed patterns
# Use | as delimiter instead of / when paths contain slashes
sed -i 's|old\path|new\path|g' file

# For complex replacements, prefer Edit tool or write a script file
```

## The Golden Rules

1. **Compare against baseline, not zero** — Only fix NEW items that appeared after baseline
2. **Three-file update** — Every package change requires packages.config + .csproj + config binding redirect
3. **Verify TFM before upgrade** — .NET Framework 4.8 only supports net462/netstandard2.0
4. **Check actual package contents** — Package structure changes between major versions (paths, TFM folders)
5. **Both directories** — Always update source (for build) AND scan directory (for Black Duck)
6. **Assembly version != NuGet version** — Map correctly (e.g., NuGet 10.0.8 → Assembly 10.0.0.8)
7. **Deeper scans find more transitive deps** — Component count can increase (71→137) without any code change; always check if "new" items existed before
8. **Black Duck misclassifies some MIT licenses** — PnP.Framework, SharePoint CSOM show "Unknown License" despite being MIT; mark as "Reviewed" in BD
9. **Regression ≠ code change** — Op MEDIUM/Lic HIGH can increase from scanner detecting pre-existing dependencies; explain root cause in report
10. **Use python csv.DictReader for CSV parsing** — Black Duck CSVs have commas inside quoted fields; simple awk/cut parsing breaks column alignment

## Common False Positives (Black Duck License Misclassification)

| Component | BD Says | Actual License | Action |
|-----------|---------|---------------|--------|
| PnP.Framework | Unknown License | MIT (GitHub) | Mark Reviewed |
| SharePoint CSOM | Unknown License | Microsoft proprietary | Mark Reviewed |
| icebox | Unknown License | Varies | Investigate |
| YCSoft.WebAPI.Utiltity | License Not Found | Custom/internal | Mark Reviewed |

## Reference
- PTTGC.KBS round 1: 85 op-risk → 54, 27 resolved, 0 new. Security 9→6. License 5→6 (1 BD reclassification).
- PTTGC.KBS round 2 (waive): Baseline 20260515 1042 (71 comps) vs version 4 (137 comps).
  - Op HIGH: 54→45 (-9), Op MED: 2→3 (+1). 15 items removed, 7 new (deeper scan).
  - Sec HIGH: 3→3 (0), Sec MED: 6→3 (-3). 3 items removed (5.4.0/12.0.1 versions gone).
  - Lic HIGH: 4→5 (+1, PnP.Framework — BD misclassifies MIT), Lic MED: 1→1 (0).
  - Waive report: xlsx with Overview + 3 risk sheets + L1-L6 detail + 3 hidden baseline sheets.
  - Old v2 was wrong: missed 6 items (AngleSharp 0.9.11, Json.NET 10.0.3, 3x Web API variants, Web Pages 3.2.7).
