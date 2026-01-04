# Building llama.cpp Native Libraries for Android

The `llama_cpp_dart` package requires native `.so` files compiled from llama.cpp.

## Prerequisites

1. **Android NDK** - Install via Android Studio:
   - Open Android Studio → Settings → Languages & Frameworks → Android SDK → SDK Tools
   - Check "NDK (Side by side)" and install

2. **CMake** - Usually installed with Android Studio

3. **Git** - To clone llama.cpp

## Build Steps

### 1. Clone llama.cpp

```bash
cd /tmp
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
```

### 2. Create Build Script

Create a file called `build_android.sh`:

```bash
#!/bin/bash

# Set your NDK path (adjust based on your installation)
# Common locations:
# macOS: ~/Library/Android/sdk/ndk/<version>
# Linux: ~/Android/Sdk/ndk/<version>
NDK_PATH=~/Library/Android/sdk/ndk/$(ls ~/Library/Android/sdk/ndk | head -1)

# Build for arm64-v8a (modern Android phones)
mkdir -p build-android-arm64
cd build-android-arm64

cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=$NDK_PATH/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-24 \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_OPENMP=OFF \
    -DGGML_BACKEND_DL=OFF

make -j$(nproc)

echo "Build complete! Libraries are in build-android-arm64/"
```

### 3. Run the Build

```bash
chmod +x build_android.sh
./build_android.sh
```

### 4. Copy Libraries to Your Flutter Project

After building, copy the `.so` files to your project:

```bash
# Create jniLibs directory
mkdir -p /Users/amansingh/Documents/personal/local_ai_chat/android/app/src/main/jniLibs/arm64-v8a

# Copy the built libraries
cp build-android-arm64/src/libllama.so \
   /Users/amansingh/Documents/personal/local_ai_chat/android/app/src/main/jniLibs/arm64-v8a/

# Copy any other required .so files (ggml, mtmd, etc.)
cp build-android-arm64/ggml/src/libggml*.so \
   /Users/amansingh/Documents/personal/local_ai_chat/android/app/src/main/jniLibs/arm64-v8a/
```

### 5. Update build.gradle (if needed)

In `android/app/build.gradle`, ensure native libs are included:

```gradle
android {
    // ... existing config ...
    
    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }
}
```

## Alternative: Use Pre-built Binaries

Check if pre-built binaries are available:
- https://github.com/netdur/llama_cpp_dart/releases
- https://github.com/nickarora/llamacpp_dart_prebuilts (community builds)

## Troubleshooting

- **libmtmd.so not found**: This is part of the newer llama.cpp multimodal support. You may need to enable it in the CMake config or use an older llama.cpp version.

- **Architecture mismatch**: Make sure you're building for the correct architecture (arm64-v8a for modern phones, armeabi-v7a for older devices).
