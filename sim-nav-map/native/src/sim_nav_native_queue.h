#pragma once

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "core/sim_nav_long_pathfinder.h"
#include "sim_nav_native_facade.h"

// True background long-path planning (knife 5 M5) with a deterministic
// fixed-latency collection contract:
//
//   pump (tick T):   collect()     — results of the batch handed at tick T-1
//                                    become visible, in ticket order. Blocks
//                                    if the worker has not finished (in
//                                    practice it never does at ~0.07 ms/plan).
//                    begin_tick()  — hands everything currently pending to
//                                    the worker, which computes while the
//                                    game tick runs.
//
// Precisely: everything PENDING AT tick T's pump becomes visible at tick
// T+1's pump. A request enqueued after the pump (e.g. a same-tick watchdog
// replan) joins tick T+1's batch and lands at T+2. Either way arrival
// depends only on enqueue position relative to the pump — never on
// wall-clock thread timing (the CORE-019 lesson).
//
// Thread-safety contract (guarded, not just documented): the worker computes
// against a CLEAN map — begin_tick() refuses to hand a batch while the map
// has dirty navcells (falls back to synchronous compute with an error),
// prewarms the jump tables for every pending mask on the main thread first,
// and freezes the in-flight regime (SimNavNativeFacade::set_batch_in_flight):
// map mutations / flush / prewarm / invalidate are refused until collect(),
// and main-thread line checks route through a read-only table lookup. A
// clean map + built tables make every worker access read-only, so the main
// thread may keep calling movement_line_clear / queries concurrently.
//
// The worker touches godot::String (statuses inside the C++ result structs)
// but never Variant/Dictionary: String's COW refcount is atomic, and each
// side works on its own copies handed over under the batch mutex — Variant
// conversion happens exclusively on the main thread in take_result().
//
// Web nothreads builds report worker_supported() == false and compute each
// batch synchronously inside begin_tick() — same API, same fixed-latency
// schedule, main-thread cost only.
class SimNavNativeQueue : public godot::RefCounted {
	GDCLASS(SimNavNativeQueue, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	SimNavNativeQueue();
	~SimNavNativeQueue();

	void setup(const godot::Ref<SimNavNativeFacade> &p_facade);
	int64_t enqueue(const godot::Dictionary &p_query);
	bool cancel(int64_t p_ticket);
	// Hand pending requests to the worker (or compute synchronously without
	// thread support). Returns the batch size.
	int64_t begin_tick();
	// Block until the in-flight batch is done and publish its results.
	// Returns the number of results published.
	int64_t collect();
	bool has_result(int64_t p_ticket) const;
	godot::Dictionary take_result(int64_t p_ticket);
	int64_t pending_count() const;
	int64_t result_count() const;
	bool worker_supported() const;
	void clear();
	godot::Dictionary get_diagnostics() const;

private:
	struct PendingRequest {
		int64_t ticket = 0;
		simnav::LongPathQuery query;
	};

	godot::Ref<SimNavNativeFacade> facade;
	int64_t next_ticket = 1;
	std::vector<PendingRequest> pending;
	// Results held as C++ structs; Dictionary conversion happens on the main
	// thread in take_result (no Variant work on the worker).
	std::unordered_map<int64_t, simnav::LongPathResult> results;
	std::vector<int64_t> result_order;
	std::unordered_set<int64_t> cancelled;
	std::unordered_set<int64_t> in_flight_tickets;
	int64_t processed_count = 0;
	int64_t batch_count = 0;
	int64_t sync_fallback_count = 0;
	int64_t stale_result_count = 0;
	int64_t last_batch_size = 0;
	// Written by the worker (under the batch mutex) and read by main-thread
	// diagnostics that may run mid-flight.
	std::atomic<int64_t> last_batch_compute_usec{ 0 };
	int64_t last_collect_wait_usec = 0;

	// Worker machinery (unused on nothreads builds).
	struct WorkerBatchEntry {
		int64_t ticket = 0;
		simnav::LongPathQuery query;
		simnav::LongPathResult result;
	};
	std::vector<WorkerBatchEntry> worker_batch;
	bool batch_in_flight = false;
	// Main-thread-only: whether the current in-flight batch was computed
	// synchronously at begin_tick (nothreads build or dirty-map fallback).
	bool current_batch_synchronous = false;
	bool worker_started = false;
	std::thread worker_thread;
	std::mutex worker_mutex;
	std::condition_variable worker_cv;
	// 0 = idle, 1 = batch ready to compute, 2 = batch done, 3 = quit.
	int worker_state = 0;

	void _worker_loop();
	void _ensure_worker();
	void _compute_batch(std::vector<WorkerBatchEntry> &p_batch);
	void _publish_batch(std::vector<WorkerBatchEntry> &p_batch, int64_t &r_published);
};
