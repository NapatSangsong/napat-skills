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

### Helper Workflows (2)

| Workflow | Purpose | Called by |
|----------|--------|---------|
| Backend - Generate Config | Copy template + sed replace for backend | WithSecret, Deploy |
| Frontend - Generate Config | Copy template + sed replace for frontend | WithSecret, Deploy |

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

## Proven Patterns

| Pattern | When to use |
|---------|------------|
| `.aipath` -> scan rules | Read include/exclude from .aipath for artifact paths |
| `git checkout branch -- path` | Cherry-pick specific files without full merge |
| Matrix + `environment:` | Configuration workflow — parallel env jobs |
| Staging directory | Control artifact layout before upload |
| `geekyeggo/delete-artifact@v5` + `if: always()` | Clean intermediate artifacts |
| `env:` block for secrets | Prevent shell injection from special chars |

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
