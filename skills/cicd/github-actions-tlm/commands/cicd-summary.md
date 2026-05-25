# CI/CD Summary — Management-friendly summary

Generate a summary suitable for management or stakeholders.

## Usage
```
/cicd-summary              # Summarize current branch changes
/cicd-summary actions      # Summarize all CI/CD actions
/cicd-summary readiness    # Deployment readiness assessment
```

## Instructions

Based on `$ARGUMENTS`:

### Default (no args or "changes")
Compare current branch vs default branch (main/master):
1. `git log --oneline <default>..<current>` — list changes
2. Group by category: CI/CD, Security, Code Quality, Bug Fixes, Documentation
3. Present in business terms — what problem it solves, not how

### "actions"
List all workflows with:
- Purpose (what it's for)
- Output (artifact names)
- Last run status
- One-line description

### "readiness"
Check deployment readiness:
- All workflows passing?
- Config templates in place?
- No hardcoded secrets?
- Branches in sync?
- Report as: Ready / Not Ready + blockers

### Style
- Thai language preferred (user preference)
- Tables over paragraphs
- No code snippets unless essential
- No technical jargon — focus on business value

$ARGUMENTS
