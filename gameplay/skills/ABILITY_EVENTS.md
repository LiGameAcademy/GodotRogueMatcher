# O4 / #60: In-run events and conditions

Target branch `feature/skill-refactor`, feature branch `feat/issue-60-ability-events`.
Migrates existing core/fuse removal blasts; keeps the 40-item runtime catalog, numbers, match, and refill rules.

## Configuration and state

Ability definitions use `event_type`, `conditions`, `max_triggers`, and `consume_on_empty`.
`on_eliminated_explosion.tres` listens for `piece_eliminated`, allows causes `match` / `explosion` / `skill_clear` / `consume`, and fires at most once.
`RemovalCauseCondition` limits `consume` to cores; cleanup and retry do not detonate.
`AbilityDefinition.trigger` and the GameplayTrigger execution path are removed; counts are no longer incremented when an event is merely accepted.

Conditions still reuse CoreSystem read-only `TriggerCondition` contracts, without activating GameplayTrigger or connecting TriggerManager.
Supported leaves: `AlwaysAbilityCondition`, event type, removal cause, and `CompositeTriggerCondition`:
AND = all, OR = any, single-child NOR = not. Evaluation short-circuits in configured order.
An empty condition array means no extras; empty composites, missing children, cycles, nesting beyond 8, negative limits, and unknown events/causes/conditions are rejected with diagnostics.
Probability and timer plugin conditions are not wired and are rejected so shared counters and global RNG cannot affect rules.

## Dispatch and application

`RunState` owns `AbilityEvents`. Callers pass the authoritative run-instance listener set for the batch; there is no second registry.
After a full removal batch, sources are frozen and dispatched, then the existing blast queue runs descendants. Effects are not executed recursively from dispatch.
Events sort by generation / source id / event id; listeners sort by owner id / install order / ability id. Duplicate instance identities are rejected.
The blast queue still processes descendants by generation / source id; plant, mine, aftershock, and dye keep their previous settle boundaries.

`AbilityEvent` carries a unique in-run event id, run id, root action, generation, cause, source snapshot, and optional parent event / source ability id.
Removal event ids and ScoreLedger score event ids are numbered separately and must not be mixed; dispatch order follows the rules above.
First-generation match/clear uses `parent_event_id = 0`; explosion descendants reference their removal trigger event.
Synthetic aftershock is not yet a normal ability event, so no fake removal parent is invented; the source-ability mark remains.

`dispatch` only builds `AbilityActivation` tickets and sets `pending_event_id`; it does not consume charges.
The resolver calls `complete` after committing effects: rejects do not consume; legal empty results follow `consume_on_empty`.
Existing blast content keeps `consume_on_empty = true`; empty blasts still score 0, and manual empty detonation still costs the core and one action.
Duplicate events or duplicate ticket completions never re-run or re-consume; a pending instance cannot enqueue again.
Preflight happens before occupancy/score commits; post-commit internal errors enter `ERROR` explicitly with no arbitrary rollback promise.

Retry closes the old `AbilityEvents` and builds a new one; the run identity token invalidates old events and unfinished tickets.
Definitions stay read-only, counts stay exclusive to `AbilityInstance`, and the dispatcher keeps no cross-run subscriptions or scene nodes.

## Recording, scope, and acceptance

Rules version is `run-commands-v18-ability-events`, recording condition config, consume policy, event ids / dedupe state, and pending ids.
v17 and earlier commands are not recomputed across versions; historical telemetry files are kept. Current records still exact-replay; old play sessions need not be re-run.
Acquire/upgrade still uses the #59 directed ChoiceEffect path; this slice does not broadcast acquire facts or add new skills / full timing coverage.
Generic leaf requests and ordered Effect composition: see `EFFECT_COMPOSITE.md` (#61). Full skill migration to #62; detailed trigger tooling to #63.

Primary acceptance scripts: `tests/rules/test_ability_events.gd`, `test_ability_triggers.gd`, `test_explosion_rules.gd`.
Godot 4.7.2: 13 related scripts, 112 tests / 2283 asserts, log `.godot/issue60-regression.log`.
Coverage includes duplicate event/ticket, legal empty and failed consume policy, snapshots, stable ordering, All/Any/Not, invalid config, retry isolation, real manual empty detonation, plus prior blast/stage/preview/bot-window/replay/card regressions.
Script and Resource import passed; no Web export or numeric analysis. Author playtest remains for review.
Authors can playtest core five-match, fuse chains, manual empty detonation, and restart; a new run must not inherit fuses, upgrades, or stale tickets.
Suggested reading order: AbilityDefinition → AbilityTriggerAdapter (query only) → AbilityEvents (dispatch/consume) → AbilityResolver (rule commit).
