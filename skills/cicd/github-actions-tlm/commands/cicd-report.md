# CI/CD Report — Generate verification report from artifacts

Generate a professional interactive HTML report + markdown from downloaded artifacts.

## Usage
```
/cicd-report ~/path/to/artifacts              # Scan directory and generate report
/cicd-report ~/path/to/artifacts --html-only  # HTML only
```

## Instructions

### Phase 1: Scan
Scan the artifact directory for workflow output:
```
find <dir> -mindepth 1 -maxdepth 3 -type d | sort
```
Identify artifact types by folder/file patterns:
- `BE-Cool-*` or similar → Backend artifacts
- `FE-Cool-*` or similar → Frontend artifacts
- `Cool-variable` → Export Variable
- `Configuration` → Configuration
- `TLMLib/` subfolder → Frontend package
- `appsettings.*` → Backend config
- `config.*.js` → Frontend config
- `*.tif` → TIF conversion

### Phase 2: Read key files
For highlighted/important files (config.js, appsettings, Cool-variable.md), read full content for embedding in report.

### Phase 3: Generate HTML Report
Create `ReportWeb/index.html` with:
- **Sidebar**: list of workflows with pass/fail status
- **Environment tabs**: switch between QAS/PRD/etc
- **Pipeline visualization**: GitHub Actions style (job boxes connected by lines)
- **Requirements section**: what each workflow should produce
- **Artifact tree**: collapsible file tree (VS Code style)
- **Clickable files**: highlighted files open modal with full content
- **Verification checks**: pass/fail table per workflow

Style: minimal, professional, no emoji. Use GitHub's color palette.

### Phase 4: Generate Markdown Report
Create `REPORT.md` with:
- Requirement matrix table
- Per-workflow per-env verification checks
- Key file listings
- Summary pass/fail table

Output to: `<artifact-dir>/ReportWeb/index.html` and `<artifact-dir>/ReportWeb/REPORT.md`

$ARGUMENTS
