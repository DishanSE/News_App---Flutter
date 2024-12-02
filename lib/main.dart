// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

// Constants
const String API_KEY = '8b08e4b1263f4baeabf24f5cba1403bf';
const String BASE_URL = 'https://newsapi.org/v2';

// Models
class Article {
  final String title;
  final String description;
  final String url;
  final String imageUrl;
  final String publishedAt;
  final String source;

  Article({
    required this.title,
    required this.description,
    required this.url,
    required this.imageUrl,
    required this.publishedAt,
    required this.source,
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    return Article(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      url: json['url'] ?? '',
      imageUrl: json['urlToImage'] ?? '',
      publishedAt: json['publishedAt'] ?? '',
      source: json['source']['name'] ?? '',
    );
  }
}

// Repository
class NewsRepository {
  final Dio dio;

  NewsRepository(this.dio) {
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 10);
    dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException e, ErrorInterceptorHandler handler) {
        print('Dio Error: ${e.message}');
        handler.next(e);
      },
    ));
  }

  Future<List<Article>> getTopHeadlines({String? category}) async {
    final response = await dio.get(
      '$BASE_URL/top-headlines',
      queryParameters: {
        'apiKey': API_KEY,
        'country': 'us',
        if (category != null) 'category': category,
      },
    );
    return (response.data['articles'] as List)
        .map((article) => Article.fromJson(article))
        .toList();
  }

  Future<List<Article>> searchNews(String query) async {
    final response = await dio.get(
      '$BASE_URL/everything',
      queryParameters: {
        'apiKey': API_KEY,
        'q': query,
      },
    );
    return (response.data['articles'] as List)
        .map((article) => Article.fromJson(article))
        .toList();
  }
}

// Cubit
class NewsCubit extends Cubit<NewsState> {
  final NewsRepository repository;

  NewsCubit(this.repository) : super(NewsInitial());

  Future<void> getTopHeadlines({String? category}) async {
    try {
      emit(NewsLoading());
      final articles = await repository.getTopHeadlines(category: category);
      emit(NewsLoaded(articles));
    } catch (e) {
      emit(NewsError('Failed to fetch news'));
    }
  }

  Future<void> searchNews(String query) async {
    try {
      emit(NewsLoading());
      final articles = await repository.searchNews(query);
      emit(NewsLoaded(articles));
    } catch (e) {
      emit(NewsError('Failed to search news'));
    }
  }
}

// States
abstract class NewsState {}

class NewsInitial extends NewsState {}

class NewsLoading extends NewsState {}

class NewsLoaded extends NewsState {
  final List<Article> articles;
  NewsLoaded(this.articles);
}

class NewsError extends NewsState {
  final String message;
  NewsError(this.message);
}

// Bookmark manager
class BookmarkManager {
  static final BookmarkManager _instance = BookmarkManager._internal();
  factory BookmarkManager() => _instance;
  BookmarkManager._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'bookmarks.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE bookmarks(url TEXT PRIMARY KEY, title TEXT, description TEXT, imageUrl TEXT, publishedAt TEXT, source TEXT)',
        );
      },
    );
  }

  Future<void> addBookmark(Article article) async {
    final db = await database;
    await db.insert(
      'bookmarks',
      {
        'url': article.url,
        'title': article.title,
        'description': article.description,
        'imageUrl': article.imageUrl,
        'publishedAt': article.publishedAt,
        'source': article.source,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeBookmark(String url) async {
    final db = await database;
    await db.delete(
      'bookmarks',
      where: 'url = ?',
      whereArgs: [url],
    );
  }

  Future<bool> isBookmarked(String url) async {
    final db = await database;
    final result = await db.query(
      'bookmarks',
      where: 'url = ?',
      whereArgs: [url],
    );
    return result.isNotEmpty;
  }

  Future<List<Article>> getBookmarks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('bookmarks');
    return maps
        .map((map) => Article(
              title: map['title'],
              description: map['description'],
              url: map['url'],
              imageUrl: map['imageUrl'],
              publishedAt: map['publishedAt'],
              source: map['source'],
            ))
        .toList();
  }
}

// Screens
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final categories = [
    'business',
    'entertainment',
    'health',
    'science',
    'sports',
    'technology'
  ];
  String selectedCategory = 'business';
  int _selectedIndex = 0;
  final BookmarkManager _bookmarkManager = BookmarkManager();
  List<Article> _bookmarkedArticles = [];

  @override
  void initState() {
    super.initState();
    _fetchTopHeadlines();
    _fetchBookmarks();
  }

  void _fetchTopHeadlines() async {
    final newsRepository = NewsRepository(Dio());
    final articles =
        await newsRepository.getTopHeadlines(category: selectedCategory);
    setState(() {});
  }

  void _fetchBookmarks() async {
    final bookmarks = await _bookmarkManager.getBookmarks();
    setState(() {
      _bookmarkedArticles = bookmarks;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'News' : 'Bookmarks'),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SearchScreen(),
                ),
              ),
            ),
        ],
      ),
      body: _selectedIndex == 0 ? _buildNewsPage() : _buildBookmarksPage(),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.lens_outlined),
            label: 'News',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_outline),
            label: 'Bookmarks',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          if (index == 1) {
            _fetchBookmarks();
          }
        },
      ),
    );
  }

  Widget _buildNewsPage() {
    return Column(
      children: [
        CategoryList(
          categories: categories,
          selectedCategory: selectedCategory,
          onCategorySelected: (category) {
            setState(() => selectedCategory = category);
            _fetchTopHeadlines();
          },
        ),
        Expanded(
          child: FutureBuilder<List<Article>>(
            future: NewsRepository(Dio())
                .getTopHeadlines(category: selectedCategory),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No news available'));
              }

              return NewsListView(articles: snapshot.data!);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBookmarksPage() {
    if (_bookmarkedArticles.isEmpty) {
      return const Center(child: Text('No bookmarks'));
    }

    return NewsListView(articles: _bookmarkedArticles);
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search news...',
            border: InputBorder.none,
          ),
          onSubmitted: (query) {
            if (query.isNotEmpty) {
              context.read<NewsCubit>().searchNews(query);
            }
          },
        ),
      ),
      body: BlocBuilder<NewsCubit, NewsState>(
        builder: (context, state) {
          if (state is NewsLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is NewsLoaded) {
            return NewsListView(articles: state.articles);
          } else if (state is NewsError) {
            return Center(child: Text(state.message));
          }
          return const Center(child: Text('Search for news'));
        },
      ),
    );
  }
}

class NewsListView extends StatelessWidget {
  final List<Article> articles;

  const NewsListView({super.key, required this.articles});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        return NewsCard(
          article: article,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ArticleDetailScreen(article: article),
            ),
          ),
        );
      },
    );
  }
}

class NewsCard extends StatefulWidget {
  final Article article;
  final VoidCallback onTap;

  const NewsCard({
    super.key,
    required this.article,
    required this.onTap,
  });

  @override
  _NewsCardState createState() => _NewsCardState();
}

class _NewsCardState extends State<NewsCard> {
  final BookmarkManager _bookmarkManager = BookmarkManager();
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkBookmarkStatus();
  }

  Future<void> _checkBookmarkStatus() async {
    final bookmarked = await _bookmarkManager.isBookmarked(widget.article.url);
    setState(() {
      _isBookmarked = bookmarked;
    });
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      await _bookmarkManager.removeBookmark(widget.article.url);
    } else {
      await _bookmarkManager.addBookmark(widget.article);
    }

    setState(() {
      _isBookmarked = !_isBookmarked;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.article.imageUrl.isNotEmpty)
              Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.article.imageUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.white70,
                      child: IconButton(
                        icon: Icon(
                          _isBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color: Colors.blue,
                        ),
                        onPressed: _toggleBookmark,
                      ),
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.article.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.article.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        widget.article.source,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        widget.article.publishedAt.substring(0, 10),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryList extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selectedCategory;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(
                category.toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => onCategorySelected(category),
            ),
          );
        },
      ),
    );
  }
}

class ArticleDetailScreen extends StatefulWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  _ArticleDetailScreenState createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  final BookmarkManager _bookmarkManager = BookmarkManager();
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkBookmarkStatus();
  }

  Future<void> _checkBookmarkStatus() async {
    final bookmarked = await _bookmarkManager.isBookmarked(widget.article.url);
    setState(() {
      _isBookmarked = bookmarked;
    });
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      await _bookmarkManager.removeBookmark(widget.article.url);
    } else {
      await _bookmarkManager.addBookmark(widget.article);
    }

    setState(() {
      _isBookmarked = !_isBookmarked;
    });
  }

  Future<void> _launchURL() async {
    final Uri url = Uri.parse(widget.article.url);
    if (!await launchUrl(url, mode: LaunchMode.inAppWebView)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Article Details'),
        actions: [
          IconButton(
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: Colors.white,
            ),
            onPressed: _toggleBookmark,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.article.imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: widget.article.imageUrl,
                height: 250,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.article.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        widget.article.source,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        widget.article.publishedAt.substring(0, 10),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.article.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _launchURL,
                    child: const Text('Read Full Article'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Main App
class NewsApp extends StatelessWidget {
  const NewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => NewsCubit(GetIt.I<NewsRepository>()),
      child: MaterialApp(
        title: 'News App',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}

void main() {
  final getIt = GetIt.instance;

  // Dependencies
  getIt.registerSingleton<Dio>(Dio());
  getIt.registerSingleton<NewsRepository>(NewsRepository(getIt<Dio>()));

  runApp(const NewsApp());
}
