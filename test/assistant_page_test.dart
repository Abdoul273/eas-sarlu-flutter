import 'package:eas_sarlu/features/assistant/assistant_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMessage model', () {
    test('serialise et déserialise correctement un message', () {
      final now = DateTime.now();
      final message = ChatMessage(
        role: 'user',
        content: 'Quel est le chiffre d\'affaires ?',
        timestamp: now,
      );

      final json = message.toJson();
      final copy = ChatMessage.fromJson(json);

      expect(copy.role, equals('user'));
      expect(copy.content, equals('Quel est le chiffre d\'affaires ?'));
      expect(
          copy.timestamp.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
    });

    test('serialise et déserialise correctement une session', () {
      final now = DateTime.now();
      final session = ChatSession(
        id: 'session_1',
        title: 'Bilan juillet',
        date: now,
        messages: [
          ChatMessage(
            role: 'user',
            content: 'Bonjour assistant',
            timestamp: now,
          ),
          ChatMessage(
            role: 'assistant',
            content: 'Bonjour ! Comment puis-je vous aider ?',
            timestamp: now,
          ),
        ],
      );

      final json = session.toJson();
      final copy = ChatSession.fromJson(json);

      expect(copy.id, equals('session_1'));
      expect(copy.title, equals('Bilan juillet'));
      expect(copy.messages.length, equals(2));
      expect(copy.messages.first.role, equals('user'));
      expect(copy.messages.last.role, equals('assistant'));
    });
  });
}
