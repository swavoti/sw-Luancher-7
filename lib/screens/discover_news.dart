import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/feed_provider.dart';

class DiscoverNewsPage extends StatefulWidget {
  const DiscoverNewsPage({super.key});

  @override
  State<DiscoverNewsPage> createState() => _DiscoverNewsPageState();
}

class _DiscoverNewsPageState extends State<DiscoverNewsPage> {
  static WebViewController? _sharedController;
  static String? _loadedUrl;
  static bool _sharedIsLoading = true;
  static bool _sharedHasError = false;

  late WebViewController _webViewController;
  bool _isLoading = _sharedIsLoading;
  bool _hasError = _sharedHasError;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('feed_provider') ?? 'msn';
    final url = FeedProvider.fromId(provider).url;

    final existingController = _sharedController;
    if (existingController == null) {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      _sharedController = controller;
      _webViewController = controller;
    } else {
      _webViewController = existingController;
    }
    await _webViewController.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          _sharedIsLoading = progress < 100;
          if (mounted) setState(() => _isLoading = _sharedIsLoading);
        },
        onPageStarted: (_) {
          _sharedIsLoading = true;
          _sharedHasError = false;
          if (mounted) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          }
        },
        onPageFinished: (_) {
          _sharedIsLoading = false;
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) {
            _sharedIsLoading = false;
            _sharedHasError = true;
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          }
        },
      ),
    );

    if (_loadedUrl != url) {
      _sharedIsLoading = true;
      _sharedHasError = false;
      await _webViewController.loadRequest(Uri.parse(url));
      _loadedUrl = url;
    } else if (mounted) {
      setState(() {
        _isLoading = _sharedIsLoading;
        _hasError = _sharedHasError;
      });
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        // Swipe right-to-left (velocity < -200) or left-to-right (velocity > 200)
        if (velocity < -200 || velocity > 200) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Stack(
            children: [
              if (_hasError)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off,
                        size: 64,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Internet Connection',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _hasError = false;
                            _isLoading = true;
                            _sharedHasError = false;
                            _sharedIsLoading = true;
                          });
                          _webViewController.reload();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else
                WebViewWidget(
                  controller: _webViewController,
                  gestureRecognizers: {
                    Factory<VerticalDragGestureRecognizer>(
                      () => VerticalDragGestureRecognizer(),
                    ),
                  },
                ),
              if (_isLoading && !_hasError)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: cs.primary,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
