import 'dart:convert';
import 'dart:io';
import 'dart:ui';
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
  static const String _defaultGoogleRss =
      'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en';

  final TextEditingController _searchController = TextEditingController();
  List<NewsArticle> _articles = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCachedNewsAndFetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedNewsAndFetch() async {
    // 1. Instant load from local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedXml = prefs.getString('cached_google_news_rss');
      if (cachedXml != null && cachedXml.isNotEmpty) {
        final cached = _parseGoogleNewsRss(cachedXml);
        if (cached.isNotEmpty && mounted) {
          setState(() {
            _articles = cached;
            _isLoading = false;
          });
        }
      }
    } catch (_) {}

    // 2. Fetch fresh Google News RSS
    await _fetchGoogleNews();
  }

  Future<void> _fetchGoogleNews([String? query]) async {
    if (!mounted) return;
    if (_articles.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final String urlStr;
    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      urlStr =
          'https://news.google.com/rss/search?q=${Uri.encodeComponent(trimmedQuery)}&hl=en-US&gl=US&ceid=US:en';
    } else {
      urlStr = _defaultGoogleRss;
    }

    try {
      final response = await http
          .get(
            Uri.parse(urlStr),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final parsed = _parseGoogleNewsRss(response.body);
        if (parsed.isNotEmpty) {
          if (mounted) {
            setState(() {
              _articles = parsed;
              _isLoading = false;
              _errorMessage = null;
            });
          }

          // Cache default feed
          if (trimmedQuery == null || trimmedQuery.isEmpty) {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('cached_google_news_rss', response.body);
            } catch (_) {}
          }
          return;
        }
      }

      if (_articles.isEmpty && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load Google News feed.';
        });
      }
    } catch (e) {
      if (_articles.isEmpty && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Network error: $e';
        });
      }
    }
  }

  String _cleanText(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    var text = raw
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ');
    // Strip HTML tags
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    // In case of double entity encoding
    text = text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ');
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<NewsArticle> _parseGoogleNewsRss(String xmlString) {
    final List<NewsArticle> articles = [];
    final itemRegex = RegExp(r'<item>(.*?)</item>', dotAll: true);
    final matches = itemRegex.allMatches(xmlString);

    for (final match in matches) {
      final itemContent = match.group(1) ?? '';

      // Title
      final titleMatch = RegExp(
        r'<title>(.*?)</title>',
        dotAll: true,
      ).firstMatch(itemContent);
      var rawTitle = _cleanText(titleMatch?.group(1) ?? '');
      if (rawTitle.isEmpty) continue;

      // Link
      final linkMatch = RegExp(
        r'<link>(.*?)</link>',
        dotAll: true,
      ).firstMatch(itemContent);
      final link = _cleanText(linkMatch?.group(1) ?? '');
      if (link.isEmpty) continue;

      // Source
      final sourceMatch = RegExp(
        r'<source(?:\s+url="([^"]*)")?[^>]*>(.*?)</source>',
        dotAll: true,
      ).firstMatch(itemContent);
      var sourceName = _cleanText(sourceMatch?.group(2) ?? '');
      final sourceDomainUrl = sourceMatch?.group(1) ?? '';

      if (sourceName.isEmpty) {
        final dashIndex = rawTitle.lastIndexOf(' - ');
        if (dashIndex != -1) {
          sourceName = rawTitle.substring(dashIndex + 3).trim();
          rawTitle = rawTitle.substring(0, dashIndex).trim();
        } else {
          sourceName = 'Google News';
        }
      } else {
        if (rawTitle.endsWith(' - $sourceName')) {
          rawTitle = rawTitle
              .substring(0, rawTitle.length - (sourceName.length + 3))
              .trim();
        }
      }

      // Date
      final dateMatch = RegExp(
        r'<pubDate>(.*?)</pubDate>',
        dotAll: true,
      ).firstMatch(itemContent);
      final rawDate = _cleanText(dateMatch?.group(1) ?? '');

      // Real Image (if provided by media tags)
      String? imageUrl;
      final mediaMatch = RegExp(
        r'<media:content[^>]+url="([^"]+)"',
        dotAll: true,
      ).firstMatch(itemContent);
      if (mediaMatch != null) {
        imageUrl = mediaMatch.group(1);
      } else {
        final imgMatch = RegExp(
          r'<img[^>]+src=["'']([^"'']+)["'']',
          dotAll: true,
        ).firstMatch(itemContent);
        if (imgMatch != null) {
          imageUrl = imgMatch.group(1);
        }
      }

      // Publisher brand favicon
      String? sourceFavicon;
      if (sourceDomainUrl.isNotEmpty) {
        try {
          final host = Uri.parse(sourceDomainUrl).host;
          if (host.isNotEmpty) {
            sourceFavicon =
                'https://www.google.com/s2/favicons?domain=$host&sz=128';
          }
        } catch (_) {}
      }

      // Snippet / description (filter out Google's <ol><li> list of links)
      final descMatch = RegExp(
        r'<description>(.*?)</description>',
        dotAll: true,
      ).firstMatch(itemContent);
      final rawDesc = descMatch?.group(1) ?? '';
      String? cleanDesc;
      if (!rawDesc.contains('&lt;ol') &&
          !rawDesc.contains('<ol') &&
          !rawDesc.contains('&lt;li') &&
          !rawDesc.contains('<li')) {
        final stripped = _cleanText(rawDesc);
        if (stripped.isNotEmpty &&
            stripped != rawTitle &&
            !stripped.startsWith('<')) {
          cleanDesc = stripped;
        }
      }

      articles.add(
        NewsArticle(
          title: rawTitle,
          description: cleanDesc,
          url: link,
          urlToImage: imageUrl,
          publishedAt: rawDate,
          sourceName: sourceName,
          sourceFavicon: sourceFavicon,
        ),
      );
    }
    return articles;
  }

  String _formatTimeAgo(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return '';
    try {
      DateTime? parsed = DateTime.tryParse(rawDate);
      if (parsed == null) {
        try {
          parsed = HttpDate.parse(rawDate);
        } catch (_) {}
      }
      if (parsed == null) return rawDate;
      final diff = DateTime.now().difference(parsed);
      if (diff.inMinutes < 60) {
        return '${diff.inMinutes.clamp(1, 59)}m';
      }
      if (diff.inHours < 24) {
        return '${diff.inHours}h';
      }
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Translucent Liquid Glass Backdrop
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: Container(
                color: cs.surface.withValues(alpha: 0.78),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Top Floating Search Bar Pill & Outside Left Back Icon
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 10),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, size: 24),
                        color: cs.onSurface,
                        tooltip: 'Back',
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (query) =>
                                      _fetchGoogleNews(query),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search Google News...',
                                    hintStyle: TextStyle(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 20),
                                  color: cs.onSurfaceVariant,
                                  onPressed: () {
                                    _searchController.clear();
                                    _fetchGoogleNews();
                                    setState(() {});
                                  },
                                ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // News Feed
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
                                      onPressed: () => _fetchGoogleNews(),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Try Again'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () =>
                                  _fetchGoogleNews(_searchController.text),
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.only(bottom: 32),
                                cacheExtent: 1500,
                                itemCount: _articles.length,
                                itemBuilder: (context, index) {
                                  final article = _articles[index];
                                  final timeAgo =
                                      _formatTimeAgo(article.publishedAt);

                                  return _NewsPostItem(
                                    key: ValueKey(
                                      article.url.isNotEmpty
                                          ? article.url
                                          : 'news_$index',
                                    ),
                                    article: article,
                                    timeAgo: timeAgo,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              NewsDetailFromDiscPage(
                                            article: article,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsPostItem extends StatelessWidget {
  final NewsArticle article;
  final String timeAgo;
  final VoidCallback onTap;

  const _NewsPostItem({
    super.key,
    required this.article,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rawImageUrl = article.urlToImage?.trim();
    final hasRealImage = rawImageUrl != null &&
        rawImageUrl.isNotEmpty &&
        !rawImageUrl.contains('favicons');
    final imageUrl = (hasRealImage && rawImageUrl.startsWith('http://'))
        ? rawImageUrl.replaceFirst('http://', 'https://')
        : rawImageUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Publisher / source and time row
                  Row(
                    children: [
                      if (article.sourceFavicon != null &&
                          article.sourceFavicon!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            article.sourceFavicon!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          article.sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
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
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Headline title
                  Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      height: 1.3,
                    ),
                  ),

                  // Image (with rounded corners ONLY)
                  if (hasRealImage && imageUrl != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          child: Image.network(
                            imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            cacheWidth: 800,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Description snippet if present
                  if (article.description != null &&
                      article.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      article.description!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 0.6,
              color: cs.outlineVariant.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}
