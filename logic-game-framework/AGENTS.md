# Logic Game Framework - Architecture Overview

> **Coding conventions** and **full API reference** are in the `lgf` skill.
> Use `load_skills=["lgf"]` when delegating tasks that involve this framework.
>
> **Quick navigation** (`.opencode/skill/lgf/`):
> - `SKILL.md` — Conventions (attribute access, actor creation, statelessness, resolvers, pre-events)
> - `reference/conventions-detail.md` — Full examples, reference chain diagrams, architecture
> - `reference/entity.md` — Actor, System, GameWorld, GameplayInstance
> - `reference/abilities.md` — Ability, AbilitySet, AbilityConfig, Components, Builder API
> - `reference/actions.md` — Action, ExecutionContext, TargetSelector, Resolvers
> - `reference/events.md` — EventProcessor, MutableEvent, Intent, Modification
> - `reference/attributes.md` — RawAttributeSet, AttributeModifier, Calculator, TagContainer
> - `reference/stdlib.md` — StatModifier, TimeDuration, Stack, Projectile, Replay, Timeline
> - `reference/example-app.md` — Three-layer example app (Core Events → Game Logic → Presentation)

---

## Core Module Dependencies

```mermaid
graph TB
    subgraph "Core"
        World[GameWorld<br/>Autoload]
        Entity[Entity System<br/>Actor/System]
        Attributes[Attribute System<br/>RawAttributeSet]
        Abilities[Ability System<br/>Ability/AbilitySet]
        Events[Event System<br/>EventProcessor]
        Actions[Action System<br/>BaseAction]
        Timeline[Timeline System<br/>TimelineRegistry]
        Tags[Tag System<br/>TagContainer]
    end
    
    subgraph "Stdlib"
        Components[Components<br/>StatModifier/Duration]
        Systems[Systems<br/>ProjectileSystem]
        Replay[Replay System<br/>BattleRecorder]
    end
    
    subgraph "Example"
        Core[hex-atb-battle-core<br/>Shared Events]
        HexBattle[hex-atb-battle<br/>Game Logic]
        Frontend[hex-atb-battle-frontend<br/>Presentation Layer]
    end
    
    World --> Entity
    World --> Events
    Entity --> Abilities
    Abilities --> Attributes
    Abilities --> Tags
    Abilities --> Actions
    Abilities --> Timeline
    Actions --> Events
    Components --> Abilities
    Systems --> Entity
    Replay --> Events
    HexBattle --> World
    HexBattle --> Core
    HexBattle --> Replay
    Frontend --> Core
    Frontend --> Replay
```

## Key Data Flows

### 1. Ability Execution Flow
```
User Input → AbilityComponent.on_event()
    ↓ Check Triggers/Conditions/Costs
AbilityExecutionInstance.tick()
    ↓ Timeline keyframe triggers
Action.execute()
    ↓ Pre-Event processing (damage reduction/immunity)
Atomic operations (push event + apply state)
    ↓ Post-Event processing (thorns/lifesteal)
EventCollector collects (replay recording)
```

### 2. Attribute Modification Flow
```
StatModifierComponent.on_apply()
    ↓ Create AttributeModifier
RawAttributeSet.add_modifier()
    ↓ Mark dirty
Actor accesses attribute
    ↓ get_current_value()
AttributeCalculator.calculate()
    ↓ 4-layer formula calculation
Return AttributeBreakdown
```

### 3. Event Processing Flow
```
Action pushes event
    ↓
EventProcessor.process_pre_event()
    ↓ Iterate Pre Handlers
    ↓ Collect Intent (PASS/MODIFY/CANCEL)
    ↓ Apply modifications
MutableEvent returned
    ↓ Action checks if cancelled
EventProcessor.process_post_event()
    ↓ Broadcast to all alive Actors
    ↓ Trigger passive abilities
EventCollector.push()
```