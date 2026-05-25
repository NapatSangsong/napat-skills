---
name: coverity-prescan-backend
description: "Coverity Pre-Scan Backend — Security-focused code review that checks C#/.NET backend code against Coverity's 21 checker patterns BEFORE the actual scan. Catches RESOURCE_LEAK, null dereference, CSRF, SQL injection, hardcoded credentials, and 15+ other issue types using pattern matching. Reduces scan-fix-rescan cycles. Trigger on /coverity-prescan-backend, or when user asks to pre-check backend code for Coverity issues, or says 'prescan backend'."
---

# Coverity Pre-Scan Backend — Catch C#/.NET Issues Before They're Found

Security-focused code review that checks C#/.NET backend code against all 21 Coverity checker patterns BEFORE submitting to the actual Coverity scan. Uses pattern matching, grep, and code reading to catch issues early and reduce scan-fix-rescan cycles.

## Usage
```
/coverity-prescan-backend                        # Scan all .cs files in current project
/coverity-prescan-backend <path>                 # Scan specific file or directory
/coverity-prescan-backend --changed-only         # Scan only git-modified files
/coverity-prescan-backend --checkers RESOURCE_LEAK,CSRF  # Scan specific checker types only
```

## How It Works

This is NOT a replacement for Coverity — it's a **pre-flight checklist** that catches the patterns Coverity WILL flag. Think of it as a code review guided by Coverity's checker rules.

**What we CAN detect (high confidence):**
- IDisposable objects not in `using`/`try-finally`
- Missing `[ValidateAntiForgeryToken]` on state-modifying endpoints
- String concatenation in SQL CommandText
- `ServerCertificateValidationCallback = delegate { return true; }`
- Hardcoded passwords/credentials in source
- `System.Random` used for security
- Missing null checks after known-nullable returns
- Plaintext sensitive data patterns
- HTTP URLs where HTTPS expected
- Server version headers not stripped

**What we CANNOT detect (Coverity-only, interprocedural):**
- Complex taint flow across method boundaries
- Precise null-path analysis through multiple branches
- Context-sensitive resource leak paths
- Cross-method SSRF taint propagation

## Instructions

### Step 1: Determine Scan Scope

```bash
# Option A: All C# files in backend
find Backend/ -name "*.cs" -not -path "*/obj/*" -not -path "*/bin/*"

# Option B: Only files changed since last scan
git diff --name-only origin/master -- '*.cs'

# Option C: Specific directory
find Backend/ProjectName/ -name "*.cs"
```

### Step 2: Run All Checker Patterns

Execute each checker pattern against the target files. For each finding, report:
- File and line number
- Checker type
- Severity (Critical/High/Medium/Low)
- Code snippet
- Recommended fix pattern (from coverity-backend skill)

---

## Checker Patterns

### 1. RESOURCE_LEAK (CWE-404) — High Confidence

**What to grep:**
```bash
# Find IDisposable objects not in using blocks
# Common IDisposable types in .NET:
grep -n "new SqlConnection\|new SqlCommand\|new HttpClient\|new WebClient\|new SmtpClient\|new StreamReader\|new StreamWriter\|new FileStream\|new MemoryStream\|new TcpClient\|new SoapHttpClientProtocol" *.cs

# Then check: is each match inside a "using" block?
# Flag any "new XxxDisposable" NOT preceded by "using" on the same or previous line
```

**Pattern to flag:**
```csharp
// FLAGGED: new IDisposable() without using
var client = new HttpClient();           // no using!
var conn = new SqlConnection(connStr);   // no using!
var cmd = new SqlCommand(sql, conn);     // no using!
```

**Pattern that's OK:**
```csharp
using (var client = new HttpClient()) { ... }
using (var conn = new SqlConnection(connStr)) { ... }
```

**Scan logic:**
1. Find all `new T()` where T is a known IDisposable type
2. Check if the line or surrounding context contains `using (`
3. If NOT in `using`, check if there's a `try/finally { .Dispose() }` nearby
4. Flag if neither pattern found

**Known IDisposable types in .NET:**
```
SqlConnection, SqlCommand, SqlDataReader, SqlDataAdapter,
HttpClient, WebClient, HttpWebRequest, HttpWebResponse,
SmtpClient, MailMessage,
StreamReader, StreamWriter, FileStream, MemoryStream, BinaryReader, BinaryWriter,
TcpClient, TcpListener, NetworkStream,
SoapHttpClientProtocol (and WSDL-generated proxies),
ClientContext (SharePoint CSOM),
Any class implementing IDisposable in the project
```

### 2. CSRF (CWE-352) — High Confidence

**What to grep:**
```bash
# Find controller actions (public methods in ApiController/Controller classes)
grep -n "\[HttpPost\]\|\[HttpGet\]\|\[HttpPut\]\|\[HttpDelete\]" Controllers/*.cs

# Check: is [ValidateAntiForgeryToken] present on state-modifying actions?
# Flag POST/PUT/DELETE without [ValidateAntiForgeryToken]
```

**Pattern to flag:**
```csharp
[HttpPost]
[Route("UpdateData")]
public IHttpActionResult UpdateData(Model m) { ... }  // no anti-forgery!
```

**Scan logic:**
1. Find all `[HttpPost]`, `[HttpPut]`, `[HttpDelete]` attributes
2. Check if `[ValidateAntiForgeryToken]` (or `[System.Web.Mvc.ValidateAntiForgeryToken]`) exists on the same method
3. Flag if missing
4. Also flag `[HttpGet]` methods that call state-modifying operations (harder to detect)

### 3. SQLI / SQL_NOT_CONSTANT (CWE-89) — High Confidence

**What to grep:**
```bash
# String concatenation in SQL
grep -n 'CommandText\s*=.*+\|CommandText\s*=.*Format\|CommandText\s*=.*\$"' *.cs
grep -n '"SELECT.*"\s*+\|"INSERT.*"\s*+\|"UPDATE.*"\s*+\|"DELETE.*"\s*+' *.cs
grep -n 'string\.Format.*SELECT\|string\.Format.*INSERT\|string\.Format.*UPDATE' *.cs
```

**Pattern to flag:**
```csharp
cmd.CommandText = "SELECT * FROM T WHERE Id = " + id;           // concatenation!
cmd.CommandText = string.Format("DELETE FROM T WHERE Id = '{0}'", id);  // format!
cmd.CommandText = $"SELECT * FROM T WHERE Name = '{name}'";     // interpolation!
```

**Pattern that's OK:**
```csharp
cmd.CommandText = "SELECT * FROM T WHERE Id = @id";
cmd.Parameters.AddWithValue("@id", id);
```

### 4. BAD_CERT_VERIFICATION (CWE-295) — Very High Confidence

**What to grep:**
```bash
grep -n "ServerCertificateValidationCallback.*return true\|ServerCertificateValidationCallback.*=>.*true\|RemoteCertificateValidationCallback.*return true" *.cs
```

**Pattern to flag:**
```csharp
ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
ServicePointManager.ServerCertificateValidationCallback = (s, c, ch, e) => true;
```

### 5. HARDCODED_CREDENTIALS (CWE-798) — High Confidence

**What to grep:**
```bash
# Literal strings in credential constructors
grep -n 'new NetworkCredential\s*(' *.cs | grep -v 'AppSettings\|GetAppSettingsByKey\|Configuration\|config\|Config'
grep -n 'Password\s*=\s*"[^"]\+"' *.cs
grep -n 'password\s*=\s*"[^"]\+"' *.cs
grep -n 'ApiKey\s*=\s*"[^"]\+"' *.cs
grep -n 'Secret\s*=\s*"[^"]\+"' *.cs
```

**Pattern to flag:**
```csharp
new NetworkCredential("user@mail.com", "P@ssw0rd!");  // hardcoded!
var password = "mySecretPass123";                       // hardcoded!
```

### 6. INSECURE_RANDOM (CWE-338) — Very High Confidence

**What to grep:**
```bash
grep -n "new Random\b\|Random()\|\.Next(\|\.NextDouble(\|\.NextBytes(" *.cs
```

**Pattern to flag (only in security/crypto context):**
```csharp
static Random random = new Random();
var token = random.Next().ToString();  // insecure for tokens/keys!
```

**Pattern that's OK:**
```csharp
// Random for non-security (UI, shuffling, etc.) is acceptable
var random = new Random();
var color = colors[random.Next(colors.Length)];
```

### 7. NULL_RETURNS / FORWARD_NULL (CWE-476) — Medium Confidence

**What to grep:**
```bash
# Methods that commonly return null
grep -n "\.FirstOrDefault(\|\.SingleOrDefault(\|\.Find(\|\.GetValue(" *.cs

# Check: is the result used without null check?
# This requires reading context — can't be done with simple grep
```

**Scan logic (requires code reading):**
1. Find `var x = collection.FirstOrDefault(...)` or `repo.Get(id)`
2. Check if the next usage of `x` is inside `if (x != null)`
3. Flag if `x` is dereferenced (`.Property`, `.Method()`) without null check

### 8. REVERSE_INULL (CWE-476) — Medium Confidence

**What to grep:**
```bash
# Variable used then null-checked later
# Hard to grep — requires reading code flow
```

**Scan logic (requires code reading):**
1. Find `if (x != null)` or `if (x == null)` checks
2. Look ABOVE the check — is `x` already dereferenced?
3. Flag if dereferenced before the null check

### 9. UNENCRYPTED_SENSITIVE_DATA (CWE-312) — Medium Confidence

**What to grep:**
```bash
# Plaintext credentials in connection strings or config reads
grep -n 'Password=\|password=\|pwd=' *.cs *.config
grep -n 'NetworkCredential.*GetAppSettingsByKey\|NetworkCredential.*AppSettings' *.cs
```

**Note:** This checker is about storing/transmitting credentials in plaintext. If passwords come from config but config stores them unencrypted, it's still flagged.

### 10. PATH_MANIPULATION (CWE-22) — Medium Confidence

**What to grep:**
```bash
grep -n 'Path\.Combine.*Request\|Path\.Combine.*param\|File\.Open.*Request\|File\.Read.*Request' *.cs
grep -n 'new FileStream.*\+\|File\.Open.*\+' *.cs
```

### 11. SSRF (CWE-918) — Medium Confidence

**What to grep:**
```bash
# User input flowing to HTTP client
grep -n 'GetAsync\s*(\|PostAsync\s*(\|DownloadData\s*(\|DownloadString\s*(' *.cs
# Check if parameter comes from method argument or request
```

### 12. URL_MANIPULATION (CWE-601) — Medium Confidence

**What to grep:**
```bash
# String concatenation in URLs
grep -n 'DownloadData.*+\|GetAsync.*+\|new Uri.*+\|"http.*"\s*+' *.cs
```

### 13. MISSING_AUTHZ (CWE-862) — Low Confidence

**Scan logic (requires code reading):**
1. Find all code paths that call database-modifying operations (ExecuteNonQuery, SaveChanges)
2. Compare parallel code paths (similar switch cases, if branches)
3. If some paths have authorization checks and others don't, flag the missing ones

### 14. COPY_PASTE_ERROR (CWE-398) — Low Confidence

**Scan logic (requires code reading):**
1. Find repetitive code blocks (foreach with if conditions, switch cases)
2. Compare variable names across similar blocks
3. Flag if one block uses a different variable than all others

### 15. UNREACHABLE (CWE-561) — High Confidence

**What to grep:**
```bash
# Code after unconditional return/break/throw
grep -n -A1 "^\s*return;\s*$\|^\s*break;\s*$\|^\s*throw " *.cs | grep -v "^--$"
# Also check #if DEBUG blocks
grep -n -A2 "#if DEBUG" *.cs
```

### 16. SIGMA.sensitive_data_in_response (CWE-200) — Very High Confidence

**What to grep:**
```bash
# Check if version headers are stripped
grep -n "DisableMvcResponseHeader" Global.asax.cs
grep -n "enableVersionHeader" Web.config
grep -n "X-Powered-By\|X-AspNet-Version\|Server" Web.config
```

**Flag if:**
- `MvcHandler.DisableMvcResponseHeader = true` is NOT in Global.asax
- `enableVersionHeader="false"` is NOT in Web.config
- `X-Powered-By` header is NOT removed in Web.config

### 17. SIGMA.missing_tls (CWE-319) — High Confidence

**What to grep:**
```bash
grep -rn '"http://' *.cs *.config | grep -v "localhost\|127.0.0.1\|://schemas\.\|://www.w3.org\|://xml\."
```

---

## Step 3: Generate Report

Output format:
```
## Pre-Scan Report: {project-name}
Date: {date}
Files scanned: {count}
Scope: {all / changed-only / specific-path}

### Summary
| Severity | Count |
|----------|-------|
| Critical | N     |
| High     | N     |
| Medium   | N     |
| Low      | N     |

### Findings

#### [CRITICAL] SQLI — {file}:{line}
Pattern: SQL-PARAM
Code: `cmd.CommandText = "SELECT * FROM T WHERE Id = " + id;`
Fix: Use parameterized query with SqlParameter
Reference: coverity-backend skill → SQL-PARAM pattern

#### [HIGH] RESOURCE_LEAK — {file}:{line}
Pattern: RL-USING
Code: `var client = new HttpClient();`
Fix: Wrap in `using` block
Reference: coverity-backend skill → RL-USING pattern

...
```

## Step 4: Provide Fix Guidance

For each finding, reference the exact fix pattern from the `coverity-backend` skill. If the user wants to fix, apply the pattern. If review-only, just report.

---

## Detection Confidence Matrix

| Checker | Grep-able? | Confidence | False Positive Risk |
|---------|-----------|------------|-------------------|
| RESOURCE_LEAK | Yes (known types) | **High** | Medium — some IDisposable don't need using |
| CSRF | Yes (attribute check) | **High** | Low — clear attribute presence/absence |
| SQLI/SQL_NOT_CONSTANT | Yes (concatenation) | **Very High** | Low — concatenation in SQL is almost always wrong |
| BAD_CERT_VERIFICATION | Yes (callback pattern) | **Very High** | None — `return true` is always wrong |
| HARDCODED_CREDENTIALS | Yes (literal strings) | **High** | Medium — test data may be flagged |
| INSECURE_RANDOM | Yes (System.Random) | **High** | Medium — non-security usage is OK |
| NULL_RETURNS | Partial (needs context) | **Medium** | High — needs flow analysis |
| FORWARD_NULL | Partial (needs context) | **Medium** | High — needs flow analysis |
| REVERSE_INULL | Partial (needs context) | **Medium** | Medium |
| UNENCRYPTED_SENSITIVE_DATA | Partial | **Medium** | Medium |
| PATH_MANIPULATION | Partial | **Medium** | Medium |
| SSRF | Partial | **Medium** | Medium |
| URL_MANIPULATION | Partial | **Medium** | Medium |
| UNREACHABLE | Yes (#if DEBUG) | **High** | Low |
| SIGMA.sensitive_data_in_response | Yes (config check) | **Very High** | None |
| SIGMA.missing_tls | Yes (http:// grep) | **High** | Medium — internal URLs may be OK |
| MISSING_AUTHZ | No (needs deep analysis) | **Low** | High |
| COPY_PASTE_ERROR | No (needs pattern match) | **Low** | High |

**Expected catch rate:** ~60-70% of issues that Coverity would find. The remaining 30-40% require Coverity's interprocedural analysis.

---

## Integration with coverity-backend Skill

This skill (prescan) finds issues → `coverity-backend` skill fixes them.

Workflow:
1. `/coverity-prescan` → identifies potential issues
2. Developer/AI reviews findings
3. `/coverity-backend fix <issues>` → applies proven fix patterns
4. Submit to Coverity scan → zero/minimal new issues
