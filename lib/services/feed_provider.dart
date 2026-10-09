class FeedProvider {
  final String id;
  final String name;
  final String url;

  const FeedProvider({
    required this.id,
    required this.name,
    required this.url,
  });

  static const List<FeedProvider> all = [
    FeedProvider(id: 'msn', name: 'MSN', url: 'https://www.msn.com'),
    FeedProvider(id: 'yahoo', name: 'Yahoo', url: 'https://www.yahoo.com'),
    FeedProvider(
      id: 'google_news',
      name: 'Google News',
      url: 'https://news.google.com',
    ),
    FeedProvider(
      id: 'bing_news',
      name: 'Bing News',
      url: 'https://www.bing.com/news',
    ),
    FeedProvider(
      id: 'bbc_news',
      name: 'BBC News',
      url: 'https://www.bbc.com/news',
    ),
    FeedProvider(
      id: 'cnn',
      name: 'CNN',
      url: 'https://edition.cnn.com',
    ),
    FeedProvider(
      id: 'reuters',
      name: 'Reuters',
      url: 'https://www.reuters.com',
    ),
    FeedProvider(
      id: 'ap_news',
      name: 'AP News',
      url: 'https://apnews.com',
    ),
    FeedProvider(
      id: 'the_guardian',
      name: 'The Guardian',
      url: 'https://www.theguardian.com/international',
    ),
    FeedProvider(
      id: 'al_jazeera',
      name: 'Al Jazeera',
      url: 'https://www.aljazeera.com',
    ),
    FeedProvider(
      id: 'sky_news',
      name: 'Sky News',
      url: 'https://news.sky.com',
    ),
  ];

  static FeedProvider fromId(String id) {
    return all.firstWhere(
      (provider) => provider.id == id,
      orElse: () => all.first,
    );
  }
}
