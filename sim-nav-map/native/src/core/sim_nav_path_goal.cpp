#include "sim_nav_path_goal.h"

#include <algorithm>
#include <cmath>

namespace simnav {

using godot::real_t;

// Twin of GDScript signf: zero maps to zero.
static double _sign(double p_value) {
	if (p_value > 0.0) {
		return 1.0;
	}
	if (p_value < 0.0) {
		return -1.0;
	}
	return 0.0;
}

PathGoal PathGoal::point(const Vector2 &p_center) {
	PathGoal goal;
	goal.type = POINT;
	goal.center = p_center;
	return goal;
}

PathGoal PathGoal::circle(const Vector2 &p_center, double p_radius) {
	PathGoal goal;
	goal.type = CIRCLE;
	goal.center = p_center;
	goal.hw = std::max(0.0, p_radius);
	goal.hh = goal.hw;
	return goal;
}

PathGoal PathGoal::inverted_circle(const Vector2 &p_center, double p_radius) {
	PathGoal goal;
	goal.type = INVERTED_CIRCLE;
	goal.center = p_center;
	goal.hw = std::max(0.0, p_radius);
	goal.hh = goal.hw;
	return goal;
}

PathGoal PathGoal::square(const Vector2 &p_center, double p_half_width, double p_half_height, double p_rotation_rad) {
	PathGoal goal;
	goal.type = SQUARE;
	goal.center = p_center;
	goal._set_square_axes(p_half_width, p_half_height, p_rotation_rad);
	return goal;
}

PathGoal PathGoal::inverted_square(const Vector2 &p_center, double p_half_width, double p_half_height, double p_rotation_rad) {
	PathGoal goal;
	goal.type = INVERTED_SQUARE;
	goal.center = p_center;
	goal._set_square_axes(p_half_width, p_half_height, p_rotation_rad);
	return goal;
}

bool PathGoal::navcell_contains_goal(const CoreMap &p_map, const Vector2i &p_coord) const {
	if (!p_map.is_valid_navcell(p_coord)) {
		return false;
	}
	Vector2 min_pos = p_map.origin + Vector2((real_t)(double)p_coord.x, (real_t)(double)p_coord.y) * (real_t)p_map.navcell_size;
	Vector2 max_pos = min_pos + Vector2((real_t)p_map.navcell_size, (real_t)p_map.navcell_size);
	switch (type) {
		case POINT:
			return p_map.world_to_navcell(center) == p_coord;
		case CIRCLE:
			return _navcell_contains_circle(min_pos, max_pos, true);
		case INVERTED_CIRCLE:
			return _navcell_contains_circle(min_pos, max_pos, false);
		case SQUARE:
			return _navcell_contains_square(min_pos, max_pos, true);
		case INVERTED_SQUARE:
			return _navcell_contains_square(min_pos, max_pos, false);
	}
	return false;
}

bool PathGoal::contains_point(const Vector2 &p_point) const {
	switch (type) {
		case POINT:
			return (double)p_point.distance_squared_to(center) < 0.0001;
		case CIRCLE:
			return (double)p_point.distance_to(center) <= hw;
		case INVERTED_CIRCLE:
			return (double)p_point.distance_to(center) >= hw;
		case SQUARE:
			return _point_is_in_square(p_point);
		case INVERTED_SQUARE:
			return !_point_is_in_square(p_point);
	}
	return false;
}

double PathGoal::distance_to_point(const Vector2 &p_point) const {
	Vector2 delta = p_point - center;
	switch (type) {
		case POINT:
			return (double)delta.length();
		case CIRCLE:
			return std::max(0.0, (double)delta.length() - hw);
		case INVERTED_CIRCLE:
			return std::max(0.0, hw - (double)delta.length());
		case SQUARE:
			return _distance_to_square(p_point, false);
		case INVERTED_SQUARE:
			return _distance_to_square(p_point, true);
	}
	return 0.0;
}

Vector2 PathGoal::nearest_point_on_goal(const Vector2 &p_point) const {
	Vector2 delta = p_point - center;
	switch (type) {
		case POINT:
			return center;
		case CIRCLE:
			if ((double)delta.length() <= hw) {
				return p_point;
			}
			return center + _safe_direction(delta) * (real_t)hw;
		case INVERTED_CIRCLE:
			if ((double)delta.length() >= hw) {
				return p_point;
			}
			return center + _safe_direction(delta) * (real_t)hw;
		case SQUARE:
			if (_point_is_in_square(p_point)) {
				return p_point;
			}
			return _nearest_point_on_square(p_point);
		case INVERTED_SQUARE:
			if (!_point_is_in_square(p_point)) {
				return p_point;
			}
			return _nearest_point_on_square_edge(p_point);
	}
	return p_point;
}

bool PathGoal::_navcell_contains_circle(const Vector2 &p_min, const Vector2 &p_max, bool p_inside) const {
	if (p_inside) {
		Vector2 nearest(
				(real_t)std::clamp((double)center.x, (double)p_min.x, (double)p_max.x),
				(real_t)std::clamp((double)center.y, (double)p_min.y, (double)p_max.y));
		return (double)nearest.distance_to(center) <= hw;
	}
	const Vector2 corners[4] = {
		Vector2(p_min.x, p_min.y),
		Vector2(p_max.x, p_min.y),
		Vector2(p_min.x, p_max.y),
		Vector2(p_max.x, p_max.y),
	};
	for (const Vector2 &corner : corners) {
		if ((double)corner.distance_to(center) >= hw) {
			return true;
		}
	}
	return false;
}

bool PathGoal::_navcell_contains_square(const Vector2 &p_min, const Vector2 &p_max, bool p_inside) const {
	if (p_inside) {
		Vector2 nearest(
				(real_t)std::clamp((double)center.x, (double)p_min.x, (double)p_max.x),
				(real_t)std::clamp((double)center.y, (double)p_min.y, (double)p_max.y));
		return _point_is_in_square(nearest);
	}
	const Vector2 corners[4] = {
		Vector2(p_min.x, p_min.y),
		Vector2(p_max.x, p_min.y),
		Vector2(p_min.x, p_max.y),
		Vector2(p_max.x, p_max.y),
	};
	for (const Vector2 &corner : corners) {
		if (!_point_is_in_square(corner)) {
			return true;
		}
	}
	return false;
}

bool PathGoal::_point_is_in_square(const Vector2 &p_point) const {
	Vector2 delta = p_point - center;
	return std::abs((double)delta.dot(u)) <= hw + EPSILON && std::abs((double)delta.dot(v)) <= hh + EPSILON;
}

double PathGoal::_distance_to_square(const Vector2 &p_point, bool p_inverted) const {
	Vector2 delta = p_point - center;
	double local_x = (double)delta.dot(u);
	double local_y = (double)delta.dot(v);
	double outside_x = std::max(std::abs(local_x) - hw, 0.0);
	double outside_y = std::max(std::abs(local_y) - hh, 0.0);
	if (!p_inverted) {
		// Twin: Vector2(outside_x, outside_y).length() — float32 construction.
		return (double)Vector2((real_t)outside_x, (real_t)outside_y).length();
	}
	if (outside_x > 0.0 || outside_y > 0.0) {
		return 0.0;
	}
	return std::min(hw - std::abs(local_x), hh - std::abs(local_y));
}

Vector2 PathGoal::_nearest_point_on_square(const Vector2 &p_point) const {
	Vector2 delta = p_point - center;
	double local_x = std::clamp((double)delta.dot(u), -hw, hw);
	double local_y = std::clamp((double)delta.dot(v), -hh, hh);
	return center + u * (real_t)local_x + v * (real_t)local_y;
}

Vector2 PathGoal::_nearest_point_on_square_edge(const Vector2 &p_point) const {
	Vector2 delta = p_point - center;
	double local_x = std::clamp((double)delta.dot(u), -hw, hw);
	double local_y = std::clamp((double)delta.dot(v), -hh, hh);
	double dist_x = hw - std::abs(local_x);
	double dist_y = hh - std::abs(local_y);
	if (dist_x <= dist_y) {
		local_x = _sign(local_x) * hw;
		if (std::abs(local_x) < 0.0001) {
			local_x = hw;
		}
	} else {
		local_y = _sign(local_y) * hh;
		if (std::abs(local_y) < 0.0001) {
			local_y = hh;
		}
	}
	return center + u * (real_t)local_x + v * (real_t)local_y;
}

void PathGoal::_set_square_axes(double p_half_width, double p_half_height, double p_rotation_rad) {
	hw = std::max(0.0, p_half_width);
	hh = std::max(0.0, p_half_height);
	u = Vector2((real_t)std::cos(p_rotation_rad), (real_t)std::sin(p_rotation_rad)).normalized();
	v = Vector2(-u.y, u.x);
}

Vector2 PathGoal::_safe_direction(const Vector2 &p_delta) const {
	if ((double)p_delta.length_squared() < 0.0001) {
		return Vector2(1.0f, 0.0f);
	}
	return p_delta.normalized();
}

} // namespace simnav
