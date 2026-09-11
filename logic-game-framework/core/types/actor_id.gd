class_name ActorId
## ActorId 工具类
##
## Actor ID 格式: "{instance_id}:{local_id}"
## 例如: "battle_001:hero_001"
##
## 使用示例:
##   var full_id := ActorId.format("battle_001", "hero_001")
##   var parsed := ActorId.parse(full_id)
##   print(parsed.instance_id)  # "battle_001"
##   print(parsed.local_id)     # "hero_001"

const SEPARATOR := ":"


## 格式化为完整 Actor ID
static func format(instance_id: String, local_id: String) -> String:
	return "%s%s%s" % [instance_id, SEPARATOR, local_id]


## 解析 Actor ID：返回 { "instance_id": String, "local_id": String }，两段的切法见 extract_instance_id / extract_local_id。
static func parse(actor_id: String) -> Dictionary:
	return {
		"instance_id": extract_instance_id(actor_id),
		"local_id": extract_local_id(actor_id),
	}


## 验证 Actor ID 格式是否有效
static func is_valid(actor_id: String) -> bool:
	if actor_id.is_empty():
		return false
	var sep_index := actor_id.find(SEPARATOR)
	if sep_index == -1:
		return false
	# 确保两部分都不为空
	return sep_index > 0 and sep_index < actor_id.length() - 1


## 提取 instance_id：第一个分隔符之前的部分；没有分隔符时为空串（按 id 反查 instance 自然查不到）。
## 按 owner id 反查 instance 每次派发 / 建 context 都会调，所以只做 find + substr、不建 Dictionary。
static func extract_instance_id(actor_id: String) -> String:
	var sep_index := actor_id.find(SEPARATOR)
	return "" if sep_index == -1 else actor_id.substr(0, sep_index)


## 提取 local_id：第一个分隔符之后的部分；没有分隔符时为整个 id。
static func extract_local_id(actor_id: String) -> String:
	var sep_index := actor_id.find(SEPARATOR)
	return actor_id if sep_index == -1 else actor_id.substr(sep_index + 1)
