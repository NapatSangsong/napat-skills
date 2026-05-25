# Phantom Namespace Migration — Executive Summary

**Status**: Fixed and validated
**Owner**: Napat Sangsong
**Affected project**: PTTGC.KBS
**Validated on**: eTCM (confirmed working)

---

## What happened

Our NuGet package audit tool recommended migrating code to a namespace that **doesn't exist** in the target library. This would have sent developers down the wrong path — writing code against an API that was never there.

## Impact

| Area | Impact |
|------|--------|
| **Developer time** | Wasted effort following incorrect migration advice |
| **Risk** | Code changes in wrong direction; compile failures discovered late |
| **Scope** | Any .NET project using packages that were rewritten (not just renamed) |
| **Severity** | Medium — no production outage, but misleading guidance |

## Root cause (non-technical)

The audit tool assumed that when a library gets a new version or successor, the internal structure stays the same. This is true for simple upgrades but **not true** when a library is completely rewritten — the old features may move to an entirely different product or be redesigned from scratch.

Think of it like GPS navigation recommending a road that was demolished and replaced with a park. The destination (city) is correct, but the specific route doesn't exist anymore.

## What we fixed

| Change | Purpose |
|--------|---------|
| Added 4-step verification checklist | Forces the tool to confirm the target actually exists before recommending migration |
| Added "known traps" database | Catalogs libraries where this assumption fails (3 known cases so far) |
| Added fallback rule | If migration requires code changes and user says "no code changes", recommend version downgrade instead |
| Added "Phantom Migration" pattern | Documents this failure mode so it's recognized and prevented in future |

## Validation

- Original issue (PTTGC.KBS): fix applied, phantom migration no longer proposed
- Cross-project test (eTCM): tool runs correctly with new verification rules
- New rules integrated into expanded tool scope (.NET Core, .NET 5-10+, Central Package Management)

## What prevented earlier detection

The tool was initially designed for straightforward version conflicts (same library, different versions). The PTTGC.KBS project was the first case where it encountered a library that was **rewritten** rather than simply upgraded. No test coverage existed for this scenario because the tool operates as a prompt-based workflow, not executable code.

## Next steps

| Action | Status |
|--------|--------|
| Verification checklist added | Done |
| Known traps database seeded | Done (3 entries) |
| Expand known traps as new cases emerge | Ongoing |
| Automated testing | Not feasible (prompt-based tool) — validated through real project usage |
