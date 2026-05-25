# CI/CD Setup — Bootstrap GitHub Actions for any project

Set up a complete CI/CD pipeline with GitHub Actions for a Thalamo web project.

## Instructions

You are setting up CI/CD workflows for a project. Work autonomously but **ask the user when unsure** about project-specific details.

### Phase 1: Detect Project Structure

Run these checks automatically:
```
1. Repo info: gh repo view --json name,defaultBranchRef
2. Backend: find . -name "*.sln" -type f
3. Backend projects: find . -name "*.csproj" -type f (identify WebAPI, Library, SchedulerApp, etc.)
4. Frontend: ls FrontEnd/ or ls frontend/ (find SitePages, TLMLib or similar)
5. Config files: find . -name "appsettings*.json" -o -name "config*.js" | head -20
6. Existing workflows: ls .github/workflows/ 2>/dev/null
7. .aipath: cat .aipath 2>/dev/null
8. .gitignore: check for .DS_Store, bin/, obj/, *.template, settings.local.json
```

### Phase 2: Ask User (use AskUserQuestion)

Based on detected structure, ask:
1. **Project prefix** for placeholders (e.g., COOL, KBS, TCM) — used in `REPLACE_WITH_{PREFIX}_*`
2. **Environments** to support (default: QAS, PRD, DEV, TLM)
3. **Which workflows** to create (show the standard 8 + 2 helper list, let user pick)
4. **Config structure**: Where should config.js live? Where are appsettings?
5. **Special requirements**: Telerik DLLs? Library folders to include/exclude? TIF conversion?
6. **Branches** to push to (default: main + current)

### Phase 3: Create Template Files

For each config file found:
- Create `*.template` version with `REPLACE_WITH_{PREFIX}_*` placeholders
- Ask user to confirm placeholder mapping (which GitHub var/secret maps to which placeholder)
- Update `.gitignore` to exclude `settings.local.json`, `.DS_Store`

### Phase 4: Create Workflows

Create workflows adapted to the detected structure. Standard set:

| # | Workflow | Key Behaviors |
|---|---------|---------------|
| 1 | Backend - SourceCode Scan | .aipath, test build, no secrets, exclude bin/obj/template |
| 2 | Frontend - SourceCode Scan | .aipath, no secrets, exclude template |
| 3 | Backend - SourceCode WithSecret | generate-config, test build, include Telerik if exists |
| 4 | Frontend - SourceCode WithSecret | generate-config, include libraries |
| 5 | Backend - Deploy | publish Release, source + package artifacts, include local DLL refs (Telerik/) |
| 6 | Frontend - Deploy | source + package (with TIF if SitePages exist) |
| 7 | Export Variable | dump all vars + secrets to markdown file + upload as artifact |
| 8 | Configuration | all envs via matrix, env-first folder structure |
| H1 | Backend - Generate Config | reusable, cp template + sed for each backend project |
| H2 | Frontend - Generate Config | reusable, cp template + sed |

Adapt paths, project names, artifact names, and sed replacements to the detected structure.

**CRITICAL: Every workflow MUST produce a downloadable artifact via `actions/upload-artifact@v4`.**
Do NOT rely on Job Summary (`$GITHUB_STEP_SUMMARY`) alone — it's only visible in the GitHub UI, not downloadable as .zip.
Every workflow must have at least one `upload-artifact` step that creates a downloadable file.

### Phase 5: Create GitHub Environments + Variables + Secrets

Set up GitHub Environments with all required variables and secrets.

#### 5a. Create Environments
For each environment (e.g., QAS, PRD, DEV, TLM):
```bash
gh api repos/{owner}/{repo}/environments/{env} -X PUT
```

#### 5b. Detect Required Variables
Scan all workflow files and templates to build a complete list:
```bash
# From templates:
grep -oh 'REPLACE_WITH_[A-Z_]*' <templates> | sort -u
# From workflows:
grep -oh 'vars\.\([A-Z_]*\)' .github/workflows/*.yml | sort -u
grep -oh 'secrets\.\([A-Z_]*\)' .github/workflows/*.yml | sort -u
```

#### 5c. Ask User for Values
For each environment, present the variable list and ask user to provide values:
- Use AskUserQuestion for the first environment (e.g., QAS)
- For subsequent environments, ask "same as QAS or different?"
- For secrets (passwords, connection strings): ask user to provide securely

Show a table like:
```
| Key | Type | QAS Value | PRD Value |
|-----|------|-----------|-----------|
| {PREFIX}_AZ_CLIENTID | var | ? | ? |
| {PREFIX}_DB_PASSWORD | secret | ? | ? |
```

#### 5d. Set Variables + Secrets
```bash
# Variables (visible):
gh variable set {KEY} --body "{VALUE}" -R {owner}/{repo} -e {env}

# Secrets (encrypted):
gh secret set {KEY} --body "{VALUE}" -R {owner}/{repo} -e {env}
```

#### 5e. Verify
```bash
gh variable list -R {owner}/{repo} -e {env}
gh secret list -R {owner}/{repo} -e {env}
```

Generate a summary table of all environments with their variable/secret counts.

### Phase 6: Push & Verify

1. Commit all new files
2. Push to current branch
3. **Check if current branch is the default branch** (main/master):
   ```bash
   DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   CURRENT=$(git branch --show-current)
   ```
   - If `$CURRENT != $DEFAULT`: **Ask user** "Workflows ถูก push ไป `$CURRENT` แต่ GitHub Actions จะแสดงเฉพาะบน `$DEFAULT` — ต้องการให้ cherry-pick เฉพาะ workflow files ไป `$DEFAULT` ด้วยไหม? (code changes อื่นๆ จะยังอยู่ที่ `$CURRENT`)"
   - If yes:
     ```bash
     git checkout $DEFAULT
     git checkout $CURRENT -- .github/workflows/ .github/actions/
     git commit -m "Add CI/CD workflows from $CURRENT"
     git push origin $DEFAULT
     git checkout $CURRENT
     ```
4. Trigger a quick test (Configuration workflow is fastest to verify — it reads all vars/secrets)
5. Download Configuration artifact and verify values are populated
6. Report results

### Reference Implementations

#### TOPCOOL (.NET 10 / ASP.NET Core)
- Config at `FrontEnd/TLMLib/js/config.js` with `config.js.template`
- Backend `appsettings.json` (base) + `appsettings.json.template` per project
- Artifact names: `BE-Cool-SourceCode`, `FE-Cool-SourceCode`, `BE-Cool-Package`, `FE-Cool-Package`
- Frontend package uses staging directory to preserve folder structure
- bin/obj cleaned after build via `find -exec rm -rf`
- Templates excluded via `!**/*.template` or `rm -f` before upload

#### PTTGC.KBS (.NET Framework 4.6 / ASP.NET)
- Config at `FrontEnd/TLMLib/js/config.js` with `config.js.template`
- Backend uses `Web.config` instead of `appsettings.json` — template is `Web.config.template`
- **Backend build requires `windows-latest` runner** — .NET Framework needs MSBuild + Visual Studio build tools (not `dotnet build`)
- **sed via env vars**: pass secrets through environment variables to avoid shell injection from special characters in connection strings
- NuGet restore via `nuget.exe` (not `dotnet restore`) — use `nuget-action` or direct download
- Solution at `Backend/PTTGC.KBS/Thalamo.GC.KBS.sln`
- Frontend workflows use `ubuntu-latest` (no build step needed)
- Environment input uses `type: choice` with options list (instead of `type: environment`)
- No `parse-aipath` custom action — uses direct path patterns for scan workflows
- Workflow filenames: `be-*` and `fe-*` prefix convention

### Lessons Learned

#### Build & Config
- **Detect .NET version first**: check .csproj for `<TargetFramework>` — `net48`/`net472` = .NET Framework (Web.config, MSBuild, windows-latest), `net8.0`/`net10.0` = .NET Core (appsettings.json, dotnet CLI, ubuntu-latest)
- **MSBuild WebPublish ใช้ไม่ได้บน Windows runner** — path ผสม D:\...\REPO/publish + ไม่มี .pubxml ทำให้ไม่สร้าง output → **ต้องใช้ `cp` staging แทนเสมอสำหรับ .NET Framework**
- **`shell: bash` ต้องระบุทุก step** ที่ใช้ sed/cp/find บน Windows runner — ถ้าไม่ระบุจะใช้ PowerShell ซึ่งไม่มี sed
- **sed injection prevention**: ห้ามใช้ `${{ secrets.* }}` ใน sed โดยตรง ต้องผ่าน `env:` block ก่อน:
  ```yaml
  env:
    CONN_STR: ${{ secrets.CONNECTION_STRING }}
  run: sed -i "s|REPLACE_WITH_CONN|$CONN_STR|g" Web.config
  ```
- **Helper workflow ไม่มี `environment:`** — standalone trigger จะได้ค่าว่าง (by design — ใช้ผ่าน workflow_call เท่านั้น)

#### GitHub Actions
- **upload-artifact path behavior**: single directory path strips directory name — use parent directory or staging dir to preserve folder structure
- **Secrets masking**: `${{ secrets.X }}` in echo writes real value to files but masks in logs — good for Export Variable, bad for job summaries
- **Intermediate artifact cleanup**: always use `geekyeggo/delete-artifact@v5` with `if: always()`
- **Workflows only show on default branch**: if working on feature branch, cherry-pick `.github/workflows/` to main/master

#### Artifact Buildability
- **Local DLL references (Telerik/) must be in .aipath include list** — if .csproj has `<HintPath>..\Telerik\*.dll</HintPath>`, the Telerik folder MUST be included in source artifacts, otherwise downloaded source won't build
- **.aipath exclude overrides include** — putting a folder in both include and exclude means it gets excluded. Always check both sections.

#### Patterns ที่ดี
- **.aipath → scan workflow rules** — อ่าน include/exclude จาก .aipath ได้เลย
- **`git checkout branch -- path`** — cherry-pick เฉพาะไฟล์ ดีกว่า `cherry-pick --no-commit`
- **Matrix + environment** — Configuration workflow ใช้ matrix + `environment:` key ทำให้แต่ละ env ได้ vars/secrets ของตัวเอง
- **Force-push protection**: check Rulesets (Settings → Rules → Rulesets), not just classic branch protection

#### Environment Setup
- **Extract secrets from existing config**: when project already has Web.config/appsettings with real values, offer to extract and set as GitHub secrets automatically
- **Placeholder secrets**: when real values unknown, set `CHANGE_ME` and list in Action Required section
- **Same secrets across envs**: common pattern is PRD values used everywhere initially, then user updates per-env later

$ARGUMENTS
