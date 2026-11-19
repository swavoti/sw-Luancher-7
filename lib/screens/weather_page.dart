import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:swavoti/services/weather_alerts.dart';
import 'package:swavoti/services/weather_service.dart';
import 'package:swavoti/widgets/weather_icon.dart';

class _CitySuggestion {
  final String name;
  final String admin1;
  final String country;

  const _CitySuggestion({
    required this.name,
    required this.admin1,
    required this.country,
  });

  String get subtitle {
    if (admin1.isNotEmpty && country.isNotEmpty) return '$admin1, $country';
    if (country.isNotEmpty) return country;
    return admin1;
  }
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> with WidgetsBindingObserver {
  FullWeatherData? _data;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;
  String? _selectedCity;

  // Inline search state
  bool _isSearching = false;
  bool _isAddingCity = false;
  String _addingCityName = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  List<_CitySuggestion> _suggestions = [];
  bool _loadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isSearching && !_isAddingCity) {
      _load();
    }
  }

  void _closePage() {
    if (_isSearching) {
      _exitSearch();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      SystemNavigator.pop();
    }
  }

  void _enterSearch() {
    setState(() {
      _isSearching = true;
      _suggestions = [];
      _searchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _exitSearch() {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _suggestions = [];
      _loadingSuggestions = false;
      _searchController.clear();
    });
  }

  void _onSearchQueryChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _suggestions = [];
        _loadingSuggestions = false;
      });
      return;
    }
    setState(() => _loadingSuggestions = true);
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      _fetchCitySuggestions(trimmed);
    });
  }

  Future<void> _fetchCitySuggestions(String query) async {
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeQueryComponent(query)}'
        '&count=8&language=en&format=json',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (!mounted || _searchController.text.trim() != query) return;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final results = (decoded['results'] as List?) ?? const [];
        final parsed = results.map((item) {
          final map = item as Map<String, dynamic>;
          return _CitySuggestion(
            name: (map['name'] as String?) ?? '',
            admin1: (map['admin1'] as String?) ?? '',
            country: (map['country'] as String?) ?? '',
          );
        }).where((s) => s.name.isNotEmpty).toList();
        setState(() {
          _suggestions = parsed;
          _loadingSuggestions = false;
        });
      } else {
        setState(() {
          _suggestions = [];
          _loadingSuggestions = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _loadingSuggestions = false;
        });
      }
    }
  }

  Future<void> _selectSuggestion(_CitySuggestion suggestion) async {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _isAddingCity = true;
      _addingCityName = suggestion.name;
      _suggestions = [];
      _searchController.clear();
    });

    final start = DateTime.now();
    await _load(city: suggestion.name);
    final elapsed = DateTime.now().difference(start);
    // Let the 2-dots cross-swap animation play smoothly for at least 900ms
    if (elapsed.inMilliseconds < 900) {
      await Future.delayed(Duration(milliseconds: 900 - elapsed.inMilliseconds));
    }
    if (mounted) {
      setState(() {
        _isAddingCity = false;
        _addingCityName = '';
      });
    }
  }

  Future<void> _load({String? city}) async {
    if (city != null) _selectedCity = city.trim();
    final generation = ++_loadGeneration;
    if (!_isAddingCity) {
      setState(() {
        _loading = _data == null;
        _error = null;
      });
    }
    final data = await WeatherService.getFullWeather(city: _selectedCity);
    if (!mounted || generation != _loadGeneration) return;
    if (data == null) {
      setState(() {
        _loading = false;
        _error = _selectedCity == null
            ? 'Could not load weather.\nCheck your internet connection.'
            : 'Could not load weather for "${_selectedCity!}".';
      });
      if (_data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_error!)),
        );
      }
    } else {
      setState(() {
        _loading = false;
        _data = data;
        _error = null;
      });
    }
  }

  String _descriptionFor(int code) {
    if (code == 0) return 'Clear sky';
    if (code == 1) return 'Mostly clear';
    if (code == 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code >= 45 && code <= 48) return 'Foggy';
    if (code >= 51 && code <= 55) return 'Drizzle';
    if (code >= 61 && code <= 65) return 'Rain';
    if (code >= 66 && code <= 67) return 'Freezing rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain showers';
    if (code >= 85 && code <= 86) return 'Snow showers';
    if (code >= 95 && code <= 99) return 'Thunderstorm';
    return 'Mixed';
  }

  String _weekdayShort(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    return days[d.weekday - 1];
  }

  String _hourLabel(DateTime t) {
    final h = t.hour;
    if (h == 0) return '12 AM';
    if (h < 12) return '$h AM';
    if (h == 12) return '12 PM';
    return '${h - 12} PM';
  }

  bool _isNight(DateTime t) => t.hour < 6 || t.hour >= 20;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isNight = _isNight(now);
    final cityLabel = _data?.locationName ?? _selectedCity ?? 'Weather';

    return PopScope(
      canPop: !_isSearching && Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closePage();
      },
      child: Scaffold(
        backgroundColor: isNight
            ? const Color(0xFF0E2346)
            : const Color(0xFF2176DE),
        body: Stack(
          children: [
            // Blue sky + soft clouds background
            Positioned.fill(
              child: _SkyCloudsBackground(isNight: isNight),
            ),

            SafeArea(
              child: Column(
                children: [
                  // Top Bar with smooth transition between City Name <-> Pill Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: SizedBox(
                      height: 48,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0.18, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: _isSearching
                            ? _buildPillSearchBar()
                            : _buildCityTopBar(cityLabel),
                      ),
                    ),
                  ),

                  // Body: Adding City 2-Dot Loader | Blank Search Mode | Weather Content
                  Expanded(
                    child: _isAddingCity
                        ? _AddingCityOverlay(cityName: _addingCityName)
                        : _isSearching
                            ? _buildSearchSuggestionsBody()
                            : _loading
                                ? const Center(
                                    child: _TwoDotSwapLoader(),
                                  )
                                : _data == null
                                    ? _ErrorView(
                                        message:
                                            _error ?? 'Could not load weather.',
                                        onRetry: () => _load(),
                                      )
                                    : _buildWeatherBody(_data!, isNight),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCityTopBar(String cityLabel) {
    return Row(
      key: const ValueKey('city_top_bar'),
      children: [
        IconButton(
          onPressed: _closePage,
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _enterSearch,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    cityLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: _enterSearch,
          tooltip: 'Search city',
          icon: const Icon(Icons.search_rounded, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildPillSearchBar() {
    return Container(
      key: const ValueKey('pill_search_bar'),
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _exitSearch,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (val) {
                final q = val.trim();
                if (q.isNotEmpty) {
                  _selectSuggestion(
                    _CitySuggestion(name: q, admin1: '', country: ''),
                  );
                }
              },
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Search city...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _searchController.clear();
                _onSearchQueryChanged('');
              },
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchSuggestionsBody() {
    if (_loadingSuggestions) {
      return const Center(
        child: _TwoDotSwapLoader(),
      );
    }
    if (_suggestions.isEmpty) {
      return const SizedBox.expand();
    }
    return ScrollConfiguration(
      behavior: const _AndroidStretchScrollBehavior(),
      child: ListView.separated(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: Colors.white.withValues(alpha: 0.16),
        ),
        itemBuilder: (context, index) {
          final item = _suggestions[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: const Icon(
              Icons.location_city_rounded,
              color: Colors.white,
              size: 22,
            ),
            title: Text(
              item.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: item.subtitle.isNotEmpty
                ? Text(
                    item.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13,
                    ),
                  )
                : null,
            onTap: () => _selectSuggestion(item),
          );
        },
      ),
    );
  }

  Widget _buildWeatherBody(FullWeatherData data, bool isNight) {
    final alerts = WeatherAlerts.evaluate(data);
    final today = data.daily.isNotEmpty ? data.daily.first : null;
    final hourly = data.hourly.take(24).toList();
    final daily = data.daily.take(7).toList();

    final weekMin = daily.isEmpty
        ? 0.0
        : daily.map((d) => d.tempMin).reduce(math.min);
    final weekMax = daily.isEmpty
        ? 30.0
        : daily.map((d) => d.tempMax).reduce(math.max);

    return ScrollConfiguration(
      behavior: const _AndroidStretchScrollBehavior(),
      child: RefreshIndicator(
        color: const Color(0xFF1E6FD9),
        backgroundColor: Colors.white,
        onRefresh: () => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Inline weather warning links (max 2, no cards)
            if (alerts.isNotEmpty) ...[
              _WarningsSection(alerts: alerts),
              const SizedBox(height: 12),
            ],

            // Hero Current Weather (straight, aligned)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                WeatherIcon(
                  weatherCode: data.currentWeatherCode,
                  size: 76,
                  isNight: isNight,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data.currentTemperature.round()}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 68,
                          fontWeight: FontWeight.w300,
                          height: 1.0,
                          letterSpacing: -2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _descriptionFor(data.currentWeatherCode),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        today != null
                            ? 'H:${today.tempMax.round()}°  L:${today.tempMin.round()}°  ·  Feels like ${data.feelsLikeTemperature.round()}°'
                            : 'Feels like ${data.feelsLikeTemperature.round()}°',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Hourly Forecast Card
            if (hourly.isNotEmpty) ...[
              _SkyCard(
                title: 'HOURLY FORECAST',
                child: SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    itemCount: hourly.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, idx) {
                      final h = hourly[idx];
                      return SizedBox(
                        width: 58,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              idx == 0 ? 'Now' : _hourLabel(h.time),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: idx == 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            WeatherIcon(
                              weatherCode: h.weatherCode,
                              size: 30,
                              isNight: _isNight(h.time),
                            ),
                            Text(
                              '${h.temperature.round()}°',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              h.precipitationProbability >= 10
                                  ? '${h.precipitationProbability.round()}%'
                                  : '',
                              style: TextStyle(
                                color: Colors.lightBlue.shade100,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 7-Day Forecast Card
            if (daily.isNotEmpty) ...[
              _SkyCard(
                title: '7-DAY FORECAST',
                child: Column(
                  children: [
                    for (int i = 0; i < daily.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 16,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      _DailyRow(
                        dayLabel: _weekdayShort(daily[i].date),
                        forecast: daily[i],
                        weekMin: weekMin,
                        weekMax: weekMax,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 2x2 Conditions Grid (straight symmetrical rows)
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.water_drop_outlined,
                    label: 'Humidity',
                    value: '${data.relativeHumidity}%',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.air_rounded,
                    label: 'Wind',
                    value: '${data.windSpeed.round()} km/h',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: Icons.wb_sunny_outlined,
                    label: 'UV Index',
                    value: data.uvIndex.toStringAsFixed(1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricTile(
                    icon: Icons.compress_rounded,
                    label: 'Pressure',
                    value: '${data.pressure.round()} hPa',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Android Overscroll Stretch Behavior ─────────────────────────────────────

class _AndroidStretchScrollBehavior extends ScrollBehavior {
  const _AndroidStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

// ─── Blue Sky + Painted Soft Clouds Background ───────────────────────────────

class _SkyCloudsBackground extends StatelessWidget {
  final bool isNight;

  const _SkyCloudsBackground({required this.isNight});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isNight
              ? const [
                  Color(0xFF0D1E3E),
                  Color(0xFF1A3A6E),
                  Color(0xFF285591),
                ]
              : const [
                  Color(0xFF1B6BD3),
                  Color(0xFF4295EE),
                  Color(0xFF7EC0FA),
                ],
        ),
      ),
      child: CustomPaint(
        painter: _SoftCloudsPainter(isNight: isNight),
      ),
    );
  }
}

class _SoftCloudsPainter extends CustomPainter {
  final bool isNight;

  const _SoftCloudsPainter({required this.isNight});

  @override
  void paint(Canvas canvas, Size size) {
    final cloudColor = isNight
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.16);
    final softPaint = Paint()
      ..color = cloudColor
      ..style = PaintingStyle.fill;

    // Upper-right cloud cluster
    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.14),
      size.width * 0.28,
      softPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.65, size.height * 0.17),
      size.width * 0.19,
      softPaint,
    );

    // Mid-left cloud cluster
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.38),
      size.width * 0.24,
      softPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.30, size.height * 0.41),
      size.width * 0.16,
      softPaint,
    );

    // Lower soft haze
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.78),
      size.width * 0.34,
      softPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SoftCloudsPainter oldDelegate) =>
      oldDelegate.isNight != isNight;
}

// ─── 2-Dots Cross-Swapping Animation ("Adding city...") ──────────────────────

class _AddingCityOverlay extends StatelessWidget {
  final String cityName;

  const _AddingCityOverlay({required this.cityName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _TwoDotSwapLoader(),
          const SizedBox(height: 18),
          Text(
            cityName.isNotEmpty ? 'Adding $cityName...' : 'Adding city...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoDotSwapLoader extends StatefulWidget {
  const _TwoDotSwapLoader();

  @override
  State<_TwoDotSwapLoader> createState() => _TwoDotSwapLoaderState();
}

class _TwoDotSwapLoaderState extends State<_TwoDotSwapLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 28,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final angle = _controller.value * 2 * math.pi;
          final dx = math.cos(angle) * 16.0;
          final s1 = 0.82 + 0.28 * ((math.sin(angle) + 1) / 2);
          final s2 = 0.82 + 0.28 * ((-math.sin(angle) + 1) / 2);

          final dot1 = Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(
              scale: s1,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
          final dot2 = Transform.translate(
            offset: Offset(-dx, 0),
            child: Transform.scale(
              scale: s2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.lightBlue.shade100,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );

          return Stack(
            alignment: Alignment.center,
            children: s1 >= s2 ? [dot2, dot1] : [dot1, dot2],
          );
        },
      ),
    );
  }
}

// ─── Sky Card + Forecast Rows ────────────────────────────────────────────────

class _SkyCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SkyCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  final String dayLabel;
  final DailyForecast forecast;
  final double weekMin;
  final double weekMax;

  const _DailyRow({
    required this.dayLabel,
    required this.forecast,
    required this.weekMin,
    required this.weekMax,
  });

  @override
  Widget build(BuildContext context) {
    final span = (weekMax - weekMin).clamp(1.0, 100.0);
    final startFrac = ((forecast.tempMin - weekMin) / span).clamp(0.0, 1.0);
    final endFrac = ((forecast.tempMax - weekMin) / span).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            dayLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        WeatherIcon(weatherCode: forecast.weatherCode, size: 26),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            forecast.precipitationProbabilityMax >= 10
                ? '${forecast.precipitationProbabilityMax.round()}%'
                : '',
            style: TextStyle(
              color: Colors.lightBlue.shade100,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${forecast.tempMin.round()}°',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final left = w * startFrac;
              final barW = math.max(8.0, w * (endFrac - startFrac));
              return Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: left,
                      width: barW,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF81D4FA), Color(0xFFFFD54F)],
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            '${forecast.tempMax.round()}°',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inline Weather Warnings + Full Warnings Page ────────────────────────────

class _WarningsSection extends StatelessWidget {
  final List<WeatherAlert> alerts;

  const _WarningsSection({required this.alerts});

  void _openWarningsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WeatherWarningsPage(alerts: alerts),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final visibleAlerts = alerts.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final alert in visibleAlerts)
          InkWell(
            onTap: () => _openWarningsPage(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFFFFE082),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      alert.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFF8E1),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFFFFE082),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Color(0xFFFFE082),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class WeatherWarningsPage extends StatelessWidget {
  final List<WeatherAlert> alerts;

  const WeatherWarningsPage({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Weather Warnings (${alerts.length})'),
      ),
      body: alerts.isEmpty
          ? Center(
              child: Text(
                'No active weather warnings',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
              ),
            )
          : ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _AlertCard(alert: alerts[index]),
            ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final WeatherAlert alert;

  const _AlertCard({required this.alert});

  IconData _iconFor(WeatherAlertType type) {
    switch (type) {
      case WeatherAlertType.thunderstorm:
        return Icons.thunderstorm_rounded;
      case WeatherAlertType.heavyRain:
        return Icons.water_drop_rounded;
      case WeatherAlertType.flooding:
        return Icons.waves_rounded;
      case WeatherAlertType.snow:
        return Icons.ac_unit_rounded;
      case WeatherAlertType.ice:
        return Icons.severe_cold_rounded;
      case WeatherAlertType.wind:
        return Icons.air_rounded;
      case WeatherAlertType.heat:
        return Icons.local_fire_department_rounded;
      case WeatherAlertType.cold:
        return Icons.severe_cold_rounded;
      case WeatherAlertType.fog:
        return Icons.foggy;
      case WeatherAlertType.lowVisibility:
        return Icons.visibility_off_rounded;
      case WeatherAlertType.uv:
        return Icons.wb_sunny_rounded;
      case WeatherAlertType.general:
        return Icons.warning_amber_rounded;
    }
  }

  (Color bg, Color fg, Color accent) _palette(ColorScheme cs) {
    switch (alert.severity) {
      case WeatherAlertSeverity.extreme:
      case WeatherAlertSeverity.severe:
        return (cs.errorContainer, cs.onErrorContainer, cs.error);
      case WeatherAlertSeverity.moderate:
        return (cs.tertiaryContainer, cs.onTertiaryContainer, cs.tertiary);
      case WeatherAlertSeverity.minor:
        return (cs.secondaryContainer, cs.onSecondaryContainer, cs.secondary);
      case WeatherAlertSeverity.info:
        return (cs.surfaceContainerHigh, cs.onSurface, cs.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg, accent) = _palette(cs);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(alert.type), color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        alert.severity.label.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  alert.description,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.35,
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
