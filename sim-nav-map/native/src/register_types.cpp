#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "sim_nav_native_facade.h"
#include "sim_nav_native_jump_point_cache.h"
#include "sim_nav_native_map.h"
#include "sim_nav_native_motion_solver.h"
#include "sim_nav_native_queue.h"
#include "sim_nav_native_support.h"

using namespace godot;

void initialize_simnav_native_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(SimNavNativeSupport);
	GDREGISTER_CLASS(SimNavNativeMap);
	GDREGISTER_CLASS(SimNavNativeJumpPointCache);
	GDREGISTER_CLASS(SimNavNativeFacade);
	GDREGISTER_CLASS(SimNavNativeMotionSolver);
	GDREGISTER_CLASS(SimNavNativeQueue);
}

void uninitialize_simnav_native_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT simnav_native_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_simnav_native_module);
	init_obj.register_terminator(uninitialize_simnav_native_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
