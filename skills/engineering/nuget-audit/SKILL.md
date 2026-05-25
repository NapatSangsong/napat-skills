---
name: nuget-audit
description: "NuGet Package Audit & Fix — Scan, audit, and fix NuGet package version conflicts in .NET Framework solutions (packages.config-based). Detects TypeLoadException/MissingMethodException causes, cross-project version conflicts, wrong/missing/stale binding redirects, and API-breaking version jumps. Applies config-only fixes (no code changes). Trigger on /nuget-audit, or proactively when user reports TypeLoadException, MissingMethodException, FileNotFoundException for a .NET assembly, or asks to audit/check/fix NuGet package versions."
---

# NuGet Package Audit & Fix

Scan, audit, and fix NuGet package version conflicts in .NET Framework solutions (packages.config-based).

TRIGGER: When the user reports a TypeLoadException, MissingMethodException, FileNotFoundException for a .NET assembly, or asks to audit/check/fix NuGet package versions, or says "nuget audit", "/nuget-audit".

ARGUMENTS: The user may provide an error message, stack trace, solution path, or scope ("scan" / "fix" / "full"). Default scope: "full".

## Workflow

### Phase 1: Discovery

1. Find all `packages.config` files:
   ```
   Glob: **/packages.config
   ```

2. Find all `.csproj` files:
   ```
   Glob: **/*.csproj
   ```

3. Find all config files with binding redirects:
   ```
   Glob: **/Web.config, **/app.config, **/App.config
   ```

4. Identify the **host project** (Web API / console app) — its config is the runtime config that matters.

5. Identify **project references** to understand the dependency tree:
   ```
   Grep: ProjectReference in *.csproj
   ```

### Phase 2: Build Version Matrix

For each `packages.config`, extract all package IDs and versions. Build a cross-project matrix:

| Package | Project A | Project B | Project C | Conflict? |
|---------|-----------|-----------|-----------|-----------|

Flag packages where:
- **Different versions** exist across projects that deploy together
- **Version is known to be breaking** (e.g., AngleSharp 0.9.x vs 0.17.x)

### Phase 3: Binding Redirect Audit

For the **host project's runtime config** (Web.config or App.config):

1. **Wrong redirects**: binding redirect `newVersion` doesn't match the installed package's assembly version
2. **Missing redirects**: package is installed but has no binding redirect (check library app.configs for hints — if a redirect exists there but not in the host config, it's likely missing)
3. **Stale redirects**: binding redirect points to an old version that no longer matches packages.config

For **library app.configs**: check for stale redirects that could cause issues if the library is used standalone.

### Phase 4: Dependency Verification

For each package that appears suspicious or is involved in the error:

1. **Fetch NuGet page** (via WebFetch) to get:
   - Supported target frameworks (netstandard2.0, net462, net48)
   - Dependencies and their version constraints

2. **Cross-reference** installed versions against dependency requirements:
   - Does Package A require Package B >= X, but Package B is installed at version Y < X?
   - Are any packages incompatible with the target framework?

3. **Check for API-breaking version jumps** where a library was compiled against an old API but the new version removed/changed types. Known breaking changes:
   - **AngleSharp** 0.9.x → 0.10+: `AngleSharp.Parser.Html` namespace removed entirely
   - **Microsoft.Graph** 4.x → 5.x: SDK rewritten with Kiota, completely new API
   - **OfficeDevPnP.Core** → **PnP.Framework**: `PnP.Framework.Pages` does NOT exist — Pages API moved to PnP.Core SDK (`IPage` interface)
   - **System.DirectoryServices** 8.0.0: dropped netstandard2.0 (restored in later versions)

### Phase 5: Report

Output a structured report:

```markdown
## NuGet Package Audit Report

### CRITICAL (causes runtime errors now)
- [Package]: [Issue] — [Fix]

### WARNING (may cause errors if code path is triggered)
- [Package]: [Issue] — [Fix]

### INFO (stale/inconsistent but not breaking)
- [Package]: [Issue] — [Fix]

### Cross-Project Version Matrix
[Table]

### Binding Redirect Status
[Table with: Assembly | Config File | Current Version | Should Be | Status]
```

### Phase 6: Fix (if scope includes fix)

Apply fixes in priority order:

1. **P0**: Fix the immediate crash (version downgrade/upgrade, binding redirect)
2. **P1**: Add missing binding redirects to host config
3. **P2**: Fix stale binding redirects in library configs
4. **P3**: Fix stale binding redirects in console app configs

For each fix, edit:
- `packages.config` — change version attribute
- `.csproj` — update `<Reference Include="...">` assembly version and `<HintPath>` path
- Config files — update `<bindingRedirect>` entries

**Important rules:**
- Do NOT change any `.cs` files — this skill is version/config only
- Create changes on a new branch if the user requests it
- For packages.config projects, output VS Package Manager Console commands as the recommended approach, plus manual edit details as fallback
- When downgrading a package that a dependency requires at higher version, verify the dependency doesn't actually USE the package at runtime before proceeding (grep all .cs files for the namespace)
- Always keep the binding redirect `oldVersion` range wide enough to cover both the old and new version requests
- .NET Framework loads assemblies lazily (type-level) — if a code path doesn't reference a type, the assembly won't be loaded

**CRITICAL — Verify before proposing namespace migration:**
- NEVER assume a successor package has the same namespace. Always verify:
  1. **Check the NuGet package page** for the actual DLL contents and target frameworks
  2. **Check GitHub source** for the exact namespace (e.g., browse `src/lib/{Package}/Pages/` directory)
  3. **Check GitHub issues** for migration reports (e.g., "missing method", "missing namespace")
  4. **WebFetch the actual URL** to confirm the namespace directory/class exists (404 = doesn't exist)
- Known traps where namespace migration FAILS:
  - `OfficeDevPnP.Core.Pages` → `PnP.Framework.Pages` — **DOES NOT EXIST**. Pages API moved to PnP.Core SDK as `IPage` interface (completely different API)
  - `Microsoft.Graph` 1.x-4.x → 5.x+ — Kiota rewrite, entirely new class hierarchy
  - `System.Web.Http` → `Microsoft.AspNetCore.Mvc` — fundamentally different framework
- If migration requires code changes and the user says "no code changes", propose version downgrade instead

### Phase 7: Verify

After applying fixes:
1. `git diff --stat` to show all changed files
2. Verify no `.cs` files were modified
3. List remaining risks or latent issues

---

## Common Patterns

### Pattern: Old library compiled against removed API
**Symptom**: `TypeLoadException: Could not load type 'X' from assembly 'Y'`
**Cause**: Library A compiled against Package B v1 API. Package B v2 removed/renamed the type. Binding redirect sends v1 requests to v2.
**Fix**: Downgrade Package B to v1-compatible version. Verify other consumers of Package B don't use v2 API at runtime.
**Example**: OfficeDevPnP.Core + AngleSharp 0.17.0 → downgrade to 0.9.9.

### Pattern: Major version jump with Kiota/rewrite
**Symptom**: `MissingMethodException` or `TypeLoadException` on Graph/Identity calls
**Cause**: Microsoft.Graph 5+ was rewritten with Kiota. Old libraries compiled against 1.x-4.x.
**Fix**: If only AuthenticationManager is used, the Graph SDK code paths aren't triggered. Document as latent risk.

### Pattern: Missing binding redirect
**Symptom**: `FileNotFoundException` or `FileLoadException` for a specific assembly version
**Cause**: Library compiled against v1, but v2 is installed. No redirect to tell CLR to use v2.
**Fix**: Add `<bindingRedirect oldVersion="0.0.0.0-{v2}" newVersion="{v2}" />` to host config.

### Pattern: Stale binding redirect
**Symptom**: Redirect points to old version, but packages.config has newer version installed
**Cause**: Package was upgraded but redirect wasn't updated (common in packages.config projects)
**Fix**: Update redirect `newVersion` to match installed assembly version.

### Pattern: Phantom namespace migration
**Symptom**: Proposing `using OldLib.Namespace;` → `using NewLib.Namespace;` but the new namespace doesn't exist.
**Cause**: Successor package restructured or removed the API entirely. Common when libraries are rewritten (OfficeDevPnP.Core → PnP.Framework, Microsoft.Graph 4.x → 5.x).
**Prevention**: Before proposing ANY namespace change, run this verification chain:
1. WebFetch the GitHub source tree URL for the expected namespace directory → expect 200, not 404
2. Search GitHub issues for "missing" + the class name → find migration reports
3. Check the NuGet package dependencies page → confirm the package actually exports the namespace
4. If the namespace doesn't exist, fall back to version downgrade (keep old library + compatible dependency version)
**Example**: `PnP.Framework.Pages.ClientSidePage` doesn't exist. `ClientSidePage.Load()` only exists in `OfficeDevPnP.Core.Pages`. PnP.Framework uses `IPage` from PnP.Core SDK — completely different API.

### Pattern: netstandard2.0 support dropped
**Symptom**: Build or runtime error when using a NuGet package on .NET Framework 4.8
**Cause**: Package dropped netstandard2.0 TFM in a newer version
**Fix**: Downgrade to the last version that supports netstandard2.0. Check NuGet page for supported frameworks.
