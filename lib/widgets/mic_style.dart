import 'dart:math';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class MicStylePopup extends StatefulWidget {
  final Function(String) onSpeechRecognized;

  const MicStylePopup({super.key, required this.onSpeechRecognized});

  @override
  _MicStylePopupState createState() => _MicStylePopupState();
}

class _MicStylePopupState extends State<MicStylePopup>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _frequencyController;
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';
  List<double> _frequencyLevels = List.generate(24, (index) => 0.0);
  final Random _random = Random();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _frequencyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(() {
        if (_isListening && mounted) {
          setState(() {
            _updateFrequencyLevels();
          });
        }
      });

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    // This part should handle the one-time initialization of the speech recognizer
    await _speechToText.stop();

    bool hasSpeech = await _speechToText.initialize(
      onStatus: (status) {
        if (mounted) {
          setState(() {
            _isListening = status == 'listening';
          });
          // This logic now only handles stopping the animation when listening ends
          if (status != 'listening') {
            _pulseController.stop();
            _frequencyController.stop();
          }
        }
      },
      onError: (errorNotification) {
        print("STT Error: ${errorNotification.errorMsg}");
      },
    );

    if (hasSpeech) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      _startListening();
    } else {
      print("The user has denied the use of speech recognition.");
    }
  }

  void _startListening() {
    // This is the key change: restart animations every time listening starts.
    _pulseController
      ..reset()
      ..repeat(reverse: true);
    _frequencyController
      ..reset()
      ..repeat();

    _speechToText.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _recognizedText = result.recognizedWords;
          });
        }

        if (result.finalResult) {
          widget.onSpeechRecognized(_recognizedText);
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      onSoundLevelChange: (level) {
        if (mounted && _isListening) {
          setState(() {
            _updateFrequencyLevelsFromSound(level);
          });
        }
      },
    );
  }

  void _updateFrequencyLevels() {
    for (int i = 0; i < _frequencyLevels.length; i++) {
      _frequencyLevels[i] = 2.0 + _random.nextDouble() * 8.0;
    }
  }

  void _updateFrequencyLevelsFromSound(double level) {
    double baseLevel = level.clamp(0, 1) * 25;
    for (int i = 0; i < _frequencyLevels.length; i++) {
      double variation = sin(i * 0.5) * 3.0;
      _frequencyLevels[i] = baseLevel + variation + _random.nextDouble() * 2.0;
    }
  }

  void _stopListening() {
    _speechToText.stop();
    _pulseController.stop();
    _frequencyController.stop();
  }

  @override
  void dispose() {
    _stopListening();
    _pulseController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 60,
                child: CustomPaint(
                  painter: FrequencyVisualizerPainter(
                      _frequencyLevels, _isListening),
                  size: Size(MediaQuery.of(context).size.width - 120, 60),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isListening ? _pulseAnimation.value : 1.0,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E5F5),
                        shape: BoxShape.circle,
                        gradient: _isListening
                            ? const RadialGradient(
                                colors: [Color(0xFFFF69B4), Color(0xFFF3E5F5)],
                                stops: [0.3, 1.0],
                              )
                            : null,
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color:
                                      const Color(0xFFFF69B4).withOpacity(0.4),
                                  blurRadius: 15,
                                  spreadRadius: 5,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.mic,
                        color: _isListening
                            ? Colors.white
                            : const Color(0xFFFF69B4),
                        size: 40,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Container(
                width: 30,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      _isListening ? const Color(0xFFFF69B4) : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _stopListening();
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FrequencyVisualizerPainter extends CustomPainter {
  final List<double> frequencyLevels;
  final bool isListening;

  FrequencyVisualizerPainter(this.frequencyLevels, this.isListening);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final barWidth = (size.width - 40) / frequencyLevels.length;
    final maxBarHeight = size.height / 2;

    for (int i = 0; i < frequencyLevels.length; i++) {
      final barHeight = frequencyLevels[i] * maxBarHeight / 30;
      final left = i * barWidth + 20;

      final paint = Paint()
        ..color = isListening
            ? Color.lerp(const Color(0xFFF3E5F5), const Color(0xFFFF69B4),
                frequencyLevels[i] / 30)!
            : Colors.grey[300]!;

      // top bar
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              left, center.dy - barHeight / 2, barWidth - 2, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );

      // bottom bar (mirror)
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              left, center.dy + barHeight / 2, barWidth - 2, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FrequencyVisualizerPainter oldDelegate) {
    return oldDelegate.frequencyLevels != frequencyLevels ||
        oldDelegate.isListening != isListening;
  }
}
