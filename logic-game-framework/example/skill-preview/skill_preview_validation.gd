## SkillPreviewValidation - 纯函数工具
##
## SkillPreviewTimeline UI 编辑期 / START 兜底校验用的算 occupy / 找冲突的纯逻辑。
## 抽出来便于单元测试调用 (UI scene 不能在 headless 里实例化, 但 static helper 可以)。
##
## occupy = 一个技能从 activate 到"可以再次 activate"的最短时间 (ms)
##        = max(timeline.total_duration, TimedCooldownCost.duration)
##
## procedure 在 fire keyframe 时不绕 cooldown, 同 skill 在 occupy 窗口内重叠 fire
## 会被 CooldownCondition silently reject —— UI 编辑期就要拦住, 让这种 timeline
## 排不出来。
class_name SkillPreviewValidation


## 算技能的 occupy 时长 (ms)。cfg=null 返回 0。
##
## 走 cfg.active_use_components, 取 timeline.total_duration 与
## TimedCooldownCost.duration 的最大值。其它 Cost 类型不计入 occupy
## (mp/hp 不约束时间, 只有 cooldown 是)。
static func ability_occupy_ms(cfg: AbilityConfig) -> int:
	if cfg == null:
		return 0
	var occupy: float = 0.0
	for au in cfg.active_use_components:
		var tl := TimelineRegistry.get_timeline(au.timeline_id)
		if tl != null:
			occupy = maxf(occupy, tl.total_duration)
		for cost in au.costs:
			if cost is HexBattleCooldownSystem.TimedCooldownCost:
				occupy = maxf(occupy, (cost as HexBattleCooldownSystem.TimedCooldownCost).get_duration())
	return int(occupy)


## 扫一条 track, 找到第一个 occupy 冲突, 返回错误描述; 无冲突返回 ""。
##
## "冲突" = track 里有两条 keyframe 满足:
##   1. skill 相同 (cooldown tag 是 cooldown:<config_id> namespace, 不同 skill 不互斥)
##   2. |t_a - t_b| < occupy(skill)
##
## skill_resolver: func(skill_id: String) -> AbilityConfig
##   单元测试用 mock dict; UI 调点直接传 HexBattleSkillIndex.get_by_id。
##
## role_label: 错误消息的"谁"字段, 不参与判定 ("caster" / "ally_0" 等)。
static func find_track_occupy_violation(
	track: Array, role_label: String, skill_resolver: Callable
) -> String:
	for i in track.size():
		for j in range(i + 1, track.size()):
			var ki: Dictionary = track[i] as Dictionary
			var kj: Dictionary = track[j] as Dictionary
			var skill_i := str(ki.get("skill", ""))
			var skill_j := str(kj.get("skill", ""))
			if skill_i != skill_j:
				continue
			var cfg: AbilityConfig = skill_resolver.call(skill_i)
			if cfg == null:
				continue
			var occupy := ability_occupy_ms(cfg)
			if occupy <= 0:
				continue
			var ti := int(ki.get("time_ms", 0))
			var tj := int(kj.get("time_ms", 0))
			if abs(ti - tj) < occupy:
				return "%s: %s @ %dms 与 @ %dms 重叠 (occupy=%dms)" % [
					role_label, cfg.display_name,
					min(ti, tj), max(ti, tj), occupy,
				]
	return ""


## 在 track 里找下一个空闲 time_ms (从 start_ms 起 100ms 步进上扫)。
##
## "占用" = track 里有一条 keyframe (skip_kf_idx 除外) 满足:
##   1. 完全相同 time_ms (同 actor 单 time 互斥)
##   2. 同 skill_id 且 [t, t+occupy_self) 与 [other_t, other_t+occupy_other) 重叠
##
## candidate_skill_id: 被放置/移动 keyframe 自身的 skill。
## skill_resolver: 同 find_track_occupy_violation。
## start_ms: 起扫位置, 会向下取整到 100 边界。
## skip_kf_idx: 排除自己 (改 time 时不算自己冲突)。
##
## 兜底: 60 秒内找不到空闲返回最后扫到的 t (10 分钟级 timeline 不实际)。
static func next_free_time_ms_in_track(
	track: Array, candidate_skill_id: String,
	skill_resolver: Callable,
	start_ms: int, skip_kf_idx: int = -1
) -> int:
	var candidate_cfg: AbilityConfig = skill_resolver.call(candidate_skill_id)
	var occupy_self := ability_occupy_ms(candidate_cfg)
	var t := max(0, start_ms - (start_ms % 100))
	for _i in range(0, 600):  # 最多扫 60s
		var occupied := false
		for j in track.size():
			if j == skip_kf_idx:
				continue
			var other_t := int((track[j] as Dictionary).get("time_ms", 0))
			if other_t == t:
				occupied = true
				break
			var other_skill := str((track[j] as Dictionary).get("skill", ""))
			if other_skill != candidate_skill_id:
				continue
			var other_cfg: AbilityConfig = skill_resolver.call(other_skill)
			var occupy_other := ability_occupy_ms(other_cfg)
			if t < other_t + occupy_other and other_t < t + occupy_self:
				occupied = true
				break
		if not occupied:
			return t
		t += 100
	return t
