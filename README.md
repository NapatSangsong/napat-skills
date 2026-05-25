# napat-skills

Claude Code custom skills for .NET / SharePoint / frontend development, engineering communication, and CI/CD pipeline management.

## Skills (9 skills + 8 CI/CD commands)

### Engineering

| Skill | Trigger | Description |
|-------|---------|-------------|
| [`nuget-audit`](skills/engineering/nuget-audit/SKILL.md) | `/nuget-audit` | Scan and fix NuGet package version conflicts across all .NET project types (.NET Framework, .NET Core/5-10+, CPM) |
| [`debug-mantra`](skills/engineering/debug-mantra/SKILL.md) | `/debug-mantra` | Four-step debugging discipline: reproduce, trace the fail path, falsify hypothesis, cross-reference breadcrumbs |
| [`scrutinize`](skills/engineering/scrutinize/SKILL.md) | `/scrutinize` | Outsider-perspective end-to-end review of plans, PRs, or code changes |
| [`blackduck-nuget`](skills/engineering/blackduck-nuget/SKILL.md) | `/blackduck-nuget` | Analyze Black Duck scans, compare against baselines, upgrade .NET Framework packages to resolve security/operational/license risks |
| [`coverity-frontend`](skills/engineering/coverity-frontend/SKILL.md) | `/coverity-frontend` | Fix Coverity DOM_XSS and URL_MANIPULATION issues in frontend JS/HTML with 17 proven fix patterns |

### Productivity

| Skill | Trigger | Description |
|-------|---------|-------------|
| [`post-mortem`](skills/productivity/post-mortem/SKILL.md) | `/post-mortem` | Write the canonical engineering record of a fixed bug (RCA) |
| [`management-talk`](skills/productivity/management-talk/SKILL.md) | `/management-talk` | Rewrite engineering content for leadership audiences (JIRA, Slack, email, meeting) |

### CI/CD

| Skill | Trigger | Description |
|-------|---------|-------------|
| [`github-actions-tlm`](skills/cicd/github-actions-tlm/SKILL.md) | `/cicd-setup` | GitHub Actions CI/CD for Thalamo web projects — 8 sub-commands |

#### CI/CD Sub-commands

| Command | Description |
|---------|-------------|
| `/cicd-setup` | Bootstrap complete CI/CD pipeline from scratch |
| `/cicd-test` | Trigger all workflows, download artifacts, verify |
| `/cicd-test-one` | Test a specific workflow |
| `/cicd-review` | Security + path + artifact integrity review |
| `/cicd-report` | Generate HTML + Markdown verification report |
| `/cicd-summary` | Management-friendly summary |
| `/cicd-sync` | Sync workflow changes across branches |
| `/cicd-env` | Manage GitHub Environments, Variables, Secrets |

---

## Proven Results

| Skill | Project | Result |
|-------|---------|--------|
| `nuget-audit` | PTTGC.KBS, eTCM | Resolved assembly conflicts, prevented phantom namespace migrations |
| `blackduck-nuget` | PTTGC.KBS | 85 → 54 operational risk items (27 resolved, 0 new) |
| `coverity-frontend` | PTTGC.KBS | 61 → 0 Coverity issues in 8 iterations |
| `coverity-frontend` | TOPCOOL | 100% pass rate |
| `github-actions-tlm` | TOPCOOL, PTTGC.KBS | 8 + 2 helper workflows, 4 environments each |

---

## Installation

### Quick Install (all skills + commands)

```bash
git clone https://github.com/NapatSangsong/napat-skills.git ~/work/napat-skills
cd ~/work/napat-skills
./scripts/link-skills.sh
```

### Manual Install (specific skills)

```bash
# Symlink a single skill
ln -sf ~/work/napat-skills/skills/engineering/nuget-audit ~/.claude/skills/nuget-audit

# Copy CI/CD commands
cp ~/work/napat-skills/skills/cicd/github-actions-tlm/commands/*.md ~/.claude/commands/
```

> After installing, **restart Claude Code** to load new skills/commands.

---

## Structure

```
napat-skills/
├── README.md              # This file — full catalog
├── CLAUDE.md              # Repo conventions
├── scripts/
│   └── link-skills.sh     # Install script
├── docs/
│   └── postmortems/       # Engineering post-mortem records
└── skills/
    ├── engineering/        # Debugging, auditing, security
    │   ├── nuget-audit/
    │   ├── debug-mantra/
    │   ├── scrutinize/
    │   ├── blackduck-nuget/
    │   └── coverity-frontend/
    ├── productivity/       # Communication, process
    │   ├── post-mortem/
    │   └── management-talk/
    └── cicd/               # CI/CD pipeline management
        └── github-actions-tlm/
            ├── SKILL.md
            └── commands/   # 8 sub-command files
```

## License

MIT
