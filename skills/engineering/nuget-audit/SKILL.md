---
name: nuget-audit
description: "NuGet Package Audit & Fix — Scan, audit, and fix NuGet package version conflicts across all .NET project types: .NET Framework (packages.config), .NET Core / .NET 5-10+ (SDK-style csproj with PackageReference), and Central Package Management (Directory.Packages.props). Detects TypeLoadException/MissingMethodException causes, cross-project version conflicts, wrong/missing/stale binding redirects, TFM compatibility issues, and API-breaking version jumps. Applies config-only fixes (no code changes). Trigger on /nuget-audit, or proactively when user reports assembly loading errors or asks to audit/check/fix NuGet package versions."
---

# NuGet Package Audit & Fix

Scan, audit, and fix NuGet package version conflicts across **all .NET project types**.

TRIGGER: When the user reports a TypeLoadException, MissingMethodException, FileNotFoundException, FileLoadException, or PlatformNotSupportedException for a .NET assembly, or asks to audit/check/fix NuGet package versions, or says "nuget audit", "/nuget-audit".

ARGUMENTS: The user may provide an error message, stack trace, solution path, or scope ("scan" / "fix" / "full"). Default scope: "full".

---

## Phase 0: Detect Project Type

Before anything else, determine the project type. This controls the entire workflow.

```
Glob: **/*.csproj, **/packages.config, **/Directory.Packages.props, **/Directory.Build.props, **/global.json
```

| Indicator | Project Type | Package System |
|-----------|-------------|----------------|
| `packages.config` exists | **.NET Framework (legacy)** | packages.config + binding redirects |
| `<PackageReference>` in .csproj, NO packages.config | **SDK-style (.NET Core / .NET 5-10+)** | PackageReference in csproj |
| `Directory.Packages.props` exists | **Central Package Management (CPM)** | PackageVersion in props, PackageReference in csproj |
| `<TargetFramework>net4*</TargetFramework>` in SDK-style csproj | **SDK-style targeting .NET Framework** | PackageReference but may need binding redirects |

Read the `<TargetFramework>` or `<TargetFrameworks>` from each csproj to know the runtime:
- `net48`, `net472`, `net461` → .NET Framework
- `netcoreapp3.1` → .NET Core 3.1
- `net6.0`, `net7.0`, `net8.0`, `net9.0`, `net10.0` → Modern .NET
- `netstandard2.0`, `netstandard2.1` → Library (check consuming projects for runtime)
- Multi-targeting (e.g., `net8.0;net48`) → check BOTH runtimes

---

## Phase 1: Discovery

### All project types
1. Find all `.csproj` / `.fsproj` / `.vbproj` files
2. Find all `global.json` (SDK version pinning)
3. Find all `Directory.Build.props` / `Directory.Packages.props`
4. Identify project references → build dependency tree
5. Identify the **host project** (Web API / console app / worker service)

### .NET Framework only
6. Find all `packages.config` files
7. Find all `Web.config`, `app.config`, `App.config` (binding redirects)

### SDK-style only
6. Check for `*.deps.json` in build output (runtime dependency manifest)
7. Check for `runtimeconfig.json` (runtime configuration)

---

## Phase 2: Build Version Matrix

### .NET Framework (packages.config)
Parse each `packages.config` — extract `<package id="..." version="..." />`.

### SDK-style (PackageReference)
Parse each `.csproj` — extract `<PackageReference Include="..." Version="..." />`.
Also run if `dotnet` CLI is available:
```bash
dotnet list <project> package
dotnet list <project> package --include-transitive
```

### Central Package Management
Parse `Directory.Packages.props` — extract `<PackageVersion Include="..." Version="..." />`.
Each csproj has `<PackageReference Include="..." />` without Version (version comes from props).

### Cross-project matrix (all types)

| Package | Project A | Project B | Project C | Conflict? |
|---------|-----------|-----------|-----------|-----------|

Flag:
- **Different versions** across projects that deploy together
- **Version is known to be breaking** (see Common Patterns)
- **Downgraded transitive dependency** (SDK-style: lower version than what a dependency expects)

---

## Phase 3: Compatibility Audit

### .NET Framework — Binding Redirect Audit
For the **host project's runtime config** (Web.config or App.config):
1. **Wrong redirects**: `newVersion` doesn't match installed assembly version
2. **Missing redirects**: package installed but no redirect (check library app.configs for hints)
3. **Stale redirects**: redirect points to old version

### SDK-style — TFM & Runtime Audit
Binding redirects are NOT used in .NET Core/.NET 5+. Instead check:
1. **TFM compatibility**: Does the package support the project's target framework?
   - Package targets `net8.0` but project targets `net6.0` → incompatible
   - Package only targets `net48` but project targets `net8.0` → incompatible (unless netstandard2.0 bridge)
2. **Platform-specific packages**: Check `runtimes/` folder support (win-x64, linux-x64, osx-arm64)
3. **Version conflicts in transitive graph**:
   ```bash
   dotnet list package --include-transitive
   ```
   Look for NU1605 (downgrade detected), NU1608 (version above what dependency expects)
4. **Deprecated/vulnerable packages**:
   ```bash
   dotnet list package --deprecated
   dotnet list package --vulnerable
   dotnet list package --outdated
   ```
5. **Runtime trimming issues** (for AOT/trimmed apps): packages that don't support trimming

### Multi-targeting projects
If a project targets multiple TFMs (e.g., `net8.0;net48`), verify the package is compatible with ALL targets.

---

## Phase 4: Dependency Verification

For each suspicious package, **fetch NuGet page** (via WebFetch) to get:
- Supported target frameworks
- Dependencies and version constraints
- Deprecation notices

### Known API-breaking version jumps

| Package | Breaking at | What changed |
|---------|-----------|--------------|
| **AngleSharp** | 0.10+ | `AngleSharp.Parser.Html` namespace removed |
| **Microsoft.Graph** | 5.x+ | Kiota rewrite, entirely new API |
| **OfficeDevPnP.Core** → **PnP.Framework** | — | `PnP.Framework.Pages` does NOT exist |
| **System.DirectoryServices** | 8.0.0 | Dropped netstandard2.0 (restored later) |
| **Newtonsoft.Json** → **System.Text.Json** | — | Different API, different behavior (case-sensitivity, etc.) |
| **Microsoft.AspNetCore.Mvc** | 3.x → 6.x+ | Minimal APIs, different hosting model |
| **EF Core** | 5.x → 7.x+ | Dropped `netstandard2.1`, requires `net6.0+` |
| **AutoMapper** | 12.x+ | Static API removed, DI-only |
| **MediatR** | 12.x+ | Changed to `IRequest<T>` pattern, removed `IRequestHandler` overloads |
| **Swashbuckle** → **Microsoft.AspNetCore.OpenApi** | .NET 9+ | Swashbuckle no longer ships with templates |
| **IdentityServer4** → **Duende IdentityServer** | — | License change + namespace change |

---

## Phase 5: Report

```markdown
## NuGet Package Audit Report

**Project type**: [.NET Framework / SDK-style / CPM]
**Target framework(s)**: [net48 / net8.0 / etc.]
**Host project**: [project name]

### CRITICAL (causes runtime errors now)
- [Package]: [Issue] — [Fix]

### WARNING (may cause errors if code path is triggered)
- [Package]: [Issue] — [Fix]

### INFO (stale/inconsistent but not breaking)
- [Package]: [Issue] — [Fix]

### Cross-Project Version Matrix
[Table]

### Binding Redirect Status (.NET Framework only)
[Table with: Assembly | Config File | Current Version | Should Be | Status]

### TFM Compatibility (.NET Core/5+ only)
[Table with: Package | Required TFM | Project TFM | Status]
```

---

## Phase 6: Fix (if scope includes fix)

### Priority order (all project types)
1. **P0**: Fix the immediate crash
2. **P1**: Fix missing config / compatibility issues
3. **P2**: Fix stale / inconsistent versions
4. **P3**: Fix deprecated / vulnerable packages

### .NET Framework fixes
Edit:
- `packages.config` — change version attribute
- `.csproj` — update `<Reference Include="...">` assembly version and `<HintPath>` path
- Config files — update `<bindingRedirect>` entries

Recommended approach: VS Package Manager Console
```powershell
Update-Package <PackageName> -Version <Version> -ProjectName <Project>
# If blocked by dependency constraints:
Update-Package <PackageName> -Version <Version> -ProjectName <Project> -IgnoreDependencies
```

### SDK-style fixes
Edit:
- `.csproj` — update `<PackageReference Include="..." Version="..." />`
- Or use CLI:
```bash
dotnet add <project> package <PackageName> --version <Version>
dotnet remove <project> package <PackageName>
```

### Central Package Management fixes
Edit:
- `Directory.Packages.props` — update `<PackageVersion Include="..." Version="..." />`
- Individual csproj files do NOT contain versions (only `<PackageReference Include="..." />`)

### Important rules (all project types)
- Do NOT change any `.cs` / `.fs` / `.vb` files — this skill is version/config only
- Create changes on a new branch if the user requests it
- When downgrading a package, verify nothing else depends on the higher version at runtime (grep all source files for the namespace)
- If migration requires code changes and the user says "no code changes", propose version downgrade instead

### .NET Framework-specific rules
- Always keep the binding redirect `oldVersion` range wide enough to cover both old and new version requests
- .NET Framework loads assemblies lazily (type-level) — unused types don't trigger assembly loading

### SDK-style-specific rules
- After fixing, run `dotnet restore` to verify the dependency graph resolves cleanly
- Check for `NU1605` warnings (version downgrade detected) — these are errors by default in .NET 8+
- For multi-targeting projects, verify the fix works for ALL target frameworks
- If using `global.json` to pin SDK version, ensure the SDK supports the target framework

**CRITICAL — Verify before proposing namespace migration:**
- NEVER assume a successor package has the same namespace. Always verify:
  1. **Check the NuGet package page** for actual DLL contents and target frameworks
  2. **Check GitHub source** for the exact namespace (browse the source tree)
  3. **Check GitHub issues** for migration reports ("missing method", "missing namespace")
  4. **WebFetch the actual URL** to confirm the namespace/class exists (404 = doesn't exist)
- Known traps where namespace migration FAILS:
  - `OfficeDevPnP.Core.Pages` → `PnP.Framework.Pages` — **DOES NOT EXIST**
  - `Microsoft.Graph` 1.x-4.x → 5.x+ — Kiota rewrite, entirely new class hierarchy
  - `System.Web.Http` → `Microsoft.AspNetCore.Mvc` — fundamentally different framework
  - `Swashbuckle.AspNetCore` → `Microsoft.AspNetCore.OpenApi` — different registration API

---

## Phase 7: Verify

### All project types
1. `git diff --stat` to show all changed files
2. Verify no source code files (`.cs`/`.fs`/`.vb`) were modified
3. List remaining risks or latent issues

### .NET Framework
4. Build in VS — verify no compile errors

### SDK-style
4. `dotnet restore` — verify clean restore
5. `dotnet build` — verify no build errors
6. `dotnet list package --include-transitive` — verify no unexpected downgrades
7. Check for `NU1605` / `NU1608` warnings

---

## Common Patterns

### Pattern: Old library compiled against removed API
**Applies to**: .NET Framework (binding redirects)
**Symptom**: `TypeLoadException: Could not load type 'X' from assembly 'Y'`
**Cause**: Library A compiled against Package B v1 API. Package B v2 removed the type. Binding redirect sends v1 requests to v2.
**Fix**: Downgrade Package B to v1-compatible version. Verify other consumers don't use v2 API at runtime.
**Example**: OfficeDevPnP.Core + AngleSharp 0.17.0 → downgrade to 0.9.9.

### Pattern: Diamond dependency conflict
**Applies to**: SDK-style (.NET Core / .NET 5+)
**Symptom**: `NU1605` warning/error — detected package downgrade. Or runtime `FileLoadException`.
**Cause**: Package A requires Lib >= 3.0, Package B requires Lib >= 2.0, but Lib 2.5 is resolved.
**Fix**: Explicitly add `<PackageReference>` for Lib at the highest required version. Or use `<PackageReference ... VersionOverride="3.0.0" />` with CPM.

### Pattern: TFM incompatibility after upgrade
**Applies to**: SDK-style
**Symptom**: `dotnet restore` fails with `NU1202` — package not compatible with target framework.
**Cause**: Package dropped support for your TFM in a newer version (e.g., EF Core 7+ requires net6.0+, dropped netstandard2.1).
**Fix**: Stay on the last version that supports your TFM. Check NuGet page "Frameworks" tab.

### Pattern: Transitive dependency hell
**Applies to**: SDK-style
**Symptom**: Runtime crash on a type you never directly referenced.
**Cause**: Two packages pull different versions of a shared transitive dependency. NuGet picks the lowest compatible, but one package needs a newer version's API.
**Fix**: Pin the transitive dependency explicitly in your csproj:
```xml
<PackageReference Include="TransitiveDep" Version="3.0.0" />
```

### Pattern: Major version jump with Kiota/rewrite
**Applies to**: All
**Symptom**: `MissingMethodException` or `TypeLoadException`
**Cause**: Microsoft.Graph 5+ was rewritten with Kiota. Old libraries compiled against 1.x-4.x.
**Fix**: If only AuthenticationManager is used, Graph SDK code paths aren't triggered. Document as latent risk.

### Pattern: Missing binding redirect
**Applies to**: .NET Framework only
**Symptom**: `FileNotFoundException` or `FileLoadException` for a specific assembly version
**Cause**: Library compiled against v1, but v2 is installed. No redirect to tell CLR to use v2.
**Fix**: Add `<bindingRedirect oldVersion="0.0.0.0-{v2}" newVersion="{v2}" />` to host config.

### Pattern: Stale binding redirect
**Applies to**: .NET Framework only
**Symptom**: Redirect points to old version, but packages.config has newer version installed
**Cause**: Package was upgraded but redirect wasn't updated
**Fix**: Update redirect `newVersion` to match installed assembly version.

### Pattern: Phantom namespace migration
**Applies to**: All
**Symptom**: Proposing `using OldLib.Namespace;` → `using NewLib.Namespace;` but the new namespace doesn't exist.
**Cause**: Successor package restructured or removed the API entirely.
**Prevention**: Before proposing ANY namespace change:
1. WebFetch the GitHub source tree URL → expect 200, not 404
2. Search GitHub issues for "missing" + class name
3. Check the NuGet package page for exported namespaces
4. If doesn't exist → fall back to version downgrade
**Example**: `PnP.Framework.Pages.ClientSidePage` doesn't exist — use version downgrade instead.

### Pattern: netstandard2.0 support dropped
**Applies to**: .NET Framework consuming modern packages
**Symptom**: Build error or runtime crash
**Cause**: Package dropped netstandard2.0 TFM in a newer version
**Fix**: Downgrade to last version with netstandard2.0 support.

### Pattern: SDK version mismatch
**Applies to**: SDK-style with global.json
**Symptom**: `dotnet restore` or `dotnet build` fails with SDK not found
**Cause**: `global.json` pins an SDK version that doesn't support the target framework (e.g., SDK 6.0 can't build net8.0)
**Fix**: Update `global.json` SDK version or remove the pin.

### Pattern: Central Package Management version override needed
**Applies to**: CPM projects
**Symptom**: One project needs a different version than what Directory.Packages.props specifies
**Cause**: Project-specific requirement (e.g., test project needs newer version of a mocking library)
**Fix**: Use `<PackageReference Include="..." VersionOverride="X.Y.Z" />` in that project's csproj.
