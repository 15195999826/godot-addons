## SkillPreviewValidation - 纯函数工具
##
## SkillPreviewTimeline UI 编辑期 / START 兜底校验用的算 occupy / 找冲突的纯逻辑。
## 抽出来便于单元测试调用 (UI scene 不能在 headless 里实例化, 但 static helper 可以)。
##
## occupy = 一个 skill instance 的 timeline 演完所需时间 (ms) = timeline.total_duration
##
## 关注点划分 (重要):
##
## 1. UI 仅防 "**同一 ability instance** 的 timeline 重叠": 同 actor 同 skill
##    两条 keyframe 间隔 < timeline 在 SkillPreview 视为非法 —— 这是产品约束,
##    不是 LGF core 契约。LGF Ability.activate_new_execution_instance 实际会
##    append 新 _execution_instances, ActiveUseComponent 也没有 existing-execution
##    guard, 框架技术上允许同一 ability 多 execution 并发 (DOT/HOT loop 就是这么
##    用的)。但 SkillPreviewProcedure._fire_due_keyframes 选择复用同 config_id
##    instance (commit 831ae32 去重 grant), 在这个 procedure 实现下"同 skill
##    timeline 演完前重启"语义错乱, 故 UI 拦。换 procedure 实现这条约束就可改。
##
## 2. UI **不**拦 "同 actor 不同 skill 同时段并发": LGF Ability._execution_instances
##    本身就是 Array, 同 actor 同 ability 的多 instance / 不同 ability 的多 instance
##    都允许并发 tick。SkillPreview 替代 ATB+AI 决策层, 真战里 ATB 一次只给 actor
##    一个行动机会是决策层产物, 不是施法管道契约。preview 用户想看 "caster 在 t=0
##    同时甩 Strike + SwiftStrike" 是合法预览意图, 不该被 UI 堵死。
##
## 3. UI **不**拦 "能否释放" (cooldown / mp / hp 等 condition / cost): 这是真战
##    施法管道的责任。LGF ActiveUseComponent 在 fire 时检查, 失败 push
##    AbilityActivateFailed 事件, 前端 console 渲染。用户能排出"间隔 ≥ timeline
##    但 < cooldown"的 timeline, START 跑起来后看到 console 标红"⛔ 释放失败:
##    冷却中"。
##
## 设计意图: preview 替代决策层, 下游施法管道与真战 100% 一致。
class_name SkillPreviewValidation


## 算技能的 occupy 时长 (ms) = timeline.total_duration。cfg=null 返回 0。
##
## 不再扫 costs: cooldown / mp / hp 等"能否释放"约束由 LGF ActiveUseComponent
## 在 fire 时处理, 失败时 push AbilityActivateFailed 事件供前端渲染, 不参与 UI 拦截。
static func ability_occupy_ms(cfg: AbilityConfig) -> int:
	if cfg == null:
		return 0
	var occupy: float = 0.0
	for au in cfg.active_use_components:
		var tl := TimelineRegistry.get_timeline(au.timeline_id)
		if tl != null:
			occupy = maxf(occupy, tl.total_duration)
	return int(occupy)


## 只读 cooldown 配置时长。当前 hex battle 技能用 TimedCooldownCost(type="timed_cooldown")
## 表达冷却；这里仅给 SkillPreview UI 做提示，不参与释放判定。
static func ability_cooldown_ms(cfg: AbilityConfig) -> int:
	if cfg == null:
		return 0
	var cooldown: float = 0.0
	for au in cfg.active_use_components:
		for cost in au.costs:
			if cost == null or cost.type != "timed_cooldown":
				continue
			var duration_value: Variant = cost.get("_duration")
			if duration_value != null:
				cooldown = maxf(cooldown, float(duration_value))
	return int(cooldown)


## 扫一条 track, 找到第一个 occupy 冲突, 返回错误描述; 无冲突返回 ""。
##
## "冲突" = track 里有两条 keyframe 满足:
##   1. skill 相同 — SkillPreview 产品约束: procedure 复用同 config_id instance,
##      演完前重启在该 procedure 实现下语义错乱 (不是 LGF 框架禁止并发, 见类
##      顶部注释); 不同 skill 是不同 instance, 允许并发
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
