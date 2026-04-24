// tessellation_thread.h — Background tessellation worker
//
// Offloads CPU-intensive tessellation to a dedicated worker thread.
// Uses double-buffered results: worker writes to back buffer, render
// thread reads front buffer. Swap happens atomically when worker finishes.
//
// Architecture:
//   Render thread:  submit(task) → read front buffer → draw
//   Worker thread:  dequeue task → tessellate → write back buffer → swap
//
// Thread safety: mutex + condition variable for task queue.
//                Atomic flag for buffer swap.

#pragma once

#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

template <typename VertexT>
class TessellationThread {
public:
  /// Task: a callable that tessellates into the provided vertex vector.
  using TessTask = std::function<void(std::vector<VertexT>&)>;

  TessellationThread() = default;

  /// Start the worker thread.
  void start() {
    if (running_.load()) return;
    running_ = true;
    worker_ = std::thread(&TessellationThread::workerLoop, this);
  }

  /// Submit a tessellation task. If worker is busy, the task replaces
  /// the pending one (latest-wins — we only care about the newest stroke).
  void submit(TessTask task) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pendingTask_ = std::move(task);
      hasTask_ = true;
    }
    cv_.notify_one();
  }

  /// Check if new results are available and swap to front buffer.
  /// Returns true if front buffer was updated (caller should re-upload).
  bool trySwap() {
    if (!resultReady_.load(std::memory_order_acquire)) return false;

    // Swap front ↔ back pointers
    {
      std::lock_guard<std::mutex> lock(swapMutex_);
      std::swap(frontBuffer_, backBuffer_);
    }
    resultReady_.store(false, std::memory_order_release);
    return true;
  }

  /// Get the front buffer (read-only, safe from render thread).
  const std::vector<VertexT>& frontVertices() const {
    return *frontBuffer_;
  }

  /// Get front buffer vertex count.
  uint32_t frontVertexCount() const {
    return static_cast<uint32_t>(frontBuffer_->size());
  }

  /// Whether the worker is currently processing a task.
  bool isBusy() const { return busy_.load(std::memory_order_relaxed); }

  /// Stop the worker thread and join.
  void stop() {
    if (!running_.load()) return;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = false;
    }
    cv_.notify_one();
    if (worker_.joinable()) worker_.join();
  }

  ~TessellationThread() { stop(); }

  // Non-copyable, non-movable
  TessellationThread(const TessellationThread&) = delete;
  TessellationThread& operator=(const TessellationThread&) = delete;

private:
  void workerLoop() {
    while (running_.load()) {
      TessTask task;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return hasTask_ || !running_.load(); });
        if (!running_.load()) break;
        task = std::move(pendingTask_);
        hasTask_ = false;
      }

      if (task) {
        busy_.store(true, std::memory_order_relaxed);

        // Tessellate into back buffer
        {
          std::lock_guard<std::mutex> lock(swapMutex_);
          backBuffer_->clear();
        }
        task(*backBuffer_);

        // Signal result ready for swap
        resultReady_.store(true, std::memory_order_release);
        busy_.store(false, std::memory_order_relaxed);
      }
    }
  }

  // ─── Thread ────────────────────────────────────────────────────
  std::thread worker_;
  std::atomic<bool> running_{false};
  std::atomic<bool> busy_{false};

  // ─── Task queue (latest-wins) ─────────────────────────────────
  std::mutex mutex_;
  std::condition_variable cv_;
  TessTask pendingTask_;
  bool hasTask_ = false;

  // ─── Double buffer ────────────────────────────────────────────
  std::vector<VertexT> bufferA_;
  std::vector<VertexT> bufferB_;
  std::vector<VertexT>* frontBuffer_ = &bufferA_;
  std::vector<VertexT>* backBuffer_ = &bufferB_;
  std::mutex swapMutex_;
  std::atomic<bool> resultReady_{false};
};
