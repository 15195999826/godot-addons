class_name CompositeCollisionDetector
extends CollisionDetector

var detectors: Array[CollisionDetector] = []

func add(detector: CollisionDetector) -> CompositeCollisionDetector:
	detectors.append(detector)
	return self

func detect(projectile: ProjectileActor, potential_targets: Array[Actor]) -> Dictionary:
	for detector in detectors:
		var result := detector.detect(projectile, potential_targets)
		if result.get("hit", false):
			return result
	return {"hit": false}
