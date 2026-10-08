# The code Compositor's macOS and Windows builds share, built outside Xcode.
#
# The macOS app is still built by Compositor-KR.xcodeproj, which compiles these same sources straight from
# Compositor/Rendering. This file builds them on their own — on Windows (MSVC) and on macOS (Clang) — with the tests
# that check they behave the same on both. See BUILD.md.
cmake_minimum_required(VERSION 3.21)
project(CompositorShared LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(COMPOSITOR_BUILD_TESTS "Build the shared-code tests" ON)

# The pixel algorithms: plain C, no OS frameworks. Threads go through ParallelFor.h (GCD on macOS, the system thread
# pool on Windows).
set(COMPOSITOR_PIXELS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/Compositor/Rendering)
set(COMPOSITOR_PIXEL_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/Compositor/Core/StylePixels.c
    ${COMPOSITOR_PIXELS_DIR}/AdjustPixels.c
    ${COMPOSITOR_PIXELS_DIR}/BrushPixels.c
    ${COMPOSITOR_PIXELS_DIR}/ContentFill.c
    ${COMPOSITOR_PIXELS_DIR}/DitherPixels.c
    ${COMPOSITOR_PIXELS_DIR}/HealPixels.c
    ${COMPOSITOR_PIXELS_DIR}/LensPixels.c
    ${COMPOSITOR_PIXELS_DIR}/LevelsPixels.c
    ${COMPOSITOR_PIXELS_DIR}/LiquifyPixels.c
    ${COMPOSITOR_PIXELS_DIR}/NoisePixels.c
    ${COMPOSITOR_PIXELS_DIR}/PSDPixels.c
    ${COMPOSITOR_PIXELS_DIR}/SmearPixels.c
    ${COMPOSITOR_PIXELS_DIR}/WandPixels.c
)
if(WIN32)
    list(APPEND COMPOSITOR_PIXEL_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/Platform/Windows/ParallelForWin32.c)
endif()

function(compositor_pixels_library name)
    add_library(${name} STATIC ${COMPOSITOR_PIXEL_SOURCES})
    target_include_directories(${name} PUBLIC ${COMPOSITOR_PIXELS_DIR})
    if(MSVC)
        # M_PI and friends. The sources are UTF-8: without /utf-8, MSVC reads them in the system code page (949 on
        # Korean Windows) and mangles the non-ASCII characters in comments (warning C4819).
        target_compile_definitions(${name} PRIVATE _USE_MATH_DEFINES)
        target_compile_options(${name} PRIVATE /W3 /utf-8)
    else()
        target_compile_options(${name} PRIVATE -Wall)
        find_library(COMPOSITOR_LIBM m)
        if(COMPOSITOR_LIBM)
            target_link_libraries(${name} PUBLIC ${COMPOSITOR_LIBM})
        endif()
    endif()
endfunction()

# What an app links.
compositor_pixels_library(compositor_pixels)

if(COMPOSITOR_BUILD_TESTS)
    enable_testing()
    # The same sources with ParallelFor.h's test switch, so the tests can run each loop on one thread and compare.
    compositor_pixels_library(compositor_pixels_testing)
    target_compile_definitions(compositor_pixels_testing PUBLIC PARALLEL_FOR_TESTING)
    add_executable(compositor_pixel_tests Tests/Pixels/PixelTests.c)
    target_link_libraries(compositor_pixel_tests PRIVATE compositor_pixels_testing)
    if(MSVC)
        target_compile_options(compositor_pixel_tests PRIVATE /utf-8)
    endif()
    add_test(NAME pixels COMMAND compositor_pixel_tests)
    # Main's style kernels use the same portable source in the app and Windows library.
    add_executable(compositor_style_tests Tests/PortableCore/style_pixels.c)
    target_link_libraries(compositor_style_tests PRIVATE compositor_pixels_testing)
    if(MSVC)
        target_compile_options(compositor_style_tests PRIVATE /utf-8 /UNDEBUG)
    else()
        target_compile_options(compositor_style_tests PRIVATE -UNDEBUG)
    endif()
    add_test(NAME portable_style COMMAND compositor_style_tests)
endif()
