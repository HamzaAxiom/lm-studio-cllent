import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/lm_studio_service.dart';

final chatServiceProvider = Provider((ref) {
  final settings = Hive.box('settings');
  final baseUrl = settings.get('baseUrl', defaultValue: 'http://localhost:1234/api/v1/chat');
  return LmStudioService(baseUrl: baseUrl);
});

final currentSessionProvider = StateProvider<ChatSession?>((ref) => null);

final chatSessionsProvider = StateNotifierProvider<ChatSessionsNotifier, List<ChatSession>>((ref) {
  return ChatSessionsNotifier();
});

final personasProvider = StateNotifierProvider<PersonasNotifier, Map<String, String>>((ref) {
  return PersonasNotifier();
});

class PersonasNotifier extends StateNotifier<Map<String, String>> {
  PersonasNotifier() : super({}) {
    _loadPersonas();
  }

  void _loadPersonas() {
    final box = Hive.box('personas');
    
    if (box.isEmpty) {
      // Default persona
      final defaults = {'Assistant': 'You are a helpful assistant.'};
      box.putAll(defaults);
    }

    final Map<String, String> loaded = {};
    for (var key in box.keys) {
      loaded[key.toString()] = box.get(key).toString();
    }
    state = loaded;
  }

  void addPersona(String name, String prompt) {
    state = {...state, name: prompt};
    final box = Hive.box('personas');
    box.put(name, prompt);
  }

  void deletePersona(String name) {
    final newState = Map<String, String>.from(state)..remove(name);
    state = newState;
    final box = Hive.box('personas');
    box.delete(name);
  }
}

class ChatSessionsNotifier extends StateNotifier<List<ChatSession>> {
  ChatSessionsNotifier() : super([]) {
    _loadSessions();
  }

  void _loadSessions() {
    final box = Hive.box<ChatSession>('sessions');
    state = box.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<ChatSession> createNewSession({String? systemPrompt}) async {
    final settings = Hive.box('settings');
    final defaultPrompt = settings.get('defaultSystemPrompt', defaultValue: 'You are a helpful assistant.');

    final session = ChatSession(
      id: const Uuid().v4(),
      title: 'New Chat',
      createdAt: DateTime.now(),
      messages: [],
      systemPrompt: systemPrompt ?? defaultPrompt,
    );
    
    final box = Hive.box<ChatSession>('sessions');
    await box.put(session.id, session);
    state = [session, ...state];
    return session;
  }

  Future<void> deleteSession(String id) async {
    final box = Hive.box<ChatSession>('sessions');
    await box.delete(id);
    state = state.where((s) => s.id != id).toList();
  }
}

final chatMessagesProvider = StateNotifierProvider.family<ChatMessagesNotifier, ChatState, String>((ref, sessionId) {
  return ChatMessagesNotifier(ref, sessionId);
});

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;

  ChatState({required this.messages, this.isLoading = false});

  ChatState copyWith({List<ChatMessage>? messages, bool? isLoading}) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ChatMessagesNotifier extends StateNotifier<ChatState> {
  final Ref ref;
  final String sessionId;

  ChatMessagesNotifier(this.ref, this.sessionId) : super(ChatState(messages: [])) {
    _loadMessages();
  }

  void _loadMessages() {
    final box = Hive.box<ChatSession>('sessions');
    final session = box.get(sessionId);
    if (session != null) {
      state = state.copyWith(messages: List.from(session.messages));
    }
  }

  Future<void> sendMessage(String text, {File? image}) async {
    String? storedImagePath;
    if (image != null) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${const Uuid().v4()}.jpg';
      final savedImage = await image.copy('${directory.path}/$fileName');
      storedImagePath = savedImage.path;
    }

    final userMessage = ChatMessage(
      content: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
      imagePath: storedImagePath,
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
    );
    _saveToHive();

    try {
      final service = ref.read(chatServiceProvider);
      
      final assistantMessage = ChatMessage(
        content: '',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        isLoading: false,
      );

      final box = Hive.box<ChatSession>('sessions');
      final session = box.get(sessionId);
      final settings = Hive.box('settings');
      final enableThinking = settings.get('enableThinking', defaultValue: true);

      final stream = service.chatStream(
        history: state.messages.sublist(0, state.messages.length - 1),
        systemPrompt: session?.systemPrompt ?? 'You are a helpful assistant.',
        enableThinking: enableThinking,
      );

      String fullContent = '';
      await for (final chunk in stream) {
        fullContent += chunk;
        
        final updatedMessages = List<ChatMessage>.from(state.messages);
        updatedMessages[updatedMessages.length - 1] = ChatMessage(
          content: fullContent,
          role: MessageRole.assistant,
          timestamp: assistantMessage.timestamp,
        );
        
        state = state.copyWith(messages: updatedMessages);
      }
      
      _saveToHive();
    } catch (e) {
      final errorMessage = ChatMessage(
        content: 'Error: ${e.toString()}',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        isLoading: false,
      );
    }
  }

  Future<void> deleteMessage(int index) async {
    final updatedMessages = List<ChatMessage>.from(state.messages);
    updatedMessages.removeAt(index);
    state = state.copyWith(messages: updatedMessages);
    _saveToHive();
  }

  Future<void> editMessage(int index, String newText) async {
    final updatedMessages = List<ChatMessage>.from(state.messages);
    final oldMessage = updatedMessages[index];
    
    updatedMessages[index] = ChatMessage(
      content: newText,
      role: oldMessage.role,
      timestamp: oldMessage.timestamp,
      imagePath: oldMessage.imagePath,
    );
    
    state = state.copyWith(messages: updatedMessages);
    _saveToHive();

    // If it was a user message, we might want to regenerate the following assistant response
    // But for now, just editing is enough as requested.
  }

  Future<void> regenerateMessage() async {
    if (state.messages.isEmpty) return;

    final lastMessage = state.messages.last;
    if (lastMessage.role != MessageRole.assistant) return;

    // Remove the last assistant message
    final newMessages = List<ChatMessage>.from(state.messages)..removeLast();
    state = state.copyWith(messages: newMessages);

    // Find the last user message to use its text/image if needed
    // But actually, we just need to re-run the service with the current (now trimmed) history
    // The history for the service call will be the messages before the one we just deleted.
    
    state = state.copyWith(isLoading: true);
    
    try {
      final service = ref.read(chatServiceProvider);
      
      final assistantMessage = ChatMessage(
        content: '',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        isLoading: false,
      );

      final box = Hive.box<ChatSession>('sessions');
      final session = box.get(sessionId);
      final settings = Hive.box('settings');
      final enableThinking = settings.get('enableThinking', defaultValue: true);

      final stream = service.chatStream(
        history: state.messages.sublist(0, state.messages.length - 1),
        systemPrompt: session?.systemPrompt ?? 'You are a helpful assistant.',
        enableThinking: enableThinking,
      );

      String fullContent = '';
      await for (final chunk in stream) {
        fullContent += chunk;
        
        final updatedMessages = List<ChatMessage>.from(state.messages);
        updatedMessages[updatedMessages.length - 1] = ChatMessage(
          content: fullContent,
          role: MessageRole.assistant,
          timestamp: assistantMessage.timestamp,
        );
        
        state = state.copyWith(messages: updatedMessages);
      }
      
      _saveToHive();
    } catch (e) {
      final errorMessage = ChatMessage(
        content: 'Error: ${e.toString()}',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        isLoading: false,
      );
    }
  }

  void _saveToHive() {
    final box = Hive.box<ChatSession>('sessions');
    final session = box.get(sessionId);
    if (session != null) {
      session.messages.clear();
      session.messages.addAll(state.messages);
      session.save();
    }
  }
  
  void updateSystemPrompt(String prompt) {
    final box = Hive.box<ChatSession>('sessions');
    final session = box.get(sessionId);
    if (session != null) {
      session.systemPrompt = prompt;
      session.save();
      
      // Save as global default for future new chats
      final settings = Hive.box('settings');
      settings.put('defaultSystemPrompt', prompt);

      // Force UI update
      ref.read(currentSessionProvider.notifier).state = null;
      ref.read(currentSessionProvider.notifier).state = session;
    }
  }
}
