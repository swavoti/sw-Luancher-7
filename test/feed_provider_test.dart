import 'package:flutter_test/flutter_test.dart';
import 'package:swavoti/services/feed_provider.dart';

void main() {
  test('keeps MSN as the default and provides nine additional feeds', () {
    expect(FeedProvider.all, hasLength(11));
    expect(FeedProvider.all.first.id, 'msn');
    expect(FeedProvider.fromId('unknown').id, 'msn');
  });

  test('all feed providers have unique IDs and valid HTTPS URLs', () {
    final ids = FeedProvider.all.map((provider) => provider.id).toSet();
    expect(ids, hasLength(FeedProvider.all.length));
    expect(
      FeedProvider.all.every(
        (provider) => Uri.parse(provider.url).scheme == 'https',
      ),
      isTrue,
    );
  });
}
