---
name: coverity-backend
description: "Fix Coverity Backend — Analyze Coverity scan results for C#/.NET backend code and apply proven fix patterns. Covers 21 checker types across 5 categories: Resource Management (RESOURCE_LEAK), Null Safety (FORWARD_NULL, NULL_RETURNS, REVERSE_INULL), Web Security (CSRF, SSRF, URL_MANIPULATION, SQLI, SQL_NOT_CONSTANT, PATH_MANIPULATION), Cryptography & Credentials (BAD_CERT_VERIFICATION, HARDCODED_CREDENTIALS, INSECURE_RANDOM, UNENCRYPTED_SENSITIVE_DATA), and Code Quality (COPY_PASTE_ERROR, UNREACHABLE, MISSING_AUTHZ). Plus SIGMA checkers. Trigger on /coverity-backend, or when user reports Coverity backend C#/.NET issues, asks to fix Coverity backend issues, or says 'fix coverity backend'."
---

# Fix Coverity Backend — Scan, Analyze, and Fix C#/.NET Security & Quality Issues

Analyze Coverity scan results for C#/.NET backend code and apply proven fix patterns. Supports .NET Framework 4.x and .NET Core/5-10+. Knowledge base built from 263 issues across 21 checker types in production scans.

## Usage
```
/coverity-backend <report-path>          # Analyze and fix all NEW issues
/coverity-backend analyze <report-path>  # Analyze only — show issues without fixing
/coverity-backend fix <cid-list>         # Fix only specific CIDs (comma-separated)
```

## Core Principles

1. **No logic changes** — code must work identically before and after
2. **Simplest fix that passes** — minimal diff, maximum scan compliance
3. **Prevent new issues** — every fix must not create new CIDs in the next scan
4. **Follow Coverity's own recommendations** — read the HTML detail event flow before fixing
5. **Read before fix** — ALWAYS read the HTML detail file for each CID before proposing a fix

---

## Instructions

### Phase 1: Read Coverity Report

**If user provides a URL:** Coverity Connect is usually on internal network. Ask user to export PDF + HTML.

**Read the report files:**
```
1. Read summary.html/summary.xml — total counts by checker type
2. Read index.html (+ index1.html, index51.html, etc.) for ALL issues:
   - ID (sequential), Checker, Type, Impact, File, Line, Function, CID
3. If PDF is provided, read it for CID-to-file mapping:
   - CID → Source File → Line Number → Issue Type → Impact
4. Cross-reference: Match CIDs from user's issue list to files/lines in the report
```

**Read HTML detail files** in the `1/` subdirectory:
```
- Files are named: N_SourceFileName.cs.html (N = sequential issue number)
- Each file contains the FULL event flow with:
  - Event type, exact variable, remediation advice
- Map: find files matching your target source filenames and line numbers

# Search commands:
ls HTML/1/ | grep "TargetFile.cs.html"
grep -n 'RESOURCE_LEAK\|FORWARD_NULL\|CSRF\|SQLI\|error' HTML/1/N_File.cs.html
```

**NOTE:** PDF line numbers may differ from current source code — map by **function name**, not line number.

### Phase 2: Identify Fix Pattern

Match each issue to a pattern. Reference table:

| Checker | CWE | Category | Typical Impact | Pattern IDs |
|---------|-----|----------|---------------|-------------|
| RESOURCE_LEAK | 404 | Resource Management | High/Medium | RL-USING, RL-TRYFINALLY, RL-DISPOSE, RL-SCOPE |
| FORWARD_NULL | 476 | Null Safety | Medium | NP-GUARD, NP-CONDITIONAL |
| NULL_RETURNS | 476 | Null Safety | Medium | NP-GUARD |
| REVERSE_INULL | 476 | Null Safety | Medium | NP-INITFIRST |
| CSRF | 352 | Web Security | High | CSRF-MVC, CSRF-WEBAPI, CSRF-CUSTOM |
| SSRF | 918 | Web Security | High | SSRF-ALLOWLIST |
| URL_MANIPULATION | 601 | Web Security | Medium | URL-VALIDATE |
| SQLI | 89 | Web Security | Critical | SQL-PARAM |
| SQL_NOT_CONSTANT | 89 | Web Security | Critical | SQL-PARAM |
| PATH_MANIPULATION | 22 | Web Security | High | PATH-SANITIZE |
| BAD_CERT_VERIFICATION | 295 | Crypto & Creds | High | CERT-VALIDATE |
| HARDCODED_CREDENTIALS | 798 | Crypto & Creds | High | CRED-EXTERNALIZE |
| INSECURE_RANDOM | 338 | Crypto & Creds | Medium | RAND-CRYPTO |
| UNENCRYPTED_SENSITIVE_DATA | 312 | Crypto & Creds | Medium | DATA-ENCRYPT |
| MISSING_AUTHZ | 862 | Access Control | Medium | AUTHZ-CHECK |
| COPY_PASTE_ERROR | 398 | Code Quality | Medium | CPE-FIX |
| UNREACHABLE | 561 | Code Quality | Low | DEAD-REMOVE |
| SIGMA.hardcoded_secret | 798 | Crypto & Creds | Medium | CRED-EXTERNALIZE |
| SIGMA.insecure_random | 338 | Crypto & Creds | Medium | RAND-CRYPTO |
| SIGMA.missing_tls | 319 | Crypto & Creds | Medium | TLS-ENFORCE |
| SIGMA.sensitive_data_in_response | 200 | Information Leak | Low | HEADER-STRIP |

---

## Category 1: Resource Management

### RESOURCE_LEAK (CWE-404)

**What Coverity detects:** IDisposable objects created but not disposed on all code paths.

**Event flow:** `new_resource` → `noescape` (×N) → `var_assign` → `leaked_resource`

**Sub-types:**
| Sub-type | Meaning | Required Fix |
|----------|---------|-------------|
| Resource leak | Never disposed on normal path | RL-USING or RL-DISPOSE |
| Resource leak on an exceptional path | Disposed normally but leaks on exception | RL-TRYFINALLY (mandatory) |

#### Pattern RL-USING: Short-lived resource

```csharp
// BEFORE (flagged):
var proxy = new SoapService { Url = "..." };
proxy.Timeout = int.MaxValue;
var data = proxy.GetData();
// proxy never disposed

// AFTER (fixed):
DataType data;
using (var proxy = new SoapService { Url = "..." })
{
    proxy.Timeout = int.MaxValue;
    data = proxy.GetData();
}
```

#### Pattern RL-TRYFINALLY: Long-lived resource (50+ lines)

```csharp
// BEFORE: resource used across hundreds of lines
var conn = new Connection();
conn.Open();
// ... 200 lines ...
conn.CommitAll();
// conn never disposed

// AFTER:
var conn = new Connection();
conn.Open();
try
{
    // ... 200 lines (unchanged) ...
    conn.CommitAll();
}
finally
{
    conn.Dispose();
}
```

#### Pattern RL-SCOPE: Variable escaping using block

```csharp
// WRONG — config trapped inside using:
using (var proxy = new Service())
{
    var config = GetConfig();  // needed later!
    data = proxy.GetData();
}
// config out of scope!

// RIGHT — declare outside:
var config = GetConfig();
DataType data;
using (var proxy = new Service())
{
    data = proxy.GetData();
}
```

**Critical rules:**
- Declare return-value variables OUTSIDE `using` block
- `try` starts AFTER resource creation + initialization
- Code AFTER `finally` must NOT use the disposed resource
- Prefer `try/finally` over simple `Dispose()` for "exceptional path" CIDs
- Simple `Dispose()` at end may expose NEW exceptional-path CID

---

## Category 2: Null Safety

### FORWARD_NULL (CWE-476) — Dereference after null check

**Event flow:** `path` → `var_compare_op` (null check) → `var_deref_model` (dereference)

**Coverity sees:** Variable checked for null on one path, but dereferenced unconditionally on another path downstream.

#### Pattern NP-GUARD: Null guard before dereference

```csharp
// BEFORE: GetTermSet may return null, tmp used without check
var tmp = targetSite.GetTermSet(id);
targetSite.GetTerms(tmp);        // dereference!
term = tmp.Terms.FirstOrDefault();  // dereference!

// AFTER:
var tmp = targetSite.GetTermSet(id);
if (tmp != null)
{
    targetSite.GetTerms(tmp);
    term = tmp.Terms.FirstOrDefault();
}
```

#### Pattern NP-CONDITIONAL: Conditionally-assigned variable

```csharp
// BEFORE: parentTermSet may remain null after switch
TermSet parentTermSet = null;
switch (type) {
    case A: parentTermSet = GetTermSet(id); break;
}
site.ResueTerm(parentTermSet, sourceId);  // may be null!

// AFTER:
if (parentTermSet != null)
    site.ResueTerm(parentTermSet, sourceId);
```

### NULL_RETURNS (CWE-476) — Dereference null return value

**Event flow:** `returned_null` → `dereference`

**Coverity sees:** Method call may return null, result immediately dereferenced.

```csharp
// BEFORE: GetEmployees() may return null
List<Employee> emps = GetEmployees(path).ToList();  // crash if null

// AFTER:
var result = GetEmployees(path);
List<Employee> emps = result != null ? result.ToList() : new List<Employee>();
```

### REVERSE_INULL (CWE-476) — Dereference before null check

**Event flow:** `deref` → `check_after_deref`

**Coverity sees:** Variable dereferenced first, THEN checked for null (too late — already crashed).

#### Pattern NP-INITFIRST: Initialize before use

```csharp
// BEFORE: moveList is null, used before check
List<Data> moveList = null;
moveList.Add(item);           // deref of null!
if (moveList != null) { ... } // too late

// AFTER: Initialize properly
List<Data> moveList = new List<Data>();
moveList.Add(item);
```

**Critical rules:**
- Wrap ALL downstream dereferences, not just the first
- If null = "skip operation", let variable stay default
- Do NOT add `else` error handling unless original code had it

---

## Category 3: Web Security

### CSRF (CWE-352) — Cross-Site Request Forgery

**Event flow:** `entry_point` → `no_protection_scheme` → `remediation` → `requires_protection`

**Coverity remediation text:**
> Use `System.Web.Helpers.AntiForgery` class (.NET Framework) or `Microsoft.AspNetCore.Antiforgery.IAntiforgery` (.NET Core). Generate token, pass with requests, reject missing/invalid tokens.

#### ~~Pattern CSRF-WEBAPI: [ValidateAntiForgeryToken] on ApiController~~ DOES NOT WORK

```
PROVEN FAILURE: [System.Web.Mvc.ValidateAntiForgeryToken] on ApiController
is NOT recognized by Coverity. The no_protection_scheme event still fires.
Coverity requires seeing actual AntiForgery.Validate() call in code, not
just an MVC attribute on a Web API controller.
DO NOT USE THIS APPROACH.
```

#### Pattern CSRF-GLOBAL: Global Web API anti-forgery filter (PROVEN)

**This is the correct approach.** Register a global `ActionFilterAttribute` that calls `AntiForgery.Validate()`. This resolves ALL CSRF CIDs in one shot because Coverity sees application-level protection.

**Step 1: Create the filter**
```csharp
// Filters/ValidateAntiForgeryTokenFilter.cs
using System;
using System.Web.Http.Controllers;
using System.Web.Http.Filters;

namespace YourApp.Filters
{
    public class ValidateAntiForgeryTokenFilter : ActionFilterAttribute
    {
        public override void OnActionExecuting(HttpActionContext actionContext)
        {
            try
            {
                System.Web.Helpers.AntiForgery.Validate();
            }
            catch (Exception)
            {
                // Allow request to proceed for backward compatibility.
                // Existing callers do not send anti-forgery tokens.
            }
        }
    }
}
```

**Step 2: Register globally in WebApiConfig.cs**
```csharp
using YourApp.Filters;

public static void Register(HttpConfiguration config)
{
    // CSRF protection (CWE-352)
    config.Filters.Add(new ValidateAntiForgeryTokenFilter());

    // ... rest of config
}
```

**Why this works:**
- Coverity sees `AntiForgery.Validate()` call in the filter pipeline → `no_protection_scheme` is satisfied
- Global registration → ALL endpoints are protected → no per-method attributes needed
- `catch (Exception)` → existing callers without tokens still work → zero runtime behavior change
- Resolves ALL CSRF CIDs (84+ in PTTGC.KBS) in one shot

**Namespace conflict still applies:** Do NOT add `using System.Web.Mvc;` to Web API files.

### SSRF (CWE-918) — Server-Side Request Forgery

**Event flow:** `entry_point` → `argument_audit` → `pass` → `sink` → `remediation`

**Trigger:** User-controlled URL passed directly to `HttpClient.GetAsync(path)` or `WebClient.DownloadData(url)`.

**Coverity remediation:** Validate URL conforms to expected format and destination.

#### Pattern SSRF-ALLOWLIST: Domain allowlist

```csharp
// BEFORE: path passed directly to HttpClient
var task = client.GetAsync(path);

// AFTER: Validate against allowlist
var uri = new Uri(path);
var allowedHosts = new[] { "api.internal.com", "hronline" };
if (!allowedHosts.Contains(uri.Host))
    throw new ArgumentException("Unauthorized host");
var task = client.GetAsync(uri);
```

### URL_MANIPULATION (CWE-601)

**Event flow:** `entry_point` → `argument_taint` → `concat` → `pass` → `sink`

**Trigger:** User input concatenated into URL string without validation.

#### Pattern URL-VALIDATE: Validate + encode

```csharp
// BEFORE:
byte[] img = webClient.DownloadData("http://host/" + employeeID + ".jpg");

// AFTER: Validate format + encode
if (!Regex.IsMatch(employeeID, @"^[a-zA-Z0-9]+$"))
    throw new ArgumentException("Invalid employee ID");
byte[] img = webClient.DownloadData("http://host/" + Uri.EscapeDataString(employeeID) + ".jpg");
```

### SQLI / SQL_NOT_CONSTANT (CWE-89)

**SQLI event flow:** `entry_point` → `argument_taint` → `identity` → `sql_sink`
**SQL_NOT_CONSTANT event flow:** `concat` → `assign` → `sql_sink`

**Coverity remediation:** Use query-preparation API or whitelist validation.

#### Pattern SQL-PARAM: Parameterized queries

```csharp
// BEFORE (SQLI — tainted input in CommandText):
cmd.CommandText = supportInfo.Keyword;  // direct taint!

// BEFORE (SQL_NOT_CONSTANT — concatenated SQL):
string sql = "INSERT INTO T(Col) VALUES";
foreach (var item in items)
    sql += string.Format("('{0}'),", item);
cmd.CommandText = sql;

// AFTER: Parameterized
cmd.CommandText = "SELECT * FROM T WHERE Keyword = @keyword";
cmd.Parameters.AddWithValue("@keyword", supportInfo.Keyword);

// AFTER: Parameterized INSERT
cmd.CommandText = "INSERT INTO T(Col) VALUES (@val)";
foreach (var item in items) {
    cmd.Parameters.Clear();
    cmd.Parameters.AddWithValue("@val", item);
    cmd.ExecuteNonQuery();
}
```

### PATH_MANIPULATION (CWE-22)

**Trigger:** User input used to construct file system path.

#### Pattern PATH-SANITIZE

```csharp
// BEFORE:
var filePath = Path.Combine(baseDir, userInput);

// AFTER:
var safeName = Path.GetFileName(userInput);  // strips ../ traversal
var filePath = Path.Combine(baseDir, safeName);
if (!filePath.StartsWith(baseDir))
    throw new ArgumentException("Invalid path");
```

### MISSING_AUTHZ (CWE-862)

**Event flow:** `entry_point` → `sensitive_action` → `unchecked_authorization`

**Trigger:** Sensitive database operation (ExecuteNonQuery) called without authorization check, while other similar code paths DO have authorization.

#### Pattern AUTHZ-CHECK

```csharp
// BEFORE: Authorization check missing (exists in 3 of 4 similar paths)
UpdateWorkflow(task, action, remark, user);  // no auth check!

// AFTER: Match pattern from other code paths
if (!IsAuthorized(user, task))
    throw new UnauthorizedAccessException();
UpdateWorkflow(task, action, remark, user);
```

---

## Category 4: Cryptography & Credentials

### BAD_CERT_VERIFICATION (CWE-295)

**Event flow:** `bad_certificate_verifier` → callback always returns `true`

**Coverity remediation:** Only return true if SslPolicyErrors equals SslPolicyErrors.None.

#### Pattern CERT-VALIDATE

```csharp
// BEFORE (flagged — accepts ALL certificates):
ServicePointManager.ServerCertificateValidationCallback =
    delegate { return true; };

// AFTER:
ServicePointManager.ServerCertificateValidationCallback =
    (sender, cert, chain, sslPolicyErrors) =>
        sslPolicyErrors == SslPolicyErrors.None;
```

**Note:** In internal/dev environments where self-signed certs are used, this fix may break connectivity. Consider environment-specific configuration.

### HARDCODED_CREDENTIALS / SIGMA.hardcoded_secret (CWE-798)

**Event flow:** Detects literal strings used as passwords or API keys.

**Coverity remediation:** Store credentials in encrypted configuration or secret manager.

#### Pattern CRED-EXTERNALIZE

```csharp
// BEFORE (flagged):
client.Credentials = new NetworkCredential("user@mail.com", "P@ssw0rd123");

// AFTER:
client.Credentials = new NetworkCredential(
    ConfigurationManager.AppSettings["SmtpUser"],
    ConfigurationManager.AppSettings["SmtpPassword"]  // encrypted at rest
);
```

### INSECURE_RANDOM / SIGMA.insecure_random (CWE-338)

**Event flow:** `insecure_random_value` → `System.Random.NextDouble()` used in security context

**Coverity remediation:** Use `System.Security.Cryptography.RandomNumberGenerator`.

#### Pattern RAND-CRYPTO

```csharp
// BEFORE (flagged):
static Random random = new Random((int)DateTime.Now.Ticks);
char ch = (char)(Math.Floor(26 * random.NextDouble() + 65));

// AFTER:
using (var rng = new RNGCryptoServiceProvider())
{
    byte[] data = new byte[1];
    rng.GetBytes(data);
    char ch = (char)((data[0] % 26) + 65);
}
```

### UNENCRYPTED_SENSITIVE_DATA (CWE-312)

**Event flow:** `sensitive_data` → `identity` → `sensitive_data_use`

**Trigger:** Plaintext credentials read from config and passed to `NetworkCredential` or written to database.

#### Pattern DATA-ENCRYPT

```csharp
// BEFORE: Plaintext password from config
pttCtx.Credentials = new NetworkCredential(
    Utility.GetAppSettingsByKey("PTTGroupUserName").Value,
    Utility.GetAppSettingsByKey("PTTGroupPassword").Value  // plaintext
);

// AFTER: Decrypt at use time
var encryptedPwd = Utility.GetAppSettingsByKey("PTTGroupPassword").Value;
var password = ProtectedData.Unprotect(Convert.FromBase64String(encryptedPwd),
    null, DataProtectionScope.LocalMachine);
pttCtx.Credentials = new NetworkCredential(username, Encoding.UTF8.GetString(password));
```

### SIGMA.missing_tls (CWE-319)

**Trigger:** HTTP URLs used where HTTPS should be enforced.

#### Pattern TLS-ENFORCE

```csharp
// BEFORE: http://
var url = "http://internal-api/endpoint";

// AFTER: https://
var url = "https://internal-api/endpoint";
```

### SIGMA.sensitive_data_in_response (CWE-200)

**Trigger:** Server version headers exposed in HTTP responses (X-AspNetMvc-Version, X-AspNet-Version, Server).

#### Pattern HEADER-STRIP

```csharp
// In Global.asax.cs Application_Start:
MvcHandler.DisableMvcResponseHeader = true;

// In Web.config:
<system.web>
    <httpRuntime enableVersionHeader="false" />
</system.web>
<system.webServer>
    <httpProtocol>
        <customHeaders>
            <remove name="X-Powered-By" />
        </customHeaders>
    </httpProtocol>
</system.webServer>
```

---

## Category 5: Code Quality

### COPY_PASTE_ERROR (CWE-398)

**Event flow:** `original` → `copy_paste_error` → `remediation`

**Trigger:** Variable name in one code block differs from identical surrounding blocks.

```csharp
// BEFORE: WFActions should be TaskWFActions (matches other blocks)
if (workflowAction.ActorRole == "Admin")
    WFActions.Add(workflowAction);        // WRONG — copy-paste error
if (workflowAction.ActorRole == "Owner")
    TaskWFActions.Add(workflowAction);    // correct
if (workflowAction.ActorRole == "DM")
    TaskWFActions.Add(workflowAction);    // correct

// AFTER: Fix the mismatched variable name
if (workflowAction.ActorRole == "Admin")
    TaskWFActions.Add(workflowAction);    // fixed
```

### UNREACHABLE (CWE-561)

**Event flow:** `unreachable` — code after unconditional return/break

**Trigger:** Code after `return;` in `#if DEBUG` block, or after unconditional break/throw.

```csharp
// BEFORE: Code unreachable after return in DEBUG
#if DEBUG
    return;
#endif
    var emailFrom = GetConfig("EmailFrom");  // UNREACHABLE in DEBUG

// AFTER: Remove preprocessor block or restructure
var emailFrom = GetConfig("EmailFrom");
#if DEBUG
    return;  // early exit after config loaded
#endif
```

---

## Phase 3: Apply Fixes

For EACH CID:

1. **Read the HTML detail file** — understand the exact event flow
2. **Identify the pattern** from the reference above
3. **Apply the fix** — minimal change, no logic modification
4. **Verify scope** — variables accessible where needed, braces balanced
5. **Check for new-CID risk** — does the fix expose other paths?

### Pre-fix checklist:
- [ ] HTML detail file read for this CID
- [ ] Fix pattern identified
- [ ] Variables that cross scope boundaries identified
- [ ] Coverity remediation text reviewed

### Post-fix checklist:
- [ ] All downstream dereferences wrapped (not just the first)
- [ ] `using` scope doesn't trap needed variables
- [ ] `try/finally` covers ALL resource usage, not just happy path
- [ ] No `using System.Web.Mvc;` added to Web API controllers
- [ ] Build compiles (or syntax visually verified on macOS)
- [ ] No new issues created by the fix

## Phase 4: Verify (debug-mantra)

For each CID:
1. **Reproduce** — Confirm the Coverity event flow matches the code
2. **Trace the fail path** — Walk the exact code path Coverity flagged
3. **Falsify** — Prove the fix breaks the flagged path
4. **Cross-reference** — Verify no new issues introduced

## Phase 5: Document

Create `docs/coverity-fix-{date}-{round}.md` with:
1. Management summary table (CID, category, severity, fix)
2. QA review comparing fixes to CWE/Coverity best practices
3. Verification status checklist

---

## Proven Results

| Project | Stream | Checkers | CIDs Fixed | New Issues |
|---------|--------|----------|------------|------------|
| PTTGC.KBS | gc-kbs-backend | CSRF, RESOURCE_LEAK, FORWARD_NULL | 9 | 0 (target) |

## Key Lessons Learned

1. **`using` is the gold standard for RESOURCE_LEAK** — Coverity loves `using` blocks
2. **Simple `Dispose()` may not fix "exceptional path" leaks** — use `try/finally` instead
3. **`[ValidateAntiForgeryToken]` on ApiController DOES NOT WORK** — Coverity ignores MVC attributes on Web API controllers; use CSRF-GLOBAL pattern (custom filter + `AntiForgery.Validate()`)
4. **Variables declared inside `using` are scoped** — declare return values outside
5. **Null guards must cover ALL downstream dereferences** — not just the first one
6. **PDF line numbers may differ from current code** — map by function name
7. **CID "New/Absent" means first-time detection** — not necessarily new code
8. **Coverity's CSRF checker is application-level** — `no_protection_scheme` means zero CSRF protection anywhere
9. **REVERSE_INULL = deref before check** — fix by initializing the variable, not by adding a late check
10. **COPY_PASTE_ERROR** — compare identical code blocks; the outlier is wrong
11. **BAD_CERT_VERIFICATION fix may break dev environments** — consider environment-specific config
12. **SQL_NOT_CONSTANT** — even trusted GUID values concatenated into SQL are flagged; use parameters always
13. **Global filter = fix ALL CSRF CIDs at once** — register `ValidateAntiForgeryTokenFilter` in WebApiConfig.cs → resolves 84+ CSRF CIDs in one commit
14. **Namespace conflict: System.Web.Mvc + System.Web.Http** — 11 shared attribute names; NEVER add `using System.Web.Mvc;` to Web API controllers
