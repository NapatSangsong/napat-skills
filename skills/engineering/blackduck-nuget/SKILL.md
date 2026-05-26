---
name: blackduck-nuget
description: "Fix Black Duck NuGet — Analyze Black Duck scan results for .NET Framework (4.x) NuGet projects, compare against a baseline version, identify NEW risk items (Operational/Security/License), and upgrade packages to resolve them while respecting .NET Framework compatibility constraints. Trigger on /blackduck-nuget, or when user reports Black Duck operational/security/license risk items, asks to fix Black Duck scan results, or says 'fix blackduck'."
---

# Fix Black Duck NuGet — Scan, Compare, and Upgrade .NET Framework packages

Analyze Black Duck scan results for .NET Framework (4.x) NuGet projects, compare against a baseline version, identify NEW risk items (Operational/Security/License), and upgrade packages to resolve them while respecting .NET Framework compatibility constraints. Learned from PTTGC.KBS project (85 operational risk items reduced to 54, 27 resolved, 0 new).

## Usage
```
/blackduck-nuget <black-duck-url> <api-token> <project-name>   # Full workflow
/blackduck-nuget compare <baseline> <current>                   # Compare two versions
/blackduck-nuget upgrade <package-name> <target-version>        # Upgrade specific package
/blackduck-nuget report                                         # Generate remediation report
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
- PTTGC.KBS round 2: Baseline (71) vs version 4 (137). Op HIGH -9, Sec MEDIUM -3, 3 vulns resolved. +1 Op MED / +1 Lic HIGH from deeper scan (not code change).
