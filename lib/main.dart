import 'package:flutter/material.dart';
import 'llama_bridge.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ffi'; // For Pointer

void main() {
  runApp(const MaterialApp(home: AiChatScreen()));
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  Pointer<Void>? _modelPtr;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _response = "Select a model to start...";
  bool _isLoading = false;
  bool _isModelLoaded = false;
  bool _cancelSignal = false;

  // 1. Load the Model via FFI (using custom LlamaBridge)
  Future<void> _pickAndLoadModel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _response = "Loading model... (This takes 5-10s)";
          _isLoading = true;
        });

        final modelPath = result.files.single.path!;
        debugPrint('📂 [Model] Selected file: $modelPath');

        final appDir = await getApplicationDocumentsDirectory();
        final newPath = '${appDir.path}/model.gguf';
        debugPrint('📦 [Model] Copying to internal storage: $newPath');

        final modelFile = File(modelPath);
        if (!await modelFile.exists()) throw Exception("Source file missing");

        final destFile = File(newPath);
        if (await destFile.exists()) await destFile.delete();
        await modelFile.copy(newPath);
        debugPrint('✅ [Model] File copied successfully');

        final verifyFile = File(newPath);
        final headerBytes = await verifyFile.openRead(0, 8).first;
        final isGGUF =
            headerBytes.length >= 4 &&
            headerBytes[0] == 0x47 &&
            headerBytes[1] == 0x47 &&
            headerBytes[2] == 0x55 &&
            headerBytes[3] == 0x46;
        debugPrint('📋 [Model] Valid GGUF: $isGGUF');

        debugPrint('🔧 [Bridge] Initializing LlamaBridge...');
        debugPrint('🔧 [Bridge] Loading model...');
        final modelPtr = LlamaBridge.loadModel(newPath);

        setState(() {
          _modelPtr = modelPtr;
          _response =
              "✅ Model Loaded Successfully!\nPointer: $modelPtr\nReady to chat!";
          _isLoading = false;
          _isModelLoaded = true;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [Load Model Error] $e');
      debugPrint('📍 [Stack Trace] $stackTrace');
      setState(() {
        _response = "Error loading model: $e";
        _isLoading = false;
      });
    }
  }

  void _stopGeneration() {
    setState(() {
      _cancelSignal = true;
    });
  }

  // 2. Generate Text
  Future<void> _generateText() async {
    if (_modelPtr == null || !_isModelLoaded) return;
    if (_controller.text.isEmpty) return;

    final prompt = _controller.text;
    _controller.clear();
    // Dismiss keyboard
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _response = "Thinking...\n";
      _isLoading = true;
      _cancelSignal = false;
    });

    try {
      // Use LlamaBridge stream
      final stream = LlamaBridge.generate(_modelPtr!, prompt);

      String generatedText = "";
      DateTime lastUpdate = DateTime.now();

      await for (final token in stream) {
        if (_cancelSignal) {
          generatedText += "\n[Stopped by user]";
          break;
        }

        generatedText += token;

        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds > 100) {
          lastUpdate = now;
          setState(() {
            _response = generatedText;
          });
          // Auto-scroll
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        }
      }

      setState(() {
        _response = generatedText;
        _isLoading = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [Generate Text Error] $e');
      debugPrint('📍 [Stack Trace] $stackTrace');
      setState(() {
        _response += "\n[Error generating text: $e]";
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Offline Llama 3.2")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Text(_response, style: const TextStyle(fontSize: 16)),
              ),
            ),
            if (_isLoading) const LinearProgressIndicator(),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isLoading,
                    decoration: const InputDecoration(
                      hintText: "Type your question...",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _isLoading ? null : _generateText(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isLoading ? Icons.stop_circle_outlined : Icons.send,
                    color: _isLoading ? Colors.red : Colors.blue,
                  ),
                  onPressed: _isLoading ? _stopGeneration : _generateText,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _pickAndLoadModel,
              child: const Text("Load Model File (.gguf)"),
            ),
          ],
        ),
      ),
    );
  }
}
