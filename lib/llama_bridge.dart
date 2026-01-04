import 'dart:ffi';
import 'dart:io';
import 'dart:isolate'; // Added for threading
import 'package:ffi/ffi.dart';
import 'llama_structs.dart';
import 'dart:convert';

// Native function signatures
typedef C_llama_backend_init = Void Function();
typedef Dart_llama_backend_init = void Function();

typedef C_llama_model_default_params = LlamaModelParams Function();
typedef Dart_llama_model_default_params = LlamaModelParams Function();

typedef C_llama_load_model_from_file =
    Pointer<Void> Function(Pointer<Utf8> path, LlamaModelParams params);
typedef Dart_llama_load_model_from_file =
    Pointer<Void> Function(Pointer<Utf8> path, LlamaModelParams params);

typedef C_llama_model_free = Void Function(Pointer<Void> model);
typedef Dart_llama_model_free = void Function(Pointer<Void> model);

// Context
typedef C_llama_context_default_params = LlamaContextParams Function();
typedef Dart_llama_context_default_params = LlamaContextParams Function();

typedef C_llama_new_context_with_model =
    Pointer<Void> Function(Pointer<Void> model, LlamaContextParams params);
typedef Dart_llama_new_context_with_model =
    Pointer<Void> Function(Pointer<Void> model, LlamaContextParams params);

typedef C_llama_free = Void Function(Pointer<Void> ctx);
typedef Dart_llama_free = void Function(Pointer<Void> ctx);

// Vocab
typedef C_llama_model_get_vocab = Pointer<Void> Function(Pointer<Void> model);
typedef Dart_llama_model_get_vocab =
    Pointer<Void> Function(Pointer<Void> model);

typedef C_llama_vocab_n_tokens = Int32 Function(Pointer<Void> vocab);
typedef Dart_llama_vocab_n_tokens = int Function(Pointer<Void> vocab);

typedef C_llama_vocab_eos = Int32 Function(Pointer<Void> vocab);
typedef Dart_llama_vocab_eos = int Function(Pointer<Void> vocab);

// Tokenize
typedef C_llama_tokenize =
    Int32 Function(
      Pointer<Void> vocab,
      Pointer<Utf8> text,
      Int32 len,
      Pointer<Int32> tokens,
      Int32 n_max,
      Bool add_special,
      Bool parse_special,
    );
typedef Dart_llama_tokenize =
    int Function(
      Pointer<Void> vocab,
      Pointer<Utf8> text,
      int len,
      Pointer<Int32> tokens,
      int n_max,
      bool add_special,
      bool parse_special,
    );

// Detokenize
typedef C_llama_token_to_piece =
    Int32 Function(
      Pointer<Void> vocab,
      Int32 token,
      Pointer<Utf8> buf,
      Int32 len,
      Int32 lstrip,
      Bool special,
    );
typedef Dart_llama_token_to_piece =
    int Function(
      Pointer<Void> vocab,
      int token,
      Pointer<Utf8> buf,
      int len,
      int lstrip,
      bool special,
    );

// Batch
typedef C_llama_batch_init =
    LlamaBatch Function(Int32 n_tokens, Int32 embd, Int32 n_seq_max);
typedef Dart_llama_batch_init =
    LlamaBatch Function(int n_tokens, int embd, int n_seq_max);

typedef C_llama_batch_free = Void Function(LlamaBatch batch);
typedef Dart_llama_batch_free = void Function(LlamaBatch batch);

// Decode
typedef C_llama_decode = Int32 Function(Pointer<Void> ctx, LlamaBatch batch);
typedef Dart_llama_decode = int Function(Pointer<Void> ctx, LlamaBatch batch);

// Logits
typedef C_llama_get_logits = Pointer<Float> Function(Pointer<Void> ctx);
typedef Dart_llama_get_logits = Pointer<Float> Function(Pointer<Void> ctx);

class LlamaBridge {
  static DynamicLibrary? _lib;

  static void initialize() {
    if (_lib != null) return;

    if (Platform.isAndroid) {
      try {
        _lib = DynamicLibrary.open('libllama.so');
      } catch (e) {
        print('❌ Failed to load libllama.so from default path: $e');
        rethrow;
      }
    } else {
      _lib = DynamicLibrary.process();
    }

    final backendInit = _lib!
        .lookupFunction<C_llama_backend_init, Dart_llama_backend_init>(
          'llama_backend_init',
        );
    backendInit();
  }

  static Pointer<Void> loadModel(String path) {
    if (_lib == null) initialize();

    final getParams = _lib!
        .lookupFunction<
          C_llama_model_default_params,
          Dart_llama_model_default_params
        >('llama_model_default_params');
    var params = getParams();
    params.n_gpu_layers = 0;
    params.use_mmap = true;

    final loadFunc = _lib!
        .lookupFunction<
          C_llama_load_model_from_file,
          Dart_llama_load_model_from_file
        >('llama_load_model_from_file');
    final pathPtr = path.toNativeUtf8();
    try {
      final model = loadFunc(pathPtr, params);
      if (model.address == 0) throw Exception('Null model pointer');
      return model;
    } finally {
      malloc.free(pathPtr);
    }
  }

  // Public Async Generator (Spawns Isolate)
  static Stream<String> generate(Pointer<Void> model, String prompt) async* {
    final receivePort = ReceivePort();

    // Send model address (int) because Pointers are not sendable across isolates
    await Isolate.spawn(_generateWorker, [
      receivePort.sendPort,
      model.address,
      prompt,
    ]);

    await for (final message in receivePort) {
      if (message == null) {
        // End of stream
        receivePort.close();
        return;
      }
      if (message is String) {
        yield message;
      } else if (message is List) {
        // Error [String error]
        throw Exception(message[0]);
      }
    }
  }

  // Worker running in background Isolate
  static void _generateWorker(List<dynamic> args) async {
    final SendPort sendPort = args[0];
    final int modelAddress = args[1];
    final String prompt = args[2];

    try {
      // Must re-initialize library in new isolate
      initialize();

      final model = Pointer<Void>.fromAddress(modelAddress);

      // calls the synchronous logic
      await for (final token in _generateSyncLogic(model, prompt)) {
        sendPort.send(token);
      }
      sendPort.send(null); // Signal Done
    } catch (e) {
      print("❌ Isolate Error: $e");
      sendPort.send(["Error: $e"]); // Send error
      sendPort.send(null);
    }
  }

  // Private Synchronous Logic (Blocking FFI calls)
  static Stream<String> _generateSyncLogic(
    Pointer<Void> model,
    String prompt,
  ) async* {
    print('🚀 Starting Generation for: "$prompt"');

    // 1. Get Vocab
    final getVocab = _lib!
        .lookupFunction<C_llama_model_get_vocab, Dart_llama_model_get_vocab>(
          'llama_model_get_vocab',
        );
    final vocab = getVocab(model);

    // 2. Create Context
    final ctxDefaultParams = _lib!
        .lookupFunction<
          C_llama_context_default_params,
          Dart_llama_context_default_params
        >('llama_context_default_params');
    var ctxParams = ctxDefaultParams();
    ctxParams.n_ctx = 2048;
    ctxParams.n_threads = 4;
    ctxParams.n_threads_batch = 4;

    final newContext = _lib!
        .lookupFunction<
          C_llama_new_context_with_model,
          Dart_llama_new_context_with_model
        >('llama_new_context_with_model');
    final ctx = newContext(model, ctxParams);

    if (ctx.address == 0) throw Exception("Failed to create context");

    final batchInit = _lib!
        .lookupFunction<C_llama_batch_init, Dart_llama_batch_init>(
          'llama_batch_init',
        );
    final batchFree = _lib!
        .lookupFunction<C_llama_batch_free, Dart_llama_batch_free>(
          'llama_batch_free',
        );
    final decode = _lib!.lookupFunction<C_llama_decode, Dart_llama_decode>(
      'llama_decode',
    );
    final getLogits = _lib!
        .lookupFunction<C_llama_get_logits, Dart_llama_get_logits>(
          'llama_get_logits',
        );
    final vocabNB = _lib!
        .lookupFunction<C_llama_vocab_n_tokens, Dart_llama_vocab_n_tokens>(
          'llama_vocab_n_tokens',
        );
    final vocabEos = _lib!
        .lookupFunction<C_llama_vocab_eos, Dart_llama_vocab_eos>(
          'llama_vocab_eos',
        );

    // Initialize Batch
    var batch = batchInit(2048, 0, 1);

    try {
      // 3. Tokenize
      final tokens = _tokenize(vocab, prompt);
      print('📝 Tokenized: ${tokens.length} tokens');

      // 4. Prefill
      for (int i = 0; i < tokens.length; i++) {
        batch.token.elementAt(i).value = tokens[i];
        batch.pos.elementAt(i).value = i;
        batch.n_seq_id.elementAt(i).value = 1;
        batch.seq_id.elementAt(i).value.elementAt(0).value = 0;
        batch.logits.elementAt(i).value = (i == tokens.length - 1) ? 1 : 0;
      }
      batch.n_tokens = tokens.length;

      if (decode(ctx, batch) != 0) throw Exception("Prefill decode failed");

      // 5. Generation Loop
      int nCur = batch.n_tokens;
      int nLen = 2048; // Max generation length
      int nVocab = vocabNB(vocab);
      int eos = vocabEos(vocab);

      print('⚡ Beginning sampling loop...');

      while (nCur < nLen) {
        final logitsPtr = getLogits(ctx);
        // Simple Greedy Sampling
        int newTokenId = 0;
        double maxVal = -double.infinity;
        for (int i = 0; i < nVocab; i++) {
          double val = logitsPtr.elementAt(i).value;
          if (val > maxVal) {
            maxVal = val;
            newTokenId = i;
          }
        }

        if (newTokenId == eos) {
          print('🏁 EOS reached');
          break;
        }

        final piece = _tokenToPiece(vocab, newTokenId);
        yield piece;

        // Prepare next batch (single token)
        batch.token.elementAt(0).value = newTokenId;
        batch.pos.elementAt(0).value = nCur;
        batch.n_seq_id.elementAt(0).value = 1;
        batch.seq_id.elementAt(0).value.elementAt(0).value = 0;
        batch.logits.elementAt(0).value = 1;
        batch.n_tokens = 1;

        if (decode(ctx, batch) != 0) {
          print("Decode failed during generation");
          break;
        }
        nCur++;
      }
    } finally {
      batchFree(batch);
      final freeCtx = _lib!.lookupFunction<C_llama_free, Dart_llama_free>(
        'llama_free',
      );
      freeCtx(ctx);
      print('🧹 Context freed');
    }
  }

  static List<int> _tokenize(Pointer<Void> vocab, String text) {
    final tokenizeFunc = _lib!
        .lookupFunction<C_llama_tokenize, Dart_llama_tokenize>(
          'llama_tokenize',
        );

    final textPtr = text.toNativeUtf8();
    final nMax = text.length + (text.length * 2) + 2;
    final tokensPtr = malloc.allocate<Int32>(sizeOf<Int32>() * nMax);

    try {
      int n = tokenizeFunc(
        vocab,
        textPtr,
        textPtr.length,
        tokensPtr,
        nMax,
        true,
        true,
      );
      if (n < 0) {
        final required = -n;
        print("Warning: token buffer small, resizing to $required");
        final tokensPtr2 = malloc.allocate<Int32>(sizeOf<Int32>() * required);
        n = tokenizeFunc(
          vocab,
          textPtr,
          textPtr.length,
          tokensPtr2,
          required,
          true,
          true,
        );

        final result = <int>[];
        for (int i = 0; i < n; i++) result.add(tokensPtr2.elementAt(i).value);
        malloc.free(tokensPtr2);
        return result;
      }

      final result = <int>[];
      for (int i = 0; i < n; i++) {
        result.add(tokensPtr.elementAt(i).value);
      }
      return result;
    } finally {
      malloc.free(textPtr);
      malloc.free(tokensPtr);
    }
  }

  static String _tokenToPiece(Pointer<Void> vocab, int token) {
    final func = _lib!
        .lookupFunction<C_llama_token_to_piece, Dart_llama_token_to_piece>(
          'llama_token_to_piece',
        );

    int size = func(vocab, token, nullptr, 0, 0, true);
    if (size < 0) size = -size;
    if (size == 0) return "";

    final buf = malloc.allocate<Utf8>(size + 1);
    try {
      int n = func(vocab, token, buf, size, 0, true);
      if (n < 0) return "";

      List<int> bytes = [];
      for (int i = 0; i < n; i++) {
        bytes.add(buf.cast<Uint8>().elementAt(i).value);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      malloc.free(buf);
    }
  }
}
