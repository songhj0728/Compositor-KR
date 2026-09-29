# Spike: the C++ Core, its tests, and the host program built against both Cores. Not part of the app; see README.md.
#
#   cmake -S Spikes/CoreModel -B build/spike [-DSWIFT_CORE_DIR=<dir with CompositorCore.lib/.dll or .dylib>]
#   cmake --build build/spike --config Release
#   ctest --test-dir build/spike --build-config Release --output-on-failure
cmake_minimum_required(VERSION 3.21)
project(CoreModelSpike LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(MSVC)
    # Source files are UTF-8 (Korean test strings); warnings on.
    add_compile_options(/utf-8 /W4 /permissive-)
else()
    add_compile_options(-Wall -Wextra)
endif()
# Keep the DLLs next to the programs that load them.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

enable_testing()

# The C++ Core.
add_library(compositor_core_cpp STATIC cpp/src/core.cpp)
target_include_directories(compositor_core_cpp PUBLIC cpp/include)
set_target_properties(compositor_core_cpp PROPERTIES POSITION_INDEPENDENT_CODE ON)

add_executable(core_tests cpp/tests/core_tests.cpp)
target_link_libraries(core_tests PRIVATE compositor_core_cpp)
add_test(NAME cpp_core COMMAND core_tests)

# The C++ Core behind the shared C header.
add_library(CompositorCoreCpp SHARED cpp/src/c_api.cpp)
target_include_directories(CompositorCoreCpp PUBLIC include)
target_compile_definitions(CompositorCoreCpp PRIVATE CC_BUILDING_DLL)
target_link_libraries(CompositorCoreCpp PRIVATE compositor_core_cpp)

add_executable(host_cpp_core hosts/cpp/host.cpp)
target_link_libraries(host_cpp_core PRIVATE CompositorCoreCpp)
add_test(NAME host_on_cpp_core COMMAND host_cpp_core)

# The same host against the Swift Core, once `swift build` has made it.
set(SWIFT_CORE_DIR "" CACHE PATH "Folder with the Swift Core's CompositorCore library (swift build output)")
if(SWIFT_CORE_DIR)
    add_library(CompositorCoreSwift SHARED IMPORTED)
    if(WIN32)
        set_target_properties(CompositorCoreSwift PROPERTIES
            IMPORTED_IMPLIB ${SWIFT_CORE_DIR}/CompositorCore.lib
            IMPORTED_LOCATION ${SWIFT_CORE_DIR}/CompositorCore.dll)
    else()
        set_target_properties(CompositorCoreSwift PROPERTIES
            IMPORTED_LOCATION ${SWIFT_CORE_DIR}/libCompositorCore${CMAKE_SHARED_LIBRARY_SUFFIX})
    endif()
    target_include_directories(CompositorCoreSwift INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/include)
    add_executable(host_swift_core hosts/cpp/host.cpp)
    target_link_libraries(host_swift_core PRIVATE CompositorCoreSwift)
    if(WIN32)
        # The Swift Core's DLL, and the Swift runtime DLLs it needs, must be found at run time.
        add_custom_command(TARGET host_swift_core POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SWIFT_CORE_DIR}/CompositorCore.dll $<TARGET_FILE_DIR:host_swift_core>)
    else()
        set_target_properties(host_swift_core PROPERTIES BUILD_RPATH ${SWIFT_CORE_DIR})
    endif()
    add_test(NAME host_on_swift_core COMMAND host_swift_core)
endif()
