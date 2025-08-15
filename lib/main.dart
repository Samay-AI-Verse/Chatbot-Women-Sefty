import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'dart:async'; // Import for TimeoutException
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // Import the markdown package

void main() {
  // Set system UI overlay style for a consistent look
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.white,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.white,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noira AI Chat Bot',
      theme: ThemeData(
        primaryColor:
            const Color(0xFF36013F), // Deep purple for a professional feel
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0, // Flat design
          iconTheme: IconThemeData(color: Color(0xFF36013F)),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black87),
          bodyMedium: TextStyle(color: Colors.black87),
        ),
        colorScheme: ColorScheme.fromSwatch()
            .copyWith(secondary: const Color(0xFFFF1493)),
        // FIX: Set the default font for the entire app to support Hindi/Marathi characters
        fontFamily: 'NotoSansDevanagari',
      ),
      home: const ChatBotScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key});

  @override
  _ChatBotScreenState createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<ChatMessage> messages = [];
  List<List<ChatMessage>> previousChats = [];
  List<List<ChatMessage>> filteredChats = [];
  bool isTyping = false;
  bool isSearching = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  FlutterTts flutterTts = FlutterTts();
  int? currentlySpeakingIndex;
  bool isTtsPlaying = false;
  bool _stopRequested = false;

  final String _serverUrl = 'http://localhost:8000/chat';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();
    _loadAllChats();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    flutterTts.stop();
    _fadeController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        filteredChats = List.from(previousChats);
      } else {
        filteredChats = previousChats.where((chat) {
          return chat
              .any((message) => message.text.toLowerCase().contains(query));
        }).toList();
      }
    });
  }

  String _getSearchHighlightedTitle(List<ChatMessage> chat, String query) {
    if (query.isEmpty) {
      return chat.isNotEmpty
          ? (chat.first.isUser ? chat.first.text : 'Chat')
          : 'Chat';
    }

    // Find the first message that contains the search query
    for (ChatMessage message in chat) {
      if (message.text.toLowerCase().contains(query.toLowerCase())) {
        String text = message.text;
        if (text.length > 50) {
          text = '${text.substring(0, 50)}...';
        }
        return text;
      }
    }

    return chat.isNotEmpty
        ? (chat.first.isUser ? chat.first.text : 'Chat')
        : 'Chat';
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      messages.add(ChatMessage(text: text, isUser: true));
      isTyping = true;
      _stopRequested = false;
    });
    _messageController.clear();
    _scrollToBottom();
    await _saveCurrentChat();

    final startTime = DateTime.now();

    try {
      final response = await http
          .post(
            Uri.parse(_serverUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': text}),
          )
          .timeout(const Duration(seconds: 20));

      final elapsed = DateTime.now().difference(startTime);
      const minTypingDuration = Duration(milliseconds: 800);
      if (elapsed < minTypingDuration) {
        await Future.delayed(minTypingDuration - elapsed);
      }
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      if (response.statusCode == 200) {
        // FIX: Properly decode UTF-8 response
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        setState(() {
          messages.add(ChatMessage(
            text: data['reply'] ?? 'No response from server.',
            isUser: false,
          ));
          isTyping = false;
        });
      } else {
        setState(() {
          messages.add(ChatMessage(
            text:
                'Server Error ${response.statusCode}: Could not get a valid response. Please check the server logs.',
            isUser: false,
          ));
          isTyping = false;
        });
      }
    } catch (e) {
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }

      String errorMessage;
      if (e is TimeoutException) {
        errorMessage =
            "Connection Timed Out.\n\nIs the Python server running and responsive?";
      } else {
        errorMessage =
            "Connection Failed.\n\n- Is the Python server running on your computer?\n- Is a firewall blocking the connection to port 5000?";
      }

      setState(() {
        messages.add(ChatMessage(
          text: errorMessage,
          isUser: false,
        ));
        isTyping = false;
      });
    }
    _scrollToBottom();
    await _saveCurrentChat();
  }

  Future<void> _regenerateResponse(int botMsgIndex) async {
    int userMsgIndex = botMsgIndex - 1;
    while (userMsgIndex >= 0 && !messages[userMsgIndex].isUser) {
      userMsgIndex--;
    }
    if (userMsgIndex < 0) return;
    final userMsg = messages[userMsgIndex].text;
    setState(() {
      messages.removeAt(botMsgIndex);
    });
    await _sendMessage(userMsg);
  }

  Future<void> _saveCurrentChat() async {
    final prefs = await SharedPreferences.getInstance();
    final chatJson = jsonEncode(messages.map((m) => m.toJson()).toList());
    await prefs.setString('current_chat', chatJson);
  }

  Future<void> _saveAllChats() async {
    final prefs = await SharedPreferences.getInstance();
    final allChatsJson = jsonEncode(previousChats
        .map((chat) => chat.map((m) => m.toJson()).toList())
        .toList());
    await prefs.setString('all_chats', allChatsJson);
  }

  Future<void> _loadCurrentChat() async {
    final prefs = await SharedPreferences.getInstance();
    final chatJson = prefs.getString('current_chat');
    if (chatJson != null) {
      final List<dynamic> decoded = jsonDecode(chatJson);
      setState(() {
        messages = decoded.map((e) => ChatMessage.fromJson(e)).toList();
      });
    }
  }

  Future<void> _loadAllChats() async {
    final prefs = await SharedPreferences.getInstance();
    final allChatsJson = prefs.getString('all_chats');
    if (allChatsJson != null) {
      final List<dynamic> decoded = jsonDecode(allChatsJson);
      setState(() {
        previousChats = decoded
            .map<List<ChatMessage>>((chat) =>
                (chat as List).map((e) => ChatMessage.fromJson(e)).toList())
            .toList();
        filteredChats = List.from(previousChats); // Initialize filtered chats
      });
    }
    await _loadCurrentChat();
  }

  void _startNewChat() async {
    if (messages.isNotEmpty) {
      previousChats.add(List<ChatMessage>.from(messages));
      await _saveAllChats();
    }
    setState(() {
      messages.clear();
    });
    await _saveCurrentChat();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
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
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: const TextStyle(
            color: Colors.black, fontSize: 19, fontWeight: FontWeight.w600),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo2.png',
              height: 50,
              width: 50,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.chat_bubble_outline, size: 40),
            ),
            const SizedBox(width: 2),
            const Text('Noira'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _startNewChat,
            tooltip: 'New chat',
          ),
        ],
      ),
      drawer: _buildSideNavigation(),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessagesList(),
              ),
            ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/logo.png',
                width: 160,
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.support_agent,
                    size: 100,
                    color: Theme.of(context).primaryColor),
              ),
              const SizedBox(height: 24),
              const Text(
                'Hello, I\'m Noira',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF36013F),
                  fontFamily: 'NotoSansDevanagari',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your personal AI for women\'s safety and support. I\'m here to listen and help.\n\nनमस्ते! मैं आपकी सुरक्षा के लिए यहाँ हूँ।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.4,
                  fontFamily: 'NotoSansDevanagari',
                ),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildSuggestionButton(
                      Icons.security, 'Tips for personal safety'),
                  _buildSuggestionButton(
                      Icons.support_agent, 'I need someone to talk to'),
                  _buildSuggestionButton(
                      Icons.location_on, 'Find local support resources'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return Container(
      color: Colors.white,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: messages.length + (isTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length && isTyping) {
            return _buildTypingIndicator();
          }
          return _buildMessageBubble(messages[index]);
        },
      ),
    );
  }

  // WIDGET FULLY REVISED TO FIX FONT ISSUES
  Widget _buildMessageBubble(ChatMessage message) {
    int index = messages.indexOf(message);
    bool isBot = !message.isUser;

    // FIX: Define a comprehensive and consistent stylesheet for markdown with balanced fonts.
    final markdownStyleSheet =
        MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(
        color: Colors.black87,
        fontSize: 15, // Increased from 14 to 15 - balanced size
        height: 1.5,
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      strong: const TextStyle(
        color: Color(0xFF36013F),
        fontWeight: FontWeight.bold,
        fontSize: 15.5, // Increased from 14.5 to 15.5 - balanced size
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      h1: const TextStyle(
        color: Color(0xFF36013F),
        fontWeight: FontWeight.bold,
        fontSize: 19, // Increased from 18 to 19 - balanced size
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      h2: const TextStyle(
        color: Color(0xFF6A1B9A),
        fontWeight: FontWeight.bold,
        fontSize: 17, // Increased from 16 to 17 - balanced size
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      h3: const TextStyle(
        color: Color(0xFF8E24AA),
        fontWeight: FontWeight.bold,
        fontSize: 16, // Increased from 15 to 16 - balanced size
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      listBullet: const TextStyle(
        color: Color(0xFF36013F),
        fontSize: 15, // Increased from 14 to 15 - balanced size
        height: 1.5,
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      blockquote: const TextStyle(
        color: Colors.black54,
        fontStyle: FontStyle.italic,
        fontSize: 14, // Increased from 13 to 14 - balanced size
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      code: const TextStyle(
        backgroundColor: Color(0xFFF3E5F5),
        color: Color(0xFF6A1B9A),
        fontFamily: 'monospace',
        fontSize: 14, // Increased from 13 to 14 - balanced size
      ),
      tableHead: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Color(0xFF36013F),
        fontSize: 15, // Increased from 14 to 15 - balanced size
        fontFamily: 'NotoSansDevanagari', // Ensure font is applied
      ),
      blockSpacing: 12,
      listIndent: 20,
    );

    // Detect legal or emergency message
    bool isLegal = isBot && message.text.toLowerCase().contains("legal help");
    bool isEmergency = isBot &&
        (message.text.toLowerCase().contains("emergency") ||
            message.text
                .toLowerCase()
                .contains("your safety is my #1 priority"));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: message.isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: isLegal || isEmergency
                    ? Card(
                        color: isLegal
                            ? const Color(0xFFFFF3E0)
                            : const Color(0xFFFFEBEE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: isLegal
                                ? const Color(0xFFFF9800)
                                : const Color(0xFFD32F2F),
                            width: 2,
                          ),
                        ),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isLegal ? Icons.gavel : Icons.warning,
                                color: isLegal
                                    ? const Color(0xFFFF9800)
                                    : const Color(0xFFD32F2F),
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: MarkdownBody(
                                  data: message.text,
                                  // FIX: Apply a derived stylesheet for special cards with balanced fonts
                                  styleSheet: markdownStyleSheet.copyWith(
                                    p: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 14,
                                        fontFamily: 'NotoSansDevanagari'),
                                    strong: TextStyle(
                                        color: isLegal
                                            ? const Color(0xFFFF9800)
                                            : const Color(0xFFD32F2F),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                        fontFamily: 'NotoSansDevanagari'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: message.isUser
                              ? const Color(0xFFF3E5F5)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: isBot
                            ? MarkdownBody(
                                data: message.text,
                                // FIX: Apply the consistent stylesheet here
                                styleSheet: markdownStyleSheet,
                              )
                            : Text(
                                message.text,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize:
                                      15, // Increased from 14 to 15 - balanced size
                                  // No need for fontFamily here, it inherits from theme
                                ),
                              ),
                      ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLargeIconButton(
                  icon: Icons.copy,
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                  },
                ),
                const SizedBox(width: 8),
                if (isBot) ...[
                  _buildLargeIconButton(
                    icon: currentlySpeakingIndex == index && isTtsPlaying
                        ? Icons.stop
                        : Icons.volume_up,
                    tooltip: currentlySpeakingIndex == index && isTtsPlaying
                        ? 'Stop'
                        : 'Speak',
                    onPressed: () async {
                      if (currentlySpeakingIndex == index && isTtsPlaying) {
                        await flutterTts.stop();
                        setState(() {
                          isTtsPlaying = false;
                          currentlySpeakingIndex = null;
                        });
                      } else {
                        await flutterTts.stop();
                        setState(() {
                          currentlySpeakingIndex = index;
                          isTtsPlaying = true;
                        });
                        await flutterTts.speak(message.text);
                        flutterTts.setCompletionHandler(() {
                          setState(() {
                            isTtsPlaying = false;
                            currentlySpeakingIndex = null;
                          });
                        });
                        flutterTts.setCancelHandler(() {
                          setState(() {
                            isTtsPlaying = false;
                            currentlySpeakingIndex = null;
                          });
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildLargeIconButton(
                    icon: Icons.refresh,
                    tooltip: 'Regenerate',
                    onPressed: () {
                      _regenerateResponse(index);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                _buildLargeIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete',
                  onPressed: () {
                    _showDeleteMessageDialog(index);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeIconButton(
      {required IconData icon,
      required String tooltip,
      required VoidCallback onPressed}) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Icon(FontAwesomeIcons.shield,
                size: 18, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Noira is typing...",
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTypingDot(0),
                  const SizedBox(width: 4),
                  _buildTypingDot(1),
                  const SizedBox(width: 4),
                  _buildTypingDot(2),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Interval(0.1 * index, 0.6 + 0.1 * index, curve: Curves.easeInOut),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).primaryColor.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final isInputNotEmpty = _messageController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            const Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF3E5F5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.add, color: Color(0xFF6A1B9A)),
                onPressed: _onAddPressed,
                tooltip: 'Add feature',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6FA),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
                ),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14), // Increased from 13 to 14 - balanced size
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                        color: Color(0xFF8E24AA),
                        fontSize: 14, // Increased from 13 to 14 - balanced size
                        fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                  ),
                  onChanged: (text) {
                    setState(() {});
                  },
                  onSubmitted: _sendMessage,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !isTyping,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (isTyping)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF69B4),
                  minimumSize: const Size(36, 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: const Icon(Icons.stop, size: 20, color: Colors.white),
                label: const Text('Stop',
                    style: TextStyle(fontSize: 15, color: Colors.white)),
                onPressed: () {
                  setState(() {
                    _stopRequested = true;
                    isTyping = false;
                  });
                },
              )
            else if (isInputNotEmpty)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF69B4), Color(0xFF6A1B9A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () => _sendMessage(_messageController.text),
                  tooltip: 'Send',
                ),
              )
            else ...[
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF3E5F5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.mic, color: Color(0xFFFF69B4)),
                  iconSize: 24,
                  onPressed: _onMicPressed,
                  tooltip: 'Voice Input',
                ),
              ),
              const SizedBox(width: 6),
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF3E5F5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon:
                      const Icon(Icons.auto_awesome, color: Color(0xFF6A1B9A)),
                  iconSize: 24,
                  onPressed: _onVoiceAssistantPressed,
                  tooltip: 'Voice Assistant',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onAddPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add feature coming soon!')),
    );
  }

  void _onMicPressed() {}

  void _onVoiceAssistantPressed() {}

  Widget _buildSideNavigation() {
    return Drawer(
      backgroundColor: const Color(0xFFFAFAFA),
      width: MediaQuery.of(context).size.width * 0.85,
      child: SafeArea(
        child: Column(
          children: [
            // Header with logo and title
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.asset(
                      'assets/logo2.png',
                      height: 32,
                      width: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.chat_bubble_outline,
                        size: 24,
                        color: Color(0xFF6A1B9A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Noira',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF36013F),
                          ),
                        ),
                        Text(
                          'AI Safety Assistant',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // New Chat Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text(
                    'New Chat',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A1B9A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: () {
                    _startNewChat();
                    Navigator.pop(context);
                  },
                ),
              ),
            ),

            // Chat history list
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.history,
                              color: Color(0xFF6A1B9A), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Recent Chats',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${previousChats.length} chats',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Chat list
                    Expanded(
                      child: previousChats.isEmpty
                          ? _buildEmptyHistoryState()
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.only(top: 8),
                              itemCount: previousChats.length,
                              itemBuilder: (context, idx) {
                                final chat = previousChats[idx];
                                final title = chat.isNotEmpty
                                    ? (chat.first.isUser
                                        ? chat.first.text
                                        : 'Chat')
                                    : 'Chat';
                                final time = chat.isNotEmpty
                                    ? _formatTime(chat.first.timestamp)
                                    : '';
                                return _buildConversationItem(title, time, idx);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // User profile section
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFF3E5F5),
                  child: Icon(Icons.person, color: Color(0xFF6A1B9A)),
                ),
                title: const Text(
                  'Samay Powade',
                  style: TextStyle(
                    color: Color(0xFF36013F),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Safety First',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.settings, color: Color(0xFF6A1B9A)),
                  onPressed: () {},
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "Today, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } else {
      return "${dt.day}/${dt.month}/${dt.year}";
    }
  }

  Widget _buildConversationItem(String title, String time, int idx) {
    return Dismissible(
      key: Key('chat_$idx'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 20),
            child: Icon(Icons.delete, color: Colors.red),
          ),
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Delete Chat'),
              content: const Text('Are you sure you want to delete this chat?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) {
        _deleteChat(idx);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              setState(() {
                messages = List<ChatMessage>.from(previousChats[idx]);
              });
              await _saveCurrentChat();
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: Color(0xFF6A1B9A),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.length > 30
                              ? '${title.substring(0, 30)}...'
                              : title,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          time,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          const Text(
            'No chat history',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Start a conversation with Noira to see your chat history here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteChatDialog(int idx) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Chat'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete this chat? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteChat(idx);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_sweep, color: Colors.red),
              SizedBox(width: 8),
              Text('Clear All Chats'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete all chat history? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _clearAllChats();
              },
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
  }

  void _deleteChat(int idx) {
    setState(() {
      if (isSearching) {
        final chatToDelete = filteredChats[idx];
        final originalIndex = previousChats.indexOf(chatToDelete);
        if (originalIndex != -1) {
          previousChats.removeAt(originalIndex);
        }
        filteredChats.removeAt(idx);
      } else {
        previousChats.removeAt(idx);
      }
    });
    _saveAllChats();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chat deleted successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _clearAllChats() {
    setState(() {
      previousChats.clear();
      filteredChats.clear();
    });
    _saveAllChats();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All chats cleared successfully'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showDeleteMessageDialog(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Message'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete this message? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteMessage(index);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _deleteMessage(int index) {
    setState(() {
      messages.removeAt(index);
    });
    _saveCurrentChat();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message deleted successfully bo'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildSuggestionButton(IconData icon, String text) {
    return SizedBox(
      width: 320,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: const Color(0xFF6A1B9A), size: 22),
        label: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF36013F),
            fontWeight: FontWeight.w600,
            fontSize: 12, // Increased from 11 to 12 - balanced size
          ),
          maxLines: 1,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF8F8FA),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          alignment: Alignment.centerLeft,
        ),
        onPressed: () => _sendMessage(text),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'],
        isUser: json['isUser'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}
