#pragma once

// Pure-C++ twin of pathfinding/sim_nav_path_goal.gd. Same float semantics:
// hw/hh/maxdist are GDScript floats (double), u/v/center are Vector2
// (float32); geometry expressions ported statement-for-statement.

#include "sim_nav_core_map.h"

namespace simnav {

struct PathGoal {
	enum Type {
		POINT,
		CIRCLE,
		INVERTED_CIRCLE,
		SQUARE,
		INVERTED_SQUARE,
	};

	static constexpr double EPSILON = 0.0001;

	int type = POINT;
	Vector2 center;
	double hw = 0.0;
	double hh = 0.0;
	Vector2 u = Vector2(1.0f, 0.0f);
	Vector2 v = Vector2(0.0f, 1.0f);
	double maxdist = 0.0;

	static PathGoal point(const Vector2 &p_center);
	static PathGoal circle(const Vector2 &p_center, double p_radius);
	static PathGoal inverted_circle(const Vector2 &p_center, double p_radius);
	static PathGoal square(const Vector2 &p_center, double p_half_width, double p_half_height, double p_rotation_rad = 0.0);
	static PathGoal inverted_square(const Vector2 &p_center, double p_half_width, double p_half_height, double p_rotation_rad = 0.0);

	bool navcell_contains_goal(const CoreMap &p_map, const Vector2i &p_coord) const;
	bool contains_point(const Vector2 &p_point) const;
	double distance_to_point(const Vector2 &p_point) const;
	Vector2 nearest_point_on_goal(const Vector2 &p_point) const;

private:
	bool _navcell_contains_circle(const Vector2 &p_min, const Vector2 &p_max, bool p_inside) const;
	bool _navcell_contains_square(const Vector2 &p_min, const Vector2 &p_max, bool p_inside) const;
	bool _point_is_in_square(const Vector2 &p_point) const;
	double _distance_to_square(const Vector2 &p_point, bool p_inverted) const;
	Vector2 _nearest_point_on_square(const Vector2 &p_point) const;
	Vector2 _nearest_point_on_square_edge(const Vector2 &p_point) const;
	void _set_square_axes(double p_half_width, double p_half_height, double p_rotation_rad);
	Vector2 _safe_direction(const Vector2 &p_delta) const;
};

} // namespace simnav
