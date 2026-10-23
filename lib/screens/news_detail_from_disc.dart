import 'package:flutter/material.dart';
import 'package:swavoti/services/launcher_service.dart';

class NewsArticle {
  final String title;
  final String? description;
  final String url;
  final String? urlToImage;
  final String? publishedAt;
  final String? content;
  final String sourceName;
  final String? sourceFavicon;
  final String? author;

  const NewsArticle({
    required this.title,
    this.description,
    required this.url,
    this.urlToImage,
    this.publishedAt,
    this.content,
    required this.sourceName,
    this.sourceFavicon,
    this.author,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as Map<String, dynamic>?;
    return NewsArticle(
      title: json['title'] as String? ?? 'No Title',
      description: json['description'] as String?,
      url: json['url'] as String? ?? '',
      urlToImage: json['urlToImage'] as String?,
      publishedAt: json['publishedAt'] as String?,
      content: json['content'] as String?,
      sourceName: source?['name'] as String? ?? 'News',
      sourceFavicon: json['sourceFavicon'] as String?,
      author: json['author'] as String?,
    );
  }
}

class NewsDetailFromDiscPage extends StatelessWidget {
  final NewsArticle article;

  const NewsDetailFromDiscPage({super.key, required this.article});

  static String cleanText(String? raw) {
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
    // Re-unescape in case of double escaping
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

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return rawDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final formattedDate = _formatDate(article.publishedAt);
    final cleanTitle = cleanText(article.title);
    final cleanDesc = cleanText(article.description);
    final cleanContent = cleanText(article.content);
    final rawImg = article.urlToImage?.trim();
    final hasRealImage = rawImg != null &&
        rawImg.isNotEmpty &&
        !rawImg.contains('favicons');

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (article.url.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded),
              tooltip: 'Open in Browser',
              onPressed: () => LauncherService.openUrlInBrowser(article.url),
            ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source & Date Badge
            Row(
              children: [
                if (article.sourceFavicon != null &&
                    article.sourceFavicon!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      article.sourceFavicon!,
                      width: 18,
                      height: 18,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    cleanText(article.sourceName),
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (formattedDate.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // Article Title
            Text(
              cleanTitle,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),

            if (article.author != null && article.author!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'By ${cleanText(article.author)}',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // Hero Image with rounded corners ONLY
            if (hasRealImage) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  rawImg,
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],

            // Description
            if (cleanDesc.isNotEmpty && cleanDesc != cleanTitle) ...[
              const SizedBox(height: 20),
              Text(
                cleanDesc,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            // Content
            if (cleanContent.isNotEmpty &&
                cleanContent != cleanDesc &&
                cleanContent != cleanTitle) ...[
              const SizedBox(height: 16),
              Text(
                cleanContent,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Open Full Article Action Button
            if (article.url.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => LauncherService.openUrlInBrowser(article.url),
                  icon: const Icon(Icons.public_rounded),
                  label: Text('Read Full Article on ${cleanText(article.sourceName)}'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

