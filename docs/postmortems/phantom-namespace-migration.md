# Post-Mortem: Phantom Namespace Migration ใน nuget-audit Skill

**Commit**: `a26a318` — fix: add namespace verification rules and phantom migration pattern
**Owner**: Napat Sangsong
**โปรเจคที่ได้รับผลกระทบ**: PTTGC.KBS

---

## Summary

Skill `/nuget-audit` เสนอให้ migrate namespace จาก `OfficeDevPnP.Core.Pages` ไปเป็น `PnP.Framework.Pages` โดยไม่ได้ตรวจสอบว่า namespace ปลายทางมีอยู่จริงหรือไม่ — ผลคือแนะนำ `using PnP.Framework.Pages;` ที่ **ไม่มีอยู่ในแพ็คเกจจริง** ทำให้ผู้ใช้เสียเวลาแก้โค้ดไปในทิศทางที่ผิด แก้ไขโดยเพิ่ม verification checklist บังคับตรวจสอบก่อนเสนอ namespace migration ทุกครั้ง และเพิ่ม pattern "Phantom namespace migration" เป็นกรณีศึกษาใน skill

---

## Symptom

เมื่อรัน `/nuget-audit` บนโปรเจค PTTGC.KBS ที่ใช้ `OfficeDevPnP.Core` บน .NET Framework 4.8 — skill ตรวจพบว่า `OfficeDevPnP.Core` เป็น deprecated package และเสนอให้ migrate ไป `PnP.Framework` ซึ่งเป็น successor ที่ถูกต้อง

แต่ skill ไปไกลกว่านั้น — เสนอให้เปลี่ยน:
```csharp
using OfficeDevPnP.Core.Pages;
// เป็น
using PnP.Framework.Pages;
```

ปัญหาคือ `PnP.Framework.Pages` **ไม่มีอยู่จริง** Pages API ถูกย้ายไป PnP.Core SDK ทั้งหมด โดยใช้ `IPage` interface ซึ่งเป็น API ที่แตกต่างอย่างสิ้นเชิง ไม่ใช่แค่เปลี่ยน namespace

---

## Root Cause

สาเหตุรากเหง้าอยู่ที่ `skills/engineering/nuget-audit/SKILL.md` ใน Phase 6 (Fix) — skill มีกฎ "ห้ามแก้ไฟล์ `.cs`" แต่ **ไม่มีกฎตรวจสอบว่า namespace ปลายทางมีอยู่จริงก่อนเสนอ migration**

กลไกที่ทำให้เกิด bug:

1. Skill ตรวจพบ deprecated package (`OfficeDevPnP.Core`)
2. Skill รู้ว่า successor คือ `PnP.Framework` (ข้อมูลถูกต้อง)
3. Skill **สมมติ** ว่า namespace structure ของ successor จะ mirror กับ original — เช่น `OfficeDevPnP.Core.Pages` → `PnP.Framework.Pages`
4. ไม่มีขั้นตอนใดใน workflow ที่บังคับให้ตรวจสอบว่า namespace ปลายทางมีอยู่จริง (เช่น เช็ค GitHub source tree, เช็ค NuGet package contents, เช็ค GitHub issues)
5. ผลลัพธ์: เสนอ migration ไปหา namespace ผี — "Phantom namespace migration"

ปัญหาเดียวกันนี้จะเกิดซ้ำได้กับ package อื่นที่ถูก rewrite ครั้งใหญ่ เช่น:
- `Microsoft.Graph` 1.x-4.x → 5.x+ (Kiota rewrite)
- `System.Web.Http` → `Microsoft.AspNetCore.Mvc`
- `Swashbuckle.AspNetCore` → `Microsoft.AspNetCore.OpenApi`

---

## ทำไมถึงแสดงอาการแบบนี้

Bug อยู่ที่ขั้นตอน "เสนอ fix" (Phase 6) แต่อาการที่ผู้ใช้เห็นคือ "คำแนะนำที่ผิด" — ซึ่งดูเหมือนเป็น output ที่สมเหตุสมผลเพราะ:

- `PnP.Framework` **เป็น** successor ของ `OfficeDevPnP.Core` จริง (ข้อมูลนี้ถูก)
- ชื่อ namespace ดู "สมเหตุสมผล" ตาม pattern ทั่วไป (OldLib.X → NewLib.X)
- ผู้ใช้ที่ไม่ได้ตรวจสอบเองจะเชื่อคำแนะนำและเริ่มแก้โค้ด

นั่นคือสิ่งที่ทำให้ bug นี้อันตราย — ไม่มี error, ไม่มี crash, แค่ **คำแนะนำที่ดูน่าเชื่อแต่ผิด** ผู้ใช้จะรู้ตัวก็ต่อเมื่อ compile แล้วไม่ผ่าน หรือค้นหา class แล้วหาไม่เจอ

---

## Fix

**Commit `a26a318`** เพิ่มสองส่วนเข้าไปใน `skills/engineering/nuget-audit/SKILL.md`:

### 1. CRITICAL verification checklist (Phase 6, หลังกฎ binding redirect)

บังคับให้ตรวจสอบ 4 ขั้นตอนก่อนเสนอ namespace migration ทุกครั้ง:
1. เช็ค NuGet package page สำหรับ DLL contents จริง
2. เช็ค GitHub source สำหรับ namespace directory ที่แน่นอน
3. เช็ค GitHub issues สำหรับรายงาน migration ที่ล้มเหลว
4. WebFetch URL จริงเพื่อยืนยันว่า namespace/class มีอยู่ (404 = ไม่มี)

เพิ่ม known traps ที่จะ migrate ไม่สำเร็จ:
- `OfficeDevPnP.Core.Pages` → `PnP.Framework.Pages` (ไม่มี)
- `Microsoft.Graph` 1.x-4.x → 5.x+ (Kiota rewrite)
- `System.Web.Http` → `Microsoft.AspNetCore.Mvc` (framework ต่างกันสิ้นเชิง)

เพิ่มกฎ fallback: ถ้า migration ต้องแก้โค้ดและผู้ใช้บอกว่า "ไม่แก้โค้ด" → ให้เสนอ version downgrade แทน

### 2. Pattern: Phantom namespace migration (Common Patterns section)

เพิ่ม pattern ใหม่ที่อธิบาย:
- **อาการ**: เสนอ `using OldLib.Namespace;` → `using NewLib.Namespace;` แต่ namespace ใหม่ไม่มีอยู่
- **สาเหตุ**: successor package ถูก restructure หรือ remove API ทั้งหมด
- **การป้องกัน**: verification chain 4 ขั้นตอน
- **ตัวอย่าง**: `PnP.Framework.Pages.ClientSidePage` ไม่มี → ใช้ version downgrade แทน

### ทำไม fix นี้แก้ root cause ไม่ใช่แค่ซ่อนอาการ

Fix ก่อนหน้า (ถ้ามี) อาจแค่เพิ่ม `PnP.Framework.Pages` เข้า blocklist แต่ fix นี้แก้ที่ **กระบวนการ** — บังคับให้ตรวจสอบ **ทุก** namespace migration ไม่ใช่แค่กรณีที่รู้แล้ว ทำให้ป้องกัน phantom migration ได้กับทุก package ในอนาคต

---

## วิธีที่ค้นพบ

1. **Repro**: รัน `/nuget-audit` บนโปรเจค PTTGC.KBS ที่ใช้ `OfficeDevPnP.Core` กับ .NET Framework 4.8 — skill เสนอ migrate ไป `PnP.Framework.Pages`
2. **ตรวจสอบ**: WebFetch GitHub source tree ของ PnP.Framework → ไม่มี directory `Pages/` → 404
3. **ค้นหา GitHub issues**: พบรายงานว่า Pages API ย้ายไป PnP.Core SDK ทั้งหมด ใช้ `IPage` interface แทน `ClientSidePage` class
4. **ยืนยัน root cause**: ตรวจสอบ SKILL.md — ไม่มีขั้นตอนตรวจสอบ namespace ก่อนเสนอ migration แม้แต่ขั้นตอนเดียว

**Hypothesis ที่ถูกปฏิเสธ:**
- "อาจเป็นเพราะใช้ข้อมูล successor package ผิด" → ไม่ใช่ — `PnP.Framework` เป็น successor จริง แต่ namespace structure ต่างกัน
- "อาจเป็น edge case เฉพาะ PnP" → ไม่ใช่ — ปัญหาเดียวกันเกิดได้กับทุก package ที่ถูก rewrite (Microsoft.Graph, etc.)

---

## ทำไมถึงหลุดไปได้

**ช่องว่างใน skill design** — Skill ถูกออกแบบมาโดยมี assumption ว่า "successor package = same namespace structure" ซึ่งเป็นจริงในหลายกรณี (เช่น package ที่แค่เปลี่ยนชื่อ) แต่ไม่จริงเมื่อ package ถูก **rewrite** ทั้งหมด

ไม่มี validation step ใน workflow ที่จะจับ assumption นี้ได้ เพราะ:
- Skill เป็น prompt-based (SKILL.md) ไม่มี automated test
- ไม่มี "known traps" database ที่จะ flag กรณีที่ namespace migration จะล้มเหลว
- กฎ "ห้ามแก้ไฟล์ .cs" ทำให้ดูเหมือนว่า namespace migration เป็น "config-only" change ที่ปลอดภัย — แต่จริงๆ แล้วการเสนอ namespace ที่ไม่มีอยู่จะทำให้ผู้ใช้ต้องแก้โค้ดอยู่ดี (และแก้ไปในทิศทางที่ผิด)

**Blameless**: นี่คือ design gap ไม่ใช่ oversight — กรณี PnP.Framework.Pages เป็นกรณีแรกที่ skill เจอ successor package ที่ restructure API ทั้งหมด

---

## Validation

- **กฎ verification ใหม่ถูกเพิ่มใน SKILL.md**: ทุก namespace migration ต้องผ่าน 4-step verification chain ก่อนเสนอ
- **Known traps ถูกเพิ่ม**: `PnP.Framework.Pages`, `Microsoft.Graph` 5.x+, `System.Web.Http` → `Microsoft.AspNetCore.Mvc`
- **Pattern "Phantom namespace migration" ถูกเพิ่ม**: เป็น reference สำหรับ AI agent ที่รัน skill ให้รู้จักและป้องกัน pattern นี้
- **Commit `b0254e5` (ถัดไป) ขยาย skill ให้รองรับ .NET Core/5+/CPM**: เป็นการยืนยันว่า fix ใน `a26a318` ถูกรวมเข้ากับ expanded skill ได้อย่างถูกต้อง รวมถึงเพิ่ม `Swashbuckle.AspNetCore` → `Microsoft.AspNetCore.OpenApi` เข้า known traps

**ตรวจสอบกับโปรเจคจริง**: ทดสอบรัน `/nuget-audit` กับโปรเจค eTCM — skill ทำงานได้ถูกต้อง ไม่เสนอ phantom namespace migration และ verification checklist ทำงานตามที่ออกแบบไว้

**ขอบเขตที่ตรวจสอบ**: SKILL.md content + ทดสอบจริงกับโปรเจค eTCM — ไม่มี automated test สำหรับ skill เนื่องจากเป็น prompt-based instruction ไม่ใช่ executable code

---

## Action Items / Follow-ups

- **Known traps database**: เพิ่ม package อื่นที่มี namespace restructure เข้า known traps เมื่อพบเคสใหม่ (Owner: Napat, ongoing)
- **กฎ fallback ถูกเพิ่มแล้ว**: "ถ้า migration ต้องแก้โค้ดและผู้ใช้บอก no code changes → เสนอ version downgrade" (เสร็จแล้ว, commit `a26a318`)
- **ไม่มี automated test**: Skill เป็น prompt-based — ไม่สามารถเขียน unit test ได้ การตรวจสอบต้องทำผ่าน manual review หรือ integration test กับโปรเจค .NET จริง
