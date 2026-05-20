# Pinball Roguelite -- Project Workflow Guide

> **For: 老李 (Li Lao)**
> **Engine: Godot 4.6 | Genre: Pinball + Roguelite**
> **Last Updated: 2026-05-20**

---

## 项目目录结构

```
pinball-rougelite/
├── assets/                  # 游戏资产
│   ├── art/                 # 美术资产（精灵、模型、纹理）
│   ├── audio/               # 音乐与音效
│   ├── vfx/                 # 粒子与视觉效果
│   ├── shaders/             # Shader 文件
│   └── data/                # JSON/YAML 配置与平衡数据
├── autoload/                # Godot Autoload 脚本（全局单例）
├── config/                  # 游戏配置（格式待定）
├── docs/                    # 文档（Godot 忽略，不进 export）
│   ├── design/              # 设计文档（GDD）
│   │   ├── gdd/             # 游戏设计文档
│   │   │   ├── core-loop.md         # 核心循环（扁平的基础系统）
│   │   │   ├── pinball-physics.md   # 弹珠物理系统
│   │   │   ├── roguelite/           # 复杂系统用独立目录
│   │   │   │   ├── build-system.md
│   │   │   │   ├── encounter.md
│   │   │   │   └── progression.md
│   │   │   └── economy.md
│   │   └── narrative/       # 叙事、剧情、对话设计
│   ├── architecture/         # ADR、技术决策记录
│   ├── engine-reference/    # 版本锁定的引擎 API 参考
│   └── registry/            # TR-ID 注册表等
├── prefabs/                 # 可复用节点树（.tscn）
├── production/              # 生产追踪
│   ├── milestones/          # 里程碑文件（mvp.md, vertical-slice.md, steam-release.md）
│   └── session-logs/       # 会话审查追踪
├── resources/               # Godot .tres 资源文件
├── scenes/                 # 场景文件（.tscn，与对应 .gd 同目录）
├── scripts/                # 非 UI、非 scene、非 prefab 的脚本
│   ├── autoload/           # Autoload 服务（不依赖场景的全局逻辑）
│   ├── core/               # 核心基础设施（事件总线、数据仓库、状态机框架）
│   ├── data/               # 数据类（Resource 子类、配置数据结构）
│   ├── gameplay/           # 游戏玩法逻辑（弹珠物理、肉鸽系统、战斗）
│   └── utils/              # 工具函数（数学库、字符串处理、编辑器工具）
└── ui/                     # UI 相关（与 scenes 并列）
    └── *.tscn / *.gd       # UI 场景与对应脚本同目录
```

**核心原则：**
- `.tscn` 与对应 `.gd` **同目录**，不拆分到 `scripts/`
- `scripts/` **不放 UI 脚本和场景脚本**，只放纯逻辑
- `docs/` 有 `.gdignore`，不参与 Godot export
- `assets/data/` 存放游戏数据配置（JSON/YAML），逻辑层通过 `ConfigLoader` 读取，不硬编码路径

---

## Phase 0: 目录初始化

新项目创建后，按以下顺序初始化目录（按需创建，不用一步到位）：

```
Phase 0 不是开发阶段，而是确保项目骨架就绪再开工。
```

| 目录 | 创建时机 | 说明 |
|------|---------|------|
| `docs/design/gdd/` | Phase 1 开始前 | GDD 的容器 |
| `scripts/core/` | Phase 3 开始前 | 等确定好核心框架再动手 |
| `scripts/autoload/` | Phase 3 Autoload 配置后 | 全局服务 |
| `production/milestones/` | 任何时候 | 里程碑追踪 |
| `assets/data/` | 平衡数据开始前 | 数值配置 |

---

## Phase 1: Concept（概念）

### 目标

定义游戏是什么、为什么值得做、核心体验是什么。

### 流程

```
/brainstorm  -->  game-concept.md  -->  /setup-engine  -->  /map-systems
```

**Step 1.1 — 头脑风暴**

```
/brainstorm
```

引导式 ideation 流程，生成 10 个概念候选 → 深度分析 → 确定最终概念。

**Step 1.2 — 编写概念文档**

输出：`docs/design/gdd/game-concept.md`

包含：
- 一句话电梯演讲
- 核心幻想（玩家在想象中做什么）
- MDA 解析
- 目标用户
- 核心循环图
- 独特卖点
- 参考游戏与差异化
- 游戏支柱（3-5 个不可妥协的设计价值）
- 反支柱（刻意避免的东西）

**Step 1.3 — 确定引擎**

```
/setup-engine godot 4.6
```

输出：`.claude/docs/technical-preferences.md`（命名规范、性能预算、引擎默认值）。

**Step 1.4 — 系统映射**

```
/map-systems
```

输出：`docs/design/gdd/systems-index.md` — 全部系统清单、依赖关系、优先级分层。

### Gate

```
/gate-check concept
```

通过标准：
- `game-concept.md` 存在且包含支柱
- `systems-index.md` 存在且包含依赖排序

---

## Phase 2: Systems Design（系统设计）

### 目标

每个系统都有完整的设计文档（GDD），定义它**怎么做**，但不写代码。

### 流程

```
/map-systems next  -->  /design-system  -->  /design-review
```

**GDD 组织原则：**
- **基础系统**（核心循环、弹珠物理）：扁平的 `docs/design/gdd/[system-name].md`
- **复杂系统**（肉鸽 build、遭遇、成长）：独立目录 `docs/design/gdd/[system-name]/`

**Section-by-Section 协作流程（来自 COLLABORATIVE-DESIGN-PRINCIPLE）：**

每个 GDD 分 8 个 section，每个 section 都遵循：

```
问题 → 选项（含分析）→ 决策 → 起草 → 审批 → 写入文件
```

每个 section 写完即写入文件，不要等全部写完再存盘。

**8 个必写 Section：**

| # | Section | 内容 |
|---|---------|------|
| 1 | Overview | 一段式系统概述 |
| 2 | Player Fantasy | 玩家使用时想象/感受到的东西 |
| 3 | Detailed Rules | 无歧义的机械规则 |
| 4 | Formulas | 每个计算公式，变量定义和范围 |
| 5 | Edge Cases | 异常情况处理，明确解决 |
| 6 | Dependencies | 双向依赖（其他系统↔本系统） |
| 7 | Tuning Knobs | 可安全调整的值及安全范围 |
| 8 | Acceptance Criteria | 如何测试系统工作，可测量 |

**GDD 内置 Game Feel 描述**：手感参考、输入响应（ms/帧）、动画手感目标（启动/激活/恢复）、冲击时刻、重量曲线。

**交叉 GDD 一致性审查**

所有 MVP 系统 GDD 完成后：

```
/review-all-gdds
```

同时读取所有 GDD，检查：
- 依赖双向性（系统 A 引用 B，B 是否也引用 A？）
- 规则矛盾
- 公式范围兼容性
- 难度曲线一致性

### Gate

```
/gate-check systems-design
```

通过标准：
- 所有 MVP 系统 GDD 状态为 `Approved`
- 交叉 GDD 审查报告存在， verdict 为 PASS 或 CONCERNS

---

## Phase 3: Technical Setup（技术架构）

### 目标

关键技术决策落地为 ADR，建立控制清单，给程序员清晰的规则。

### 流程

```
/create-architecture  -->  ADR(x N)  -->  /architecture-review
        |                                        |
        v                                        v
  架构主文档                              验证完整性、依赖排序、
  docs/architecture/                    引擎兼容性
  architecture.md
        |
        v
  /create-control-manifest
        |
        v
  控制清单 docs/architecture/control-manifest.md
```

**必须完成的 3 个 Foundation 层 ADR：**
- 场景/节点架构（scene tree 结构、场景间数据流）
- 状态管理（Autoload vs 局部状态 vs Resource）
- 物理/弹珠系统集成方式（Jolt Physics 参数配置）

**Control Manifest** 是给程序员的扁平规则表：Required / Forbidden / Guardrails，按代码层组织。

### Gate

```
/gate-check technical-setup
```

通过标准：
- `docs/architecture/architecture.md` 存在
- 至少 3 个 ADR 已 Accept
- `docs/architecture/control-manifest.md` 存在

---

## Phase 4: Pre-Production（预生产）

### 目标

核心循环可玩，验证游戏**有趣**。

### 流程

```
/ux-design  -->  /prototype  -->  /create-milestones  -->  Vertical Slice
```

**Step 4.1 — UX Specs（仅关键界面）**

对于有 UI 的系统：
```
/ux-design core-gameplay-hud
```

不追求覆盖所有界面，只做**核心 UI** 的 spec（主游戏 HUD、暂停菜单、局运 Build 选择界面）。

**Step 4.2 — 原型（按需）**

不是所有系统都需要原型。原型针对：
- 不确定是否有趣的机制
- 不确定是否可行的技术方案
- 两个设计方案都看起来可行，需要感受差异

```
/prototype "弹珠与肉鸽 build 的耦合方式"
```

原型在隔离的 git worktree 中进行，不污染主代码。

**Step 4.3 — 里程碑定义**

```
/create-milestones
```

在 `production/milestones/` 下创建里程碑文件：
- `mvp.md` — 最小可玩产品（核心弹珠循环 + 一个肉鸽元素）
- `vertical-slice.md` — 完整核心循环可玩，品质达标
- `content-brief.md` — 内容规模确定（多少个 encounter、relic、bonus）
- `steam-release.md` — Steam 上线版本

每个里程碑包含：目标描述、验收标准、当前状态。

**Step 4.4 — Vertical Slice（硬性门槛）**

在进入 Phase 5 之前，必须完成：

- 核心循环从头到尾可玩
- 至少 3 次无引导会话
- 撰写 playtest 报告

### Gate

```
/gate-check pre-production
```

通过标准：
- 核心游戏 HUD UX spec 存在
- 至少 1 个原型有 README
- Vertical Slice 可玩并有 playtest 报告

---

## Phase 5: Production（生产）

### 目标

实现所有设计，按里程碑推进，直到内容完备。

### 流程

```
story-by-story 实现  -->  /story-done  -->  milestone 审查  -->  下一 milestone
```

**Story 实现流程：**

```
/story-done production/stories/[name].md
```

实现前验证 story 完备性（design-complete、architecture-covered、scope-clear）。

每个 story 完成后：
- 代码审查
- 偏差检查（是否偏离 GDD/ADR）
- 更新 story 状态

**不要引入 formal sprint 体系**（单人不需 sprint planning）。用 milestone 驱动即可。

**多系统特性使用 Team Skill：**

```
/team-combat "ball bumper 碰撞效果"
/team-ui "build selection screen"
```

**Design Change 传播：**

GDD 变更后：

```
/propagate-design-change docs/design/gdd/roguelite/build-system.md
```

审计受影响的故事和 ADR，生成影响报告。

### Gate

```
/gate-check production
```

通过标准：
- MVP milestone 达成
- Vertical Slice milestone 达成
- 至少 3 次覆盖不同阶段的 playtest

---

## Phase 6: Polish（打磨）

### 目标

游戏好玩，现在让它**感觉好**。

### 流程

```
/perf-profile  -->  /balance-check  -->  /playtest-report(x3)  -->  /team-polish
```

- 性能 profiling：CPU/GPU/内存瓶颈
- 平衡公式审查
- 3 次 playtest 覆盖：新手体验、中期系统、难度曲线
- 协调打磨：性能 + 美术 + 音频 + UX

### Gate

```
/gate-check polish
```

通过标准：
- 至少 3 份 playtest 报告
- 无阻塞性性能问题
- Accessibility 目标达成

---

## Phase 7: Release（发行）

### 目标

上线 Steam。

### 流程

```
/release-checklist v1.0.0  -->  /launch-checklist  -->  Steam 上线
```

- `msteam-release.md` 里程碑更新为 DONE
- 补丁说明生成
- 上线后记录 post-mortem

---

## 协作设计原则（必须遵循）

**核心哲学：** Agent = 专家顾问，User = 创意总监（最终决策者）

**每个 Agent 交互必须遵循：Question → Options → Decision → Draft → Approval**

禁止：
- Agent 自主生成设计并写入
- Agent 未经审批写入代码
- Agent 未经提问直接做决策

**文件写入协议：**

```
1. Agent: "已完成 [设计/代码]。摘要：[要点]。
           可以写入 [filepath] 吗？"
2. User: "可以" 或 "不行，先改 X"
3. IF "可以"：Agent 使用 Write/Edit 工具写入文件
   IF "不行"：Agent 修改后回到步骤 1
```

**增量写入规则：**

多 section 设计文档，每个 section 审批后**立即写入文件**，不要在对话里积压全部内容后再存盘。

详见 `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md`。

---

## 附录 A：目录结构说明

| 目录 | 放什么 | 不放什么 |
|------|--------|---------|
| `scenes/` | 游戏场景 .tscn + 同目录 .gd | UI 场景（去 `ui/`）、预制体（去 `prefabs/`）|
| `ui/` | UI 场景 .tscn + 同目录 .gd | 游戏逻辑脚本（去 `scripts/`）|
| `scripts/` | 纯逻辑脚本（core/gameplay/data/utils/autoload）| .tscn、.gd UI 脚本、场景拥有脚本 |
| `prefabs/` | 可复用的节点树定义（.tscn）| 场景实例（去 `scenes/`）|
| `resources/` | Godot .tres 资源文件 | 配置数据（去 `assets/data/`）|
| `assets/data/` | JSON/YAML 数值配置 | 代码（代码读配置，不放配置放代码）|
| `docs/design/gdd/` | GDD 文件 | 代码、技术文档（去 `docs/architecture/`）|

**命名对齐原则（来自 user-programming-habits）：**
- 一个概念 → 一个名字：文件名校名 = 节点名 = `class_name`
- 例外：role-specific scene（如 `ball_preview.tscn`）用不同 use case 名称

---

## 附录 B：GDScript 文件头顺序

新建或显著改写脚本时，文件顶部顺序：

```gdscript
extends Node3D

class_name PinballBall

## 弹珠球的物理与碰撞逻辑，管理速度、加速度、边界反弹。

# === Constants ===
# === Signals ===
# === Public Variables ===
# === Private Variables ===
# === Built-in Callbacks ===
# === Public Methods ===
# === Private Methods ===
```

`extends` → `class_name`（需要时）→ 空行 → `##` 职责说明 → 空行 → 分组注释 → 内容。

---

## 附录 C：Agent 快速索引

| 需求 | Agent | Tier |
|------|-------|------|
| 设计弹珠物理系统 | `game-designer` | 2 |
| 设计肉鸽 build 系统 | `systems-designer` | 3 |
| 实现玩法代码 | `gameplay-programmer` | 3 |
| 实现核心框架 | `engine-programmer` | 3 |
| Godot 特定问题 | `godot-specialist` | 3 |
| GDScript 代码审查 | `godot-gdscript-specialist` | 3 |
| UI 实现 | `ui-programmer` | 3 |
| 性能优化 | `performance-analyst` | 3 |
| 技术决策 | `technical-director` | 1 |
| 规划里程碑 | `producer` | 1 |

详细索引和完整 Phase 说明见 `.claude/docs/agent-roster.md`。
