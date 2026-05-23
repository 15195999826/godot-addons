## FireTile - 火焰地形 EnvironmentActor (路线 A: passable overlay)
##
## V1 实现 (Phase C · Fire Tile minimal):
## - 不占 grid (overlay 语义): spawn 时不调 place_occupant, 让 character 可与 fire tile 同 coord 共存
## - blocks_path = false (寻路穿透)
## - pushable = false (不被推开)
## - 高 HP (默认 200, 可被 Thorn 反伤等打死, 但通常靠 lifetime 到期 cleanup)
## - 自带 passive: HexBattleFireTilePulse (每 1s 对同 coord 上的 alive CharacterActor 造 pure damage)
##                + HexBattleFireTileLifetime (TimeDuration + auto remove)
##
## Goal Phase C 设计 placement_mode (UNPLACED/OCCUPANT/OVERLAY) + remove_actor switch
## + 双线 tick (all HexBattleActor ability tick vs only alive CharacterActor ATB/AI)
## 在 minimal V1 中暂未做, 因为 scenario / skill-preview 路径不依赖 grid.occupant clobber
## 风险 (fire tile 不 place_occupant 自然不会跟 character occupant 打架)。完整 placement_mode
## 抽象留 Goal-spec follow-up。
class_name HexBattleFireTile


const KIND := "fire_tile"
const DEFAULT_HP := 200.0
const DEFAULT_PULSE_INTERVAL_MS := 1000.0
const DEFAULT_PULSE_DAMAGE := 20.0
const DEFAULT_LIFETIME_MS := 5000.0


static func create() -> EnvironmentActor:
	var profile := CollisionProfile.new()
	profile.blocks_path = false  # 寻路穿透 — character 可以走过 / 站上
	profile.pushable = false
	profile.damage_taken_on_blocked_push = 0.0
	profile.damage_dealt_to_pusher = 0.0

	var tile := EnvironmentActor.new(KIND, profile)
	tile.attribute_set.set_max_hp_base(DEFAULT_HP)
	tile.attribute_set.set_hp_base(DEFAULT_HP)
	tile.set_display_name("火焰地形")
	return tile
