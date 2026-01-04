# Building a Local LLM Chat App with Flutter & Llama.cpp (Manual FFI)

This document details the complete implementation of running a Llama 3.2 model entirely offline on an Android device using Flutter and Dart FFI (Foreign Function Interface). We bypassed third-party wrappers to ensure full control over the build process, stability, and performance.

## 🚀 The Architecture

1.  **Native Layer (C++)**: `llama.cpp` compiled as shared libraries (`.so`) for Android.
2.  **Bridge Layer (Dart)**: `dart:ffi` bindings to call C functions directly.
3.  **Application Layer (Flutter)**: UI that manages model loading, threading (Isolates), and chat state.

---

## � Project Structure

Here is the file layout mapping the critical components:

```text
local_ai_chat/
├── android/
│   └── app/
│       └── src/
│           └── main/
│               ├── jniLibs/                 # 📍 Native Libraries Directory
│               │   └── arm64-v8a/           # 📱 Target ABI (Android 64-bit)
│               │       ├── libc++_shared.so # STL Dependency
│               │       ├── libggml.so       # GGML Backend
│               │       ├── libggml-cpu.so   # CPU Backend
│               │       ├── libllama.so      # Main Llama Library
│               │       └── libomp.so        # OpenMP Dependency
│               └── build.gradle.kts         # NDK Config & Version
├── lib/
│   ├── llama_bridge.dart  # 🌉 FFI Logic, Isolates, Generation Loop
│   ├── llama_structs.dart # 🧱 C Structures (LlamaModelParams, LlamaBatch)
│   └── main.dart          # 📱 UI, Throttling, File Picking
├── pubspec.yaml           # Dependencies (ffi, path_provider, etc.)
└── IMPLEMENTATION_DOCS.md
```

---

## �🛠 Step 1: Manual Native Build

We encountered issues with the `llama_cpp_dart` package (build failures, space issues, NDK mismatches). The solution was to manually compile the native libraries.

### 1.1 Compile `llama.cpp`
We used the Android NDK to cross-compile the library for `arm64-v8a`.

**CMake Command Used:**
```bash
# Executed in llama.cpp root
cmake -B build-android \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-26 \
    -DANDROID_STL=c++_shared \
    -DBUILD_SHARED_LIBS=ON \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF
    
cd build-android
make llama -j4
```

### 1.2 Install Libraries
Post-compilation, we installed the necessary Shared Objects (`.so`) into the Android project's JNI directory.

*   **Source:** `llama.cpp/build-android/src/*.so`
*   **Dependencies:** `libc++_shared.so` and `libomp.so` (Found in NDK toolchain).
*   **Destination:** `android/app/src/main/jniLibs/arm64-v8a/`
*   **Installed Files:**
    *   `libllama.so`
    *   `libggml.so`
    *   `libggml-cpu.so`
    *   `libggml-base.so`
    *   `libc++_shared.so`
    *   `libomp.so`

### 1.3 Android Configuration
In `android/app/build.gradle.kts`, we explicitly set the NDK version to match the compiler:
```kotlin
android {
    ndkVersion = "27.0.12077973"
    // ...
}
```

---

## 🔗 Step 2: FFI Structures (`llama_structs.dart`)

To communicate with C, we defined Dart classes backed by `dart:ffi` `Struct`. These MUST match the memory layout of `llama.h`.

**Key Struct: `LlamaModelParams`**
Used to configure the model load (GPU layers, Memory Mapping).
```dart
base class LlamaModelParams extends Struct {
  external Pointer<Void> devices;
  external Pointer<Void> tensor_buft_overrides;
  @Int32() external int n_gpu_layers;
  // ...
  @Bool() external bool use_mmap; // Crucial for Android RAM efficiency
}
```

**Key Struct: `LlamaBatch`**
Used to feed tokens to the decoder engine.
```dart
base class LlamaBatch extends Struct {
  @Int32() external int n_tokens;
  external Pointer<Int32> token;
  external Pointer<Int8> logits;
  // ... memory layout matches C definition
}
```

---

## 🌉 Step 3: The FFI Bridge (`llama_bridge.dart`)

The bridge connects the Dart world to the C++ world.

### 3.1 Loading the Library
```dart
// On Android, the OS loads libraries from the APK
_lib = DynamicLibrary.open('libllama.so'); 
```

### 3.2 Threading & Isolates
To prevent the **Main UI Thread** from freezing (ANR) during heavy inference, we moved generation to a background **Isolate**.

*   **Public Method:** `generate(model, prompt)` spawns the worker.
*   **Worker:** Re-opens the library, creates the context, runs the loop, and sends tokens back via `SendPort`.

### 3.3 The Generation Loop
1.  **Tokenize:** Convert String prompt -> `List<int>` tokens.
2.  **Prefill:** Feed all prompt tokens to `llama_decode`.
3.  **Sample Loop:**
    *   Calculate Logits (probabilities).
    *   Greedy Sample (Select highest probability token).
    *   Decode new token.
    *   Convert Token ID -> String Piece.
    *   Stream piece to UI.

---

## 📱 Step 4: The Flutter App (`main.dart`)

### 4.1 UI Throttling
Generating 30+ tokens/second floods the UI thread if we `setState` on every token. We optimized this by throttling updates to ~100ms.

```dart
if (now.difference(lastUpdate).inMilliseconds > 100) { 
    lastUpdate = now;
    setState(() { _response = generatedText; });
}
```

### 4.2 Application Flow
1.  **Pick File:** User selects `.gguf` file.
2.  **Copy:** File copied to internal app storage (accessible via `fopen`).
3.  **Load:** `LlamaBridge.loadModel` initializes the C++ backend.
4.  **Chat:** User input -> Bridge -> Stream -> Text Display.

---

## ✅ Performance & Status

*   **Architecture:** `arm64-v8a` (Modern Android).
*   **Method:** Direct FFI (No JNI Java wrappers).
*   **Stability:** High (Isolates prevent UI freeze).
*   **Offline:** Yes.

---

## 📦 Dependencies (`pubspec.yaml`)

We kept the dependencies minimal to avoid bloat and conflicts.

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Core FFI support (required for manual bindings)
  ffi: ^2.1.0 
  
  # Path utilities (to find internal storage for model copy)
  path_provider: ^2.1.2 
  
  # File picking (to select .gguf from device)
  file_picker: ^8.0.0 

  # Removed: llama_cpp_dart (We replaced this with our manual bridge!)
```

This documentation serves as the blueprint for the current working implementation.
