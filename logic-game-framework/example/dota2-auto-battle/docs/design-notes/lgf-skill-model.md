# LGF Skill Model For Dota2 Auto Battle

Status: design draft. M1 basic attack is intentionally Ability-backed from the
first battle implementation.

This note depends on the tick model and logic/view contract. Do not implement
skills before the single-threaded fixed-tick clock boundary and read-only
frontend boundary are agreed.

## Framing

DOTA2 has three different kinds of "things units do":

1. future player/debug requests: move, attack target, stop, cast;
2. autonomous controller behavior: lane march, acquire target, chase, attack;
3. authored abilities: basic attack timing, passives, buffs, DOT/HOT, projectiles,
   active hero skills, auras, modifiers.

The first version should not force every continuous behavior into LGF Ability.
However, any effect that needs event recording, passive reactions, periodic ticks,
or replay-visible combat state should eventually pass through LGF-style
Ability/Action/Event boundaries.

## Useful Hex ATB Lessons

From `hex-atb-battle`, keep these ideas:

- Ability decides the configured capability.
- AbilityComponent/Timeline decides when actions fire.
- Action performs the atomic state mutation.
- Event records what happened for frontend/replay/passive reactions.
- AI strategy is stateless and returns intent.
- Actor owns runtime identity/state such as team, position, target, cooldown, and
  tags.
- AttributeSet owns runtime stats such as HP, attack damage, attack range, and
  move speed, but stats live on the correct typed AttributeSet family member
  rather than one unit-only bag.

Do not keep these hex-specific ideas:

- ATB charge as the main action gate.
- Hex grid targeting as the default range model.
- Full battle pre-simulation before frontend playback.

## First-Version Skill Split

### Basic Attack

Decision: basic attack is an LGF Ability from M1.

- `Dota2LaneCreepController` can choose a persistent `AttackTargetIntent`.
- movement execution advances chase/stop until the target is in range.
- `AbilitySet` requests/advances `Dota2BasicAttackAbility` when range and
  target validity allow it.
- Timeline models at least the attack point; backswing/projectile timing can be
  added without changing the intent contract.
- `Dota2DamageAction` applies damage and death.
- Events are emitted for attack start / attack hit / damage / death.
- Cooldown and cast timing are Ability/AbilitySet execution state, not ad hoc
  controller state.
- Combat reads damage/range/timing stats from the relevant typed
  `actor.attribute_set`, not from actor forwarding getters. Unit and tower attack
  stats may live on different AttributeSet subclasses.

First-version timeline can be minimal, but the boundary should already be the
final one:

```text
AttackTargetIntent
  -> Dota2BasicAttackAbility
    -> attack_started event
    -> attack_point keyframe
      -> Dota2DamageAction
      -> attack_landed / damage_applied / unit_died events
```

Attack modifiers hook through pre/post damage events. Projectile attacks can
later launch a projectile event before hit resolution.

### Passive And Modifier Effects

Passives should not become ad hoc if branches in Procedure. They should be
represented as abilities, tags, event handlers, or modifier objects attached to
the actor's AbilitySet.

Examples:

- lifesteal listens to post-damage and emits heal,
- thorns listens to post-damage and emits reflected damage,
- slow applies a tag/modifier that movement reads through attributes,
- poison is a timed ability with repeated damage tags.

Attribute-modifying effects should modify AttributeSet values/modifiers. They
should not patch actor fields directly.

Tower/building modifiers follow the same rule: backdoor protection, glyph-like
states, tower damage changes, and tower attack speed changes should be modeled
through AbilitySet tags/modifiers and the tower/building AttributeSet family, not
as one-off fields on `Dota2TowerActor`.

### Active Hero Skills

Not in M1/M2. When added, active skills should use the same LGF shape as hex:

- a future `PlayerController` or unit controller selects a persistent
  `CastAbilityIntent`;
- condition/cost decide whether activation is legal,
- timeline models cast point / projectile launch / hit / end,
- actions mutate state,
- events feed frontend effects.

## Remaining Skill Questions

- What is the minimum `AbilitySet` setup needed for a lane creep that only has
  `Dota2BasicAttackAbility`?
- How small can the first basic-attack Timeline be while still preserving the
  future cast point / backswing / projectile path?
- How should future player cast requests interact with autonomous controller
  state: override, fail while busy, or use a later queued-command model?
- What is the minimum event vocabulary for frontend debug panels:
  `attack_started`, `attack_landed`, `damage_applied`, `heal_applied`,
  `unit_died`, `modifier_added`, `modifier_removed`?

## Initial Recommendation

Start narrow:

- M1/M2: basic attack uses `AbilitySet` + `Dota2BasicAttackAbility` + Timeline
  + Action + Events.
- Actor still owns an AbilitySet so future passive/active abilities have a home.
- `CastAbilityIntent` is only a request; actual legality and execution remain in
  `AbilitySet`.
- Do not use Timeline for lane march or chase.
- Use Timeline only when timing is authored behavior, such as attack windup, DOT,
  projectile impact, or active skills.
