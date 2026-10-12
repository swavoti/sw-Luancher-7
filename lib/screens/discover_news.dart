import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/screens/news_detail_from_disc.dart';

class DiscoverNewsPage extends StatefulWidget {
  const DiscoverNewsPage({super.key});

  @override
  State<DiscoverNewsPage> createState() => _DiscoverNewsPageState();
}

class _DiscoverNewsPageState extends State<DiscoverNewsPage> {
  static const String _baseUrl = 'https://saurav.tech/NewsAPI/top-headlines/category';
  static const List<String> _categories = [
    'general',
    'technology',
    'business',
    'entertainment',
    'sports',
    'health',
    'science',
  ];

  String _selectedCategory = 'general';
  List<NewsArticle> _articles = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCachedNewsAndFetch();
  }

  Future<void> _loadCachedNewsAndFetch() async {
    // 1. Instant load from local cache if available
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_news_$_selectedCategory');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson) as List<dynamic>;
        final cachedArticles = decoded
            .map((item) => NewsArticle.fromJson(item as Map<String, dynamic>))
            .where((a) => a.title.isNotEmpty && a.title != '[Removed]')
            .toList();
        if (cachedArticles.isNotEmpty && mounted) {
          setState(() {
            _articles = cachedArticles;
            _isLoading = false;
          });
        }
      }
    } catch (_) {}

    // 2. Fetch fresh articles from SauravKanchan NewsAPI
    await _fetchNews();
  }

  Future<void> _fetchNews() async {
    if (!mounted) return;
    if (_articles.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final url = Uri.parse('$_baseUrl/$_selectedCategory/us.json');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawArticles = data['articles'] as List<dynamic>? ?? [];
        final parsed = rawArticles
            .map((item) => NewsArticle.fromJson(item as Map<String, dynamic>))
            .where((a) => a.title.isNotEmpty && a.title != '[Removed]')
            .toList();

        if (mounted) {
          setState(() {
            _articles = parsed;
            _isLoading = false;
            _errorMessage = null;
          });
        }

        // Cache in background
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'cached_news_$_selectedCategory',
            jsonEncode(rawArticles),
          );
        } catch (_) {}
      } else {
        if (_articles.isEmpty && mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Could not load news feed (${response.statusCode})';
          });
        }
      }
    } catch (e) {
      if (_articles.isEmpty && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Network error. Please check your connection.';
        });
      }
    }
  }

  void _onCategorySelected(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
      _articles = [];
      _isLoading = true;
      _errorMessage = null;
    });
    _loadCachedNewsAndFetch();
  }

  String _formatTimeAgo(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) {
        return '${diff.inMinutes.clamp(1, 59)}m ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h ago';
      } else {
        return '${diff.inDays}d ago';
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200 || velocity > 200) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Discover News',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Feed',
              onPressed: _fetchNews,
            ),
          ],
        ),
        body: Column(
          children: [
            // Category selector tabs
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _selectedCategory;
                  return FilterChip(
                    label: Text(
                      cat[0].toUpperCase() + cat.substring(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? cs.onPrimary : cs.onSurface,
                      ),
                    ),
                    selected: isSelected,
                    showCheckmark: false,
                    backgroundColor: cs.surfaceContainerHighest,
                    selectedColor: cs.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onSelected: (_) => _onCategorySelected(cat),
                  );
                },
              ),
            ),
            const Divider(height: 1),

            // News feed content
            Expanded(
              child: _isLoading && _articles.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null && _articles.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.newspaper_outlined,
                                  size: 56,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Feed Offline',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                FilledButton.tonalIcon(
                                  onPressed: _fetchNews,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchNews,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: _articles.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final article = _articles[index];
                              final timeAgo = _formatTimeAgo(article.publishedAt);

                              return InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => NewsDetailFromDiscPage(
                                        article: article,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Small rounded image
                                      if (article.urlToImage != null &&
                                          article.urlToImage!.isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            article.urlToImage!,
                                            width: 80,
                                            height: 80,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 80,
                                              height: 80,
                                              decoration: BoxDecoration(
                                                color: cs.surfaceContainerHigh,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                Icons.image_outlined,
                                                color: cs.onSurfaceVariant,
                                                size: 28,
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.newspaper_outlined,
                                            color: cs.onSurfaceVariant,
                                            size: 28,
                                          ),
                                        ),
                                      const SizedBox(width: 12),

                                      // Headline & Meta details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              article.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: cs.onSurface,
                                                height: 1.25,
                                              ),
                                            ),
                                            if (article.description != null &&
                                                article.description!.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                article.description!,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: cs.onSurfaceVariant,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    article.sourceName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: cs.primary,
                                                    ),
                                                  ),
                                                ),
                                                if (timeAgo.isNotEmpty) ...[
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '• $timeAgo',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
