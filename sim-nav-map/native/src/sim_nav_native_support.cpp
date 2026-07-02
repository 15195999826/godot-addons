#include "sim_nav_native_support.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Bumped per milestone; smokes assert non-empty, not a specific value.
static const char *SIMNAV_NATIVE_VERSION = "0.1.0-m1";

void SimNavNativeSupport::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &SimNavNativeSupport::version);
	ClassDB::bind_method(D_METHOD("build_info"), &SimNavNativeSupport::build_info);
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
