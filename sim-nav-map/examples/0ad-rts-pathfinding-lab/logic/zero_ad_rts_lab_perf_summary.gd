class_name ZeroAdRtsLabPerfSummary


const DEFAULT_WARMUP_STEPS: int = 120
const DEFAULT_SLOW_FRAME_THRESHOLD_USEC: int = 8000


static func summarize_steps(
	step_usec_samples: Array[int],
	idle_step_usec_samples: Array[int],
	warmup_steps: int = DEFAULT_WARMUP_STEPS
) -> Dictionary:
	var warm_samples := _samples_after_warmup(step_usec_samples, warmup_steps)
	var percentile_samples := warm_samples
	if percentile_samples.is_empty():
		percentile_samples = _copy_samples(step_usec_samples)
	return {
		"warmup_step_count": mini(maxi(warmup_steps, 0), step_usec_samples.size()),
		"sample_count": step_usec_samples.size(),
		"warm_sample_count": warm_samples.size(),
		"idle_sample_count": idle_step_usec_samples.size(),
		"warm_avg_step_usec": _average_usec(warm_samples),
		"p95_step_usec": _percentile_usec(percentile_samples, 95.0),
		"p99_step_usec": _percentile_usec(percentile_samples, 99.0),
		"idle_avg_step_usec": _average_usec(idle_step_usec_samples),
		"percentile_scope": "warm_after_%d_steps" % warmup_steps if not warm_samples.is_empty() else "all_samples",
	}


static func is_idle_profile(profile: Dictionary) -> bool:
	return (
		not bool(profile.get("active_mobile", false))
		and int(profile.get("processed_paths", 0)) == 0
		and int(profile.get("pending_path_requests", 0)) == 0
		and int(profile.get("pending_path_results", 0)) == 0
	)


static func classify_step(profile: Dictionary) -> Dictionary:
	var stages := stage_costs(profile)
	var top_stage := "none"
	var top_stage_usec := 0
	for stage_key in stages.keys():
		var stage_name := String(stage_key)
		var stage_usec := int(stages.get(stage_name, 0))
		if stage_usec > top_stage_usec:
			top_stage = stage_name
			top_stage_usec = stage_usec
	var total_usec := int(profile.get("total_usec", 0))
	if total_usec <= 0:
		total_usec = _sum_stage_usec(stages)
	var stage_ratio := 0.0
	if total_usec > 0:
		stage_ratio = float(top_stage_usec) / float(total_usec)
	return {
		"stage": top_stage,
		"stage_usec": top_stage_usec,
		"stage_ratio": stage_ratio,
		"stage_costs": stages,
		"total_profile_usec": total_usec,
		"active_mobile": bool(profile.get("active_mobile", false)),
		"processed_paths": int(profile.get("processed_paths", 0)),
		"path_request": path_request_summary(profile),
	}


static func stage_costs(profile: Dictionary) -> Dictionary:
	return {
		"path_request": int(profile.get("path_budget_usec", 0)),
		"path_result": int(profile.get("apply_results_usec", 0)),
		"movement": int(profile.get("step_units_usec", 0)),
		"refresh": int(profile.get("refresh_before_usec", 0)) + int(profile.get("refresh_after_usec", 0)),
		"push": int(profile.get("push_adjust_usec", 0)),
		"diagnostics": int(profile.get("pair_contacts_usec", 0)),
		"bookkeeping": (
			int(profile.get("snapshot_usec", 0))
			+ int(profile.get("dispatch_pre_usec", 0))
			+ int(profile.get("dispatch_post_usec", 0))
			+ int(profile.get("active_check_usec", 0))
		),
	}


static func path_request_summary(profile: Dictionary) -> Dictionary:
	var batch: Array = profile.get("path_request_batch", []) as Array
	var kind_counts: Dictionary = {}
	var max_compute_usec := 0
	var max_compute_kind := ""
	for request_item in batch:
		if typeof(request_item) != TYPE_DICTIONARY:
			continue
		var request: Dictionary = request_item as Dictionary
		var kind := String(request.get("kind", "unknown"))
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		var compute_usec := int(request.get("compute_usec", 0))
		if compute_usec > max_compute_usec:
			max_compute_usec = compute_usec
			max_compute_kind = kind
	return {
		"count": batch.size(),
		"kind_counts": kind_counts,
		"max_compute_usec": max_compute_usec,
		"max_compute_kind": max_compute_kind,
	}


static func summarize_slow_frames(slow_frames: Array[Dictionary]) -> Dictionary:
	var stage_counts: Dictionary = {}
	var dominant_stage := "none"
	var dominant_count := 0
	for frame in slow_frames:
		var classification: Dictionary = frame.get("stage_classification", {}) as Dictionary
		var stage := String(classification.get("stage", "unknown"))
		stage_counts[stage] = int(stage_counts.get(stage, 0)) + 1
		var stage_count := int(stage_counts.get(stage, 0))
		if stage_count > dominant_count:
			dominant_count = stage_count
			dominant_stage = stage
	return {
		"slow_frame_count": slow_frames.size(),
		"slow_frame_stage_counts": stage_counts,
		"slow_frame_dominant_stage": dominant_stage,
	}


static func summarize_stage_profiles(
	step_profiles: Array[Dictionary],
	idle_step_profiles: Array[Dictionary],
	warmup_steps: int = DEFAULT_WARMUP_STEPS
) -> Dictionary:
	var warm_profiles := _profiles_after_warmup(step_profiles, warmup_steps)
	var all_stage_avg := _average_stage_costs(step_profiles)
	var warm_stage_avg := _average_stage_costs(warm_profiles)
	var idle_stage_avg := _average_stage_costs(idle_step_profiles)
	return {
		"stage_avg_usec": all_stage_avg,
		"warm_stage_avg_usec": warm_stage_avg,
		"idle_stage_avg_usec": idle_stage_avg,
		"dominant_stage": _dominant_average_stage(all_stage_avg),
		"warm_dominant_stage": _dominant_average_stage(warm_stage_avg),
		"idle_dominant_stage": _dominant_average_stage(idle_stage_avg),
	}


static func _average_usec(samples: Array[int]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0
	for sample in samples:
		total += sample
	return float(total) / float(samples.size())


static func _percentile_usec(samples: Array[int], percentile: float) -> int:
	if samples.is_empty():
		return 0
	var sorted := _copy_samples(samples)
	sorted.sort()
	var rank := int(ceil((percentile / 100.0) * float(sorted.size()))) - 1
	var index := mini(maxi(rank, 0), sorted.size() - 1)
	return sorted[index]


static func _samples_after_warmup(samples: Array[int], warmup_steps: int) -> Array[int]:
	var result: Array[int] = []
	var start_index := mini(maxi(warmup_steps, 0), samples.size())
	for i in range(start_index, samples.size()):
		result.append(samples[i])
	return result


static func _copy_samples(samples: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for sample in samples:
		result.append(sample)
	return result


static func _profiles_after_warmup(profiles: Array[Dictionary], warmup_steps: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index := mini(maxi(warmup_steps, 0), profiles.size())
	for i in range(start_index, profiles.size()):
		result.append(profiles[i])
	return result


static func _average_stage_costs(profiles: Array[Dictionary]) -> Dictionary:
	var totals: Dictionary = {}
	for profile in profiles:
		var costs := stage_costs(profile)
		for stage_key in costs.keys():
			var stage_name := String(stage_key)
			totals[stage_name] = int(totals.get(stage_name, 0)) + int(costs.get(stage_name, 0))
	var averages: Dictionary = {}
	for stage_key in totals.keys():
		var stage_name := String(stage_key)
		averages[stage_name] = float(totals.get(stage_name, 0)) / float(maxi(profiles.size(), 1))
	return averages


static func _dominant_average_stage(stage_averages: Dictionary) -> Dictionary:
	var top_stage := "none"
	var top_usec := 0.0
	for stage_key in stage_averages.keys():
		var stage_name := String(stage_key)
		var stage_usec := float(stage_averages.get(stage_name, 0.0))
		if stage_usec > top_usec:
			top_stage = stage_name
			top_usec = stage_usec
	return {
		"stage": top_stage,
		"avg_usec": top_usec,
	}


static func _sum_stage_usec(stages: Dictionary) -> int:
	var total := 0
	for stage_key in stages.keys():
		total += int(stages.get(stage_key, 0))
	return total
