# 🦙 Tutorial: Build a Private AI Chat App with Flutter & Llama.cpp

Run powerful LLMs (like Llama 3.2 1B/3B) directly on your Android device—offline, private, and free. No servers, no APIs.

In this guide, I will show you how to build a production-ready engine using **Flutter** and **Dart FFI** from scratch.

---

## � Prerequisites
*   **Flutter SDK** installed.
*   **Android SDK & NDK** (Side-by-side) installed via Android Studio.
*   **CMake** installed (`brew install cmake` or via Android SDK).
*   **Git**.

---

## 🚀 Step 1: Compile the Native Engine

We need `llama.cpp` compiled as a Shared Library (`.so`) for Android.

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/ggerganov/llama.cpp
    cd llama.cpp
    ```

2.  **Compile for Android (ARM64):**
    Copy-paste this command. Make sure to define `ANDROID_NDK_HOME` (usually `~/Library/Android/sdk/ndk/<version>`).

    ```bash
    # Set your NDK path if not set (Example: 27.0.12077973)
    export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.0.12077973

    # Configure CMake
    cmake -B build-android \
        -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
        -DANDROID_ABI=arm64-v8a \
        -DANDROID_PLATFORM=android-26 \
        -DANDROID_STL=c++_shared \
        -DBUILD_SHARED_LIBS=ON \
        -DLLAMA_CURL=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF

    # Build
    cd build-android
    make llama -j4
    ```

---

## 📂 Step 2: Project Setup

1.  **Create your Flutter App:**
    ```bash
    flutter create local_ai_chat
    cd local_ai_chat
    ```

2.  **Add Dependencies:**
    Add these to your `pubspec.yaml`:
    ```yaml
    dependencies:
      flutter:
        sdk: flutter
      ffi: ^2.1.0        # Key for calling C++
      path_provider: ^2.1.2
      file_picker: ^8.0.0
    ```

3.  **Install the Libraries:**
    Create the folder structure and copy the `.so` files you just built.

    ```bash
    # Create directory
    mkdir -p android/app/src/main/jniLibs/arm64-v8a/
    ```

    **Copy these files into that folder:**
    *   From `llama.cpp/build-android/src/`:
        *   `libllama.so`
        *   `libggml.so`
        *   `libggml-cpu.so`
        *   `libggml-base.so`
    *   From NDK (`$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/.../lib64/clang/.../lib/linux/aarch64/` - search for them):
        *   `libc++_shared.so`
        *   `libomp.so`

---

## 🌉 Step 3: The Binding Code

Create a file `lib/llama_structs.dart`. This maps C++ memory to Dart.

```dart
// lib/llama_structs.dart
import 'dart:ffi';

base class LlamaModelParams extends Struct {
  external Pointer<Void> devices;
  external Pointer<Void> tensor_buft_overrides;
  @Int32() external int n_gpu_layers;
  @Int32() external int split_mode;
  @Int32() external int main_gpu;
  external Pointer<Float> tensor_split; 
  external Pointer<Void> progress_callback;
  external Pointer<Void> progress_callback_user_data;
  external Pointer<Void> kv_overrides;
  @Bool() external bool vocab_only;
  @Bool() external bool use_mmap; // Important!
  @Bool() external bool use_mlock;
  @Bool() external bool check_tensors;
  @Bool() external bool use_extra_bufts;
  @Bool() external bool no_host;
  @Bool() external bool no_alloc;
}

// See documentation for LlamaBatch and LlamaContextParams...
```

---

## 🧠 Step 4: The Bridge Logic

Create `lib/llama_bridge.dart`. This is where the magic happens.

```dart
// lib/llama_bridge.dart
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'llama_structs.dart';

class LlamaBridge {
  static DynamicLibrary? _lib;

  // 1. Load the Library
  static void initialize() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libllama.so');
    }   
    // ... binding setup ...
    final backendInit = _lib!.lookupFunction<C_init, Dart_init>('llama_backend_init');
    backendInit();
  }

  // 2. The Generation Loop (Background Isolate)
  static Stream<String> generate(Pointer<Void> model, String prompt) async* {
    final port = ReceivePort();
    await Isolate.spawn(_worker, [port.sendPort, model.address, prompt]);
    
    await for (final token in port) {
       yield token as String;
    }
  }
}
```

---

## � Step 5: The UI

In `lib/main.dart`, we connect it all.

1.  **Load Model:** Use `FilePicker` to get the `.gguf` file.
2.  **Copy:** Copy it to `getApplicationDocumentsDirectory()` so C++ can read it (`fopen`).
3.  **Run:** Call `LlamaBridge.generate()` and listen to the stream.

**Performance Tip:** Use a throttle to only `setState` every 100ms, otherwise the app will freeze trying to render 50 tokens/second!

```dart
if (now.difference(lastUpdate).inMilliseconds > 100) { 
    setState(() { _response = text; });
}
```

---

## � Result

You now have a fully offline AI chat app.
*   **Cost:** $0.
*   **Privacy:** 100%.
*   **Speed:** Native C++ performance.

Happy Coding! 🚀
