import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:math' as math;
// import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  _AIAssistantScreenState createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen>
    with TickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _isListening = false;
  // String _text = ''; // text variable is now for internal use only
  bool _isResponding = false;
  bool _isProcessing = false;

  late AnimationController _particleController;
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _breathingController;

  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _breathingAnimation;

  final String _serverUrl =
      'https://samay-verse-womensafety-backend-chatbot.hf.space/chat';

  List<String> _sentencesToSpeak = [];
  int _currentSentenceIndex = 0;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    _breathingAnimation = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    _initTts();
    _speakInitialMessage();
  }

  void _speakInitialMessage() async {
    await _tts.speak('Hi, I\'m Shakti AI. How can I assist you today?');
    // After the intro is spoken, start listening for the user's command
    _startListening();
  }

  void _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      setState(() => _isResponding = true);
    });

    // This handler now controls the flow of speaking one sentence at a time.
    _tts.setCompletionHandler(() {
      _currentSentenceIndex++;
      if (_currentSentenceIndex < _sentencesToSpeak.length) {
        // Speak the next sentence.
        _speakResponse();
      } else {
        // All sentences have been spoken, reset and start listening again.
        setState(() {
          _isResponding = false;
        });
        _sentencesToSpeak = [];
        _currentSentenceIndex = 0;
        _startListening();
      }
    });

    _tts.setErrorHandler((msg) {
      setState(() {
        _isResponding = false;
      });
      _startListening();
    });
  }

  void _startListening() async {
    if (!_isListening && !_isProcessing) {
      bool available = await _speech.initialize(
        onError: (error) {
          setState(() {
            _isListening = false;
          });
          // Speak the error message instead of displaying text
          _tts.speak('Speech recognition error. Please try again.');
          _startListening();
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
        });

        _speech.listen(
          onResult: (result) {
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              _processVoiceCommand(result.recognizedWords);
              _stopListening();
            }
          },
          partialResults: true,
          localeId: 'en_US',
          cancelOnError: false,
        );
      } else {
        _tts.speak('Unable to start voice recognition');
      }
    }
  }

  void _stopListening() {
    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    }
  }

  void _processVoiceCommand(String command) async {
    if (command.trim().isEmpty) {
      _startListening();
      return;
    }

    setState(() {
      _isProcessing = true;
      _isListening = false;
    });

    try {
      final response = await http
          .post(
            Uri.parse(_serverUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': command}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        final reply = data['reply'] ??
            'I apologize, but I couldn\'t process that request.';

        // Split the response into sentences for sequential speaking
        _sentencesToSpeak = _splitIntoSentences(reply);
        _currentSentenceIndex = 0;

        setState(() {
          _isProcessing = false;
        });

        _speakResponse();
      } else {
        _tts.speak(
            'I\'m experiencing technical difficulties. Please try again.');
        setState(() {
          _isProcessing = false;
        });
        _startListening();
      }
    } catch (e) {
      String errorMessage;
      if (e is TimeoutException) {
        errorMessage =
            'Connection timeout. Please check your internet and try again.';
      } else {
        errorMessage =
            'I\'m having trouble connecting. Please try again later.';
      }

      _tts.speak(errorMessage);
      setState(() {
        _isProcessing = false;
      });
      _startListening();
    }
  }

  // Recursive function to speak sentences one by one.
  Future<void> _speakResponse() async {
    if (_currentSentenceIndex < _sentencesToSpeak.length) {
      final sentence = _sentencesToSpeak[_currentSentenceIndex].trim();
      if (sentence.isNotEmpty) {
        await _tts.speak(sentence);
      } else {
        // Skip empty sentences
        _currentSentenceIndex++;
        _speakResponse();
      }
    }
  }

  // Simple sentence splitting function. Can be improved for more complex cases.
  List<String> _splitIntoSentences(String text) {
    // Regex to split by . ! ? followed by a space or end of string.
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _stopSpeaking() async {
    await _tts.stop();
    setState(() {
      _isResponding = false;
    });
    _startListening();
  }

  void _resetToInitial() {
    setState(() {
      _isListening = false;
      _isProcessing = false;
    });
    _stopListening();
    _stopSpeaking();
    _speakInitialMessage();
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _particleController.dispose();
    _pulseController.dispose();
    _rotationController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [
                  Color(0xFF1A0033),
                  Color(0xFF0D001A),
                  Color(0xFF000000),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: AmbientLightPainter(
                animationValue: _particleController.value,
                isActive: _isListening || _isProcessing || _isResponding,
              ),
            ),
          ),
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _getStatusColor(),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _getStatusColor().withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Shakti AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getStatusText(),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _resetToInitial,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _particleController,
                _pulseController,
                _rotationController,
                _breathingController,
              ]),
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening
                      ? _pulseAnimation.value
                      : _isProcessing || _isResponding
                          ? _breathingAnimation.value
                          : 1.0,
                  child: Transform.rotate(
                    angle: _rotationAnimation.value,
                    child: CustomPaint(
                      size: const Size(320, 320),
                      painter: AdvancedParticleSphere3D(
                        animationValue: _particleController.value,
                        isListening: _isListening,
                        isResponding: _isResponding,
                        isProcessing: _isProcessing,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // The text display widget is completely removed here.
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  icon: Icons.refresh,
                  isActive: false,
                  onTap: _resetToInitial,
                ),
                GestureDetector(
                  onTap: () {
                    if (_isListening) {
                      _stopListening();
                    } else if (_isProcessing) {
                      return;
                    } else {
                      _startListening();
                    }
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _getMainButtonGradient(),
                      boxShadow: [
                        BoxShadow(
                          color: _getMainButtonColor().withOpacity(0.5),
                          blurRadius: 25,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      _getMainButtonIcon(),
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                _buildControlButton(
                  icon: Icons.stop,
                  isActive: _isResponding,
                  onTap: _stopSpeaking,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? const Color(0xFFFF6B9D).withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFF6B9D)
                : Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? const Color(0xFFFF6B9D) : Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (_isListening) return const Color(0xFFFF6B9D);
    if (_isProcessing) return const Color(0xFFFFB347);
    if (_isResponding) return const Color(0xFF00FF88);
    return const Color(0xFF8B5CF6);
  }

  String _getStatusText() {
    if (_isListening) return 'Listening';
    if (_isProcessing) return 'Processing';
    if (_isResponding) return 'Speaking';
    return 'Ready to help';
  }

  LinearGradient _getMainButtonGradient() {
    if (_isListening) {
      return const LinearGradient(
        colors: [Color(0xFFFF6B9D), Color(0xFFC44569)],
      );
    } else if (_isProcessing) {
      return const LinearGradient(
        colors: [Color(0xFFFFB347), Color(0xFFFF8C00)],
      );
    } else if (_isResponding) {
      return const LinearGradient(
        colors: [Color(0xFF00FF88), Color(0xFF00CC6A)],
      );
    }
    return const LinearGradient(
      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
    );
  }

  Color _getMainButtonColor() {
    if (_isListening) return const Color(0xFFFF6B9D);
    if (_isProcessing) return const Color(0xFFFFB347);
    if (_isResponding) return const Color(0xFF00FF88);
    return const Color(0xFF8B5CF6);
  }

  IconData _getMainButtonIcon() {
    if (_isListening) return Icons.mic;
    if (_isProcessing) return Icons.hourglass_bottom;
    if (_isResponding) return Icons.volume_up;
    return Icons.mic_none;
  }
}

class AdvancedParticleSphere3D extends CustomPainter {
  final double animationValue;
  final bool isListening;
  final bool isResponding;
  final bool isProcessing;

  AdvancedParticleSphere3D({
    required this.animationValue,
    required this.isListening,
    required this.isResponding,
    required this.isProcessing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.25;

    final radius = baseRadius + (math.sin(animationValue * 2 * math.pi) * 10);

    final particles = <Particle>[];
    const particleCount = 1200;

    for (int i = 0; i < particleCount; i++) {
      final t = i / particleCount;

      final phi = math.acos(1 - 2 * t);
      final theta = 2 * math.pi * (i / ((1 + math.sqrt(5)) / 2));

      final noiseX = (math.sin(animationValue * 3 + i * 0.1) * 0.1);
      final noiseY = (math.cos(animationValue * 2.5 + i * 0.15) * 0.1);
      final noiseZ = (math.sin(animationValue * 4 + i * 0.08) * 0.1);

      var x = radius * math.sin(phi) * math.cos(theta) + noiseX * radius;
      var y = radius * math.sin(phi) * math.sin(theta) + noiseY * radius;
      var z = radius * math.cos(phi) + noiseZ * radius;

      final rotationSpeed = isListening
          ? 2.0
          : isProcessing
              ? 1.5
              : 1.0;
      final rotation = animationValue * rotationSpeed * 2 * math.pi;

      final rotatedX = x * math.cos(rotation) - z * math.sin(rotation);
      final rotatedZ = x * math.sin(rotation) + z * math.cos(rotation);

      final rotation2 = animationValue * rotationSpeed * math.pi;
      final finalY = y * math.cos(rotation2) - rotatedZ * math.sin(rotation2);
      final finalZ = y * math.sin(rotation2) + rotatedZ * math.cos(rotation2);

      final perspective = 600.0;
      final projectedX = (rotatedX * perspective) / (perspective + finalZ);
      final projectedY = (finalY * perspective) / (perspective + finalZ);

      final depth = (finalZ + radius) / (2 * radius);
      final opacity = math.max(0.05, math.min(1.0, depth));
      final particleSize = math.max(0.3, math.min(3.0, 1.5 * depth));

      particles.add(Particle(
        position: Offset(
          center.dx + projectedX,
          center.dy + projectedY,
        ),
        opacity: opacity,
        size: particleSize,
        depth: depth,
      ));
    }

    particles.sort((a, b) => a.depth.compareTo(b.depth));

    for (final particle in particles) {
      final paint = Paint()
        ..color = _getParticleColor().withOpacity(particle.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        particle.position,
        particle.size,
        paint,
      );

      if (isListening || isProcessing || isResponding) {
        final glowPaint = Paint()
          ..color = _getParticleColor().withOpacity(particle.opacity * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

        canvas.drawCircle(
          particle.position,
          particle.size * 2.5,
          glowPaint,
        );
      }
    }

    _drawAdvancedConnections(canvas, particles);
  }

  void _drawAdvancedConnections(Canvas canvas, List<Particle> particles) {
    const maxDistance = 60.0;
    final connectionPaint = Paint()..strokeWidth = 0.3;

    for (int i = 0; i < particles.length; i += 8) {
      for (int j = i + 1; j < particles.length && j < i + 15; j++) {
        final distance =
            (particles[i].position - particles[j].position).distance;
        if (distance < maxDistance) {
          final opacity = ((1 - distance / maxDistance) * 0.15) *
              (particles[i].opacity + particles[j].opacity) /
              2;
          connectionPaint.color = _getParticleColor().withOpacity(opacity);
          canvas.drawLine(
            particles[i].position,
            particles[j].position,
            connectionPaint,
          );
        }
      }
    }
  }

  Color _getParticleColor() {
    if (isResponding) {
      return const Color(0xFF00FF88);
    } else if (isProcessing) {
      return const Color(0xFFFFB347);
    } else if (isListening) {
      return const Color(0xFFFF6B9D);
    } else {
      return const Color(0xFF8B5CF6);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class AmbientLightPainter extends CustomPainter {
  final double animationValue;
  final bool isActive;

  AmbientLightPainter({
    required this.animationValue,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive) return;

    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF8B5CF6).withOpacity(0.1),
          Colors.transparent,
        ],
        stops: [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.4));

    canvas.drawCircle(center, size.width * 0.4, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class Particle {
  final Offset position;
  final double opacity;
  final double size;
  final double depth;

  Particle({
    required this.position,
    required this.opacity,
    required this.size,
    required this.depth,
  });
}
