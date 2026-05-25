# CI/CD Env — Manage GitHub Environments, Variables, and Secrets

Create, list, update, or copy environment configurations.

## Usage
```
/cicd-env list                      # List all envs with their vars/secrets
/cicd-env create QAS                # Create QAS environment + set vars/secrets interactively
/cicd-env copy QAS DEV              # Copy all vars from QAS to DEV (ask for secrets)
/cicd-env export                    # Export all env configs to markdown
/cicd-env import vars.tsv           # Import vars/secrets from TSV file
/cicd-env diff QAS PRD              # Show differences between environments
```

## Instructions

Detect repo: `gh repo view --json nameWithOwner --jq .nameWithOwner`

### "list" (default if no args)
```bash
# List environments
gh api repos/{repo}/environments --jq '.environments[].name'

# For each environment, list vars + secrets
for env in $(environments); do
  echo "=== $env ==="
  gh variable list -R {repo} -e $env
  gh secret list -R {repo} -e $env
done
```
Present as a formatted table.

### "create {env}"
1. Create environment: `gh api repos/{repo}/environments/{env} -X PUT`
2. Scan workflow files for required vars/secrets:
   ```bash
   grep -roh 'vars\.\([A-Z_]*\)' .github/workflows/*.yml | sed 's/vars\.//' | sort -u
   grep -roh 'secrets\.\([A-Z_]*\)' .github/workflows/*.yml | sed 's/secrets\.//' | sort -u
   ```
3. Ask user for each value using AskUserQuestion:
   - Group by category (Azure AD, Database, Frontend, etc.)
   - Show which workflows use each variable
   - For secrets: remind user the value will be encrypted
4. Set values:
   ```bash
   gh variable set {KEY} --body "{VALUE}" -R {repo} -e {env}
   gh secret set {KEY} --body "{VALUE}" -R {repo} -e {env}
   ```
5. Verify: list all vars/secrets for the new environment

### "copy {source} {target}"
1. Create target environment if not exists
2. List all vars from source: `gh variable list -R {repo} -e {source} --json name,value`
3. Copy each variable to target
4. For secrets: cannot read values — ask user to provide them
   - Show secret names and ask "same as {source} or enter new value?"
5. Verify both environments

### "export"
Generate markdown table of all environments:
```
| Env | Type | Key | Value |
|-----|------|-----|-------|
| QAS | var | PREFIX_AZ_CLIENTID | xxx-xxx |
| QAS | secret | PREFIX_DB_PASSWORD | (set) |
| PRD | var | PREFIX_AZ_CLIENTID | yyy-yyy |
```
Save to `github-env-export.md` in current directory.

### "import {file}"
Read TSV/CSV file with columns: Env, Type, Key, Value
```
QAS	var	COOL_AZ_CLIENTID	79f6f4f1-xxx
QAS	secret	COOL_DB_PASSWORD	mypassword
PRD	var	COOL_AZ_CLIENTID	8b3e818c-xxx
```
- Create environments if not exists
- Set all vars/secrets
- Show summary of what was imported

### "diff {env1} {env2}"
Compare two environments side by side:
```
| Key | Type | {env1} | {env2} | Status |
|-----|------|--------|--------|--------|
| PREFIX_AZ_CLIENTID | var | xxx | yyy | Different |
| PREFIX_DB_SERVER | var | srv1 | srv1 | Same |
| PREFIX_DB_PASSWORD | secret | (set) | (not set) | Missing |
```

$ARGUMENTS
