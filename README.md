# napat-skills

Claude Code custom skills for .NET / SharePoint development workflows.

## Skills

### Engineering

| Skill | Description |
|-------|-------------|
| `nuget-audit` | NuGet Package Audit & Fix — Scan, audit, and fix package version conflicts in .NET Framework solutions |

## Installation

```bash
# Clone the repo
git clone https://github.com/NapatSangsong/napat-skills.git ~/work/napat-skills

# Symlink skills into Claude Code
ln -s ~/work/napat-skills/skills/engineering/nuget-audit ~/.claude/skills/nuget-audit
```

## Usage

In Claude Code:
```
/nuget-audit
```

Or trigger automatically by pasting a `TypeLoadException` / `MissingMethodException` stack trace.
