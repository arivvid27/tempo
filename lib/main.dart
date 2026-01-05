import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:epubx/epubx.dart' as epub;
import 'package:html/parser.dart';

// -----------------------------------------------------------------------------
// 1. APP ENTRY
// -----------------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TempoApp());
}

class TempoApp extends StatelessWidget {
  const TempoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tempo',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        primaryColor: const Color(0xFFE57373),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: const CatalogPage(),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. DATA MODELS & PARSING
// -----------------------------------------------------------------------------
class Book {
  final int id;
  final String title;
  final List<String> authors;
  final List<String> subjects;
  final List<String> bookshelves;
  final List<String> summaries;
  final int downloadCount;
  final String? coverUrl;
  final String? epubUrl;

  Book({
    required this.id, required this.title, required this.authors,
    required this.subjects, required this.bookshelves, required this.summaries,
    required this.downloadCount, this.coverUrl, this.epubUrl
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    final formats = json['formats'] as Map<String, dynamic>? ?? {};
    List<String> getList(String k) => (json[k] as List? ?? []).map((e) => e.toString()).toList();
    
    return Book(
      id: json['id'],
      title: json['title'] ?? 'Untitled',
      authors: (json['authors'] as List? ?? []).map((a) => a['name'].toString()).toList(),
      subjects: getList('subjects'),
      bookshelves: getList('bookshelves'),
      summaries: getList('summaries'),
      downloadCount: json['download_count'] ?? 0,
      coverUrl: formats['image/jpeg'],
      epubUrl: formats['application/epub+zip'],
    );
  }
}

class EpubProcessor {
  /// Returns a tuple: [List<String> allWords, List<String> allSentences, List<int> wordToSentenceMap]
  static Future<ParsedBookData?> process(Uint8List bytes) async {
    try {
      epub.EpubBook epubBook = await epub.EpubReader.readBook(bytes);
      StringBuffer fullTextBuffer = StringBuffer();

      // Extract raw text from all chapters
      if (epubBook.Chapters != null) {
        for (var chapter in epubBook.Chapters!) {
          fullTextBuffer.write(_extractHtmlRecursively(chapter));
          fullTextBuffer.write(" "); // Space between chapters
        }
      }

      // 1. Clean HTML to Text
      String rawText = _parseHtmlToText(fullTextBuffer.toString());

      // 2. Flatten newlines to spaces as requested
      rawText = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (rawText.isEmpty) return null;

      // 3. Split into sentences (simple Regex for punctuation)
      // This regex looks for . ! ? followed by a space or end of string
      final RegExp sentenceRegex = RegExp(r'[^.!?]+[.!?]+');
      List<String> sentences = sentenceRegex.allMatches(rawText)
          .map((m) => m.group(0)!.trim())
          .toList();
      
      // Fallback if regex fails (no punctuation)
      if (sentences.isEmpty && rawText.isNotEmpty) sentences = [rawText];

      List<String> words = [];
      List<int> wordToSentenceIndex = [];

      // 4. Split sentences into words and map them
      for (int i = 0; i < sentences.length; i++) {
        List<String> sWords = sentences[i].split(' ').where((w) => w.isNotEmpty).toList();
        for (var w in sWords) {
          words.add(w);
          wordToSentenceIndex.add(i);
        }
      }

      return ParsedBookData(words, sentences, wordToSentenceIndex);

    } catch (e) {
      debugPrint("Parsing Error: $e");
      return null;
    }
  }

  static String _extractHtmlRecursively(epub.EpubChapter chapter) {
    StringBuffer sb = StringBuffer();
    if (chapter.HtmlContent != null) sb.write(chapter.HtmlContent);
    if (chapter.SubChapters != null) {
      for (var sub in chapter.SubChapters!) sb.write(_extractHtmlRecursively(sub));
    }
    return sb.toString();
  }

  static String _parseHtmlToText(String htmlContent) {
    var document = parse(htmlContent);
    return parse(document.body?.text).documentElement?.text ?? "";
  }
}

class ParsedBookData {
  final List<String> words;
  final List<String> sentences;
  final List<int> wordToSentenceMap;
  ParsedBookData(this.words, this.sentences, this.wordToSentenceMap);
}

class GutenbergService {
  static Future<List<Book>> fetchCatalog() async {
    try {
      final res = await http.get(Uri.parse('https://gutendex.com/books?languages=en&sort=popular'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return (data['results'] as List).map((j) => Book.fromJson(j)).toList();
      }
    } catch (e) { debugPrint("Catalog Error: $e"); }
    return [];
  }

  static Future<Uint8List?> fetchEpubBytes(String url) async {
    try {
      final proxyUrl = "https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}";
      final res = await http.get(Uri.parse(proxyUrl));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (e) { debugPrint("Fetch Error: $e"); }
    return null;
  }
}

// -----------------------------------------------------------------------------
// 3. UI: CATALOG & DETAILS
// -----------------------------------------------------------------------------

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  List<Book> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    GutenbergService.fetchCatalog().then((b) => setState(() { _books = b; _loading = false; }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TEMPO LIBRARY', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFE57373))) 
        : GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // Wide grid
              childAspectRatio: 0.7,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            itemCount: _books.length,
            itemBuilder: (context, i) => _BookCard(book: _books[i]),
          ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        pageBuilder: (ctx, _, __) => BookDetailOverlay(book: book),
        transitionsBuilder: (ctx, anim, __, child) => FadeTransition(opacity: anim, child: child),
      )),
      child: Column(
        children: [
          Expanded(
            child: Hero(
              tag: 'cover_${book.id}',
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  image: book.coverUrl != null 
                    ? DecorationImage(image: NetworkImage(book.coverUrl!), fit: BoxFit.cover)
                    : null,
                  color: Colors.grey[850],
                ),
                child: book.coverUrl == null ? const Center(child: Icon(Icons.book, size: 40)) : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, 
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(book.authors.firstOrNull ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis, 
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}

class BookDetailOverlay extends StatefulWidget {
  final Book book;
  const BookDetailOverlay({super.key, required this.book});

  @override
  State<BookDetailOverlay> createState() => _BookDetailOverlayState();
}

class _BookDetailOverlayState extends State<BookDetailOverlay> {
  bool _downloading = false;

  void _startReading() async {
    if (widget.book.epubUrl == null) return;
    setState(() => _downloading = true);

    final bytes = await GutenbergService.fetchEpubBytes(widget.book.epubUrl!);
    if (bytes != null && mounted) {
      final data = await EpubProcessor.process(bytes);
      if (data != null && mounted) {
        Navigator.pop(context); // Close overlay
        Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(bookData: data)));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not extract text.")));
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download failed.")));
    }
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      body: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              // Left: Info
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close), 
                        onPressed: () => Navigator.pop(context),
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 20),
                      Text(widget.book.title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFE57373))),
                      const SizedBox(height: 10),
                      Text("By ${widget.book.authors.join(", ")}", style: const TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 30),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            widget.book.summaries.firstOrNull ?? "No summary available.",
                            style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        children: widget.book.subjects.take(3).map((s) => Chip(
                          label: Text(s), 
                          backgroundColor: const Color(0xFF2C2C2C),
                          labelStyle: const TextStyle(fontSize: 10),
                        )).toList(),
                      )
                    ],
                  ),
                ),
              ),
              // Right: Cover + Action
              Expanded(
                flex: 4,
                child: Container(
                  color: const Color(0xFF222222),
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Hero(
                          tag: 'cover_${widget.book.id}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: widget.book.coverUrl != null 
                              ? Image.network(widget.book.coverUrl!, fit: BoxFit.contain)
                              : const Icon(Icons.book, size: 100),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: _downloading 
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFFE57373)))
                        : ElevatedButton(
                            onPressed: _startReading,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE57373),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            child: const Text("READ NOW", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                          ),
                      )
                    ],
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

// -----------------------------------------------------------------------------
// 4. RSVP READER (The Merged Implementation)
// -----------------------------------------------------------------------------

class ReaderPage extends StatefulWidget {
  final ParsedBookData bookData;
  const ReaderPage({super.key, required this.bookData});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late List<String> _words;
  late List<String> _sentences;
  late List<int> _wordToSentenceMap;

  int _currentIndex = 0;
  Timer? _timer;
  bool _isPlaying = false;
  bool _showRestart = false;
  bool _isHoveringRestart = false;
  int _wpm = 300;
  bool _showContextMode = false;

  final Color _cream = const Color(0xFFF5F5DC);
  final Color _softRed = const Color(0xFFE57373);
  final Color _lightCharcoal = const Color(0xFF2C2C2C);
  final Color _lighterCharcoal = const Color(0xFF3A3A3A);

  static const double _fontSize = 48.0;
  static const double _letterSpacing = 4.0;
  static const String _fontFamily = 'monospace';
  static const double _pivotSpacing = 8.0;

  @override
  void initState() {
    super.initState();
    _words = widget.bookData.words;
    _sentences = widget.bookData.sentences;
    _wordToSentenceMap = widget.bookData.wordToSentenceMap;
  }

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
    int duration = isEndOfSentence ? (baseMs * 2.5).round() : baseMs; // Slight pause boost

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

  // --- RENDERING LOGIC ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _updateWPM(25),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _updateWPM(-25),
          const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        },
        child: Focus(
          autofocus: true,
          child: GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              color: Colors.transparent,
              child: Stack(
                children: [
                  // 1. Guides
                  Center(
                    child: CustomPaint(
                      size: const Size(double.infinity, 140),
                      painter: RSVPGuidePainter(guideColor: _lightCharcoal),
                    ),
                  ),
                  
                  // 2. The Content (Context or Static)
                  Center(
                    child: _showContextMode 
                      ? _buildVerticalContext() 
                      : _buildStaticRSVP(),
                  ),

                  // 3. UI Controls
                  Positioned(bottom: 40, right: 40, child: _buildControls()),
                  _buildRestartButton(),
                  
                  // 4. Back Button
                  Positioned(
                    top: 40, left: 40,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: _lighterCharcoal), 
                      onPressed: () => Navigator.pop(context)
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

  Widget _buildVerticalContext() {
    // Current sentence index
    int sIdx = _wordToSentenceMap[_currentIndex];
    
    String prevSentence = (sIdx > 0) ? _sentences[sIdx - 1] : "";
    String nextSentence = (sIdx < _sentences.length - 1) ? _sentences[sIdx + 1] : "";

    return SizedBox(
      height: 400, // height to accommodate stack
      width: 800,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous Sentence
          Text(
            prevSentence,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _fontFamily,
              fontSize: 18,
              color: _lighterCharcoal.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 40),
          
          // ACTIVE WORD (The RSVP Element)
          _buildStaticRSVP(),
          
          const SizedBox(height: 40),
          
          // Next Sentence
          Text(
            nextSentence,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _fontFamily,
              fontSize: 18,
              color: _lighterCharcoal.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaticRSVP() {
    String word = _words[_currentIndex];
    int orp = _calculateORP(word);

    const textStyle = TextStyle(fontSize: _fontSize, fontFamily: _fontFamily, letterSpacing: _letterSpacing);
    
    // Measure pivot to center it
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
          // Center Pivot (Red)
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
          // Prefix (Left)
          if (orp > 0)
            Positioned(
              right: 300 + (pivotWidth / 2) + _pivotSpacing,
              child: Text(
                word.substring(0, orp),
                style: textStyle.copyWith(color: _cream),
                textAlign: TextAlign.right,
              ),
            ),
          // Suffix (Right)
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
    // Current progress
    String progress = "${_currentIndex + 1}/${_words.length}";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showContextMode = !_showContextMode),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Context', style: TextStyle(color: _lighterCharcoal, fontSize: 12, fontStyle: FontStyle.italic)),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38, height: 20,
                decoration: BoxDecoration(
                  color: _showContextMode ? _softRed : _lightCharcoal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: _showContextMode ? Alignment.centerRight : Alignment.centerLeft,
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
        Text(progress, style: const TextStyle(color: Colors.grey, fontSize: 10)),
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
    // Top and bottom lines
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
    // Center notch markers
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, 20), paint);
    canvas.drawLine(Offset(centerX, size.height), Offset(centerX, size.height - 20), paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}