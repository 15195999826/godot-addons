#include "sim_nav_native_support.h"

#include <cmath>

#include <godot_cpp/core/class_db.hpp>

#include "core/sim_nav_motion_solver.h"

using namespace godot;

// Bumped per milestone; smokes assert non-empty, not a specific value.
static const char *SIMNAV_NATIVE_VERSION = "0.1.0-m1";

void SimNavNativeSupport::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &SimNavNativeSupport::version);
	ClassDB::bind_method(D_METHOD("build_info"), &SimNavNativeSupport::build_info);
	ClassDB::bind_method(D_METHOD("probe_from_angle", "angles"), &SimNavNativeSupport::probe_from_angle);
	ClassDB::bind_method(D_METHOD("probe_from_angle_via_double", "angles"), &SimNavNativeSupport::probe_from_angle_via_double);
	ClassDB::bind_method(D_METHOD("probe_vec_angle", "vectors"), &SimNavNativeSupport::probe_vec_angle);
	ClassDB::bind_method(D_METHOD("probe_normalized", "vectors"), &SimNavNativeSupport::probe_normalized);
	ClassDB::bind_method(D_METHOD("probe_length", "vectors"), &SimNavNativeSupport::probe_length);
	ClassDB::bind_method(D_METHOD("probe_distance", "pairs"), &SimNavNativeSupport::probe_distance);
	ClassDB::bind_method(D_METHOD("probe_dot", "pairs"), &SimNavNativeSupport::probe_dot);
	ClassDB::bind_method(D_METHOD("probe_rotated", "vectors", "angles"), &SimNavNativeSupport::probe_rotated);
}

PackedVector2Array SimNavNativeSupport::probe_from_angle(const PackedFloat64Array &p_angles) const {
	PackedVector2Array out;
	out.resize(p_angles.size());
	Vector2 *w = out.ptrw();
	for (int64_t i = 0; i < p_angles.size(); i++) {
		float angle = (float)p_angles[i];
		w[i] = Vector2(std::cos(angle), std::sin(angle));
	}
	return out;
}

PackedVector2Array SimNavNativeSupport::probe_from_angle_via_double(const PackedFloat64Array &p_angles) const {
	PackedVector2Array out;
	out.resize(p_angles.size());
	Vector2 *w = out.ptrw();
	for (int64_t i = 0; i < p_angles.size(); i++) {
		float angle = (float)p_angles[i];
		w[i] = Vector2((float)std::cos((double)angle), (float)std::sin((double)angle));
	}
	return out;
}

PackedFloat64Array SimNavNativeSupport::probe_vec_angle(const PackedVector2Array &p_vectors) const {
	PackedFloat64Array out;
	out.resize(p_vectors.size());
	double *w = out.ptrw();
	for (int64_t i = 0; i < p_vectors.size(); i++) {
		w[i] = (double)std::atan2((float)p_vectors[i].y, (float)p_vectors[i].x);
	}
	return out;
}

PackedVector2Array SimNavNativeSupport::probe_normalized(const PackedVector2Array &p_vectors) const {
	PackedVector2Array out;
	out.resize(p_vectors.size());
	Vector2 *w = out.ptrw();
	for (int64_t i = 0; i < p_vectors.size(); i++) {
		w[i] = p_vectors[i].normalized();
	}
	return out;
}

PackedFloat64Array SimNavNativeSupport::probe_length(const PackedVector2Array &p_vectors) const {
	PackedFloat64Array out;
	out.resize(p_vectors.size());
	double *w = out.ptrw();
	for (int64_t i = 0; i < p_vectors.size(); i++) {
		w[i] = (double)p_vectors[i].length();
	}
	return out;
}

PackedFloat64Array SimNavNativeSupport::probe_distance(const PackedVector2Array &p_pairs) const {
	PackedFloat64Array out;
	out.resize(p_pairs.size() / 2);
	double *w = out.ptrw();
	for (int64_t i = 0; i < p_pairs.size() / 2; i++) {
		w[i] = (double)p_pairs[i * 2].distance_to(p_pairs[i * 2 + 1]);
	}
	return out;
}

PackedFloat64Array SimNavNativeSupport::probe_dot(const PackedVector2Array &p_pairs) const {
	PackedFloat64Array out;
	out.resize(p_pairs.size() / 2);
	double *w = out.ptrw();
	for (int64_t i = 0; i < p_pairs.size() / 2; i++) {
		w[i] = (double)p_pairs[i * 2].dot(p_pairs[i * 2 + 1]);
	}
	return out;
}

PackedVector2Array SimNavNativeSupport::probe_rotated(const PackedVector2Array &p_vectors, const PackedFloat64Array &p_angles) const {
	// Solver-twin semantics: float trig via double-then-narrow (matches
	// MotionSolver::_rotated and, per the 200k-sample probe, the engine
	// binary's own sinf/cosf).
	PackedVector2Array out;
	out.resize(p_vectors.size());
	Vector2 *w = out.ptrw();
	for (int64_t i = 0; i < p_vectors.size(); i++) {
		float by = (float)p_angles[i];
		float sine = (float)std::sin((double)by);
		float cosine = (float)std::cos((double)by);
		w[i] = Vector2(p_vectors[i].x * cosine - p_vectors[i].y * sine, p_vectors[i].x * sine + p_vectors[i].y * cosine);
	}
	return out;
}

String SimNavNativeSupport::version() const {
	return String(SIMNAV_NATIVE_VERSION);
}

Dictionary SimNavNativeSupport::build_info() const {
	Dictionary info;
	info["version"] = String(SIMNAV_NATIVE_VERSION);
#if defined(__EMSCRIPTEN__)
	info["platform"] = "web";
#elif defined(_WIN32)
	info["platform"] = "windows";
#elif defined(__linux__)
	info["platform"] = "linux";
#elif defined(__APPLE__)
	info["platform"] = "macos";
#else
	info["platform"] = "other";
#endif
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
	info["threads"] = false;
#else
	info["threads"] = true;
#endif
#ifdef DEBUG_ENABLED
	info["build"] = "debug";
#else
	info["build"] = "release";
#endif
	return info;
}
