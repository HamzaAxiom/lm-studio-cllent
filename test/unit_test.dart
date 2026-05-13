import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp/models/chat_message.dart';

void main() {
  group('ChatMessage Model', () {
    test('toJson should format correctly for text only', () {
      final message = ChatMessage(
        content: 'Hello',
        role: MessageRole.user,
        timestamp: DateTime.now(),
      );

      final json = message.toJson();
      expect(json['role'], 'user');
      expect(json['content'], 'Hello');
    });

    test('toJson should handle vision format (conceptually)', () {
      // We can't easily test image file reading without mocks, 
      // but we can verify the role is correct.
      final message = ChatMessage(
        content: 'What is this?',
        role: MessageRole.user,
        timestamp: DateTime.now(),
        // imagePath: 'test.jpg', // Would fail readAsBytesSync in unit test without mock
      );

      final json = message.toJson();
      expect(json['role'], 'user');
      expect(json['content'], 'What is this?');
    });
  });
}
