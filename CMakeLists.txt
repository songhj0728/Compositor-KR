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

# The pixel algorithms: plain C, no OS frameworks. Threads go through PixelParallel.
set(COMPOSITOR_PIXELS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/Compositor/Rendering)
add_library(compositor_pixels STATIC
    ${COMPOSITOR_PIXELS_DIR}/AdjustPixels.c
    ${COMPOSITOR_PIXELS_DIR}/BrushPixels.c
    ${COMPOSITOR_PIXELS_DIR}/ContentFill.c
    ${COMPOSITOR_PIXELS_DIR}/DitherPixels.c
    ${COMPOSITOR_PIXELS_DIR}/HealPixels.c
    ${COMPOSITOR_PIXELS_DIR}/LensPixels.c
    ${COMPOSITOR_PIXELS_DIR}/LevelsPixels.c
    ${COMPOSITOR_PIXELS_DIR}/LiquifyPixels.c
    ${COMPOSITOR_PIXELS_DIR}/NoisePixels.c
    ${COMPOSITOR_PIXELS_DIR}/PixelParallel.c
    ${COMPOSITOR_PIXELS_DIR}/PSDPixels.c
    ${COMPOSITOR_PIXELS_DIR}/SmearPixels.c
    ${COMPOSITOR_PIXELS_DIR}/WandPixels.c
)
target_include_directories(compositor_pixels PUBLIC ${COMPOSITOR_PIXELS_DIR})
if(MSVC)
    # M_PI and friends.
    target_compile_definitions(compositor_pixels PRIVATE _USE_MATH_DEFINES)
    target_compile_options(compositor_pixels PRIVATE /W3)
else()
    target_compile_options(compositor_pixels PRIVATE -Wall)
endif()
if(NOT WIN32)
    find_library(COMPOSITOR_LIBM m)
    if(COMPOSITOR_LIBM)
        target_link_libraries(compositor_pixels PUBLIC ${COMPOSITOR_LIBM})
    endif()
endif()

if(COMPOSITOR_BUILD_TESTS)
    enable_testing()
    add_executable(compositor_pixel_tests Tests/Pixels/PixelTests.c)
    target_link_libraries(compositor_pixel_tests PRIVATE compositor_pixels)
    add_test(NAME pixels COMMAND compositor_pixel_tests)
endif()
