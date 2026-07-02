#pragma once

// Pure-C++ twin of the Dota2LabMotionEngine hot path (Phase A intent step
// with contact steering + Phase B separation solve), example/dota2-rts-
// pathfinding-lab/logic/dota2_lab_motion_engine.gd. One step() call per tick
// covers every unit (SoA arrays); Phase C (arrival/watchdog/orders) stays in
// GDScript on the unit objects.
//
// Both the brute-force pair paths and the hashed grid paths are ported —
// the separation_brute_force_max threshold semantics (and therefore the
// user-validated <=16-unit feel path) are preserved exactly. Engine builtin
// math (angle_difference / rotate_toward / from_angle / angle / rotated) is
// re-implemented with the exact Godot algorithms and float widths.

#include <cstdint>
#include <unordered_map>
#include <vector>

#include <godot_cpp/variant/vector2.hpp>

namespace simnav {

using godot::Vector2;

struct MotionParams {
	double delta = 0.0;
	double pushability_moving = 0.35;
	double pushability_idle = 1.0;
	bool contact_steering_enabled = true;
	int separation_brute_force_max = 16;
	Vector2 map_size;
};

// Parallel static-shape arrays (from the wrapper's shape cache).
struct MotionStatics {
	std::vector<Vector2> center;
	std::vector<double> width;
	std::vector<double> height;
	std::vector<double> rotation_rad;
};

// Parallel per-unit state. position/facing/steer_side/last_* are read-write;
// the rest is read-only input for the step.
struct MotionState {
	std::vector<Vector2> position;
	std::vector<double> facing_angle_rad;
	std::vector<double> radius;
	std::vector<double> speed;
	std::vector<double> turn_rate_rad_per_sec;
	std::vector<uint8_t> moving;
	std::vector<uint8_t> mobile;
	std::vector<uint8_t> has_path;
	std::vector<Vector2> track_point;
	std::vector<double> steer_side;
	std::vector<int32_t> id_rank; // lexicographic rank of unit.id (String order)
	std::vector<double> last_speed_factor;
	std::vector<double> last_turn_delta_rad;

	size_t size() const { return position.size(); }
};

struct MotionStats {
	int separation_rounds = 0;
	double max_residual_overlap = 0.0;
};

class MotionSolver {
public:
	// Twin constants of the GDScript engine.
	static constexpr double TURN_ALIGN_FULL_RAD = 0.20;
	static constexpr double TURN_ALIGN_ZERO_RAD = 1.35;
	static constexpr int SEPARATION_ITERATIONS = 6;
	static constexpr double SEPARATION_SLACK = 0.01;
	static constexpr double HEAD_ON_ALIGN_DOT = 0.85;
	static constexpr double HEAD_ON_LATERAL_BIAS = 0.6;
	static constexpr double CONTACT_STEER_GAP_RANGE = 8.0;
	static constexpr double CONTACT_STEER_FRONT_DOT_MIN = 0.3;
	static constexpr double CONTACT_STEER_WEIGHT = 0.9;
	static constexpr double CONTACT_STEER_SIDE_DEADZONE = 0.05;

	MotionStats step(MotionState &p_state, const MotionStatics &p_statics, const MotionParams &p_params);
	double max_overlap_depth(const MotionState &p_state, int p_brute_force_max);

private:
	// Flat-grid scratch reused across calls (twin of the engine-level
	// transient buffers).
	std::vector<int32_t> grid_heads;
	std::vector<int32_t> grid_next;
	std::vector<int32_t> grid_candidates;

	struct SteerBuckets {
		double cell_size = 0.0;
		std::unordered_map<int64_t, std::vector<int32_t>> buckets;
	};

	static int64_t _bucket_key(int32_t p_x, int32_t p_y) {
		return ((int64_t)(uint32_t)p_y << 32) | (uint32_t)p_x;
	}

	void _advance_unit(MotionState &p_state, int p_i, const MotionParams &p_params, const SteerBuckets &p_buckets);
	double _contact_steered_heading(MotionState &p_state, int p_i, const Vector2 &p_toward_track, const MotionParams &p_params, const SteerBuckets &p_buckets);
	// (bias.x, bias.y, contact) — twin of the Vector3-returning helper.
	bool _steer_contribution(const MotionState &p_state, int p_i, int p_other, const Vector2 &p_toward_track, double p_my_push, const MotionParams &p_params, double p_locked_side, double &r_used_side, Vector2 &r_bias) const;
	static double _pick_steer_side(const Vector2 &p_to_other, const Vector2 &p_intent_dir);
	static double _alignment_factor(double p_heading_error);
	double _pushability(const MotionState &p_state, int p_i, const MotionParams &p_params) const;

	bool _separate_pair(MotionState &p_state, int p_a, int p_b, const MotionParams &p_params);
	double _separation_weight_a(const MotionState &p_state, int p_a, int p_b, const MotionParams &p_params) const;
	Vector2 _head_on_biased(const MotionState &p_state, int p_a, int p_b, const Vector2 &p_direction) const;
	bool _separate_pairs_hashed(MotionState &p_state, double p_cell_size, const MotionParams &p_params);
	static double _separation_hash_cell_size(const MotionState &p_state);
	static double _steering_hash_cell_size(const MotionState &p_state, double p_delta);
	static void _build_position_buckets(const MotionState &p_state, double p_cell_size, std::unordered_map<int64_t, std::vector<int32_t>> &r_buckets);

	bool _project_out_of_world(MotionState &p_state, int p_i, const MotionStatics &p_statics, const std::vector<float> &p_bounds, const MotionParams &p_params) const;
	bool _project_out_of_shape(MotionState &p_state, int p_i, const MotionStatics &p_statics, int p_shape) const;
	double _max_overlap_depth_hashed(const MotionState &p_state);

	// Exact Godot builtin twins.
	static double _angle_difference(double p_from, double p_to);
	static double _rotate_toward(double p_from, double p_to, double p_delta);
	static Vector2 _from_angle(double p_angle);
	static double _vec_angle(const Vector2 &p_v);
	static Vector2 _rotated(const Vector2 &p_v, double p_by);
};

} // namespace simnav
