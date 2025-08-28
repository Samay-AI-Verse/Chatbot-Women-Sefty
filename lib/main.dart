import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io'; // Import for File
import 'dart:async'; // Import for TimeoutException and Timer
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart'; // Import the markdown package
import 'package:image_picker/image_picker.dart'; // Import for image picking
import 'package:file_picker/file_picker.dart'; // Import for file picking
import 'package:http_parser/http_parser.dart'; // Add this line
// main.dart
import 'widgets/mic_style.dart'; // Add this line
// import 'package:speech_to_text/speech_to_text.dart'; // Add this line
import 'voice_assistant/voice_assistant_screen.dart';

void main() {
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
      title: 'Shakti AI Chat Bot',
      theme: ThemeData(
        primaryColor: const Color(0xFF36013F),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF36013F)),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black87),
          bodyMedium: TextStyle(color: Colors.black87),
        ),
        colorScheme: ColorScheme.fromSwatch()
            .copyWith(secondary: const Color(0xFFFF1493)),
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
  int? _currentChatIndex;
  List<ChatMessage> messages = [];
  List<List<ChatMessage>> previousChats = [];
  List<List<ChatMessage>> filteredChats = [];
  bool isTyping = false;
  bool isSearching = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // New animation controller for the sliding effect
  late AnimationController _drawerAnimationController;
  late Animation<double> _drawerSlideAnimation;

  FlutterTts flutterTts = FlutterTts();
  int? currentlySpeakingIndex;
  bool isTtsPlaying = false;
  bool _stopRequested = false;

  final String _serverUrl =
      'https://women-safety-backend-host.onrender.com/chat';

  Timer? _searchDebounceTimer;

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

    // Initialize the new animation controller
    _drawerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // This will animate the body's horizontal position
    _drawerSlideAnimation = Tween<double>(
      begin: 0.0,
      end: 0.8, // The factor of the screen width to slide
    ).animate(CurvedAnimation(
      parent: _drawerAnimationController,
      curve: Curves.easeInOut,
    ));

    _loadAllChats();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    flutterTts.stop();
    _fadeController.dispose();
    _drawerAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.toLowerCase().trim();
      final wasSearching = isSearching;
      final newIsSearching = query.isNotEmpty;
      if (wasSearching != newIsSearching ||
          (newIsSearching &&
              (filteredChats.isEmpty ||
                  !_areChatsEqual(filteredChats, _getFilteredChats(query))))) {
        setState(() {
          isSearching = newIsSearching;
          if (query.isEmpty) {
            filteredChats = List.from(previousChats);
          } else {
            filteredChats = _getFilteredChats(query);
          }
        });
      }
    });
  }

  List<List<ChatMessage>> _getFilteredChats(String query) {
    return previousChats.where((chat) {
      return chat.any((message) => message.text.toLowerCase().contains(query));
    }).toList();
  }

  bool _areChatsEqual(
      List<List<ChatMessage>> chats1, List<List<ChatMessage>> chats2) {
    if (chats1.length != chats2.length) return false;
    for (int i = 0; i < chats1.length; i++) {
      if (chats1[i].length != chats2[i].length) return false;
      for (int j = 0; j < chats1[i].length; j++) {
        if (chats1[i][j].text != chats2[i][j].text ||
            chats1[i][j].isUser != chats2[i][j].isUser) {
          return false;
        }
      }
    }
    return true;
  }

  String _getSearchHighlightedTitle(List<ChatMessage> chat, String query) {
    if (query.isEmpty) {
      return chat.isNotEmpty
          ? (chat.first.isUser ? chat.first.text : 'Chat')
          : 'Chat';
    }
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
    // New logic to highlight the chat after the first message is sent
    if (_currentChatIndex == null) {
      setState(() {
        if (previousChats.isEmpty ||
            previousChats.last.first.text != messages.first.text) {
          previousChats.add(List<ChatMessage>.from(messages));
        }
        _currentChatIndex = previousChats.length - 1;
      });
    }
  }

  Future<void> _regenerateResponse(int botMsgIndex) async {
    int userMsgIndex = botMsgIndex - 1;
    while (userMsgIndex >= 0 && !messages[userMsgIndex].isUser) {
      userMsgIndex--;
    }
    if (userMsgIndex < 0) return;
    setState(() {
      messages.removeAt(botMsgIndex);
    });
    setState(() {
      isTyping = true;
      _stopRequested = false;
    });
    final userMsg = messages[userMsgIndex].text;
    try {
      final response = await http
          .post(
            Uri.parse(_serverUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': userMsg}),
          )
          .timeout(const Duration(seconds: 20));
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        setState(() {
          messages.add(ChatMessage(
            text: data['reply'] ?? 'No response from server.',
            isUser: false,
            type: 'text',
          ));
          isTyping = false;
        });
      } else {
        setState(() {
          messages.add(ChatMessage(
            text:
                'Server Error ${response.statusCode}: Could not get a valid response.',
            isUser: false,
            type: 'text',
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
            "Connection Failed.\n\n- Is the Python server running on your computer?\n- Is a firewall blocking the connection?";
      }
      setState(() {
        messages.add(ChatMessage(
          text: errorMessage,
          isUser: false,
          type: 'text',
        ));
        isTyping = false;
      });
    }
    _scrollToBottom();
    await _saveCurrentChat();
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
        filteredChats = List.from(previousChats);
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
      // _currentChatIndex = null; // Add this line
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
          onPressed: () {
            // Open the drawer and start the slide animation
            _scaffoldKey.currentState?.openDrawer();
          },
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
            const Text('Shakti'),
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
      drawer: Drawer(
        backgroundColor: const Color(0xFFFAFAFA),
        width: MediaQuery.of(context).size.width * 0.90,
        child: _buildSideNavigation(),
      ),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width,
      onDrawerChanged: (isOpened) {
        if (isOpened) {
          _drawerAnimationController.forward();
        } else {
          _drawerAnimationController.reverse();
        }
      },
      body: AnimatedBuilder(
        animation: _drawerAnimationController,
        builder: (context, child) {
          final double slide =
              MediaQuery.of(context).size.width * _drawerSlideAnimation.value;
          final double scale = 1.0 -
              (_drawerSlideAnimation.value * 0.2); // Optional scaling effect
          final double borderRadius = _drawerAnimationController.value * 24;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(slide)
              ..scale(scale),
            child: GestureDetector(
              onTap: () {
                if (_scaffoldKey.currentState!.isDrawerOpen) {
                  Navigator.pop(context);
                }
              },
              onHorizontalDragUpdate: (details) {
                if (!_scaffoldKey.currentState!.isDrawerOpen) {
                  _drawerAnimationController.value += details.primaryDelta! /
                      (MediaQuery.of(context).size.width * 0.90);
                }
              },
              onHorizontalDragEnd: (details) {
                if (_drawerAnimationController.value > 0.5) {
                  _scaffoldKey.currentState!.openDrawer();
                } else {
                  _drawerAnimationController.reverse();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: AbsorbPointer(
                  absorbing: _scaffoldKey.currentState!.isDrawerOpen,
                  child: Stack(
                    children: [
                      FadeTransition(
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
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ... rest of the code remains unchanged
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
                'Hello, I\'m Shakti',
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

  Widget _buildMessageBubble(ChatMessage message) {
    int index = messages.indexOf(message);
    bool isBot = !message.isUser;
    final markdownStyleSheet =
        MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(
        color: Colors.black87,
        fontSize: 16,
        height: 1.5,
        fontFamily: 'NotoSansDevanagari',
      ),
      strong: const TextStyle(
        color: Color(0xFF36013F),
        fontWeight: FontWeight.bold,
        fontSize: 16.5,
        fontFamily: 'NotoSansDevanagari',
      ),
      h1: const TextStyle(
        color: Color(0xFF36013F),
        fontWeight: FontWeight.bold,
        fontSize: 20,
        fontFamily: 'NotoSansDevanagari',
      ),
      h2: const TextStyle(
        color: Color(0xFF6A1B9A),
        fontWeight: FontWeight.bold,
        fontSize: 18,
        fontFamily: 'NotoSansDevanagari',
      ),
      h3: const TextStyle(
        color: Color(0xFF8E24AA),
        fontWeight: FontWeight.bold,
        fontSize: 17,
        fontFamily: 'NotoSansDevanagari',
      ),
      listBullet: const TextStyle(
        color: Color(0xFF36013F),
        fontSize: 16,
        height: 1.5,
        fontFamily: 'NotoSansDevanagari',
      ),
      blockquote: const TextStyle(
        color: Colors.black54,
        fontStyle: FontStyle.italic,
        fontSize: 15,
        fontFamily: 'NotoSansDevanagari',
      ),
      code: const TextStyle(
        backgroundColor: Color(0xFFF3E5F5),
        color: Color(0xFF6A1B9A),
        fontFamily: 'monospace',
        fontSize: 14,
      ),
      tableHead: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Color(0xFF36013F),
        fontSize: 16,
        fontFamily: 'NotoSansDevanagari',
      ),
      blockSpacing: 12,
      listIndent: 20,
    );
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
                          child: isLegal
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.gavel,
                                      color: const Color(0xFFFF9800),
                                      size: 24,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: MarkdownBody(
                                        data: message.text,
                                        styleSheet: markdownStyleSheet.copyWith(
                                          p: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 14,
                                              fontFamily: 'NotoSansDevanagari'),
                                          strong: const TextStyle(
                                              color: Color(0xFFFF9800),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14.5,
                                              fontFamily: 'NotoSansDevanagari'),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  child: MarkdownBody(
                                    data: message.text,
                                    styleSheet: markdownStyleSheet.copyWith(
                                      p: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 14,
                                          fontFamily: 'NotoSansDevanagari'),
                                      strong: const TextStyle(
                                          color: Color(0xFFD32F2F),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                          fontFamily: 'NotoSansDevanagari'),
                                    ),
                                  ),
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
                        child: _buildContent(
                            message), // Call the new content builder
                      ),
              ),
            ],
          ),
          if (isBot)
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
                ],
              ),
            ),
        ],
      ),
    );
  }

  // New method to build content based on message type
  Widget _buildContent(ChatMessage message) {
    if (message.type == 'image' && message.filePath != null) {
      return Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: message.isUser
              ? const Color(0xFFF3E5F5)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Image.file(
              File(message.filePath!),
              width: 200, // Adjust size as needed
              height: 200,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 8),
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    } else if (message.type == 'file' && message.filePath != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, color: Color(0xFF36013F)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.text,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
              ),
            ),
          ),
        ],
      );
    } else {
      // Existing MarkdownBody or Text widget for regular text messages
      return !message.isUser
          ? MarkdownBody(
              data: message.text,
              styleSheet:
                  MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  height: 1.5,
                  fontFamily: 'NotoSansDevanagari',
                ),
                strong: const TextStyle(
                  color: Color(0xFF36013F),
                  fontWeight: FontWeight.bold,
                  fontSize: 16.5,
                  fontFamily: 'NotoSansDevanagari',
                ),
                h1: const TextStyle(
                  color: Color(0xFF36013F),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  fontFamily: 'NotoSansDevanagari',
                ),
                h2: const TextStyle(
                  color: Color(0xFF6A1B9A),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'NotoSansDevanagari',
                ),
                h3: const TextStyle(
                  color: Color(0xFF8E24AA),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  fontFamily: 'NotoSansDevanagari',
                ),
                listBullet: const TextStyle(
                  color: Color(0xFF36013F),
                  fontSize: 16,
                  height: 1.5,
                  fontFamily: 'NotoSansDevanagari',
                ),
                blockquote: const TextStyle(
                  color: Colors.black54,
                  fontStyle: FontStyle.italic,
                  fontSize: 15,
                  fontFamily: 'NotoSansDevanagari',
                ),
                code: const TextStyle(
                  backgroundColor: Color(0xFFF3E5F5),
                  color: Color(0xFF6A1B9A),
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                tableHead: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF36013F),
                  fontSize: 16,
                  fontFamily: 'NotoSansDevanagari',
                ),
                blockSpacing: 12,
                listIndent: 20,
              ),
            )
          : Text(
              message.text,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
              ),
            );
    }
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
                "Shakti is typing...",
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
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(
                        color: Color(0xFF8E24AA),
                        fontSize: 14,
                        fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                  ),
                  onChanged: (text) {
                    final newIsInputNotEmpty = text.trim().isNotEmpty;
                    if (newIsInputNotEmpty != isInputNotEmpty) {
                      setState(() {});
                    }
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Draggable handle
                Center(
                  child: Container(
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildOptionTile(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage();
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'File',
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 24,
                color: const Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF36013F),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E5F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: const Color(0xFF6A1B9A),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF36013F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final fileBytes = await pickedFile.readAsBytes();
      final chatMessage = ChatMessage(
        text: "User uploaded an image.",
        isUser: true,
        type: 'image',
        filePath: pickedFile.path,
        data: fileBytes,
      );
      setState(() {
        messages.add(chatMessage);
      });
      _scrollToBottom();
      _sendMessageWithFile(chatMessage);
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
    );
    if (result != null) {
      final fileBytes = await File(result.files.single.path!).readAsBytes();
      final chatMessage = ChatMessage(
        text: "User uploaded a file: ${result.files.single.name}",
        isUser: true,
        type: 'file',
        filePath: result.files.single.path,
        data: fileBytes,
      );
      setState(() {
        messages.add(chatMessage);
      });
      _scrollToBottom();
      _sendMessageWithFile(chatMessage);
    }
  }

  Future<void> _sendMessageWithFile(ChatMessage message) async {
    if (message.data == null) return;
    setState(() {
      isTyping = true;
      _stopRequested = false;
    });
    _scrollToBottom();
    await _saveCurrentChat();
    final startTime = DateTime.now();

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_serverUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'file', // Field name for the file on your backend
        message.data!,
        filename: message.filePath!.split('/').last,
        contentType: message.type == 'image'
            ? MediaType('image', 'jpeg')
            : MediaType('application', 'octet-stream'),
      ));
      request.fields['message'] = message.text; // Add the message text

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 40));
      final response = await http.Response.fromStream(streamedResponse);

      // ... rest of your response handling logic from _sendMessage
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
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        setState(() {
          messages.add(ChatMessage(
            text: data['reply'] ?? 'No response from server.',
            isUser: false,
            type: 'text',
          ));
          isTyping = false;
        });
      } else {
        setState(() {
          messages.add(ChatMessage(
            text:
                'Server Error ${response.statusCode}: Could not get a valid response. Please check the server logs.',
            isUser: false,
            type: 'text',
          ));
          isTyping = false;
        });
      }
    } catch (e) {
      // ... your existing error handling
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      String errorMessage;
      if (e is TimeoutException) {
        errorMessage =
            "Connection Timed Out. Is the Python server running and responsive?";
      } else {
        errorMessage =
            "Connection Failed. Is the Python server running and accessible?";
      }
      setState(() {
        messages.add(ChatMessage(
          text: errorMessage,
          isUser: false,
          type: 'text',
        ));
        isTyping = false;
      });
    }
    _scrollToBottom();
    await _saveCurrentChat();
  }

  // main.dart
  void _onMicPressed() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return MicStylePopup(
          onSpeechRecognized: (String text) {
            if (text.isNotEmpty) {
              _messageController.text = text;
              _sendMessage(text);
            }
          },
        );
      },
    );
  }

  void _onVoiceAssistantPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AIAssistantScreen()),
    );
  }

  Widget _buildSideNavigation() {
    return Drawer(
      backgroundColor: const Color(0xFFFAFAFA),
      width: MediaQuery.of(context).size.width * 0.90,
      child: SafeArea(
        child: Column(
          children: [
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
                          'Shakti',
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
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFF3E5F5),
                    child: Icon(Icons.person, color: Color(0xFF6A1B9A)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InkWell(
                onTap: () {
                  _startNewChat();
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEFF4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 20, color: Color(0xFF36013F)),
                      SizedBox(width: 12),
                      Text(
                        'New chat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF36013F),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
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
            Container(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Resources',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF36013F),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildResourceBox('Safety Tips', Icons.security),
                        _buildResourceBox('Emergency Help', Icons.warning),
                        _buildResourceBox('Legal Support', Icons.gavel),
                        _buildResourceBox('Support Groups', Icons.group),
                        _buildResourceBox('Self Defense', Icons.shield),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationItem(String title, String time, int idx) {
    final isSelected = _currentChatIndex == idx;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF3E5F5) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            setState(() {
              messages = List<ChatMessage>.from(previousChats[idx]);
              _currentChatIndex = idx; // Add this line
            });
            await _saveCurrentChat();
            Navigator.pop(context);
          },
          onLongPress: () => _showDeleteChatDialog(idx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
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
              ],
            ),
          ),
        ),
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

  void _deleteChat(int idx) {
    try {
      setState(() {
        if (isSearching) {
          if (idx >= 0 && idx < filteredChats.length) {
            final chatToDelete = filteredChats[idx];
            final originalIndex = previousChats.indexOf(chatToDelete);
            if (originalIndex != -1) {
              previousChats.removeAt(originalIndex);
            }
            filteredChats.removeAt(idx);
          }
        } else {
          if (idx >= 0 && idx < previousChats.length) {
            previousChats.removeAt(idx);
          }
        }
      });
      if (isSearching) {
        final query = _searchController.text.toLowerCase().trim();
        if (query.isEmpty) {
          filteredChats = List.from(previousChats);
        } else {
          filteredChats = previousChats.where((chat) {
            return chat
                .any((message) => message.text.toLowerCase().contains(query));
          }).toList();
        }
      }
      _saveAllChats();
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text('Chat deleted successfully'),
      //     backgroundColor: Colors.green,
      //   ),
      // );
    } catch (e) {
      print('Error deleting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error deleting chat. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildResourceBox(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        _sendMessage(label);
        Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6A1B9A), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: const Color(0xFF6A1B9A)),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6A1B9A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
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
              'Start a conversation with Shakti to see your chat history here',
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
                // Navigator.of(context).pop();
                // _clearAllChats();
              },
              child: const Text('Clear All'),
            ),
          ],
        );
      },
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
    try {
      if (index >= 0 && index < messages.length) {
        setState(() {
          messages.removeAt(index);
        });
        _saveCurrentChat();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error deleting message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error deleting message. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
            fontSize: 12,
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
  final String? filePath;
  final String? type;
  final List<int>? data; // Add this line

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.filePath,
    this.type = 'text',
    this.data, // Add this line
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'filePath': filePath,
        'type': type,
        'data': data, // Add this line
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'],
        isUser: json['isUser'],
        timestamp: DateTime.parse(json['timestamp']),
        filePath: json['filePath'],
        type: json['type'],
        data: (json['data'] as List?)?.cast<int>(), // Add this line
      );
}
