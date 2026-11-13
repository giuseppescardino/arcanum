# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_arcanum")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
# Flutter reaches this folder through a symlink in
# linux/flutter/ephemeral/.plugin_symlinks/, and on Linux ".." follows the
# link target (app/rust_builder/linux), so the path is relative to that.
apply_cargokit(${PROJECT_NAME} ../../../core/arcanum-ffi rust_lib_arcanum "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rust_lib_arcanum_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
