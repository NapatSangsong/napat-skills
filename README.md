# napat-skills

Claude Code custom skills for .NET / SharePoint development workflows, engineering communication, and process.

## Skills

### Engineering

| Skill | Trigger | Description |
|-------|---------|-------------|
| [`nuget-audit`](skills/engineering/nuget-audit/SKILL.md) | `/nuget-audit`, TypeLoadException, MissingMethodException | Scan, audit, and fix NuGet package version conflicts across all .NET project types |

### Productivity

| Skill | Trigger | Description |
|-------|---------|-------------|
| [`post-mortem`](skills/productivity/post-mortem/SKILL.md) | `/post-mortem`, "write the RCA", "document this fix" | Write the canonical engineering record of a fixed bug |
| [`management-talk`](skills/productivity/management-talk/SKILL.md) | `/management-talk`, "executive summary", "make this less technical" | Rewrite engineering content for leadership audiences |

### nuget-audit

Supports **all .NET project types**:

| Project Type | Detection | Package System |
|---|---|---|
| .NET Framework 4.x | `packages.config` | packages.config + binding redirects |
| .NET Core / .NET 5-10+ | `<PackageReference>` in csproj | SDK-style csproj + `dotnet` CLI |
| Central Package Management | `Directory.Packages.props` | PackageVersion in props |
| Multi-targeting | `<TargetFrameworks>` | Verifies ALL target frameworks |

**What it detects:**
- Cross-project version conflicts
- Wrong / missing / stale binding redirects (.NET Framework)
- TFM incompatibility (SDK-style)
- Diamond & transitive dependency conflicts
- API-breaking version jumps (AngleSharp, Microsoft.Graph, EF Core, AutoMapper, MediatR, etc.)
- Phantom namespace migrations (e.g., `PnP.Framework.Pages` that doesn't exist)
- Deprecated / vulnerable packages (`dotnet list package --vulnerable`)

**What it fixes (config only, no code changes):**
- `packages.config`, `.csproj`, `Web.config`, `app.config`, `Directory.Packages.props`

## Installation

```bash
# Clone the repo
git clone https://github.com/NapatSangsong/napat-skills.git ~/work/napat-skills

# Symlink skills into Claude Code
ln -s ~/work/napat-skills/skills/engineering/nuget-audit ~/.claude/skills/nuget-audit
```

## Usage

```
/nuget-audit
```

Or trigger automatically by pasting a stack trace with `TypeLoadException`, `MissingMethodException`, or `FileLoadException`.
