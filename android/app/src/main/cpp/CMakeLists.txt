cmake_minimum_required(VERSION 3.22.1)
project(cpfont_ft)

set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# FreeType source directory
set(FREETYPE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/freetype-2.13.2)

# Include our dummy hb.h BEFORE freetype includes
include_directories(BEFORE ${CMAKE_CURRENT_SOURCE_DIR})

# FreeType include directories
include_directories(
    ${FREETYPE_DIR}/include
    ${FREETYPE_DIR}/include/freetype/config
)

# FreeType source files (full build)
set(FREETYPE_SRC
    ${FREETYPE_DIR}/src/autofit/autofit.c
    ${FREETYPE_DIR}/src/base/ftbase.c
    ${FREETYPE_DIR}/src/base/ftbbox.c
    ${FREETYPE_DIR}/src/base/ftbitmap.c
    ${FREETYPE_DIR}/src/base/ftdebug.c
    ${FREETYPE_DIR}/src/base/ftglyph.c
    ${FREETYPE_DIR}/src/base/ftinit.c
    ${FREETYPE_DIR}/src/base/ftmm.c
    ${FREETYPE_DIR}/src/base/ftstroke.c
    ${FREETYPE_DIR}/src/base/ftsynth.c
    ${FREETYPE_DIR}/src/base/ftsystem.c
    ${FREETYPE_DIR}/src/base/fttype1.c
    ${FREETYPE_DIR}/src/base/ftwinfnt.c
    ${FREETYPE_DIR}/src/bdf/bdf.c
    ${FREETYPE_DIR}/src/cache/ftcache.c
    ${FREETYPE_DIR}/src/cff/cff.c
    ${FREETYPE_DIR}/src/cid/type1cid.c
    ${FREETYPE_DIR}/src/gzip/ftgzip.c
    ${FREETYPE_DIR}/src/lzw/ftlzw.c
    ${FREETYPE_DIR}/src/pcf/pcf.c
    ${FREETYPE_DIR}/src/pfr/pfr.c
    ${FREETYPE_DIR}/src/psaux/psaux.c
    ${FREETYPE_DIR}/src/pshinter/pshinter.c
    ${FREETYPE_DIR}/src/psnames/psnames.c
    ${FREETYPE_DIR}/src/raster/raster.c
    ${FREETYPE_DIR}/src/sdf/sdf.c
    ${FREETYPE_DIR}/src/sfnt/sfnt.c
    ${FREETYPE_DIR}/src/smooth/smooth.c
    ${FREETYPE_DIR}/src/svg/svg.c
    ${FREETYPE_DIR}/src/truetype/truetype.c
    ${FREETYPE_DIR}/src/type1/type1.c
    ${FREETYPE_DIR}/src/type42/type42.c
    ${FREETYPE_DIR}/src/winfonts/winfnt.c
)

# Build FreeType as static library
add_library(freetype STATIC ${FREETYPE_SRC})

target_compile_definitions(freetype PRIVATE FT2_BUILD_LIBRARY)

# Our wrapper
add_library(cpfont_ft SHARED cpfont_freetype.c)

target_link_libraries(cpfont_ft
    freetype
    android
    log
)
