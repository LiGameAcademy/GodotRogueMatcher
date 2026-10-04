# User programming habits — project_minimal_storm

> **同步**：Cursor 侧镜像：`.cursor/skills/user-programming-habits/SKILL.md`。

Use this skill when working in this repo so implementation matches the maintainer’s conventions. **Extend this file over time** when new preferences are stated explicitly.

## Naming alignment

- Prefer **one concept → one name** across: PackedScene file name, scene root node name, script file name, and `class_name` (when used).
- Example target: `building_instance.tscn` + root `BuildingInstance` + `building_instance.gd` + `class_name BuildingInstance` (only if that class is the single owner of the concept; see Data vs node below).
- Exceptions are allowed for **role-specific scenes** (e.g. `building_preview.tscn`) when the name expresses a different **use case**, not a different domain type.

## Architecture preferences (confirmed)

- **Composition over inheritance** for visuals: instance root vs `BuildingView` vs `VisualRoot` vs `building_visuals/*.tscn`.
- **Data as truth**: definable gameplay data in `.tres` / resources; avoid hardcoded paths in business logic; registry/repository where appropriate.
- **Logic vs presentation**: simulation/rules separate from meshes and input feedback where practical.
- **Scene template first**: prefabs under `prefabs/`, scripts under `scripts/`, data under `data/`.
- **Teaching-oriented**: keep runnable demos; note at least one failure/recovery path when relevant.
- **跨系统编排**：需要同时协调网格、相机、校验、管理器、预览实例的流程（例如建筑摆放），放在专用 **Controller / Service** 节点或 RefCounted 服务中；**`BuildingNode` 只代表世界中已存在的一栋建筑**，不负责全局摆放状态机。

## Data object vs scene node (Building example)

- **RefCounted (or small Resource) “runtime record”**: id, defs reference id, tile_id, state flags, workers — **no** `Node` API, **no** transform. Good for managers, save/load, tests.
- **Node3D “instance root”**: world transform, children for view/collision/audio — **references** the runtime record by id (or carries duplicated fields if the project later chooses a single Node-only entity).
- If two types coexist, **avoid the same `class_name` for both**. Rename the data type (e.g. `BuildingRuntimeData`, `BuildingRecord`) or the node (e.g. keep `BuildingNode`) so names encode **role**, not duplicate domain wording.

## Collaboration

- Follow repo `CLAUDE.md` / `docs/agent_collaboration_protocol.md`: question → options → decision → draft → approval for broad changes; avoid drive-by refactors.

## GDScript 文件头顺序

- 新建或显著改写脚本时，文件顶部顺序固定为：
  1. `extends ...`
  2. `class_name ...`（需要时；不需要则省略）
  3. 空行
  4. `## ...` 一两句职责说明（优先中文）
- `class_name` 与 `extends` 之间不留空行；说明与 `class_name`（或 `extends`）之间空一行。

## Language / docs

- User-facing explanations: **中文** unless asked otherwise.
- Tutorial markdown: 老李游戏学院标题与格式约定（见 CLAUDE.md 用户规则摘要）。

## Changelog (maintainer fills)

- 2026-04-22: Initial skill — naming unity, composition, data vs node split, collaboration.
- 2026-04-22: Documented Cursor mirror path `.cursor/skills/user-programming-habits/SKILL.md`.
- 2026-04-22: GDScript 文件头顺序 — `extends` → `class_name`（可选）→ 空行 → `##` 说明。
