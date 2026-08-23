#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm \
    cmake         \
    fmt           \
    libdecor      \
    libzip        \
    ninja         \
    nlohmann-json \
    sdl2          \
    spdlog        \
    tcc           \
    tinyxml2

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

make-aur-package zenity-rs-bin

echo "Making stable build of Ghostship..."
echo "---------------------------------------------------------------"
REPO="https://github.com/HarbourMasters/Ghostship"
VERSION="$(git ls-remote --tags --sort="v:refname" "$REPO" | tail -n1 | sed 's/.*\///; s/\^{}//')"
git clone --branch "$VERSION" --single-branch --recursive --depth 1 "$REPO" ./Ghostship
echo "$VERSION" > ~/version

mkdir -p ./AppDir/bin
cd ./Ghostship
patch -Np1 -i "../ghostship-fix-mtxf_copy-incorrect-values.patch"

# On aarch64, GNU ld fails with ".eh_frame_hdr refers to overlapping FDEs"
# because libtcc1.a is compiled by tcc itself and tcc's arm64 .eh_frame
# generation is broken. Build it with the system compiler instead (official
# tinycc knob) and skip .eh_frame_hdr generation as a safety net.
LINKER_FLAGS=""
if [ "$ARCH" = "aarch64" ]; then
    sed -i 's|-C "[$][{]tinycc_SOURCE_DIR[}]/lib"|& arm64-libtcc1-usegcc=yes|' \
        libultraship/cmake/dependencies/common.cmake
    grep -q 'arm64-libtcc1-usegcc=yes' \
        libultraship/cmake/dependencies/common.cmake
    LINKER_FLAGS="-DCMAKE_EXE_LINKER_FLAGS=-Wl,--no-eh-frame-hdr"
fi

cmake . \
    -Bbuild \
    -GNinja \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    $LINKER_FLAGS

# armflush.c calls __arm64_clear_cache(), a tcc-only builtin. With
# arm64-libtcc1-usegcc=yes the file is compiled by GCC instead, where
# that is an implicit-declaration error (GCC 14+). The tinycc sources
# only exist after configure (FetchContent), so patch them here.
if [ "$ARCH" = "aarch64" ]; then
    sed -i 's|__arm64_clear_cache(beg, end);|__builtin___clear_cache(beg, end);|' \
        build/_deps/tinycc-src/lib/armflush.c
fi

cmake --build build --config Release
cmake --build build --config Release --target GeneratePortO2R

mv -v build/assets ../AppDir/bin
mv -v build/Ghostship ../AppDir/bin
mv -v build/config.yml ../AppDir/bin
mv -v build/ghostship.o2r ../AppDir/bin
#mv -v libultraship/libtcc.so ../AppDir/bin
wget -O ../AppDir/bin/gamecontrollerdb.txt https://raw.githubusercontent.com/mdqinc/SDL_GameControllerDB/master/gamecontrollerdb.txt
cp -v logo.png ../AppDir/.DirIcon
mv -v logo.png ../AppDir/ghostship.png
