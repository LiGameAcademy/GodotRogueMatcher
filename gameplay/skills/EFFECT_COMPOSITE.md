# O4 / #61: Ordered Effect composition

Target branch `feature/skill-refactor`, feature branch `feat/issue-61-effect-composite`.
Unifies acquire effect application through `AbilityEffectRunner` and adds `CompositeEffect`.

## Contract

- `SkillEffect` is the read-only root type. `ChoiceEffect` and `ExplodeEffect` are leaves; `CompositeEffect` nests `SkillEffect` children in array order.
- Leaf1 commits and updates authoritative state before leaf2 freezes/builds. Offer-time freeze is preview; leaves after index 0 reselect at apply.
- `CLEAR` inside a composite holds blast descendants via `AbilityResolver.resolve_removal(..., hold_blasts=true)` until the composite flushes once.
- `fixed_target_policy`: `REJECT` (default) fails the acquire before mutation when leaf0 preflight fails; `SKIP_INVALID` drops dead fixed piece ids and may yield a legal empty clear/dye leaf.
- No new `skill_id` branches. Acceptance skills are ordinary `SkillDefinition` + `SkillLevelDefinition` resources or test fixtures.
- Rules version: `run-commands-v19-effect-composite`. Older recordings are not recomputed across versions.

## Scope

In this slice: acquire composites of existing choice leaves (e.g. Refill+ColorWeight, Clear+Dye). Removal stays single `ExplodeEffect` (`on_eliminated_explosion.tres`). Full catalog migration is #62.

## Catalog composite cards

| Resource | Skill id | Order |
| --- | --- | --- |
| `gameplay/progression/content/composite_refill_color.tres` | `composite_refill_color` | Refill −1 (3 batches) → color weight +2 |
| `gameplay/progression/content/composite_clear_dye.tres` | `composite_clear_dye` | Color clear (includes fuses) → dye survivors; blasts flush after dye |

Kept in the runtime catalog with normal offer weights (#64). For fuse deferral: take `assign_fuse` first, then **清色后染**.

## Reading order

`SkillEffect` → `CompositeEffect` → `AbilityEffectRunner` → `SkillRules.apply` → `AbilityResolver` hold/flush.
