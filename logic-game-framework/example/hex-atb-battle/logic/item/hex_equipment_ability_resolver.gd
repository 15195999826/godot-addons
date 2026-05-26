## HexEquipmentAbilityResolver - 装备 grant ability 配置解析器
##
## Phase G §"Logic 层 · Item 配置 + 新 passive" 落地:
##
##   装备 item config `granted_abilities[*].ability_config_id` 必须能解析为已注册的
##   AbilityConfig, 否则 `HexItemDomain.can_move_item` reject 整次 move。本 resolver
##   提供"config_id → AbilityConfig"的查询入口, 与 `HexBattleSkillIndex` 解耦
##   (后者只服务 SkillPreview 技能选单, 不应被装备 grant 链路依赖)。
##
## 数据源: `HexBattleAllSkills.all_abilities()` (manifest 单一源头, 加新 ability /
## buff 自动在此 resolver 可见)。不缓存为 static var: Godot 4.6 Windows headless
## 在 static array + static reader 模式下会崩, 保持与 HexBattleAllSkills 相同的
## "每次重建"策略。
##
## V1 用法:
##   var cfg := HexEquipmentAbilityResolver.resolve(&"passive_daedalus_critical_strike")
##   if cfg == null:
##       reject move
##   else:
##       Ability.new(cfg, owner_actor_id) → ability_set.grant_ability(...)
class_name HexEquipmentAbilityResolver


## 按 config_id 查找 AbilityConfig; 未注册 / 找不到返回 null。
##
## [param config_id] 装备 item config `granted_abilities[*].ability_config_id`,
##   可传入 StringName 或 String —— 内部 normalize 后按 String 比较 AbilityConfig.config_id。
## [return] 找到的 AbilityConfig, 或 null。
static func resolve(config_id: Variant) -> AbilityConfig:
	var target_id := _normalize_id(config_id)
	if target_id.is_empty():
		return null
	for cfg in HexBattleAllSkills.all_abilities():
		if cfg.config_id == target_id:
			return cfg
	return null


## 批量解析: granted_abilities 数组(item config 内字段)逐项校验, 任一失败返回 false。
##
## [param granted_abilities] item config["granted_abilities"]; 期望 Array[Dictionary]
##   每项含 `ability_config_id` (StringName/String)。其它字段(source 等)忽略。
## [return] 所有项可解析 → true; 任一无法解析 → false。
static func resolve_all_ok(granted_abilities: Variant) -> bool:
	if granted_abilities == null:
		return true  # 没有 grant 也算合法
	if not (granted_abilities is Array):
		return false
	var arr := granted_abilities as Array
	for entry in arr:
		if not (entry is Dictionary):
			return false
		var entry_dict := entry as Dictionary
		var raw_id: Variant = entry_dict.get("ability_config_id", "")
		if resolve(raw_id) == null:
			return false
	return true


static func _normalize_id(raw: Variant) -> String:
	if raw is StringName:
		return String(raw)
	if raw is String:
		return raw as String
	return ""
