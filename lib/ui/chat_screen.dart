import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive/hive.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import 'widgets/glass_container.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  File? _selectedImage;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(chatSessionsProvider);
    final currentSession = ref.watch(currentSessionProvider);
    
    // Auto-create session if none exists
    if (currentSession == null && sessions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(currentSessionProvider.notifier).state = sessions.first;
      });
    } else if (currentSession == null && sessions.isEmpty) {
        // We'll show a "Start New Chat" button or handle it
    }

    return Scaffold(
      drawer: _buildDrawer(sessions),
      appBar: AppBar(
        title: const Text('Astro Chat'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context),
          ),
          if (currentSession != null)
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: () => _showSystemPromptDialog(context, currentSession),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.5, -0.5),
            radius: 1.5,
            colors: [
              Color(0xFF1E293B),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: Column(
          children: [
            if (currentSession != null) _buildPersonaSelector(currentSession),
            Expanded(
              child: currentSession == null 
                ? _buildEmptyState()
                : _buildMessageList(currentSession.id),
            ),
            if (_selectedImage != null) _buildImagePreview(),
            _buildInputArea(currentSession),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.rocket_launch, size: 80, color: Color(0xFF6366F1))
              .animate()
              .scale(delay: 200.ms, duration: 600.ms, curve: Curves.elasticOut)
              .shimmer(delay: 1.seconds, duration: 2.seconds),
          const SizedBox(height: 20),
          Text(
            'Ready to explore?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () async {
              final newSession = await ref.read(chatSessionsProvider.notifier).createNewSession();
              ref.read(currentSessionProvider.notifier).state = newSession;
            },
            child: const Text('Start New Mission'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(String sessionId) {
    final chatState = ref.watch(chatMessagesProvider(sessionId));
    final messages = chatState.messages;
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length + (chatState.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return _buildLoadingBubble().animate().fadeIn();
        }
        final message = messages[index];
        return _buildMessageBubble(message).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
      },
    );
  }

  Widget _buildLoadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF334155),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Thinking...',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMessageContent(ChatMessage message) {
    final content = message.content;
    
    // Pattern to match thinking blocks: <think>...</think> or <|channel>thought...<channel|>
    final thinkRegex = RegExp(r'(?:<\|channel>thought|<think>)([\s\S]*?)(?:<channel\|>|</think>|$)', caseSensitive: false);
    final match = thinkRegex.firstMatch(content);

    if (match != null) {
      final thinking = match.group(1)?.trim() ?? '';
      final isFinishedThinking = content.toLowerCase().contains('<channel|>') || content.toLowerCase().contains('</think>');
      final actualResponse = content.replaceAll(match.group(0)!, '').trim();

      return [
        if (thinking.isNotEmpty || !isFinishedThinking)
          ThinkingBlock(
            thinking: thinking,
            isFinished: isFinishedThinking,
          ),
        if (actualResponse.isNotEmpty)
          MarkdownBody(
            data: actualResponse,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(color: Colors.white, fontSize: 16),
              listBullet: const TextStyle(color: Colors.white70),
              code: const TextStyle(
                backgroundColor: Colors.black26,
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              codeblockDecoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ];
    }

    return [
      MarkdownBody(
        data: content,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(color: Colors.white, fontSize: 16),
          listBullet: const TextStyle(color: Colors.white70),
          code: const TextStyle(
            backgroundColor: Colors.black26,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
          codeblockDecoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    ];
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF6366F1) : const Color(0xFF334155),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(message.imagePath!)),
                ),
              ),
            ..._buildMessageContent(message),
            if (!isUser) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.white24),
                    onPressed: () {
                      final currentSession = ref.read(currentSessionProvider);
                      if (currentSession != null) {
                        ref.read(chatMessagesProvider(currentSession.id).notifier).regenerateMessage();
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Regenerate',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(_selectedImage!, height: 100, width: 100, fit: BoxFit.cover),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _selectedImage = null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ChatSession? session) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GlassContainer(
        borderRadius: 30,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined, color: Colors.white70),
              onPressed: _pickImage,
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) => _handleSend(session),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Color(0xFF6366F1)),
              onPressed: () => _handleSend(session),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSend(ChatSession? session) {
    if (session == null || (_textController.text.isEmpty && _selectedImage == null)) return;
    
    ref.read(chatMessagesProvider(session.id).notifier).sendMessage(
      _textController.text,
      image: _selectedImage,
    );
    
    _textController.clear();
    setState(() => _selectedImage = null);
    _scrollToBottom();
  }

  Widget _buildDrawer(List<ChatSession> sessions) {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: Column(
        children: [
          const DrawerHeader(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rocket_launch, size: 40, color: Color(0xFF6366F1)),
                  SizedBox(height: 10),
                  Text('Mission History', style: TextStyle(color: Colors.white, fontSize: 20)),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add, color: Colors.white),
            title: const Text('New Mission', style: TextStyle(color: Colors.white)),
            onTap: () async {
              final newSession = await ref.read(chatSessionsProvider.notifier).createNewSession();
              ref.read(currentSessionProvider.notifier).state = newSession;
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return ListTile(
                  title: Text(session.title, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(session.createdAt.toString().substring(0, 16), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: () {
                    ref.read(currentSessionProvider.notifier).state = session;
                    Navigator.pop(context);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 20),
                    onPressed: () => ref.read(chatSessionsProvider.notifier).deleteSession(session.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonaSelector(ChatSession session) {
    final personas = ref.watch(personasProvider);
    
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...personas.entries.map((entry) {
            final isSelected = session.systemPrompt == entry.value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.key),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(chatMessagesProvider(session.id).notifier).updateSystemPrompt(entry.value);
                  }
                },
                backgroundColor: Colors.white.withOpacity(0.05),
                selectedColor: const Color(0xFF6366F1).withOpacity(0.3),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 12,
                ),
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.white24),
            onPressed: () => _showAddPersonaDialog(context),
          ),
        ],
      ),
    );
  }

  void _showAddPersonaDialog(BuildContext context) {
    final nameController = TextEditingController();
    final promptController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('New Persona'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: 'Persona Name (e.g. Yoda)'),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: promptController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'System Prompt...'),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && promptController.text.isNotEmpty) {
                ref.read(personasProvider.notifier).addPersona(nameController.text, promptController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSystemPromptDialog(BuildContext context, ChatSession session) {
    final controller = TextEditingController(text: session.systemPrompt);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Adjust System Directives'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter system prompt...',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ref.read(chatMessagesProvider(session.id).notifier).updateSystemPrompt(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    final settings = Hive.box('settings');
    final controller = TextEditingController(text: settings.get('baseUrl', defaultValue: 'http://192.168.1.100:1234/v1'));
    bool enableThinking = settings.get('enableThinking', defaultValue: true);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('Base Station Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LM Studio API URL', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Enable Thinking', style: TextStyle(color: Colors.white70)),
                    Switch(
                      value: enableThinking,
                      activeColor: const Color(0xFF6366F1),
                      onChanged: (val) {
                        setState(() {
                          enableThinking = val;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  settings.put('baseUrl', controller.text);
                  settings.put('enableThinking', enableThinking);
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        }
      ),
    );
  }
}

class ThinkingBlock extends StatefulWidget {
  final String thinking;
  final bool isFinished;

  const ThinkingBlock({
    super.key,
    required this.thinking,
    required this.isFinished,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Default to expanded while it's still generating
    _isExpanded = !widget.isFinished;
  }

  @override
  void didUpdateWidget(ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If it's still generating, keep it expanded
    if (!widget.isFinished) {
      _isExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 18, color: Colors.white38),
                  const SizedBox(width: 12),
                  Text(
                    widget.isFinished ? 'Thought Process' : 'Thinking...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.white24,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded && widget.thinking.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: MarkdownBody(
                data: widget.thinking,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                  code: const TextStyle(
                    backgroundColor: Colors.black26,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
