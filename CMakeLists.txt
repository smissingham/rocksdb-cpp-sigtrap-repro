cmake_minimum_required(VERSION 3.20)

project(rocksdb_cpp_sigtrap_repro VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(ROCKSDB REQUIRED rocksdb)

add_executable(rocksdb-cpp-repro src/main.cpp)

target_include_directories(
  rocksdb-cpp-repro
  PRIVATE
  ${ROCKSDB_INCLUDE_DIRS}
)

target_link_directories(
  rocksdb-cpp-repro
  PRIVATE
  ${ROCKSDB_LIBRARY_DIRS}
)

target_link_libraries(
  rocksdb-cpp-repro
  PRIVATE
  ${ROCKSDB_LIBRARIES}
)

target_compile_options(
  rocksdb-cpp-repro
  PRIVATE
  ${ROCKSDB_CFLAGS_OTHER}
)
