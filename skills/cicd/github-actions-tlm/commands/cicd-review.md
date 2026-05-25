# CI/CD Review — Scrutinize all workflows

Review all GitHub Actions workflows for correctness, security, and consistency.

## Usage
```
/cicd-review              # Review all workflows in current project
/cicd-review security     # Focus on security checks only
```

## Instructions

### Phase 1: Discover
```
1. List all workflow files: ls .github/workflows/*.yml
2. Read each file completely
3. Find config templates: find . -name "*.template" -type f
4. Find .aipath: cat .aipath
```

### Phase 2: Check Categories

#### Security
- [ ] No hardcoded secrets (grep for password, secret, connectionstring in non-template files)
- [ ] No settings.local.json committed
- [ ] No .env files committed
- [ ] License keys reviewed (kendo-ui-license.js etc.)
- [ ] Secrets properly referenced as `${{ secrets.* }}` not `${{ vars.* }}`

#### Path Consistency
- [ ] Config file paths match between: generate-config workflow, download steps, rm template steps
- [ ] Template file paths exist in repo
- [ ] .aipath paths match actual directory structure
- [ ] Artifact upload paths are correct

#### Artifact Integrity
- [ ] Templates excluded from all artifacts (via `rm -f` or `!**/*.template`)
- [ ] bin/obj excluded from source artifacts
- [ ] No source code in package artifacts
- [ ] Correct artifact names per workflow
- [ ] Local DLL references (e.g., Telerik/) included in source artifacts — check .aipath include/exclude and upload-artifact paths
- [ ] .aipath include paths cover all folders needed for a buildable source artifact (check HintPath refs in .csproj)

#### Workflow Logic
- [ ] Reusable workflows have both `workflow_dispatch` and `workflow_call` triggers
- [ ] Jobs with `needs:` reference valid job names
- [ ] Cleanup jobs use `if: always()` and delete correct intermediate artifacts
- [ ] Matrix strategy correct for Configuration workflow

#### Sed Replacements
- [ ] All REPLACE_WITH_* placeholders in templates have matching sed rules
- [ ] No extra sed rules for placeholders that don't exist
- [ ] WebAPI and SchedulerApp have different replacement sets (LIMS, CORS only in WebAPI)

### Phase 3: Report
Format as:
```
## CRITICAL — must fix
## WARNING — should fix
## INFO — observations
## PASS — all checks passed
```

$ARGUMENTS
