## SpawnFireTile #C - 火焰地形召唤主动技能
##
## V1 行为:
## - cast 后 timeline HIT @ t=400ms → SpawnFireTileAction 在 target 的 hex coord 上 spawn FireTile
## - FireTile passive: FireTilePulse (每 1s 对同格 character 造 pure damage) +
##   FireTileLifetime (默认 5000ms 后自动 remove)
## - range=3 (主动技能可施法到 3 格内目标坐标)
class_name HexBattleSpawnFireTile


const CONFIG_ID := "skill_spawn_fire_tile"
const TIMELINE_ID := "skill_spawn_fire_tile"
const COOLDOWN_MS := 8000.0
const FIRE_TILE_LIFETIME_MS := 5000.0


static var SPAWN_FIRE_TILE_TIMELINE := TimelineData.new(
	TIMELINE_ID,
	600.0,
	{
		TimelineTags.HIT: 400.0,
		TimelineTags.END: 600.0,
	}
)


static var ABILITY := create_config(FIRE_TILE_LIFETIME_MS)


static func create_config(lifetime_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("火焰地形")
		.description("在目标位置生成一个火焰地形, 每 1s 对同格角色造 20 纯伤, %.1fs 后消失" % (lifetime_ms / 1000.0))
		.ability_tags(["skill", "active", "ranged", "enemy", "fire_tile"])
		.meta(HexBattleSkillMetaKeys.RANGE, 3)
		.meta("fire_tile_lifetime_ms", lifetime_ms)
		.active_use(
			HexBattleCooldownSystem.apply_standard_active_gating(ActiveUseConfig.builder(), COOLDOWN_MS)
			.timeline_id(TIMELINE_ID)
			.on_timeline_start([StageCueAction.new(
				HexBattleTargetSelectors.current_target(),
				Resolvers.str_val("fire_tile_cast"),
			)])
			.on_tag(TimelineTags.HIT, [
				HexBattleSpawnFireTileAction.new(
					HexBattleTargetSelectors.current_target(),
					HexBattleFireTilePulse.DEFAULT_PULSE_INTERVAL_MS,
					HexBattleFireTilePulse.DEFAULT_PULSE_DAMAGE,
					lifetime_ms,
				),
			])
			.build()
		)
		.build()
	)
