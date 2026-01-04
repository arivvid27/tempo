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
  bool _showSentenceContext = false; 

  final Color _cream = const Color(0xFFF5F5DC);
  final Color _softRed = const Color(0xFFE57373);
  final Color _lightCharcoal = const Color(0xFF2C2C2C);
  final Color _lighterCharcoal = const Color(0xFF3A3A3A);

  // Constants for pixel-perfect alignment
  static const double _fontSize = 48.0;
  static const double _letterSpacing = 4.0;
  static const String _fontFamily = 'monospace';
  static const double _pivotSpacing = 8.0; // Spacing on both sides of the red pivot letter

  int _calculateORP(String word) {
    int length = word.length;
    if (length == 1) return 0;
    if (length <= 3) return 1;
    return (length * 0.35).floor();
  }

  void _runTimer() {
    _timer?.cancel();
    int baseMs = (60000 / _wpm).round();
    String currentWord = _words[_currentIndex];
    bool isEndOfSentence = currentWord.endsWith('.') || currentWord.endsWith('?') || currentWord.endsWith('!');
    int duration = isEndOfSentence ? (baseMs * 2) : baseMs;

    _timer = Timer(Duration(milliseconds: duration), () {
      if (!mounted) return;
      setState(() {
        if (_currentIndex < _words.length - 1) {
          _currentIndex++;
          _runTimer();
        } else {
          _isPlaying = false;
          _showRestart = true;
        }
      });
    });
  }

  void _togglePlayback() {
    if (_showRestart) return;
    if (_isPlaying) { _timer?.cancel(); } else { _runTimer(); }
    setState(() => _isPlaying = !_isPlaying);
  }

  void _updateWPM(int delta) {
    setState(() => _wpm = (_wpm + delta).clamp(30, 900));
    if (_isPlaying) _runTimer();
  }

  Widget _buildMovingSentence(double screenWidth) {
    const textStyle = TextStyle(
      fontSize: _fontSize,
      fontFamily: _fontFamily,
      letterSpacing: _letterSpacing,
    );

    // Measure the actual width of the word spacing (3 spaces)
    final spacePainter = TextPainter(
      text: const TextSpan(text: '  ', style: textStyle),
      textDirection: TextDirection.ltr,
    );
    spacePainter.layout();
    final wordSpacing = spacePainter.width;

    // Calculate the actual width before the pivot character
    double widthBeforePivot = 0;
    
    // Add width of all words before the current word
    for (int i = 0; i < _currentIndex; i++) {
      final wordPainter = TextPainter(
        text: TextSpan(text: _words[i], style: textStyle),
        textDirection: TextDirection.ltr,
      );
      wordPainter.layout();
      widthBeforePivot += wordPainter.width;
      
      // Add spacing after word (except after the last word before current)
      if (i < _currentIndex - 1) {
        widthBeforePivot += wordSpacing;
      }
    }
    
    // Add spacing before current word if there are words before it
    if (_currentIndex > 0) {
      widthBeforePivot += wordSpacing;
    }
    
    // Add width of the prefix (characters before the pivot) of the current word
    String currentWord = _words[_currentIndex];
    int orpIndex = _calculateORP(currentWord);
    String prefix = currentWord.substring(0, orpIndex);
    String pivot = currentWord.substring(orpIndex, orpIndex + 1);
    
    if (prefix.isNotEmpty) {
      final prefixPainter = TextPainter(
        text: TextSpan(text: prefix, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      prefixPainter.layout();
      widthBeforePivot += prefixPainter.width;
    }
    
    // Add spacing before the pivot
    widthBeforePivot += _pivotSpacing;
    
    // Measure the pivot character width to center it perfectly
    final pivotPainter = TextPainter(
      text: TextSpan(text: pivot, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    pivotPainter.layout();
    double pivotWidth = pivotPainter.width;

    // Center the pivot character: screen center - width before pivot - half of pivot width
    double screenCenter = screenWidth / 2;
    double xOffset = screenCenter - widthBeforePivot - (pivotWidth / 2);

    return Transform(
      transform: Matrix4.translationValues(xOffset, 0, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_words.length, (index) {
          String word = _words[index];
          int orp = _calculateORP(word);
          
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildWordSpans(word, orp, index == _currentIndex),
              if (index < _words.length - 1) 
                SizedBox(width: wordSpacing),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildWordSpans(String word, int orp, bool isActive) {
    const style = TextStyle(fontSize: _fontSize, fontFamily: _fontFamily, letterSpacing: _letterSpacing);
    
    if (!isActive) {
      return Text(word, style: style.copyWith(color: _lighterCharcoal));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (orp > 0)
          Text(word.substring(0, orp), style: style.copyWith(color: _cream)),
        SizedBox(width: _pivotSpacing),
        Text(word.substring(orp, orp + 1), style: style.copyWith(color: _softRed)),
        SizedBox(width: _pivotSpacing),
        if (orp < word.length - 1)
          Text(word.substring(orp + 1), style: style.copyWith(color: _cream)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

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
                  // 1. Center Guides
                  Center(
                    child: CustomPaint(
                      size: const Size(double.infinity, 140),
                      painter: RSVPGuidePainter(guideColor: _lightCharcoal),
                    ),
                  ),

                  // 2. The Moving Tape
                  Center(
                    child: SingleChildScrollView( // Prevents overflow if zoomed
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: _showSentenceContext 
                        ? _buildMovingSentence(screenWidth)
                        : _buildStaticRSVP(),
                    ),
                  ),

                  // 3. UI Controls
                  Positioned(bottom: 40, right: 40, child: _buildControls()),
                  _buildRestartButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticRSVP() {
    String word = _words[_currentIndex];
    int orp = _calculateORP(word);
    
    // Measure the pivot character to center it perfectly
    const textStyle = TextStyle(fontSize: _fontSize, fontFamily: _fontFamily, letterSpacing: _letterSpacing);
    final pivotPainter = TextPainter(
      text: TextSpan(text: word.substring(orp, orp + 1), style: textStyle),
      textDirection: TextDirection.ltr,
    );
    pivotPainter.layout();
    double pivotWidth = pivotPainter.width;

    return SizedBox(
      width: 600,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pivot character centered with spacing
          SizedBox(
            width: pivotWidth + (_pivotSpacing * 2),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: _pivotSpacing),
                  Text(word.substring(orp, orp + 1), style: textStyle.copyWith(color: _softRed)),
                  SizedBox(width: _pivotSpacing),
                ],
              ),
            ),
          ),
          // Prefix positioned to the left
          if (orp > 0)
            Positioned(
              right: 300 + (pivotWidth / 2) + _pivotSpacing,
              child: Text(
                word.substring(0, orp), 
                style: textStyle.copyWith(color: _cream), 
                textAlign: TextAlign.right,
              ),
            ),
          // Suffix positioned to the right
          if (orp < word.length - 1)
            Positioned(
              left: 300 + (pivotWidth / 2) + _pivotSpacing,
              child: Text(
                word.substring(orp + 1), 
                style: textStyle.copyWith(color: _cream), 
                textAlign: TextAlign.left,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showSentenceContext = !_showSentenceContext),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Context', style: TextStyle(color: _lighterCharcoal, fontSize: 12, fontStyle: FontStyle.italic)),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38, height: 20,
                decoration: BoxDecoration(
                  color: _showSentenceContext ? _softRed : _lightCharcoal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: _showSentenceContext ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 14, height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(color: _cream, shape: BoxShape.circle),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('$_wpm wpm', style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 18)),
      ],
    );
  }

  Widget _buildRestartButton() {
    return Positioned(
      bottom: 40, left: 40,
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