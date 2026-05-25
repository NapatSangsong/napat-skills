# CI/CD Test — Trigger all workflows, download artifacts, verify

Test all GitHub Actions workflows for the current project.

## Usage
```
/cicd-test                    # Test all workflows, QAS + PRD
/cicd-test QAS                # Test all workflows, QAS only
/cicd-test --output ~/path    # Custom output directory
```

## Instructions

### Phase 1: Detect
```
1. REPO: gh repo view --json nameWithOwner --jq .nameWithOwner
2. WORKFLOWS: gh workflow list -R $REPO --json name,id | jq -r '.[].name'
3. DEFAULT_BRANCH: gh repo view -R $REPO --json defaultBranchRef --jq .defaultBranchRef.name
4. Parse $ARGUMENTS for environment filter or output path
```

### Phase 2: Trigger
For each workflow:
- If workflow accepts `environment` input → trigger for each env (from args or default QAS+PRD)
- If workflow has no environment input (e.g., Configuration) → trigger once
- Use: `gh workflow run "<name>" -f environment=<env> --ref <branch> -R <repo>`
- Collect all run URLs

### Phase 3: Wait
Poll `gh run list -R <repo> --limit <count>` until all runs complete.
Report any failures immediately with `gh run view <id> --log-failed`.

### Phase 4: Download
- Output dir: `$ARGUMENTS` path or `~/Documents/Work2026/COOL/Test Actions/<timestamp>/`
- Create directory structure: `<workflow-name>/<env>/`
- Download: `gh run download <id> -R <repo> -D <dir>`
- For runs with cleanup jobs that delete intermediate artifacts, use `-n <artifact-name>` to download specific artifacts only

### Phase 5: Verify
For each downloaded artifact, run checks appropriate to the workflow type:
- **SourceCode artifacts**: no bin/obj, no *.template, check config replacement status, verify local DLL refs (Telerik/) present if project uses them
- **Package artifacts**: correct folder structure, no source code, config files present
- **Configuration**: env-first structure, correct files per env
- **Export Variable**: has real values for secrets

### Phase 6: Report
Print summary table:
```
| Workflow | Env | Status | Checks | Artifact Path |
```

$ARGUMENTS
