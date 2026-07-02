#include "sim_nav_native_queue.h"

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
#define SIMNAV_QUEUE_NO_THREADS 1
#else
#define SIMNAV_QUEUE_NO_THREADS 0
#endif

using namespace godot;

void SimNavNativeQueue::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "facade"), &SimNavNativeQueue::setup);
	ClassDB::bind_method(D_METHOD("enqueue", "query"), &SimNavNativeQueue::enqueue);
	ClassDB::bind_method(D_METHOD("cancel", "ticket"), &SimNavNativeQueue::cancel);
	ClassDB::bind_method(D_METHOD("begin_tick"), &SimNavNativeQueue::begin_tick);
	ClassDB::bind_method(D_METHOD("collect"), &SimNavNativeQueue::collect);
	ClassDB::bind_method(D_METHOD("has_result", "ticket"), &SimNavNativeQueue::has_result);
	ClassDB::bind_method(D_METHOD("take_result", "ticket"), &SimNavNativeQueue::take_result);
	ClassDB::bind_method(D_METHOD("pending_count"), &SimNavNativeQueue::pending_count);
	ClassDB::bind_method(D_METHOD("result_count"), &SimNavNativeQueue::result_count);
	ClassDB::bind_method(D_METHOD("worker_supported"), &SimNavNativeQueue::worker_supported);
	ClassDB::bind_method(D_METHOD("clear"), &SimNavNativeQueue::clear);
	ClassDB::bind_method(D_METHOD("get_diagnostics"), &SimNavNativeQueue::get_diagnostics);
}

SimNavNativeQueue::SimNavNativeQueue() {
}

SimNavNativeQueue::~SimNavNativeQueue() {
#if !SIMNAV_QUEUE_NO_THREADS
	if (worker_started) {
		{
			std::unique_lock<std::mutex> lock(worker_mutex);
			worker_state = 3; // quit
		}
		worker_cv.notify_all();
		if (worker_thread.joinable()) {
			worker_thread.join();
		}
	}
#endif
}

void SimNavNativeQueue::setup(const Ref<SimNavNativeFacade> &p_facade) {
	ERR_FAIL_COND(p_facade.is_null());
	facade = p_facade;
}

int64_t SimNavNativeQueue::enqueue(const Dictionary &p_query) {
	ERR_FAIL_COND_V_MSG(facade.is_null(), 0, "queue has no facade (call setup first)");
	PendingRequest request;
	request.ticket = next_ticket;
	next_ticket += 1;
	request.query = SimNavNativeFacade::query_from_dict_public(p_query);
	pending.push_back(std::move(request));
	return pending.back().ticket;
}

bool SimNavNativeQueue::cancel(int64_t p_ticket) {
	if (p_ticket <= 0) {
		return false;
	}
	cancelled.insert(p_ticket);
	bool removed = false;
	for (size_t i = pending.size(); i > 0; i--) {
		if (pending[i - 1].ticket == p_ticket) {
			pending.erase(pending.begin() + (i - 1));
			removed = true;
		}
	}
	if (results.erase(p_ticket) > 0) {
		stale_result_count += 1;
		removed = true;
	}
	// A ticket in the in-flight batch still computes; its result is dropped
	// as stale at collect(). Like the GDScript queue's _in_worker branch,
	// cancelling it counts as removed.
	if (in_flight_tickets.count(p_ticket)) {
		removed = true;
	}
	return removed;
}

int64_t SimNavNativeQueue::begin_tick() {
	ERR_FAIL_COND_V_MSG(facade.is_null(), 0, "queue has no facade (call setup first)");
	ERR_FAIL_COND_V_MSG(batch_in_flight, 0, "previous batch not collected (call collect first)");
	if (pending.empty()) {
		return 0;
	}

	std::vector<WorkerBatchEntry> batch;
	batch.reserve(pending.size());
	for (PendingRequest &request : pending) {
		WorkerBatchEntry entry;
		entry.ticket = request.ticket;
		entry.query = std::move(request.query);
		batch.push_back(std::move(entry));
	}
	pending.clear();
	last_batch_size = (int64_t)batch.size();
	batch_count += 1;
	in_flight_tickets.clear();
	for (const WorkerBatchEntry &entry : batch) {
		in_flight_tickets.insert(entry.ticket);
	}

	// Worker accesses must be pure reads: the map must be clean and every
	// mask's jump tables built before the batch leaves the main thread.
	bool map_clean = !facade->core_map_for_queue().has_dirty_navcells();
	if (map_clean) {
		std::unordered_set<int32_t> masks;
		for (const WorkerBatchEntry &entry : batch) {
			if (entry.query.pass_mask != 0 && masks.insert(entry.query.pass_mask).second) {
				facade->core_facade().long_path().prewarm_jump_point_cache(entry.query.pass_mask);
			}
		}
	}

#if SIMNAV_QUEUE_NO_THREADS
	bool use_worker = false;
#else
	bool use_worker = map_clean;
#endif
	if (!use_worker) {
		if (!map_clean) {
			ERR_PRINT("[SimNavNativeQueue] begin_tick with dirty navcells — flush (recompute_dirty) before begin_tick; computing this batch synchronously");
			sync_fallback_count += 1;
		}
		uint64_t start_usec = Time::get_singleton()->get_ticks_usec();
		_compute_batch(batch);
		last_batch_compute_usec = (int64_t)(Time::get_singleton()->get_ticks_usec() - start_usec);
		worker_batch = std::move(batch);
		batch_in_flight = true;
		current_batch_synchronous = true;
		return last_batch_size;
	}
	current_batch_synchronous = false;

#if !SIMNAV_QUEUE_NO_THREADS
	_ensure_worker();
	facade->set_batch_in_flight(true);
	{
		std::unique_lock<std::mutex> lock(worker_mutex);
		worker_batch = std::move(batch);
		worker_state = 1; // ready to compute
	}
	worker_cv.notify_all();
	batch_in_flight = true;
#endif
	return last_batch_size;
}

int64_t SimNavNativeQueue::collect() {
	if (!batch_in_flight) {
		return 0;
	}
	int64_t published = 0;
#if SIMNAV_QUEUE_NO_THREADS
	_publish_batch(worker_batch, published);
	worker_batch.clear();
	batch_in_flight = false;
	in_flight_tickets.clear();
#else
	if (current_batch_synchronous) {
		// Synchronous-fallback batch (dirty-map guard) — already computed.
		_publish_batch(worker_batch, published);
		worker_batch.clear();
		batch_in_flight = false;
		in_flight_tickets.clear();
		return published;
	}
	uint64_t wait_start = Time::get_singleton()->get_ticks_usec();
	{
		std::unique_lock<std::mutex> lock(worker_mutex);
		worker_cv.wait(lock, [this] { return worker_state == 2 || worker_state == 0; });
		last_collect_wait_usec = (int64_t)(Time::get_singleton()->get_ticks_usec() - wait_start);
		_publish_batch(worker_batch, published);
		worker_batch.clear();
		worker_state = 0; // idle
	}
	batch_in_flight = false;
	in_flight_tickets.clear();
	facade->set_batch_in_flight(false);
#endif
	return published;
}

void SimNavNativeQueue::_publish_batch(std::vector<WorkerBatchEntry> &p_batch, int64_t &r_published) {
	r_published = 0;
	for (WorkerBatchEntry &entry : p_batch) {
		if (cancelled.count(entry.ticket)) {
			stale_result_count += 1;
			continue;
		}
		results[entry.ticket] = std::move(entry.result);
		result_order.push_back(entry.ticket);
		processed_count += 1;
		r_published += 1;
	}
}

void SimNavNativeQueue::_compute_batch(std::vector<WorkerBatchEntry> &p_batch) {
	for (WorkerBatchEntry &entry : p_batch) {
		entry.result = facade->core_facade().compute_path_result(entry.query);
	}
}

void SimNavNativeQueue::_ensure_worker() {
#if !SIMNAV_QUEUE_NO_THREADS
	if (worker_started) {
		return;
	}
	worker_started = true;
	worker_thread = std::thread(&SimNavNativeQueue::_worker_loop, this);
#endif
}

void SimNavNativeQueue::_worker_loop() {
#if !SIMNAV_QUEUE_NO_THREADS
	while (true) {
		std::unique_lock<std::mutex> lock(worker_mutex);
		worker_cv.wait(lock, [this] { return worker_state == 1 || worker_state == 3; });
		if (worker_state == 3) {
			return;
		}
		uint64_t start_usec = Time::get_singleton()->get_ticks_usec();
		_compute_batch(worker_batch);
		last_batch_compute_usec = (int64_t)(Time::get_singleton()->get_ticks_usec() - start_usec);
		worker_state = 2; // done
		lock.unlock();
		worker_cv.notify_all();
	}
#endif
}

bool SimNavNativeQueue::has_result(int64_t p_ticket) const {
	return results.count(p_ticket) > 0;
}

Dictionary SimNavNativeQueue::take_result(int64_t p_ticket) {
	auto found = results.find(p_ticket);
	if (found == results.end()) {
		return Dictionary();
	}
	Dictionary out = SimNavNativeFacade::result_to_dict_public(found->second);
	results.erase(found);
	return out;
}

int64_t SimNavNativeQueue::pending_count() const {
	// Consumer view: queued + in-flight (no result visible yet).
	return (int64_t)pending.size() + (batch_in_flight ? (int64_t)worker_batch.size() : 0);
}

int64_t SimNavNativeQueue::result_count() const {
	return (int64_t)results.size();
}

bool SimNavNativeQueue::worker_supported() const {
#if SIMNAV_QUEUE_NO_THREADS
	return false;
#else
	return true;
#endif
}

void SimNavNativeQueue::clear() {
	collect();
	pending.clear();
	results.clear();
	result_order.clear();
	cancelled.clear();
	last_batch_size = 0;
}

Dictionary SimNavNativeQueue::get_diagnostics() const {
	Dictionary out;
	out["next_ticket"] = next_ticket;
	out["pending_count"] = pending_count();
	out["result_count"] = result_count();
	out["batch_in_flight"] = batch_in_flight;
	out["processed_count"] = processed_count;
	out["batch_count"] = batch_count;
	out["sync_fallback_count"] = sync_fallback_count;
	out["stale_result_count"] = stale_result_count;
	out["last_batch_size"] = last_batch_size;
	out["last_batch_compute_usec"] = last_batch_compute_usec.load();
	out["last_collect_wait_usec"] = last_collect_wait_usec;
	out["worker_supported"] = worker_supported();
	return out;
}
