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


## 解析 Actor ID
## 返回 { "instance_id": String, "local_id": String }
## 如果格式无效，返回 { "instance_id": "", "local_id": actor_id }
static func parse(actor_id: String) -> Dictionary:
	var sep_index := actor_id.find(SEPARATOR)
	if sep_index == -1:
		# 兼容旧格式：没有分隔符时，整个 ID 作为 local_id
		return {
			"instance_id": "",
			"local_id": actor_id,
		}
	return {
		"instance_id": actor_id.substr(0, sep_index),
		"local_id": actor_id.substr(sep_index + 1),
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


## 提取 instance_id 部分
static func extract_instance_id(actor_id: String) -> String:
	return parse(actor_id).instance_id


## 提取 local_id 部分
static func extract_local_id(actor_id: String) -> String:
	return parse(actor_id).local_id
