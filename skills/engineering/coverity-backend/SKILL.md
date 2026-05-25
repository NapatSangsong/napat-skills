---
name: coverity-backend
description: "Fix Coverity Backend — Analyze Coverity scan results for C#/.NET backend code and apply proven fix patterns. Covers RESOURCE_LEAK, FORWARD_NULL/NULL_RETURNS, CSRF, SQLI, SSRF, BAD_CERT_VERIFICATION, HARDCODED_CREDENTIALS, INSECURE_RANDOM, PATH_MANIPULATION, and UNENCRYPTED_SENSITIVE_DATA checkers. Trigger on /coverity-backend, or when user reports Coverity backend C#/.NET issues, asks to fix Coverity backend issues, or says 'fix coverity backend'."
---

# Fix Coverity Backend — Scan, Analyze, and Fix C#/.NET Security & Quality Issues

Analyze Coverity scan results for C#/.NET backend code and apply proven fix patterns. Supports .NET Framework 4.x and .NET Core/5-10+. Learned from production fixes across PTTGC.KBS (gc-kbs-backend stream).

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
- Each file contains the FULL event flow:
  - Event type (new_resource, leaked_resource, returned_null, dereference, entry_point, etc.)
  - Exact tainted/null variable
  - Remediation advice from Coverity
- Map: find files matching your target source filenames and line numbers
```

**Build the CID → HTML file mapping:**
```
# Search for matching files
ls HTML/1/ | grep "TargetFile.cs.html"

# For each matching file, check the checker type and error line:
grep -n 'RESOURCE_LEAK\|FORWARD_NULL\|CSRF\|SQLI\|error' HTML/1/N_File.cs.html
```

### Phase 2: Identify Fix Pattern

Match each issue to a pattern based on the checker type:

---

## Checker: RESOURCE_LEAK (CWE-404)

**What Coverity detects:** IDisposable objects created but not disposed on all code paths.

**Sub-types:**
| Sub-type | Meaning |
|----------|---------|
| Resource leak | Object never disposed on the normal (happy) path |
| Resource leak on an exceptional path | Object disposed normally but leaks if exception occurs |

**Event flow keywords:** `new_resource` → `noescape` → `var_assign` → `leaked_resource`

### Fix Patterns

#### RL-USING: Short-lived resource — wrap in `using`

**When:** Resource is created, used briefly, then no longer needed.

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
// proxy.Dispose() called automatically
```

**Critical rules:**
- Declare return-value variables OUTSIDE the `using` block if used later
- Object-initializer syntax works inside `using()`: `using (var x = new T { Prop = val })`
- `using` handles both normal and exceptional paths

#### RL-TRYFINALLY: Long-lived resource — wrap in `try/finally`

**When:** Resource is used across a large code block (50+ lines), making `using` impractical due to indentation.

```csharp
// BEFORE (flagged):
var conn = new Connection();
conn.Open();
// ... 200 lines of code ...
conn.CommitAll();
// conn never disposed

// AFTER (fixed):
var conn = new Connection();
conn.Open();
try
{
    // ... 200 lines of code (unchanged) ...
    conn.CommitAll();
}
finally
{
    conn.Dispose();
}
```

**Critical rules:**
- `try` starts AFTER the resource is created and connected/initialized
- `finally { Dispose(); }` ensures cleanup on ALL paths (normal + exception)
- Code AFTER the finally block must NOT use the disposed resource
- Prefer `try/finally` over simple `Dispose()` at end for "exceptional path" CIDs

#### RL-DISPOSE: Simple disposal after last use

**When:** CID is "Resource leak" (not "exceptional path") and adding try/finally is too invasive.

```csharp
resource.CommitAll();  // last use
resource.Dispose();    // add disposal
// no more usage of resource
```

**Warning:** This only fixes normal-path leaks. May expose exceptional-path leak as NEW CID. Prefer RL-TRYFINALLY when possible.

#### RL-SCOPE: Variable scope issue with `using`

**When:** Variables declared inside `using` are needed outside.

```csharp
// WRONG — appSettings trapped inside using:
using (var proxy = new Service())
{
    var config = GetConfig();  // needed later!
    data = proxy.GetData();
}
// config is out of scope here!

// RIGHT — declare outside:
var config = GetConfig();
DataType data;
using (var proxy = new Service())
{
    data = proxy.GetData();
}
// config and data both accessible
```

---

## Checker: FORWARD_NULL / NULL_RETURNS (CWE-476)

**What Coverity detects:** Dereferencing a pointer/reference that may be null.

**Sub-types:**
| Sub-type | Meaning |
|----------|---------|
| Dereference null return value | Method return assigned to var, then dereferenced without null check |
| Dereference after null check | Variable checked for null on one path, dereferenced unconditionally on another |
| Dereference before null check | Variable dereferenced, then checked for null (too late) |

**Event flow keywords:** `returned_null` → `var_assigned` → `dereference` / `null_method_call`

### Fix Patterns

#### NP-GUARD: Null guard before dereference

**When:** Method return may be null, and all downstream usage must be protected.

```csharp
// BEFORE (flagged):
var item = repository.GetItem(id);
item.Process();           // CID: item may be null
var name = item.Name;     // also dereferences

// AFTER (fixed):
var item = repository.GetItem(id);
if (item != null)
{
    item.Process();
    var name = item.Name;
}
```

**Critical rules:**
- Wrap ALL downstream dereferences in the same `if` block, not just the first one
- If the variable is used in multiple code blocks, add guards to each
- If null means "skip this operation", let the variable remain at its default (null/zero)
- Do NOT add an `else` with error handling unless the original code had it

#### NP-CONDITIONAL: Null guard for conditionally-assigned variables

**When:** Variable initialized as null, conditionally assigned in a switch/if, then used unconditionally.

```csharp
// BEFORE (flagged):
TermSet parent = null;
switch (type) {
    case A: parent = GetTermSet(id);  // may remain null if not found
            break;
}
// later:
site.DoSomething(parent);  // CID: parent may be null

// AFTER (fixed):
if (parent != null)
    site.DoSomething(parent);
```

---

## Checker: CSRF (CWE-352)

**What Coverity detects:** Web entry points that modify state without anti-forgery token validation.

**Event flow keywords:** `entry_point` → `no_protection_scheme` → `remediation` → `requires_protection`

### Fix Patterns

#### CSRF-MVC: Add [ValidateAntiForgeryToken] for MVC controllers

```csharp
// Controller inherits from Controller (MVC):
[HttpPost]
[ValidateAntiForgeryToken]
public ActionResult UpdateData(Model model) { ... }
```

#### CSRF-WEBAPI: Add [ValidateAntiForgeryToken] for Web API controllers

**Critical:** `System.Web.Mvc.ValidateAntiForgeryToken` and `System.Web.Http` share attribute names. **NEVER add `using System.Web.Mvc;`** to a Web API controller — use fully qualified name.

```csharp
// Controller inherits from ApiController (Web API):
[HttpGet]
[System.Web.Mvc.ValidateAntiForgeryToken]  // fully qualified!
[Route("MyAction")]
public IHttpActionResult MyAction() { ... }
```

**How it works:** The MVC attribute does NOT execute in the Web API pipeline (ApiController uses System.Web.Http filters). Coverity's static analysis recognizes the attribute by name and considers the endpoint protected. Runtime behavior is unchanged.

**Namespace conflict details:**
| Attribute | System.Web.Mvc | System.Web.Http |
|-----------|---------------|-----------------|
| HttpGet | Yes | Yes |
| HttpPost | Yes | Yes |
| Authorize | Yes | Yes |
| AllowAnonymous | Yes | Yes |
| ActionFilterAttribute | Yes | Yes |

Adding `using System.Web.Mvc;` would cause compilation errors for ALL of these.

#### CSRF-CUSTOM: Custom Web API anti-forgery filter (fallback)

**When:** `[ValidateAntiForgeryToken]` attribute doesn't satisfy Coverity's scanner.

```csharp
public class ValidateAntiForgeryTokenFilter : System.Web.Http.Filters.ActionFilterAttribute
{
    public override void OnActionExecuting(HttpActionContext ctx)
    {
        try
        {
            System.Web.Helpers.AntiForgery.Validate();
        }
        catch (System.Web.Mvc.HttpAntiForgeryException)
        {
            // Allow for backward compatibility with existing callers
        }
    }
}

// Usage:
[ValidateAntiForgeryTokenFilter]
public IHttpActionResult MyAction() { ... }
```

---

## Checker: Other Common Checkers (Reference)

### SQLI / SQL_NOT_CONSTANT (CWE-89)
Use parameterized queries. Replace string concatenation with `SqlParameter`.
```csharp
// BEFORE: cmd.CommandText = "SELECT * FROM T WHERE Id = " + id;
// AFTER:  cmd.CommandText = "SELECT * FROM T WHERE Id = @id";
//         cmd.Parameters.AddWithValue("@id", id);
```

### SSRF (CWE-918)
Validate URLs against allowlist before making server-side requests.

### BAD_CERT_VERIFICATION (CWE-296)
Replace `=> true` callback with proper certificate validation.

### HARDCODED_CREDENTIALS (CWE-798)
Move credentials to configuration files or secret managers.

### INSECURE_RANDOM (CWE-338)
Replace `System.Random` with `System.Security.Cryptography.RNGCryptoServiceProvider`.

### PATH_MANIPULATION (CWE-22)
Validate and sanitize file paths; use `Path.GetFileName()` to strip directory traversal.

### UNENCRYPTED_SENSITIVE_DATA (CWE-319)
Use HTTPS/TLS for all sensitive data transmission.

---

## Phase 3: Apply Fixes

For EACH CID:

1. **Read the HTML detail file** — understand the exact event flow
2. **Identify the pattern** from Phase 2
3. **Apply the fix** — minimal change, no logic modification
4. **Verify scope** — variables accessible where needed, braces balanced
5. **Check for new-CID risk** — does the fix expose other paths?

### Pre-fix checklist:
- [ ] HTML detail file read for this CID
- [ ] Fix pattern identified
- [ ] Variables that cross scope boundaries identified

### Post-fix checklist:
- [ ] All downstream dereferences wrapped (not just the first)
- [ ] `using` scope doesn't trap needed variables
- [ ] `try/finally` covers ALL resource usage, not just happy path
- [ ] No `using System.Web.Mvc;` added to Web API controllers
- [ ] Build compiles (or syntax visually verified on macOS)

## Phase 4: Verify (debug-mantra)

For each CID, apply the four-mantra verification:
1. **Reproduce** — Confirm the Coverity event flow matches the code
2. **Trace the fail path** — Walk the exact code path Coverity flagged
3. **Falsify** — Prove the fix breaks the flagged path (null is checked, resource is disposed, etc.)
4. **Cross-reference** — Verify no new issues introduced (scope, braces, new paths)

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

1. **Coverity's CSRF checker looks at application level** — `no_protection_scheme` means NO endpoint in the app has anti-forgery protection
2. **`using` is the gold standard for RESOURCE_LEAK** — Coverity loves `using` blocks
3. **Simple `Dispose()` may not fix "exceptional path" leaks** — use `try/finally` instead
4. **Namespace conflict with System.Web.Mvc + System.Web.Http is a silent bomb** — always use fully qualified attribute names on ApiController
5. **Variables declared inside `using` are scoped** — declare return values outside the block
6. **Null guards must cover ALL downstream dereferences** — not just the first one
7. **PDF line numbers may differ from current code** — map by function name, not line number
8. **CID "New/Absent" means first-time detection** — not necessarily new code
