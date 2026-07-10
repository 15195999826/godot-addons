## Shadow Step #12 - 影袭瞬移
##
## 设计卡: 瞬移到目标 "身后", +50% 一击。
##
## 实现 (per phase-02-shadow-step.md):
##   1. CAST tag (t=150ms): _ShadowStepTeleportAction 计算落点 (背→背左→背右→侧后→正面),
##      写 shadow_step.teleport_success 进 ExecutionContext.execution_state,
##      push ActorDisplacedEvent (kind=teleport) + face target。
##   2. HIT tag (t=300ms): FlowAction.if_(teleport_success, [DamageAction(atk×1.5)])
##      只在瞬移成功时造伤。失败仍消耗冷却 (whiff)。
##
## 落点选择 6 邻格优先级: 背 → 背左 → 背右 → 侧后左 → 侧后右 → 正面。
## 全部不可用 (occupy / reserve / out of map) → teleport_success=false。
class_name HexBattleShadowStep


const CONFIG_ID := "skill_shadow_step"
const TIMELINE_ID := "skill_shadow_step"
const DAMAGE_MULT := 1.5
const COOLDOWN_MS := 6000.0
const TELEPORT_SUCCESS_KEY := "shadow_step.teleport_success"
const DISPLACEMENT_KIND_TELEPORT := "teleport"


static var SHADOW_STEP_TIMELINE := TimelineData.new(TIMELINE_ID, 500.0, {
	TimelineTags.CAST: 150.0,
	TimelineTags.HIT: 300.0,
	TimelineTags.END: 500.0,
})


# ============================================================
# Damage resolver: caster.atk × 1.5
# ============================================================
static var _ATK_X15: FloatResolver = HexBattleSkillHelpers.caster_atk_damage(DAMAGE_MULT)


# ============================================================
# HIT tag predicate: 仅当 CAST 阶段写 teleport_success=true 时造伤
# ============================================================
static func _shadow_step_teleport_succeeded(ctx: ExecutionContext) -> bool:
	return bool(ctx.get_execution_state(TELEPORT_SUCCESS_KEY, false))


# ============================================================
# SkillLocalAction: 仅本技能私有过程
# ============================================================
class _ShadowStepTeleportAction:
	extends Action.SkillLocalAction

	func _init(target_selector: TargetSelector) -> void:
		super._init(target_selector, HexBattleShadowStep.CONFIG_ID)
		type = "shadow_step_teleport"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		ctx.set_execution_state(HexBattleShadowStep.TELEPORT_SUCCESS_KEY, false)
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		var targets := get_targets(ctx)
		if battle == null or caster_id == "" or targets.is_empty():
			return ActionResult.create_success_result([], { "skipped": "missing context" })
		var caster := battle.get_character_actor(caster_id)
		var target := battle.get_character_actor(targets[0])
		if caster == null or target == null or target.is_dead():
			return ActionResult.create_success_result([], { "skipped": "caster/target invalid" })

		var from_pos := caster.hex_position
		var land := _landing_slot(target, battle)
		if land == null:
			return ActionResult.create_success_result([], { "teleported": false })

		if not battle.grid.move_occupant(from_pos, land):
			return ActionResult.create_success_result([], { "teleported": false })
		caster.hex_position = land
		ctx.set_execution_state(HexBattleShadowStep.TELEPORT_SUCCESS_KEY, true)

		var dist := from_pos.distance_to(land)
		var events: Array[Dictionary] = []
		var displaced := BattleEvents.ActorDisplacedEvent.create(
			caster_id,
			from_pos.to_dict(),
			land.to_dict(),
			HexBattleShadowStep.DISPLACEMENT_KIND_TELEPORT,
			caster_id,   # source = caster 自己 (自位移)
			dist,
			0.0,         # 自位移无 stagger
			0.0,
		)
		events.append(ctx.event_collector.push(displaced.to_dict()))
		events.append_array(HexFacing.face_actor_toward(
			caster,
			target.hex_position,
			HexFacing.REASON_SHADOW_STEP,
			ctx.event_collector,
		))
		return ActionResult.create_success_result(events, { "teleported": true })

	## 落点选择: 背 → 背左 → 背右 → 侧后左 → 侧后右 → 正面
	## 任意一格存在 / 未占 / 未预订 → 选它。全失败 → null。
	func _landing_slot(target: CharacterActor, battle: HexWorldGameplayInstance) -> HexCoord:
		var behind_dir := HexFacing.opposite(target.get_facing_direction())
		for dir in _landing_priority_dirs(behind_dir):
			var land := target.hex_position.neighbor(dir)
			if not battle.grid.has_tile(land):
				continue
			if battle.grid.get_occupant(land) != null:
				continue
			if battle.grid.is_reserved(land):
				continue
			return land
		return null

	static func _landing_priority_dirs(behind_dir: int) -> Array[int]:
		return [
			posmod(behind_dir, 6),       # 正背侧
			posmod(behind_dir - 1, 6),   # 背侧左
			posmod(behind_dir + 1, 6),   # 背侧右
			posmod(behind_dir - 2, 6),   # 侧后左
			posmod(behind_dir + 2, 6),   # 侧后右
			posmod(behind_dir + 3, 6),   # 正面 (最后 fallback)
		]


# ============================================================
# Ability definition
# ============================================================
static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("影袭")
	.description("瞬移到目标背侧并造成 150% 攻击力的一击")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 4)
	.meta(HexBattleSkillMetaKeys.TARGETING, HexBattleSkillMetaKeys.TARGETING_ACTOR)
	.active_use(HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
		.timeline(SHADOW_STEP_TIMELINE)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val(HexBattleCues.MELEE_SLASH)
		)])
		.on_tag(TimelineTags.CAST, [_ShadowStepTeleportAction.new(
			HexBattleTargetSelectors.current_target()
		)])
		.on_tag(TimelineTags.HIT, [FlowAction.if_(
			_shadow_step_teleport_succeeded,
			[HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_ATK_X15,
				BattleEvents.DamageType.PHYSICAL
			)] as Array[Action.BaseAction]
		)])
		.build())
	.build())
