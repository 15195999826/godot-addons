class_name DistanceCollisionDetector
extends CollisionDetector

var hit_distance: float

func _init(p_hit_distance: float = 50.0) -> void:
	hit_distance = p_hit_distance

func detect(projectile: ProjectileActor, potential_targets: Array[Actor]) -> Dictionary:
	var projectile_pos := projectile.position

	for target in potential_targets:
		var dx := target.position.x - projectile_pos.x
		var dy := target.position.y - projectile_pos.y
		var dist := sqrt(dx * dx + dy * dy)

		if dist <= hit_distance:
			return {
				"hit": true,
				"target_actor_id": target.id,
				"hitPosition": Vector3(projectile_pos.x, projectile_pos.y, projectile_pos.z),
			}

	return {"hit": false}
