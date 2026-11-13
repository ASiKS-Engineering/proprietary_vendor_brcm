#!/bin/bash
# Builds libhailort.so (HailoRT 4.24.0) for Android arm64 with the Android NDK and installs it to
# rpi5/proprietary/vendor/lib64/, from where rpi5-vendor.mk packages it into /vendor/lib64.
#
# Run it on Linux/WSL2 (needs git, curl, unzip, python3). CMake, Ninja and a host clang come from an
# AOSP checkout, because the build machine has no host compiler; HailoRT first builds a host protoc.
#
#   AOSP_TOP=~/aosp/AOSP-17 ./build_hailort_android.sh
#
# Environment overrides: AOSP_TOP, WORK_DIR, NDK_VERSION, ANDROID_API, HAILORT_TAG
set -euo pipefail

AOSP_TOP=${AOSP_TOP:-$HOME/aosp/AOSP-17}
WORK_DIR=${WORK_DIR:-$HOME/hailort-android}
NDK_VERSION=${NDK_VERSION:-r27c}
ANDROID_API=${ANDROID_API:-34}
HAILORT_TAG=${HAILORT_TAG:-v4.24.0}
HOST_CLANG=${HOST_CLANG:-$AOSP_TOP/prebuilts/clang/host/linux-x86/clang-r584948b}
HOST_SYSROOT_DIR=${HOST_SYSROOT_DIR:-$AOSP_TOP/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEST_DIR=$SCRIPT_DIR/../proprietary/vendor/lib64
NDK=$WORK_DIR/android-ndk-$NDK_VERSION
SRC=$WORK_DIR/hailort
BUILD=$WORK_DIR/build
HOSTTOOLS=$WORK_DIR/hosttools

for p in "$HOST_CLANG/bin/clang" "$HOST_SYSROOT_DIR/sysroot" "$AOSP_TOP/prebuilts/cmake/linux-x86/bin/cmake" \
         "$AOSP_TOP/prebuilts/build-tools/linux-x86/bin/ninja"; do
    [ -e "$p" ] || { echo "missing: $p (set AOSP_TOP)" >&2; exit 1; }
done

mkdir -p "$WORK_DIR" "$DEST_DIR" "$HOSTTOOLS"

if [ ! -d "$NDK" ]; then
    echo "== Downloading NDK $NDK_VERSION"
    curl -fL -o "$WORK_DIR/ndk.zip" "https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip"
    unzip -q "$WORK_DIR/ndk.zip" -d "$WORK_DIR"
    rm -f "$WORK_DIR/ndk.zip"
fi

if [ ! -d "$SRC" ]; then
    echo "== Cloning HailoRT $HAILORT_TAG"
    git clone --depth 1 --branch "$HAILORT_TAG" https://github.com/hailo-ai/hailort.git "$SRC"
fi

# Host compiler wrappers for the protoc build (no system gcc/libc headers on the build machine).
GCC_LIB=$(ls -d "$HOST_SYSROOT_DIR"/lib/gcc/x86_64-linux/* | head -n 1)
COMMON="--sysroot=$HOST_SYSROOT_DIR/sysroot -B$GCC_LIB -L$GCC_LIB -L$HOST_SYSROOT_DIR/x86_64-linux/lib64 -fuse-ld=lld"
printf '#!/bin/bash\nexec %s/bin/clang %s "$@"\n' "$HOST_CLANG" "$COMMON" > "$HOSTTOOLS/cc"
printf '#!/bin/bash\nexec %s/bin/clang++ %s -stdlib=libc++ -static-libstdc++ "$@"\n' "$HOST_CLANG" "$COMMON" > "$HOSTTOOLS/cxx"
chmod +x "$HOSTTOOLS/cc" "$HOSTTOOLS/cxx"
for t in ar ranlib nm strip; do ln -sf "$HOST_CLANG/bin/llvm-$t" "$HOSTTOOLS/$t"; done

export HOST_CC=$HOSTTOOLS/cc HOST_CXX=$HOSTTOOLS/cxx
export PATH=$AOSP_TOP/prebuilts/cmake/linux-x86/bin:$AOSP_TOP/prebuilts/build-tools/linux-x86/bin:$HOSTTOOLS:/usr/bin:/bin

# HailoRT runs the host protoc build in an env -i shell; hand it the host compiler and PATH.
git -C "$SRC" checkout hailort/cmake/execute_cmake.cmake
sed -i 's#PATH=/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin bash -l -c#PATH=$ENV{PATH} CC=$ENV{HOST_CC} CXX=$ENV{HOST_CXX} bash -c#' \
    "$SRC/hailort/cmake/execute_cmake.cmake"
grep -q 'HOST_CC' "$SRC/hailort/cmake/execute_cmake.cmake" || { echo "execute_cmake.cmake patch failed" >&2; exit 1; }

echo "== Configuring"
rm -rf "$BUILD" "$SRC/hailort/external"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$ANDROID_API -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    -DHAILO_BUILD_EXAMPLES=OFF -DHAILO_BUILD_UT=OFF -DHAILO_BUILD_SERVICE=OFF -DHAILO_BUILD_GSTREAMER=OFF \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -Wno-dev

echo "== Building libhailort"
ninja -C "$BUILD" libhailort

LIB=$BUILD/hailort/libhailort/src/libhailort.so
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded -o "$DEST_DIR/libhailort.so" "$LIB"

echo "== Installed $DEST_DIR/libhailort.so ($(stat -c %s "$DEST_DIR/libhailort.so") bytes)"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf" -d "$DEST_DIR/libhailort.so" | grep -E 'NEEDED|SONAME'
