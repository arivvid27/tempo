import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// -----------------------------------------------------------------------------
// 1. APP ROOT & INITIALIZATION
// -----------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: .env file not found. Secrets will not load.");
  }
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
      home: const HomePage(),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. DATA MODELS & TEXT PROCESSING
// -----------------------------------------------------------------------------
class Book {
  final int id;
  final String title;
  final List<String> authors;
  final String? coverUrl;
  final String? textUrl;

  Book({required this.id, required this.title, required this.authors, this.coverUrl, this.textUrl});

  factory Book.fromJson(Map<String, dynamic> json) {
    final formats = json['formats'] as Map<String, dynamic>? ?? {};
    return Book(
      id: json['id'],
      title: json['title'] ?? 'Untitled',
      authors: (json['authors'] as List).map((a) => a['name'].toString()).toList(),
      coverUrl: formats['image/jpeg'],
      textUrl: formats['text/plain; charset=utf-8'] ?? formats['text/plain'],
    );
  }
}

class BookProcessor {
  static Map<String, List<String>> splitIntoChapters(String rawText) {
    Map<String, List<String>> chapters = {};
    
    // Remove Gutenberg Header
    int startIndex = rawText.indexOf('*** START OF');
    if (startIndex != -1) {
      int actualStart = rawText.indexOf('\n', startIndex) + 1;
      rawText = rawText.substring(actualStart);
    }

    // RegEx for "Chapter 1", "Letter 1", "CHAPTER I", etc.
    final RegExp chapterRegex = RegExp(r'^(Chapter|Letter|CHAPTER)\s+\d+', multiLine: true);
    Iterable<RegExpMatch> matches = chapterRegex.allMatches(rawText);
    
    if (matches.isEmpty) {
      chapters["Full Text"] = _processLines(rawText);
      return chapters;
    }

    int lastMatchEnd = 0;
    String currentTitle = "Introduction";

    for (var match in matches) {
      String content = rawText.substring(lastMatchEnd, match.start).trim();
      if (content.isNotEmpty) chapters[currentTitle] = _processLines(content);
      currentTitle = match.group(0) ?? "Unknown Section";
      lastMatchEnd = match.start; 
    }
    chapters[currentTitle] = _processLines(rawText.substring(lastMatchEnd));

    return chapters;
  }

  static List<String> _processLines(String text) {
    return text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }
}

// -----------------------------------------------------------------------------
// 3. SERVICES
// -----------------------------------------------------------------------------
class GutenbergService {
  static Future<List<Book>> fetchBooks() async {
    try {
      final res = await http.get(Uri.parse('https://gutendex.com/books?languages=en'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return (data['results'] as List).map((j) => Book.fromJson(j)).toList();
      }
    } catch (e) { debugPrint("Catalog Error: $e"); }
    return [];
  }

  static Future<String?> fetchBookContent(String url) async {
    try {
      // PROXY to bypass CORS blocks in Web
      final proxyUrl = "https://cors-anywhere.herokuapp.com/${url.replaceFirst('http://', 'https://')}";
      final res = await http.get(Uri.parse(proxyUrl), headers: {'X-Requested-With': 'XMLHttpRequest'});
      if (res.statusCode == 200) return res.body;
    } catch (e) { debugPrint("Fetch Error: $e"); }
    return null;
  }
}

class GeminiService {
  static Future<String> generateSummary(String title, String author) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) return "API Key missing.";
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      final prompt = 'Summarize "$title" by $author in two short, punchy paragraphs.';
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "Summary unavailable.";
    } catch (e) { return "Summary failed to load."; }
  }
}

// -----------------------------------------------------------------------------
// 4. UI PAGES (HomePage, Catalog, Detail, Reader)
// -----------------------------------------------------------------------------

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('T E M P O', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: 8, color: Color(0xFFE57373))),
            const SizedBox(height: 60),
            OutlinedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogPage())),
              child: const Text('ENTER LIBRARY', style: TextStyle(color: Color(0xFFE57373))),
            ),
          ],
        ),
      ),
    );
  }
}

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
    GutenbergService.fetchBooks().then((books) => setState(() { _books = books; _loading = false; }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog'), backgroundColor: Colors.transparent),
      body: _loading 
        ? const Center(child: CircularProgressIndicator()) 
        : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.7, crossAxisSpacing: 16, mainAxisSpacing: 16),
            itemCount: _books.length,
            itemBuilder: (context, i) => _buildBookCard(_books[i]),
          ),
    );
  }

  Widget _buildBookCard(Book book) {
    return GestureDetector(
      onTap: () => showDialog(context: context, builder: (_) => BookDetailModal(book: book)),
      child: Column(
        children: [
          Expanded(child: book.coverUrl != null 
            ? Image.network(book.coverUrl!, errorBuilder: (_,__,___) => const Icon(Icons.book, size: 50)) 
            : const Icon(Icons.book)),
          Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class BookDetailModal extends StatefulWidget {
  final Book book;
  const BookDetailModal({super.key, required this.book});
  @override
  State<BookDetailModal> createState() => _BookDetailModalState();
}

class _BookDetailModalState extends State<BookDetailModal> {
  String _summary = "Summarizing with Gemini...";
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    GeminiService.generateSummary(widget.book.title, widget.book.authors.first).then((s) => setState(() => _summary = s));
  }

  void _startReading() async {
    if (widget.book.textUrl == null) return;
    setState(() => _isReading = true);
    final raw = await GutenbergService.fetchBookContent(widget.book.textUrl!);
    if (raw != null && mounted) {
      final chapters = BookProcessor.splitIntoChapters(raw);
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(
        chapterTitle: chapters.keys.first, 
        sentences: chapters.values.first,
      )));
    }
    setState(() => _isReading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(widget.book.title),
      content: SingleChildScrollView(child: Text(_summary, style: const TextStyle(color: Colors.grey))),
      actions: [
        if (_isReading) const CircularProgressIndicator() 
        else TextButton(onPressed: _startReading, child: const Text("READ NOW", style: TextStyle(color: Color(0xFFE57373)))),
      ],
    );
  }
}

class ReaderPage extends StatefulWidget {
  final String chapterTitle;
  final List<String> sentences;
  const ReaderPage({super.key, required this.chapterTitle, required this.sentences});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  int _wpm = 300;

  void _toggle() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _timer = Timer.periodic(Duration(milliseconds: (60000 / _wpm).round()), (t) {
        if (_currentIndex < widget.sentences.length - 1) {
          setState(() => _currentIndex++);
        } else {
          t.cancel();
          setState(() => _isPlaying = false);
        }
      });
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chapterTitle), backgroundColor: Colors.transparent),
      body: GestureDetector(
        onTap: _toggle,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Clean Text: No effects, No warp
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  widget.sentences[_currentIndex],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, height: 1.4, color: Color(0xFFF5F5DC)),
                ),
              ),
              const SizedBox(height: 100),
              Text('${_currentIndex + 1} / ${widget.sentences.length}', style: const TextStyle(color: Colors.grey)),
              if (!_isPlaying) const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text("TAP TO PLAY", style: TextStyle(color: Color(0xFFE57373), letterSpacing: 2)),
              )
            ],
          ),
        ),
      ),
    );
  }
}