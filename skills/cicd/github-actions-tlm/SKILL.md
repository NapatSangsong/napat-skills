---
name: github-actions-tlm
description: "GitHub Actions CI/CD for TLM Projects — Create, test, review, and manage CI/CD pipelines via GitHub Actions for Thalamo web projects (.NET Core / .NET Framework). 8 sub-commands covering setup, testing, review, reporting, sync, and environment management. Tested on TOPCOOL (.NET 10) and PTTGC.KBS (.NET Framework 4.8). Trigger on /cicd-setup, /cicd-test, /cicd-review, /cicd-report, /cicd-summary, /cicd-sync, /cicd-test-one, /cicd-env."
---

# GitHub Actions CI/CD for TLM Projects

Create, test, review, and manage CI/CD pipelines via GitHub Actions for Thalamo web projects. Supports both .NET Core (.NET 5-10+) and .NET Framework (4.x).

Tested and proven on:
- **TOPCOOL** — .NET 10 / ASP.NET Core
- **PTTGC.KBS** — .NET Framework 4.8 / ASP.NET

## Commands (8 sub-commands)

| Command | Description |
|---------|-------------|
| `/cicd-setup` | Bootstrap complete CI/CD pipeline from scratch |
| `/cicd-test` | Trigger all workflows, download artifacts, verify |
| `/cicd-test-one` | Test a specific workflow |
| `/cicd-review` | Security + path + artifact integrity review of all workflows |
| `/cicd-report` | Generate HTML + Markdown verification report from artifacts |
| `/cicd-summary` | Management-friendly summary (Thai) |
| `/cicd-sync` | Sync workflow changes across branches |
| `/cicd-env` | Manage GitHub Environments, Variables, and Secrets |

Each command file is in the `commands/` subdirectory. Install by copying to `~/.claude/commands/`.

## Installation

```bash
# Copy all commands to Claude Code
cp commands/*.md ~/.claude/commands/

# Or symlink for easy updates
for f in commands/*.md; do
  ln -sf "$(pwd)/$f" ~/.claude/commands/$(basename "$f")
done
```

## Workflows Created by `/cicd-setup`

### Standard Workflows (8)

| # | Workflow | Secret Replace | Build | Artifact |
|---|---------|:-:|:-:|----------|
| 1 | Backend - SourceCode Scan | | Test | BE-SourceCode-Scan |
| 2 | Frontend - SourceCode Scan | | | FE-SourceCode-Scan |
| 3 | Backend - SourceCode WithSecret | Yes | Test | BE-SourceCode |
| 4 | Frontend - SourceCode WithSecret | Yes | | FE-SourceCode |
| 5 | Backend - Deploy | Yes | Release | Source + Package |
| 6 | Frontend - Deploy | Yes | | Source + Package |
| 7 | Export Variable | Yes | | variable.md |
| 8 | Configuration | Yes | | Configuration |

### Helper Workflows (3)

| Workflow | Purpose | Called by |
|----------|--------|---------|
| Backend - Generate Config | Copy template + sed replace for backend | WithSecret, Deploy, Configuration |
| Frontend - Generate Config | Copy template + sed replace for frontend | WithSecret, Deploy, Configuration |
| Frontend - Webparts Build | Build SPFx webparts (.sppkg) with env-specific config | Deploy, Configuration |

## Project Type Detection

`/cicd-setup` auto-detects the project type from `<TargetFramework>` in .csproj:

| | .NET Core / .NET 5+ | .NET Framework |
|---|---|---|
| Example | TOPCOOL (.NET 10) | PTTGC.KBS (.NET 4.8) |
| Config | `appsettings.json` | `Web.config` (XML) |
| Template | `appsettings.json.template` | `Web.config.template` |
| Build | `dotnet build` / `dotnet publish` | MSBuild |
| Runner | `ubuntu-latest` | `windows-latest` |
| NuGet | `dotnet restore` (PackageReference) | `nuget.exe restore` (packages.config) |
| Shell | default (bash) | Must specify `shell: bash` for sed/cp/find |

## Config Template Pattern

```
[repo]                    [CI/CD]                      [artifact]
config.js.template  ->  cp + sed replace  ->  config.js (real values)
```

- **Variables** (`vars.*`) — non-sensitive: URLs, database names
- **Secrets** (`secrets.*`) — sensitive: passwords, connection strings

### Placeholder Convention
```
REPLACE_WITH_{PREFIX}_{CATEGORY}_{NAME}

REPLACE_WITH_COOL_AZ_CLIENTID        -> Azure AD Client ID
REPLACE_WITH_COOL_DB_PASSWORD         -> Database password (secrets.*)
REPLACE_WITH_KBS_API_BASE_URL         -> API endpoint URL (vars.*)
```

### sed Injection Prevention
```yaml
# WRONG — shell injection risk from special chars in connection strings
run: sed -i "s|REPLACE|${{ secrets.CONN }}|g" Web.config

# CORRECT — pass through env var first
env:
  CONN_STR: ${{ secrets.CONN }}
run: sed -i "s|REPLACE|${CONN_STR}|g" Web.config
```

## Lessons Learned

| Problem | Cause | Fix |
|---------|-------|-----|
| Workflow not in Actions tab | On feature branch, not default | Cherry-pick `.github/workflows/` to main |
| sed replace gets wrong value | Connection string has `&`, `;` | Use `env:` block, not inline `${{ secrets.* }}` |
| MSBuild publish no output | Mixed Windows/Linux paths | Use `cp` staging directory |
| PowerShell has no sed | Windows runner default shell | Specify `shell: bash` every step |
| Artifact missing folder | `upload-artifact` strips single path | Use staging directory |
| Source artifact build fails | Missing Telerik/ folder from HintPath | Check .csproj HintPath, include folder |
| Force-push blocked | GitHub Rulesets (not branch protection) | Settings -> Rules -> Rulesets -> disable temp |
| FE Source has REPLACE_WITH_* | Upload source BEFORE downloading config | Move "Download config" step before "Upload source" |
| npm ci fails EUSAGE | package-lock.json out of sync after adding overrides | Delete node_modules + lock file, run `npm install` to regenerate |
| npm transitive dep vulnerability | Parent package pins vulnerable version | Add `"qs": "6.15.2"` to `overrides` in package.json |
| Disk full downloading FE artifacts | FE with libraries (kendoui etc.) ~159MB each | Download one at a time, zip immediately, delete before next |
| `.aipath`-excluded `packages/` ships in source artifact (1.3GB / 25MB bloat) | `packages/` committed **or** restored, but only `Deploy` removed it — `Scan` & `WithSecret` did not | Add `rm -rf <proj>/packages` to **every** source-export workflow, not just Deploy |
| WithSecret artifact has **no config** | clean step deleted `Web.config`/`config.js` after build | WithSecret must **keep** the generated real config (that is its purpose); only strip `*.template` |
| WithSecret FE artifact **missing libraries** | clean step deleted kendoui/bootstrap/fontawesome | WithSecret **keeps** libs; only **Scan** strips them (size reduction) |
| Deploy Package leaks `.cs` source | `Pages/` copy pulled ASMX code-behind (`*.asmx.cs`) | `find publish -name "*.cs" -delete` after staging — code-behind is compiled into `bin/` |
| Export Variable exports non-existent secrets / misses real ones | hand-written var list drifted from the actual environment schema | Generate the list from `gh variable list` + `gh secret list`; the workflow must mirror the env exactly |
| **Green CI run but wrong artifact** | verified run *status*, not artifact *contents* | Always inspect artifact **contents** (`unzip -l/-p`) against each requirement — a passing run says nothing about correctness |

## Proven Patterns

| Pattern | When to use |
|---------|------------|
| `.aipath` -> scan rules | Read include/exclude from .aipath for artifact paths |
| `git checkout branch -- path` | Cherry-pick specific files without full merge |
| Matrix + `environment:` | Configuration workflow — parallel env jobs |
| Staging directory | Control artifact layout before upload |
| `geekyeggo/delete-artifact@v5` + `if: always()` | Clean intermediate artifacts |
| `env:` block for secrets | Prevent shell injection from special chars |
| Download before Upload | Deploy workflow: download config artifact THEN upload source |
| npm `overrides` for security | Fix transitive dep CVE without downgrading parent packages |

## Delivery Artifact Verification

When verifying artifacts for delivery, check each against its purpose:

| Artifact Type | Must Have | Must NOT Have |
|---------------|-----------|---------------|
| Source for Scan (Replace Secret = **No**) | committed/placeholder config only | Secrets/real config, templates, bin/obj, **`packages/`**; FE excludes libraries |
| Source for Developer (Replace Secret = **Yes**) | Real config values, all libraries (FE), Telerik (BE) | Templates, bin/obj, **`packages/`**, node_modules |
| Deploy Package (BE) | Release DLLs under `bin/`, replaced `Web.config` | Templates, **`*.cs` source** (ASMX code-behind), `packages/` |
| Deploy source (BE) | replaced config | bin/obj, **`packages/`**, source build output |
| Deploy Package (FE) | .tif files, .sppkg, config.js replaced | Templates, node_modules |
| Configuration | All env folders, FE+BE configs per env, .sppkg per env | — |
| Export Variable | Markdown with all vars + secrets — **real values, not `***`** (the artifact file holds real values; only `$GITHUB_STEP_SUMMARY` masks them) | bogus/non-existent keys |

### Quick Verification Commands
```bash
# Check for unreplaced placeholders
grep -rn "REPLACE_WITH" <artifact-dir>/

# Check no template files
find <artifact-dir> -name "*.template"

# FE Scan: verify no libraries
ls <fe-scan>/TLMLib/  # should only have css/, Images/, js/

# FE WithSecret: verify libraries present
ls <fe-withsecret>/TLMLib/kendoui  # should exist
```

### Verifying without extracting (disk-safe — `unzip -l/-p` on the raw artifact zip)
On a nearly-full disk, do NOT `gh run download` (it extracts). Pull the raw zip and inspect it:
```bash
aid=$(gh api repos/$R/actions/runs/$RUN/artifacts --jq '.artifacts[]|select(.name=="BE-KBS-Package").id')
gh api repos/$R/actions/artifacts/$aid/zip > pkg.zip      # raw zip = the deliverable, no extraction
unzip -l pkg.zip | awk '{print $4}' | grep -cE '(^|/)packages/'   # 0 expected
unzip -p pkg.zip Web.config | grep -c REPLACE_WITH_              # 0 expected (read one file to stdout)
```
- **grep gotcha:** zip entries at the artifact root are printed as `packages/...`, **not** `/packages/`. Anchor with `(^|/)packages/` — a `/packages/` pattern silently misses root-level dirs and gives false "clean" passes.
- **Size is a fast bloat proxy:** a BE source artifact that should be ~2MB but is 25MB–1.3GB almost always still contains `packages/`.

### Committing workflow fixes when local `git` is unusable
If the repo lives on a synced/slow volume (e.g. iCloud `~/Documents`) where `git status/diff/commit/fetch` hang, commit **server-side via the GitHub API**: `git/blobs` → `git/trees` (with `base_tree`) → `git/commits` → PATCH `git/refs/heads/<branch>`.
- **Danger:** build each JSON with a temp file + `gh api --input <file>` (piping `--input -` inside `$(...)` can yield an HTML error → **empty blob sha**). A create-tree entry with an **empty `sha` silently DELETES that path** — it once wiped a workflow file. Always assert the blob sha is non-empty before creating the tree, and re-fetch the file (`contents` API) to confirm size/content after the PATCH.

## .aipath Include/Exclude

```
##Include Front End Path:
/FrontEnd

##Exclude Front End Path:
/FrontEnd/TLMLib/bootstrap
/FrontEnd/TLMLib/kendoui

##Include Back End Path:
/Backend/Project.sln
/Backend/Project.WebAPI
/Backend/Telerik              # Required for build (HintPath refs)

##Exclude Back End Path:
/Backend/**/bin
/Backend/**/obj
```

- Exclude overrides Include
- Local DLL folders (Telerik/) must be in Include for build
- `##Exclude For Source Code Scan` — extra exclusions for scan-only workflows
