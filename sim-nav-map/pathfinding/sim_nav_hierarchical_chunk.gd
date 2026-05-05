class_name SimNavHierarchicalChunk
extends RefCounted


const CHUNK_SIZE: int = 96

var ci: int = 0
var cj: int = 0
var regions_id: PackedInt32Array = PackedInt32Array()
var regions: PackedInt32Array = PackedInt32Array()


func _init(p_ci: int = 0, p_cj: int = 0) -> void:
	ci = p_ci
	cj = p_cj
	regions.resize(CHUNK_SIZE * CHUNK_SIZE)


func get_region(local_i: int, local_j: int) -> int:
	return regions[local_j * CHUNK_SIZE + local_i]
