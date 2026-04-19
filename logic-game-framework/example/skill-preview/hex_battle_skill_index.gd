## HexBattle 技能索引
##
## 服务于 SkillPreview 开发者工具: 把所有 HexBattle*.ABILITY 汇总成一张表,
## 供 UI 下拉枚举。active/passive 由 AbilityConfig.active_use_components 字段判定。
##
## 加新技能 = 下面 _build_all() 里加一行。
class_name HexBattleSkillIndex


## 枚举所有 AbilityConfig (含主动和被动)
static func all() -> Array[AbilityConfig]:
	return _build_all()


## 返回所有 ActiveUse 技能 (active_use_components 非空)
static func actives() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = []
	for cfg in _build_all():
		if not cfg.active_use_components.is_empty():
			out.append(cfg)
	return out


## 返回所有纯被动技能 (active_use_components 为空)
static func passives() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = []
	for cfg in _build_all():
		if cfg.active_use_components.is_empty():
			out.append(cfg)
	return out


## 按 config_id 查找
static func get_by_id(config_id: String) -> AbilityConfig:
	for cfg in _build_all():
		if cfg.config_id == config_id:
			return cfg
	return null


static func _build_all() -> Array[AbilityConfig]:
	var out: Array[AbilityConfig] = [
		HexBattleStrike.ABILITY,
		HexBattleCrushingBlow.ABILITY,
		HexBattleSwiftStrike.ABILITY,
		HexBattlePreciseShot.ABILITY,
		HexBattleFireball.ABILITY,
		HexBattleHolyHeal.ABILITY,
		HexBattlePoison.ABILITY,
		HexBattleMove.ABILITY,
		HexBattleThorn.ABILITY,
		HexBattleDeathrattleAoe.ABILITY,
		HexBattleVitality.ABILITY,
		HexBattleVigor.ABILITY,
	]
	return out
