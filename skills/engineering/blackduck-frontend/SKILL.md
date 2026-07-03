---
name: blackduck-frontend
description: "Fix Black Duck Frontend (npm/SPFx) — Analyze Black Duck scan results for JavaScript/TypeScript front-end projects (SharePoint Framework / Heft / webpack / npm), classify Security / Operational / License risk, remediate transitive vulnerabilities via npm `overrides`, and generate a waive report (Excel) for what cannot be fixed. Trigger on /blackduck-frontend, or when the user reports Black Duck risk items on a frontend/npm/SPFx project, asks to fix/waive Black Duck frontend findings, or says 'fix blackduck' on a JS/TS codebase. For .NET/NuGet projects use blackduck-nuget instead."
---

# Fix Black Duck Frontend — npm / SPFx dependency remediation

Analyze Black Duck SCA results for **npm-based** front-end projects (SharePoint Framework 1.2x, Heft/Rushstack, webpack, vanilla JS), classify each finding, remediate what is genuinely fixable through the npm `overrides` block, and waive what is not — with an accurate, evidence-backed Excel report. Learned from TOPCOOL (`FrontEnd/webparts`, SPFx 1.23.0, Heft) — 5 security components fixed at source, 5 License + 2 Operational waived.

Sibling skill: **blackduck-nuget** (.NET Framework / NuGet). Use that for `packages.config` / `PackageReference` projects.

## Usage
```
/blackduck-frontend                 # full workflow on the current npm project
/blackduck-frontend classify        # read the CSV export, classify Security/Operational/License
/blackduck-frontend fix             # apply npm overrides for fixable security items + verify build
/blackduck-frontend waive           # generate the Excel waive report for un-fixable items
```

## Core principles (read first — these are the load-bearing lessons)

1. **Three risk types, three different treatments.** Do not lump them together:
   - **Security Risk** = a real advisory (BDSA/CVE) on a component version → **fixable** by upgrading to a clean version via npm `overrides`, *if one exists*.
   - **Operational Risk** = a component-**health** score (version currency + upstream activity), **not a vulnerability** → usually **not fixable at source**; waive. (A latest-version, low-activity library is flagged High even with 0 vulns.)
   - **License Risk** = frequently "Unknown License" because the package's `license` field is a **URL, not an SPDX id** → waive with the *real* license identified.

2. **Trust the CSV export, not the UI screenshots.** The Details tab's "0 Vulnerabilities" widget can mislead. The authoritative sources are the CSV export files (see Phase 1). **Real mistake to avoid:** components were dismissed as "phantom / 0-vuln" from the Details tab, but the `security_*.csv` proved them real BDSA advisories with fixes available. Always reconcile against the CSV.

3. **`npm audit` ≠ Black Duck.** BDSA is Black Duck's own advisory DB (a superset of NVD/GHSA). `npm audit` can report **0 vulnerabilities** while Black Duck flags several BDSA items. A clean `npm audit` does **not** mean a clean Black Duck scan.

4. **Fix at source only what has a safe path.** Deviating from a parent's declared range (a forced `overrides`) is justified to remove a **real vulnerability** — it is *not* justified merely to lower a cosmetic Operational score. Weigh: real vuln? BD-recommended? small blast radius? verified build? If not all yes for an Operational bump, waive it.

## Phase 1 — Get ground truth: the CSV export

Ask the user to export the project-version report from Black Duck (Reports → export, or the "…" menu). It arrives as a `.zip` / folder containing CSVs. **macOS gotcha:** the sandbox usually cannot read `~/Downloads` (TCC blocks it — "Operation not permitted" even with the sandbox disabled). Ask the user to `cp` the file into the repo or a temp dir you can read.

Files and what to read:
- **`security_*.csv`** — the authoritative vuln list. Columns of interest: `Component name`, `Component version name`, `Vulnerability id` (e.g. `BDSA-2026-17215`), `Base score`, `Security Risk`, `Solution available`, `Remediation status`, `Match type` (Direct/Transitive Dependency).
- **`project_version_upgrade_guidance_*.csv`** — Black Duck's **own recommended fix versions**: `Short Term Recommended Version Name` (the safe, in-range fix) and `Long Term Recommended Version Name` (latest, may need a parent bump). Also `Short/Long Term {Critical,High,Medium,Low} Vulnerability` counts (0 = clean). **This tells you exactly what version to override to.**
- **`components_*.csv`** — full BOM (all components + risk columns + license). Grep it for Operational/License items (which the `security` CSV does not include).
- **`version_*.csv`** — project/version metadata.

Output of this phase: a table of `component | version | risk type | prod/dev | BDSA/CVE | recommended fix version | consumer chain`.

## Phase 2 — Classify & trace

For each flagged component, determine:
- **Risk type** (Security / Operational / License) — from the CSVs.
- **prod vs dev** — `npm why <pkg>` and whether the top-level entry is in `dependencies` (prod) or `devDependencies`/build-tooling. Build-only findings never ship in the bundle; that strengthens a waive and lowers real-world exploitability.
- **Consumer chain** — `npm why <pkg>@<version>` shows which top-level dep pulls it and via which intermediate (e.g., `minimatch@3` ← eslint; `ajv` ← @microsoft/sp-module-interfaces).

## Phase 3 — Remediate Security via npm `overrides`

Edit the `overrides` block in `package.json`. Then `npm install` (regenerates `package-lock.json`), and **commit the lockfile** — CI typically uses `npm ci`, which hard-fails if `package.json`/lock are out of sync.

Override mechanics and gotchas:
- **Version-scoped keys** (`"pkg@major": "x.y.z"`) target one major without disturbing sibling majors. Proven syntax (e.g. `"ajv@8": "8.20.0"`).
- **Direct dep** flagged → bump the declared version directly.
- **Cross-major export-shape trap** (important): forcing a transitive to a newer major can break its consumers if the export shape changed. Real example: `brace-expansion` 5.x exports `{ expand }` (an object), but 1.x/2.x export the function via `module.exports = expand`. `minimatch@3` does `var expand = require('brace-expansion'); expand(...)` and `minimatch@9` uses `.default` — both **break** with 5.x. `minimatch@10` uses `.expand` and works. **Solution:** don't force the leaf across an incompatible major; instead **bump the intermediate** (`"minimatch": "10.2.3"`) so every consumer uses the API-compatible line, then `"brace-expansion@5": "<fix>"` covers them all. Always confirm by reading the consumer's source (`require('pkg')` used as function vs `.x`).
- **In-range vs latest:** prefer Black Duck's **Short-Term** recommendation (stays inside the parent's declared range — e.g. `fast-uri 3.1.3` inside `ajv`'s `^3`). Only force the **Long-Term** latest (e.g. `fast-uri 4.1.0` past `ajv`'s `^3`) if the user wants "latest" AND it verifies clean — it's an unsupported combo, so document it as reversible.
- **Never** do a bare global override of `minimatch`/`brace-expansion` without checking export compat, or force cssnano's `postcss-selector-parser` 6.x→7.x blindly — verify the build.

## Phase 4 — Operational risk (usually waive)

Operational risk has **no "fixed version"** in the guidance CSV — it is a health score. Decide per component:
- **Latest version already?** → cannot upgrade → **waive** (e.g. `tslib 2.8.1`, `Newer Versions: 0`; High comes from low upstream activity — outside your control).
- **Forced transitively?** → `npm why` may show a prod dep pins it (e.g. `@swc/helpers` requires `tslib ^2.8.0` via `@microsoft/decorators`) — removing your direct declaration won't help → **waive**.
- **A newer version exists (version-currency score)?** Test a bump empirically, but **only ship it if it (a) builds clean and (b) is worth deviating from the supported config.** Example: `typescript 5.3.3` (SPFx-pinned) — TS 6.0.3 breaks the build (rig sets `moduleResolution=node10`/`target=ES5`, deprecated in TS 6); TS 5.9.3 builds but Heft warns "may not work correctly" and it won't guarantee clearing the flag (6.x is always newer) for **zero security gain** → **waive**, don't bump.

## Phase 5 — License risk (usually waive, with the real license)

Common cause: `package.json` `license` is a **URL** (e.g. Microsoft SPFx packages use `"https://aka.ms/spfx/license"`) rather than an SPDX identifier, so Black Duck's KB can't classify it → **"Unknown License" = High**. This is a metadata artifact, not a restrictive license.
- Identify the **actual** license: read the package's `license` field, follow the URL (e.g. `aka.ms/spfx/license` → "Microsoft SharePoint Framework - Standalone (free) Use Terms", proprietary but royalty-free).
- Confirm **Commercial Impact = No** (permissive / free-use; no copyleft; not redistributed).
- These are almost always build-only devDeps → waive.

## Phase 6 — Verify (before commit)

Run in the project dir. Adapt script names to the toolchain (SPFx/Heft shown):
1. `npm install` → regenerates lockfile with overrides.
2. `npm audit` → expect 0 (but remember it ≠ Black Duck).
3. `npm ls <changed pkgs> --all` → confirm the resolved versions actually moved and old copies are gone.
4. `npm run build` → **runs ESLint** (SPFx Heft has no standalone lint script). Watch for the "TypeScript newer than tested" warning.
5. `npm run package-solution` (SPFx) → produces the `.sppkg`; also exercises **ajv manifest validation** (good test for ajv/fast-uri overrides).
6. `npm test` → smoke (may be "No tests found" — then vulnerable test-tooling paths like `@istanbuljs/load-nyc-config` + js-yaml are unreachable anyway).
7. **Positive-control for lint matching** (when you forced `minimatch`): inject a deliberate lint error into a source file, confirm `npm run build` fails at lint on that line, then revert. Proves ESLint still actively lints under the forced minimatch (not silently skipping).
8. Commit `package.json` + `package-lock.json` **together**.

## Phase 7 — Waive report (Excel)

Reuse the blackduck-nuget openpyxl generator (Phase 9 there), adapted for npm:
- **Mode B** (initial scan, no baseline): Overview shows `Risk | Waived Count` via COUNTIF; add a baseline (Mode A) only on a later re-scan against an already-reviewed version.
- Sheets: **Overview**, **SecurityRisk** (empty if all fixed — add a note row), **LicenseRisk**, **OperationRisk**, optional **L1..LN** license-evidence detail sheets, plus a **Security-Fixed** sheet documenting source remediations.
- Column schemas: SecurityRisk uses `High/Medium` (title case); OperationRisk & LicenseRisk use `HIGH/MEDIUM` (uppercase) — COUNTIF casing must match.
- Reuse Thai mitigation phrasing (`frontend_only`, `locked_parent`, etc.) to match prior reports.

**openpyxl image gotcha (critical):** `openpyxl.load_workbook()` **drops embedded images on save**. If the user has pasted screenshots (e.g. into L1..LN), do **NOT** load+save with openpyxl — it wipes them. Instead:
- **Surgical XML edit** (safest): `unzip` the `.xlsx`, edit only the text worksheet XML (`xl/worksheets/sheetN.xml`) and `xl/sharedStrings.xml` for the sheets you're changing, validate with `minidom.parseString`, and re-zip (Content_Types first). Leave `xl/media/*`, `xl/drawings/*`, and image-bearing sheets untouched → images preserved byte-for-byte. Map sheet↔drawing↔media via `xl/_rels`, `xl/worksheets/_rels/sheetN.xml.rels`, `xl/drawings/_rels/*.rels`.
- **Regenerate + re-add images** requires **Pillow** (`openpyxl.drawing.image.Image` fails with "You must install Pillow" otherwise). Extract the old `xl/media/*` first so you can re-insert.
- Always keep an extracted copy of the user's file before regenerating — it lets you recover pasted images.

## SPFx / Heft specifics (quick reference)
- `@microsoft/sp-*`, `@microsoft/spfx-*`, and the pinned `typescript` are a **matched set per SPFx version** (e.g. 1.23.0) — you can't bump them independently; that's a framework upgrade.
- `tslib` is pulled by `@swc/helpers` (via `@microsoft/decorators`) and by `importHelpers: true` in the rig's `tsconfig-base` → effectively unremovable.
- SPFx build tooling (eslint-config-spfx, spfx-heft-plugins, spfx-web-build-rig, sp-css-loader) ships the `aka.ms/spfx/license` URL → "Unknown License" false-High.
- The shipped artifact is the `.sppkg`; build-only deps (eslint/jest/heft/cssnano/typescript) never ship — state this in waives.

## Decision summary
| Finding | Action |
|---|---|
| Security, fix version exists (guidance CSV) | **Fix** via `overrides` (version-scoped; bump intermediate if export-shape incompatible); verify build |
| Security, no in-major fix + incompatible major | Bump the intermediate consumer, or **waive** if dev-only and unfixable safely |
| Operational, already latest / forced transitively | **Waive** (health score, not a vuln) |
| Operational, newer exists but bump is unsupported/cosmetic | **Waive** (don't deviate from supported config for a non-vuln) |
| License "Unknown" from URL license field | **Waive** with the real (SPFx/proprietary-free) license, Commercial Impact = No |
