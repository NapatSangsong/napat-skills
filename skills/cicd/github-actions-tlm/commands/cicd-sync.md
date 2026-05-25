# CI/CD Sync — Sync changes across branches

Push current changes to multiple branches.

## Usage
```
/cicd-sync                          # Auto-detect and sync all branches
/cicd-sync main Modernize_bk        # Sync to specific branches
/cicd-sync --force main             # Force-push to main (use with caution)
```

## Instructions

### Phase 1: Detect
```
1. Current branch: git branch --show-current
2. All local branches: git branch --list
3. All remote branches: git branch -r
4. Uncommitted changes: git status --short
5. Parse $ARGUMENTS for target branches or --force flag
```

### Phase 2: Ask if needed
If no target branches specified in args:
- Show list of available branches
- Ask user which ones to sync to (use AskUserQuestion)

### Phase 3: Sync
For each target branch:
1. `git stash --include-untracked` if dirty
2. `git checkout <target>`
3. `git pull origin <target>` (if remote exists)
4. Try: `git checkout <source> -- .github/workflows/ CLAUDE.md .claude/commands/` (safe files first)
5. If more changes needed: cherry-pick or merge
6. Resolve conflicts:
   - `settings.local.json` → always `git rm --cached`
   - Other conflicts → prefer source branch version
7. `git push origin <target>` (or `--force` if flag set)
8. Return to original branch + `git stash pop`

### Phase 4: Verify
Show latest commit on each synced branch to confirm.

$ARGUMENTS
