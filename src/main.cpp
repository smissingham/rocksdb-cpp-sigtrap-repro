#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <rocksdb/utilities/optimistic_transaction_db.h>

namespace {

std::atomic<bool> k_shutdown_requested{false};

void handle_signal(int signum) {
  if (signum == SIGINT || signum == SIGTERM) {
    k_shutdown_requested.store(true, std::memory_order_relaxed);
  }
}

std::string env_or_default(const char* key, const char* fallback) {
  const char* value = std::getenv(key);
  if (value == nullptr || value[0] == '\0') {
    return std::string(fallback);
  }
  return std::string(value);
}

rocksdb::DBOptions build_db_options() {
  rocksdb::DBOptions opts;
  opts.create_if_missing = true;
  opts.create_missing_column_families = true;
  opts.info_log_level = rocksdb::InfoLogLevel::WARN_LEVEL;
  opts.max_open_files = 1024;
  opts.max_background_jobs = 28;
  opts.use_adaptive_mutex = true;
  opts.allow_concurrent_memtable_write = true;
  opts.enable_write_thread_adaptive_yield = true;
  opts.max_subcompactions = 4;
  return opts;
}

rocksdb::ColumnFamilyOptions build_cf_options() {
  rocksdb::ColumnFamilyOptions opts;
  opts.compression = rocksdb::kLZ4Compression;
  opts.level_compaction_dynamic_level_bytes = true;
  opts.enable_blob_files = true;
  opts.min_blob_size = 4096;
  opts.blob_file_size = 268435456;
  opts.enable_blob_garbage_collection = true;
  opts.blob_garbage_collection_age_cutoff = 0.5;
  opts.blob_garbage_collection_force_threshold = 0.5;
  return opts;
}

}  // namespace

int main() {
  std::signal(SIGINT, handle_signal);
  std::signal(SIGTERM, handle_signal);

  const std::string db_path = env_or_default("REPRO_DB_PATH", "./db");

  std::cerr << "[repro] opening rocksdb at " << db_path << std::endl;

  auto db_options = build_db_options();
  auto cf_options = build_cf_options();

  std::vector<rocksdb::ColumnFamilyDescriptor> cf_descriptors;
  cf_descriptors.emplace_back(rocksdb::kDefaultColumnFamilyName, cf_options);

  std::vector<rocksdb::ColumnFamilyHandle*> cf_handles;
  rocksdb::OptimisticTransactionDB* tx_db = nullptr;

  const rocksdb::Status open_status = rocksdb::OptimisticTransactionDB::Open(
      db_options,
      db_path,
      cf_descriptors,
      &cf_handles,
      &tx_db);

  if (!open_status.ok()) {
    std::cerr << "[repro] open failed: " << open_status.ToString() << std::endl;
    return 1;
  }

  std::unique_ptr<rocksdb::OptimisticTransactionDB> db_guard(tx_db);

  std::cerr << "READY" << std::endl;

  const std::size_t write_count =
      static_cast<std::size_t>(std::stoull(env_or_default("REPRO_WRITE_COUNT", "20000")));
  const std::string payload(256, 'x');
  for (std::size_t i = 0; i < write_count; ++i) {
    const std::string key = "key-" + std::to_string(i);
    const rocksdb::Status write_status = tx_db->Put(rocksdb::WriteOptions(), key, payload);
    if (!write_status.ok()) {
      std::cerr << "[repro] write failed at i=" << i << ": " << write_status.ToString()
                << std::endl;
      break;
    }
  }

  while (!k_shutdown_requested.load(std::memory_order_relaxed)) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }

  std::cerr << "SHUTDOWN" << std::endl;

  for (auto* handle : cf_handles) {
    delete handle;
  }

  return 0;
}
