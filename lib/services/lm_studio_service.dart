import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/chat_message.dart';

class LmStudioService {
  final Dio _dio = Dio();
  String baseUrl;

  LmStudioService({this.baseUrl = 'http://localhost:1234/v1'});

  Stream<String> chatStream({
    required List<ChatMessage> history,
    required String systemPrompt,
    bool enableThinking = true,
  }) async* {
    try {
      final messages = [
        {'role': 'system', 'content': systemPrompt},
        ...history.map((m) => m.toJson()),
      ];

      final response = await _dio.post(
        '$baseUrl/chat/completions',
        data: {
          'messages': messages,
          'model': 'google/gemma-4-e4b',
          'temperature': 0.7,
          'stream': true,
          'enable_thinking': enableThinking,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Content-Type': 'application/json'},
        ),
      );

      final Stream<List<int>> stream = response.data.stream.cast<List<int>>();
      bool isReasoning = false;
      
      await for (final chunk in stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          final data = chunk.substring(6);
          if (data == '[DONE]') break;
          
          try {
            final json = jsonDecode(data);
            final delta = json['choices'][0]['delta'];
            
            // Handle reasoning_content
            final reasoning = delta['reasoning_content'];
            if (reasoning != null && reasoning.toString().isNotEmpty) {
              if (!isReasoning) {
                isReasoning = true;
                yield '<think>';
              }
              yield reasoning.toString();
              continue; // Don't process content if we have reasoning
            } else if (isReasoning) {
              isReasoning = false;
              yield '</think>';
            }

            final content = delta['content'];
            if (content != null) {
              yield content;
            }
          } catch (e) {
            // Ignore parse errors for partial chunks
          }
        }
      }
      if (isReasoning) yield '</think>';
    } catch (e) {
      yield 'Error: $e';
    }
  }

  static String encodeImage(File imageFile) {
    List<int> imageBytes = imageFile.readAsBytesSync();
    return base64Encode(imageBytes);
  }
}
