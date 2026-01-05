import 'dart:async';
import 'dart:convert';
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
  final List<String> summaries;
  final String? coverUrl;
  final String? epubUrl;

  Book({
    required this.id, required this.title, required this.authors,
    required this.subjects, required this.summaries,
    this.coverUrl, this.epubUrl
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    final formats = json['formats'] as Map<String, dynamic>? ?? {};
    List<String> getList(String k) => (json[k] as List? ?? []).map((e) => e.toString()).toList();
    
    return Book(
      id: json['id'],
      title: json['title'] ?? 'Untitled',
      authors: (json['authors'] as List? ?? []).map((a) => a['name'].toString()).toList(),
      subjects: getList('subjects'),
      summaries: getList('summaries'),
      coverUrl: formats['image/jpeg'],
      epubUrl: formats['application/epub+zip'],
    );
  }
}

class ParsedChapter {
  final String title;
  final List<String> words;
  final List<String> sentences;
  final List<int> wordToSentenceMap;
  ParsedChapter(this.title, this.words, this.sentences, this.wordToSentenceMap);
}

class ParsedBookData {
  final List<ParsedChapter> chapters;
  ParsedBookData(this.chapters);
}

class EpubProcessor {
  static Future<ParsedBookData?> process(Uint8List bytes) async {
    try {
      epub.EpubBook epubBook = await epub.EpubReader.readBook(bytes);
      List<ParsedChapter> chapters = [];

      if (epubBook.Chapters != null) {
        for (var ch in epubBook.Chapters!) {
          String rawHtml = _extractHtmlRecursively(ch);
          var document = parse(rawHtml);
          String text = parse(document.body?.text).documentElement?.text ?? "";
          text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

          if (text.isEmpty) continue;

          final RegExp sentenceRegex = RegExp(r'[^.!?]+[.!?]+');
          List<String> sentences = sentenceRegex.allMatches(text)
              .map((m) => m.group(0)!.trim())
              .toList();
          if (sentences.isEmpty) sentences = [text];

          List<String> words = [];
          List<int> wordMap = [];
          for (int i = 0; i < sentences.length; i++) {
            List<String> sWords = sentences[i].split(' ').where((w) => w.isNotEmpty).toList();
            for (var w in sWords) {
              words.add(w);
              wordMap.add(i);
            }
          }
          chapters.add(ParsedChapter(ch.Title ?? "Untitled", words, sentences, wordMap));
        }
      }
      return ParsedBookData(chapters);
    } catch (e) {
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
    _fetch();
  }

  _fetch() async {
    final res = await http.get(Uri.parse('https://gutendex.com/books?languages=en&sort=popular'));
    if (res.statusCode == 200) {
      setState(() {
        _books = (json.decode(res.body)['results'] as List).map((j) => Book.fromJson(j)).toList();
        _loading = false;
      });
    }
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
              crossAxisCount: 3, childAspectRatio: 0.7, crossAxisSpacing: 24, mainAxisSpacing: 24,
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
    final res = await http.get(Uri.parse("https://api.allorigins.win/raw?url=${Uri.encodeComponent(widget.book.epubUrl!)}"));
    final data = await EpubProcessor.process(res.bodyBytes);
    if (data != null && mounted) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(bookData: data)));
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
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context), padding: EdgeInsets.zero),
                      const SizedBox(height: 20),
                      Text(widget.book.title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFE57373))),
                      const SizedBox(height: 10),
                      Text("By ${widget.book.authors.join(", ")}", style: const TextStyle(fontSize: 16, color: Colors.white70)),
                      const SizedBox(height: 30),
                      Expanded(child: SingleChildScrollView(child: Text(widget.book.summaries.firstOrNull ?? "No summary available.", style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.grey)))),
                      const SizedBox(height: 20),
                      Wrap(spacing: 8, children: widget.book.subjects.take(3).map((s) => Chip(label: Text(s), backgroundColor: const Color(0xFF2C2C2C), labelStyle: const TextStyle(fontSize: 10))).toList())
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  color: const Color(0xFF222222), padding: const EdgeInsets.all(40),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Expanded(child: Hero(tag: 'cover_${widget.book.id}', child: ClipRRect(borderRadius: BorderRadius.circular(4), child: widget.book.coverUrl != null ? Image.network(widget.book.coverUrl!, fit: BoxFit.contain) : const Icon(Icons.book, size: 100)))),
                    const SizedBox(height: 40),
                    SizedBox(width: double.infinity, height: 50, child: _downloading ? const Center(child: CircularProgressIndicator(color: Color(0xFFE57373))) : ElevatedButton(onPressed: _startReading, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE57373), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))), child: const Text("READ NOW", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2))))
                  ]),
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
// 4. RSVP READER
// -----------------------------------------------------------------------------

class ReaderPage extends StatefulWidget {
  final ParsedBookData bookData;
  const ReaderPage({super.key, required this.bookData});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  int _chapterIndex = 0;
  int _currentIndex = 0;
  Timer? _timer;
  bool _isPlaying = false;
  bool _isHoveringRestart = false;
  int _wpm = 300;
  bool _showContextMode = false;

  final Color _cream = const Color(0xFFF5F5DC);
  final Color _softRed = const Color(0xFFE57373);
  final Color _lightCharcoal = const Color(0xFF2C2C2C);
  final Color _lighterCharcoal = const Color(0xFF3A3A3A);

  ParsedChapter get _currentChapter => widget.bookData.chapters[_chapterIndex];

  void _runTimer() {
    _timer?.cancel();
    int baseMs = (60000 / _wpm).round();
    String currentWord = _currentChapter.words[_currentIndex];
    bool isPause = currentWord.endsWith('.') || currentWord.endsWith('?') || currentWord.endsWith('!');
    int duration = isPause ? (baseMs * 2.5).round() : baseMs;

    _timer = Timer(Duration(milliseconds: duration), () {
      if (!mounted) return;
      setState(() {
        if (_currentIndex < _currentChapter.words.length - 1) {
          _currentIndex++;
          _runTimer();
        } else {
          _isPlaying = false;
        }
      });
    });
  }

  void _togglePlayback() {
    if (_isPlaying) { _timer?.cancel(); } else { _runTimer(); }
    setState(() => _isPlaying = !_isPlaying);
  }

  void _changeChapter(int delta) {
    int newIdx = _chapterIndex + delta;
    if (newIdx >= 0 && newIdx < widget.bookData.chapters.length) {
      setState(() {
        _chapterIndex = newIdx;
        _currentIndex = 0;
        _isPlaying = false;
        _timer?.cancel();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(() => _wpm = (_wpm + 25).clamp(30, 900)),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(() => _wpm = (_wpm - 25).clamp(30, 900)),
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        },
        child: Focus(
          autofocus: true,
          child: GestureDetector(
            onTap: _togglePlayback,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Center(child: CustomPaint(size: const Size(double.infinity, 140), painter: RSVPGuidePainter(guideColor: _lightCharcoal))),
                Center(child: _showContextMode ? _buildVerticalContext() : _buildStaticRSVP()),
                Positioned(bottom: 40, right: 40, child: _buildRightControls()),
                Positioned(bottom: 40, left: 40, child: _buildNavigationCluster()),
                Positioned(top: 40, left: 40, child: IconButton(icon: Icon(Icons.arrow_back, color: _lighterCharcoal), onPressed: () => Navigator.pop(context))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalContext() {
    int sIdx = _currentChapter.wordToSentenceMap[_currentIndex];
    String prev = (sIdx > 0) ? _currentChapter.sentences[sIdx - 1] : "";
    String next = (sIdx < _currentChapter.sentences.length - 1) ? _currentChapter.sentences[sIdx + 1] : "";

    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(prev, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: _lighterCharcoal.withOpacity(0.5))),
      const SizedBox(height: 40),
      _buildStaticRSVP(),
      const SizedBox(height: 40),
      Text(next, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: _lighterCharcoal.withOpacity(0.5))),
    ]);
  }

  Widget _buildStaticRSVP() {
    String word = _currentChapter.words[_currentIndex];
    int orp = word.length == 1 ? 0 : (word.length <= 3 ? 1 : (word.length * 0.35).floor());
    const style = TextStyle(fontSize: 48, letterSpacing: 4, fontWeight: FontWeight.bold);

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 300, child: Text(word.substring(0, orp), textAlign: TextAlign.right, style: style.copyWith(color: _cream))),
      const SizedBox(width: 8),
      Text(word.substring(orp, orp + 1), style: style.copyWith(color: _softRed)),
      const SizedBox(width: 8),
      SizedBox(width: 300, child: Text(orp < word.length - 1 ? word.substring(orp + 1) : "", textAlign: TextAlign.left, style: style.copyWith(color: _cream))),
    ]);
  }

  Widget _buildNavigationCluster() {
    return Row(
      children: [
        // Prev Chapter
        if (_chapterIndex > 0)
          IconButton(icon: Icon(Icons.arrow_back_ios_new, color: _lighterCharcoal, size: 20), onPressed: () => _changeChapter(-1)),
        const SizedBox(width: 10),
        // Restart Arrow
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveringRestart = true),
          onExit: (_) => setState(() => _isHoveringRestart = false),
          child: GestureDetector(
            onTap: () => setState(() { _currentIndex = 0; _isPlaying = false; _timer?.cancel(); }),
            child: AnimatedRotation(
              turns: _isHoveringRestart ? 1 : 0, duration: const Duration(milliseconds: 500),
              child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _lightCharcoal, shape: BoxShape.circle), child: Icon(Icons.refresh, color: _cream, size: 24)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Next Chapter
        if (_chapterIndex < widget.bookData.chapters.length - 1)
          IconButton(icon: Icon(Icons.arrow_forward_ios, color: _lighterCharcoal, size: 20), onPressed: () => _changeChapter(1)),
      ],
    );
  }

  Widget _buildRightControls() {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      GestureDetector(
        onTap: () => setState(() => _showContextMode = !_showContextMode),
        child: Row(children: [
          Text('Context', style: TextStyle(color: _lighterCharcoal, fontSize: 12)),
          const SizedBox(width: 8),
          Container(width: 38, height: 20, decoration: BoxDecoration(color: _showContextMode ? _softRed : _lightCharcoal, borderRadius: BorderRadius.circular(10)), child: AnimatedAlign(alignment: _showContextMode ? Alignment.centerRight : Alignment.centerLeft, duration: const Duration(milliseconds: 200), child: Container(width: 14, height: 14, margin: const EdgeInsets.all(3), decoration: BoxDecoration(color: _cream, shape: BoxShape.circle))))
        ]),
      ),
      const SizedBox(height: 8),
      Text('$_wpm wpm', style: const TextStyle(color: Colors.grey, fontSize: 18)),
      Text("${_currentIndex + 1}/${_currentChapter.words.length}", style: const TextStyle(color: Colors.grey, fontSize: 10)),
    ]);
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