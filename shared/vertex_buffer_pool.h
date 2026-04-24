// vertex_buffer_pool.h — Pre-allocated CPU vertex vector pool
//
// Avoids repeated heap allocation of std::vector<T> during tessellation.
// Each stroke acquires a pre-reserved vector, tessellates into it, uploads
// to GPU, then releases it back to the pool.
//
// Usage:
//   auto& verts = pool.acquire();   // Get pre-reserved vector
//   tessellateStroke(..., verts);    // Fill with vertices
//   memcpy(gpuBuf, verts.data(), ...); // Upload
//   pool.release(verts);            // Return to pool (clear, don't dealloc)
//
// Thread safety: NOT thread-safe. Use from render thread only.

#pragma once

#include <vector>
#include <cstdint>
#include <algorithm>

template <typename T>
class VertexBufferPool {
public:
  /// Create pool with N pre-reserved buffers, each with initialCapacity.
  explicit VertexBufferPool(int poolSize = 4, size_t initialCapacity = 32768)
      : initialCapacity_(initialCapacity) {
    pool_.resize(poolSize);
    inUse_.resize(poolSize, false);
    for (int i = 0; i < poolSize; i++) {
      pool_[i].reserve(initialCapacity);
    }
  }

  /// Acquire a pre-reserved buffer. Returns reference + slot index.
  /// If all buffers are in use, recycles the oldest one.
  std::vector<T>& acquire(int& outSlot) {
    // Find first free slot
    for (int i = 0; i < (int)pool_.size(); i++) {
      if (!inUse_[i]) {
        inUse_[i] = true;
        pool_[i].clear(); // Reset size but keep capacity
        outSlot = i;
        return pool_[i];
      }
    }
    // All in use — grow pool
    int newSlot = (int)pool_.size();
    pool_.emplace_back();
    pool_.back().reserve(initialCapacity_);
    inUse_.push_back(true);
    outSlot = newSlot;
    return pool_.back();
  }

  /// Convenience: acquire without needing slot index.
  std::vector<T>& acquire() {
    int slot;
    return acquire(slot);
  }

  /// Release a buffer back to the pool by slot index.
  void release(int slot) {
    if (slot >= 0 && slot < (int)inUse_.size()) {
      inUse_[slot] = false;
      // Shrink oversized buffers to prevent memory bloat
      if (pool_[slot].capacity() > initialCapacity_ * 4) {
        pool_[slot].clear();
        pool_[slot].shrink_to_fit();
        pool_[slot].reserve(initialCapacity_);
      }
    }
  }

  /// Release all buffers (call on stroke end / clear).
  void releaseAll() {
    for (int i = 0; i < (int)inUse_.size(); i++) {
      inUse_[i] = false;
    }
  }

  /// Get total pool size.
  int size() const { return (int)pool_.size(); }

  /// Get number of buffers currently in use.
  int inUseCount() const {
    int count = 0;
    for (bool b : inUse_) { if (b) count++; }
    return count;
  }

  /// Total bytes reserved across all pool buffers.
  size_t totalReservedBytes() const {
    size_t total = 0;
    for (const auto& v : pool_) {
      total += v.capacity() * sizeof(T);
    }
    return total;
  }

  /// Trim all free buffers to initial capacity (memory pressure relief).
  void trim() {
    for (int i = 0; i < (int)pool_.size(); i++) {
      if (!inUse_[i] && pool_[i].capacity() > initialCapacity_) {
        pool_[i].clear();
        pool_[i].shrink_to_fit();
        pool_[i].reserve(initialCapacity_);
      }
    }
  }

private:
  std::vector<std::vector<T>> pool_;
  std::vector<bool> inUse_;
  size_t initialCapacity_;
};
