import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 0)
enum MessageRole {
  @HiveField(0)
  system,
  @HiveField(1)
  user,
  @HiveField(2)
  assistant,
}

@HiveType(typeId: 1)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String content;

  @HiveField(1)
  final MessageRole role;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final String? imagePath;

  ChatMessage({
    required this.content,
    required this.role,
    required this.timestamp,
    this.imagePath,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'role': role.name,
    };

    if (imagePath != null) {
      final file = File(imagePath!);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        final base64 = base64Encode(bytes);
        
        data['content'] = [
          {'type': 'text', 'text': content},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$base64'}
          },
        ];
      } else {
        data['content'] = content;
      }
    } else {
      data['content'] = content;
    }

    return data;
  }
}
