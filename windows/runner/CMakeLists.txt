cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "engine_channel_windows.cpp"
  "tray_icon_windows.cpp"
  "../../desktop_shared/desktop_engine.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
# v4.36k: flutter_wrapper_plugin joined the link. engine_channel_windows.cpp
# drives the 3.47 C++ embedding the same way url_launcher_windows does —
# PluginRegistrarManager::GetInstance()->GetRegistrar<PluginRegistrar>(ref) —
# and those symbols (plugin_registrar.cc: the PluginRegistrar ctor,
# PluginRegistrarManager::GetInstance, OnRegistrarDestroyed) are compiled
# ONLY into flutter_wrapper_plugin (windows/flutter/CMakeLists.txt:
# CPP_WRAPPER_SOURCES_PLUGIN). The stock template links wrapper_app alone
# because a stock runner never touches the plugin registrar API. Run
# 42218962864 died at exactly these three LNK2019s. The two wrapper libs
# share core_implementations.cc/standard_codec.cc, but static-archive
# extraction is demand-driven — the second copy is simply never pulled in,
# so there is no duplicate-symbol risk.
target_link_libraries(${BINARY_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# v4.40 — wininet: the system-proxy companion of the tunnel mode
# (InternetSetOptionW notifies WinInet consumers after the registry write;
# see desktop_shared/desktop_engine.cpp SetSystemProxy).
target_link_libraries(${BINARY_NAME} PRIVATE "wininet.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)


# v4.36 desktop round: the shared engine layer (../../desktop_shared) and the
# frozen zeptun C header (native/zeptun/include/zeptun.h at pin 08a1ab05).
# CMAKE_CURRENT_SOURCE_DIR is <repo>/windows/runner — the repo root is TWO
# levels up (runner -> windows -> root). v4.36h: was three levels (one above
# the repo), so MSVC never found zeptun.h (C1083) while the linux leg —
# whose CMakeLists resolves the same header through CMAKE_SOURCE_DIR — did.
target_include_directories(${BINARY_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../.."
  "${CMAKE_CURRENT_SOURCE_DIR}/../../native/zeptun/include")

# v4.36i: the bounded core-log capture uses ISO-C fopen (rotating appends —
# the same calls the linux leg compiles clean). MSVC flags fopen as C4996
# (deprecation, "consider fopen_s"), and the template's /WX turns it fatal.
# Silence it for THIS file only — /W4 /WX stay fully armed everywhere else.
set_source_files_properties("../../desktop_shared/desktop_engine.cpp" PROPERTIES
  COMPILE_DEFINITIONS "_CRT_SECURE_NO_WARNINGS")

# v4.36j: the LNK1327 manifest-merge conflict (run 42216088653, and the same
# first-flight failure flutter/flutter#98416 hit): link.exe's generated
# manifest carries the DEFAULT UAC fragment (asInvoker) while
# runner.exe.manifest ships requireAdministrator — mt.exe refuses to merge
# ("Values of attribute 'level' not equal in different manifest snippets")
# and LINK reports — and hides — "failure during running mt.exe". The
# matching /MANIFESTUAC makes the linker fragment agree with the file, so
# the merge has two identical entries. Elevation itself still comes from the
# file (the flag is the agreement, not the source of truth).
target_link_options(${BINARY_NAME} PRIVATE "/MANIFESTUAC:level='requireAdministrator'")
