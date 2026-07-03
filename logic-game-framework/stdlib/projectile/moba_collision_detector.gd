class_name MobaCollisionDetector
extends CollisionDetector

func detect(projectile: ProjectileActor, _potential_targets: Array[Actor]) -> Dictionary:
	if projectile.get_projectile_type() != ProjectileActor.PROJECTILE_TYPE_MOBA:
		return {"hit": false}

	var target_actor_id := projectile.get_target_actor_id()
	if target_actor_id == "":
		return {"hit": false}

	if projectile.should_moba_hit():
		var pos := projectile.position
		return {
			"hit": true,
			"target_actor_id": target_actor_id,
			"hitPosition": Vector3(pos.x, pos.y, pos.z),
		}

	return {"hit": false}
