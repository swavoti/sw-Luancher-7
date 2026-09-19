import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiscoverNewsPage extends StatefulWidget {
  const DiscoverNewsPage({super.key});

  @override
  State<DiscoverNewsPage> createState() => _DiscoverNewsPageState();
}

// Global cached webview controller to maintain state across page pushes
WebViewController? _cachedWebViewController;
String? _cachedUrl;

class _DiscoverNewsPageState extends State<DiscoverNewsPage> {
  late WebViewController _webViewController;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('feed_provider') ?? 'msn';
    final url = provider == 'yahoo'
        ? 'https://www.yahoo.com'
        : 'https://www.msn.com';

    if (_cachedWebViewController != null && _cachedUrl == url) {
      _webViewController = _cachedWebViewController!;
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _isLoading = progress < 100);
          },
          onPageStarted: (_) {
            if (mounted)
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    _cachedWebViewController = _webViewController;
    _cachedUrl = url;

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              if (_hasError)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, size: 64, color: Colors.white54),
                      const SizedBox(height: 16),
                      const Text(
                        'No Internet Connection',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _hasError = false);
                          _webViewController.reload();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else
                WebViewWidget(controller: _webViewController),
              if (_isLoading && !_hasError)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
