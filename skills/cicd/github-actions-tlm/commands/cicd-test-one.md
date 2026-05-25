# CI/CD Test One — Test a specific workflow

Test a single GitHub Actions workflow, download its artifacts, and verify.

## Usage
```
/cicd-test-one Backend - Deploy QAS
/cicd-test-one Frontend - SourceCode WithSecret PRD
/cicd-test-one Configuration
/cicd-test-one Export Variable QAS
```

## Instructions

### Parse Arguments
From `$ARGUMENTS`, extract:
1. **Workflow name** — match against available workflows: `gh workflow list -R <repo> --json name`
2. **Environment** — last word if it matches QAS/PRD/DEV/TLM (default: QAS)

### Execute
1. **Trigger**: `gh workflow run "<name>" -f environment=<env> --ref <default-branch> -R <repo>`
   - For Configuration (no env input): `gh workflow run "Configuration" --ref <branch> -R <repo>`
2. **Wait**: Poll until complete
3. **Download**: To `<project-root>/test-output/<workflow-name>/<env>/`
   - Read workflow file to find artifact names (`grep "name:" .github/workflows/<file>.yml`)
   - Download each artifact by name: `gh run download <id> -R <repo> -D <dir> -n <artifact>`
4. **Verify**: Run appropriate checks based on workflow type
5. **Report**: Print pass/fail table + download path

### Auto-detect checks based on workflow content
Read the workflow yml file to determine:
- Does it call generate-config? → verify config replacement
- Does it run dotnet build/publish? → check for bin/obj exclusion
- Does it upload multiple artifacts? → verify each one
- Does it have template removal steps? → verify no templates in output
- Does the project reference local DLLs (HintPath in .csproj)? → verify those folders exist in source artifact

$ARGUMENTS
