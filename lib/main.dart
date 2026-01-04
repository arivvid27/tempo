import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const TempoApp());

class TempoApp extends StatelessWidget {
  const TempoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFF1A1A1A)),
      home: const ReaderPage(),
    );
  }
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final List<String> _words = "Welcome to Tempo. The red letter stays still. minute. up. on. Everything is aligned.".split(" ");
  int _currentIndex = 0;
  Timer? _timer;
  bool _isPlaying = false;
  bool _showRestart = false;
  bool _isHoveringRestart = false;
  int _wpm = 300; 

  // Colors
  final Color _cream = const Color(0xFFF5F5DC);
  final Color _softRed = const Color(0xFFE57373);
  final Color _lightCharcoal = const Color(0xFF2C2C2C);

  int _calculateORP(String word) {
    int length = word.length;
    if (length == 1) return 0;
    if (length == 2) return 1;
    if (length == 3) return 1;
    return (length * 0.35).floor();
  }

  // REFINED TIMER: Handles the "Offbeat" pause for punctuation
  void _runTimer() {
    _timer?.cancel();
    
    // Calculate base speed
    int baseMs = (60000 / _wpm).round();
    String currentWord = _words[_currentIndex];
    
    // Check for sentence-ending punctuation
    bool isEndOfSentence = currentWord.endsWith('.') || 
                           currentWord.endsWith('?') || 
                           currentWord.endsWith('!');
    
    // If it's a period, we wait for 2 beats instead of 1
    int duration = isEndOfSentence ? (baseMs * 2) : baseMs;

    _timer = Timer(Duration(milliseconds: duration), () {
      if (!mounted) return;
      setState(() {
        if (_currentIndex < _words.length - 1) {
          _currentIndex++;
          _runTimer(); // Recursively trigger the next word with its own timing
        } else {
          _isPlaying = false;
          _showRestart = true;
        }
      });
    });
  }

  void _togglePlayback() {
    if (_showRestart) return;
    if (_isPlaying) { 
      _timer?.cancel(); 
    } else { 
      _runTimer(); 
    }
    setState(() => _isPlaying = !_isPlaying);
  }

  void _updateWPM(int delta) {
    setState(() => _wpm = (_wpm + delta).clamp(30, 900));
    // If it's playing, we restart the timer loop to apply the new speed immediately
    if (_isPlaying) _runTimer();
  }

  @override
  Widget build(BuildContext context) {
    String word = _words[_currentIndex];
    int orpIndex = _calculateORP(word);
    
    String prefix = word.substring(0, orpIndex);
    String pivot = word.substring(orpIndex, orpIndex + 1);
    String suffix = word.substring(orpIndex + 1);

    const textStyle = TextStyle(
      fontSize: 48, 
      fontWeight: FontWeight.w400, 
      fontFamily: 'monospace', 
      letterSpacing: 0,
    );

    const double pivotWidth = 40.0; 

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _updateWPM(25),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _updateWPM(-25),
          const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
        },
        child: Focus(
          autofocus: true,
          child: GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Center(
                    child: CustomPaint(
                      size: const Size(double.infinity, 140),
                      painter: RSVPGuidePainter(guideColor: _lightCharcoal),
                    ),
                  ),

                  Center(
                    child: SizedBox(
                      width: 600, 
                      height: 100,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: pivotWidth,
                            child: Center(
                              child: Text(pivot, style: textStyle.copyWith(color: _softRed)),
                            ),
                          ),
                          Positioned(
                            right: (600 / 2) + (pivotWidth / 2),
                            child: Text(
                              prefix, 
                              style: textStyle.copyWith(color: _cream),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Positioned(
                            left: (600 / 2) + (pivotWidth / 2),
                            child: Text(
                              suffix, 
                              style: textStyle.copyWith(color: _cream),
                              textAlign: TextAlign.left,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Positioned(
                    bottom: 40,
                    right: 40,
                    child: Text('$_wpm wpm', style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 18)),
                  ),

                  Positioned(
                    bottom: 40,
                    left: 40,
                    child: AnimatedOpacity(
                      opacity: _showRestart ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 500),
                      child: IgnorePointer(
                        ignoring: !_showRestart,
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _isHoveringRestart = true),
                          onExit: (_) => setState(() => _isHoveringRestart = false),
                          child: GestureDetector(
                            onTap: () => setState(() { _currentIndex = 0; _showRestart = false; }),
                            child: AnimatedRotation(
                              turns: _isHoveringRestart ? 1 : 0,
                              duration: const Duration(milliseconds: 600),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: _lightCharcoal, shape: BoxShape.circle),
                                child: Icon(Icons.refresh, color: _cream, size: 28),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RSVPGuidePainter extends CustomPainter {
  final Color guideColor;
  RSVPGuidePainter({required this.guideColor});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = guideColor..strokeWidth = 2.0..style = PaintingStyle.stroke;
    double centerX = size.width / 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, 20), paint);
    canvas.drawLine(Offset(centerX, size.height), Offset(centerX, size.height - 20), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}