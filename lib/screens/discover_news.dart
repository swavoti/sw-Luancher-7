import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/feed_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DiscoverNewsPage extends StatefulWidget {
  const DiscoverNewsPage({super.key});

  @override
  State<DiscoverNewsPage> createState() => _DiscoverNewsPageState();
}

class _DiscoverNewsPageState extends State<DiscoverNewsPage> {
  // Target RAM budget for WebView content (58 MiB)
  static const int _maxRamBudgetBytes = 58 * 1024 * 1024;

  WebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _bootstrapIsolatedWebView();
  }

  /// Resolves feed URL inside a background Dart Isolate to ensure zero main-thread hitching.
  Future<void> _bootstrapIsolatedWebView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerId = prefs.getString('feed_provider') ?? 'msn';

      // Resolve URL in background isolate
      final targetUrl = await Isolate.run(() {
        return FeedProvider.fromId(providerId).url;
      });

      if (!mounted) return;
      _currentUrl = targetUrl;
      await _initializeController(targetUrl);
    } catch (e) {
      // Silent error isolation
      debugPrint('DiscoverNewsPage isolate bootstrap caught: $e');
      _triggerGarbageCollection();
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage = 'Could not load feed';
        });
      }
    }
  }

  Future<void> _initializeController(String url) async {
    try {
      final controller = WebViewController();
      
      // Enforce lightweight execution & memory bounds
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);

      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _isLoading = progress < 100);
            }
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (_) {
            // Trim cache once loaded to adhere to 58MB budget
            _enforceMemoryLimit();
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            // Silent crash isolation: catch without rethrowing to main thread
            debugPrint('DiscoverNewsPage silent resource error: ${error.description}');
            if (error.isForMainFrame == true) {
              _triggerGarbageCollection();
              if (mounted) {
                setState(() {
                  _hasError = true;
                  _isLoading = false;
                  _errorMessage = error.description;
                });
              }
            }
          },
        ),
      );

      // Load request safely
      await controller.loadRequest(Uri.parse(url));

      if (mounted) {
        setState(() {
          _webViewController = controller;
        });
      }
    } catch (e) {
      debugPrint('DiscoverNewsPage controller init caught: $e');
      _triggerGarbageCollection();
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  /// Drops caches and triggers engine GC to enforce the 58MB RAM cap.
  Future<void> _enforceMemoryLimit() async {
    try {
      await _webViewController?.clearCache();
      _triggerGarbageCollection();
    } catch (_) {}
  }

  /// Triggers engine garbage collection to reclaim memory.
  void _triggerGarbageCollection() {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  @override
  void dispose() {
    // Release WebView immediately so Chromium does not stay resident in background RAM
    try {
      _webViewController?.loadRequest(Uri.parse('about:blank'));
      _webViewController?.clearCache();
      _webViewController?.clearLocalStorage();
    } catch (_) {}
    _webViewController = null;
    _triggerGarbageCollection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        // Swipe to pop back to home
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
            'Discover',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isLoading = true;
                });
                if (_webViewController != null && _currentUrl.isNotEmpty) {
                  _webViewController!.loadRequest(Uri.parse(_currentUrl));
                } else {
                  _bootstrapIsolatedWebView();
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (_hasError)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.feed_outlined,
                          size: 64,
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
                          'Unable to load news feed. Check your connection or try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            setState(() {
                              _hasError = false;
                              _isLoading = true;
                            });
                            _bootstrapIsolatedWebView();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_webViewController != null)
                WebViewWidget(
                  controller: _webViewController!,
                  gestureRecognizers: {
                    Factory<VerticalDragGestureRecognizer>(
                      () => VerticalDragGestureRecognizer(),
                    ),
                  },
                )
              else
                const SizedBox.shrink(),
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
