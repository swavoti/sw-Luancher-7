import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:swavoti/services/weather_service.dart';
import 'package:swavoti/widgets/weather_icon.dart';

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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      _load();
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  Future<void> _load({String? city}) async {
    if (city != null) _selectedCity = city.trim();
    final generation = ++_loadGeneration;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    final data = await WeatherService.getFullWeather(city: _selectedCity);
    if (!mounted || generation != _loadGeneration) return;
    if (data == null) {
      setState(() {
        _loading = false;
        _error = _selectedCity == null
            ? 'Could not load weather.\nCheck your internet connection.'
            : 'Could not load weather for "${_selectedCity!}". Check the city name and try again.';
      });
      if (_data != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error!)));
      }
    } else {
      setState(() {
        _loading = false;
        _data = data;
        _error = null;
      });
    }
  }

  Future<void> _refresh() async {
    await _load();
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
    if (h == 0) return '12am';
    if (h < 12) return '${h}am';
    if (h == 12) return '12pm';
    return '${h - 12}pm';
  }

  bool _isNight(DateTime t) => t.hour < 6 || t.hour >= 20;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isNight = now.hour < 6 || now.hour >= 20;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: _loading
            ? Center(child: M3EProgressIndicator.circular(color: cs.primary))
            : _data == null
            ? _ErrorView(message: _error!, onRetry: _refresh)
            : RefreshIndicator(
                color: cs.primary,
                onRefresh: _refresh,
                child: _WeatherContent(
                  data: _data!,
                  descriptionFor: _descriptionFor,
                  weekdayShort: _weekdayShort,
                  hourLabel: _hourLabel,
                  isNightTime: _isNight,
                  isCurrentlyNight: isNight,
                  onSearchCity: (city) => _load(city: city),
                  onRefresh: _refresh,
                ),
              ),
      ),
    );
  }
}

// ─── Error state ─────────────────────────────────────────────────────────────

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
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ─── Main content ─────────────────────────────────────────────────────────────

class _WeatherContent extends StatelessWidget {
  final FullWeatherData data;
  final String Function(int) descriptionFor;
  final String Function(DateTime) weekdayShort;
  final String Function(DateTime) hourLabel;
  final bool Function(DateTime) isNightTime;
  final bool isCurrentlyNight;
  final ValueChanged<String> onSearchCity;
  final Future<void> Function() onRefresh;

  const _WeatherContent({
    required this.data,
    required this.descriptionFor,
    required this.weekdayShort,
    required this.hourLabel,
    required this.isNightTime,
    required this.isCurrentlyNight,
    required this.onSearchCity,
    required this.onRefresh,
  });

  String _uvLabel(double value) {
    if (value < 3) return 'Low';
    if (value < 6) return 'Moderate';
    if (value < 8) return 'High';
    if (value < 11) return 'Very high';
    return 'Extreme';
  }

  String _windDirection(int degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return directions[((degrees % 360) / 45).round() % directions.length];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // ── Back button + location ──────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: cs.onSurface,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.location_on_rounded,
                  color: cs.onSurfaceVariant,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    data.locationName.isNotEmpty
                        ? '${data.locationName}, ${data.country}'
                        : 'Your Location',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) {
                        final controller = TextEditingController();
                        return AlertDialog(
                          title: const Text('Search City'),
                          content: TextField(
                            controller: controller,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'Enter city name...',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                Navigator.pop(ctx);
                                onSearchCity(value);
                              }
                            },
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                final value = controller.text;
                                if (value.trim().isNotEmpty) {
                                  Navigator.pop(ctx);
                                  onSearchCity(value);
                                }
                              },
                              child: const Text('Search'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  icon: Icon(
                    Icons.search_rounded,
                    color: cs.onSurface,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh weather',
                  onPressed: onRefresh,
                  icon: Icon(Icons.refresh_rounded, color: cs.onSurface),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Updated ${data.updatedAt.hour.toString().padLeft(2, '0')}:${data.updatedAt.minute.toString().padLeft(2, '0')} · refreshes every 5 minutes',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ),

        // ── Hero current temperature ────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    WeatherIcon(
                      weatherCode: data.currentWeatherCode,
                      size: 72,
                      isNight: isCurrentlyNight,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${data.currentTemperature.round()}°',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 80,
                            fontWeight: FontWeight.w200,
                            height: 1.0,
                            letterSpacing: -2,
                          ),
                        ),
                        Text(
                          descriptionFor(data.currentWeatherCode),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.air_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${data.windSpeed.round()} km/h wind',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'CURRENT CONDITIONS',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
              children: [
                _WeatherDetailTile(
                  icon: Icons.thermostat_rounded,
                  label: 'Feels like',
                  value: '${data.feelsLikeTemperature.round()}°',
                ),
                _WeatherDetailTile(
                  icon: Icons.water_drop_outlined,
                  label: 'Humidity',
                  value: '${data.relativeHumidity}%',
                ),
                _WeatherDetailTile(
                  icon: Icons.wb_sunny_outlined,
                  label: 'UV index · ${_uvLabel(data.uvIndex)}',
                  value: data.uvIndex.toStringAsFixed(1),
                ),
                _WeatherDetailTile(
                  icon: Icons.air_rounded,
                  label: 'Wind · ${_windDirection(data.windDirection)}',
                  value: '${data.windSpeed.round()} km/h',
                ),
                _WeatherDetailTile(
                  icon: Icons.air_rounded,
                  label: 'Wind gusts',
                  value: '${data.windGusts.round()} km/h',
                ),
                _WeatherDetailTile(
                  icon: Icons.speed_rounded,
                  label: 'Pressure',
                  value: '${data.pressure.round()} hPa',
                ),
                _WeatherDetailTile(
                  icon: Icons.visibility_outlined,
                  label: 'Visibility',
                  value: data.visibility >= 1000
                      ? '${(data.visibility / 1000).toStringAsFixed(1)} km'
                      : '${data.visibility.round()} m',
                ),
              ],
            ),
          ),
        ),

        // ── Hourly forecast (horizontal scroll) ─────────────────
        SliverToBoxAdapter(child: _SectionLabel(label: 'Today — Hourly')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 120,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: data.hourly.length,
              itemBuilder: (context, i) {
                final h = data.hourly[i];
                final isNow = i == 0;
                return _HourlyTile(
                  time: isNow ? 'Now' : hourLabel(h.time),
                  temperature: h.temperature,
                  weatherCode: h.weatherCode,
                  precipitationProbability: h.precipitationProbability,
                  isNight: isNightTime(h.time),
                  highlight: isNow,
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Daily forecast ──────────────────────────────────────
        SliverToBoxAdapter(child: _SectionLabel(label: '7-Day Forecast')),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final day = data.daily[i];
            final isToday = i == 0;
            return _DailyRow(
              label: isToday ? 'Today' : weekdayShort(day.date),
              date: day.date,
              weatherCode: day.weatherCode,
              tempMax: day.tempMax,
              tempMin: day.tempMin,
              precipProbability: day.precipitationProbabilityMax,
            );
          }, childCount: data.daily.length),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }
}

class _WeatherDetailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WeatherDetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─── Hourly tile ─────────────────────────────────────────────────────────────

class _HourlyTile extends StatelessWidget {
  final String time;
  final double temperature;
  final int weatherCode;
  final double precipitationProbability;
  final bool isNight;
  final bool highlight;

  const _HourlyTile({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    required this.precipitationProbability,
    required this.isNight,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 68,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? cs.secondaryContainer : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? cs.primary : cs.outlineVariant,
          width: highlight ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            time,
            style: TextStyle(
              color: highlight ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          WeatherIcon(weatherCode: weatherCode, size: 30, isNight: isNight),
          Text(
            '${temperature.round()}°',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (precipitationProbability > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.water_drop_rounded, size: 10, color: cs.tertiary),
                const SizedBox(width: 2),
                Text(
                  '${precipitationProbability.round()}%',
                  style: TextStyle(
                    color: cs.tertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Daily row ────────────────────────────────────────────────────────────────

class _DailyRow extends StatelessWidget {
  final String label;
  final DateTime date;
  final int weatherCode;
  final double tempMax;
  final double tempMin;
  final double precipProbability;

  const _DailyRow({
    required this.label,
    required this.date,
    required this.weatherCode,
    required this.tempMax,
    required this.tempMin,
    required this.precipProbability,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Day name
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // Weather icon
          WeatherIcon(weatherCode: weatherCode, size: 28, isNight: false),

          const SizedBox(width: 10),

          // Precipitation %
          if (precipProbability > 5) ...[
            Icon(Icons.water_drop_rounded, size: 13, color: cs.tertiary),
            const SizedBox(width: 2),
            SizedBox(
              width: 36,
              child: Text(
                '${precipProbability.round()}%',
                style: TextStyle(
                  color: cs.tertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else
            const SizedBox(width: 50),

          const Spacer(),

          // Temp range bar
          _TempBar(tempMin: tempMin, tempMax: tempMax),

          const SizedBox(width: 12),

          // Low
          SizedBox(
            width: 38,
            child: Text(
              '${tempMin.round()}°',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // High
          SizedBox(
            width: 38,
            child: Text(
              '${tempMax.round()}°',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Temperature range bar ───────────────────────────────────────────────────

class _TempBar extends StatelessWidget {
  final double tempMin;
  final double tempMax;

  const _TempBar({required this.tempMin, required this.tempMax});

  @override
  Widget build(BuildContext context) {
    // Relative cold-to-warm gradient for the bar
    return Container(
      width: 60,
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        gradient: const LinearGradient(
          colors: [Color(0xFF7DD3FC), Color(0xFFFBBF24)],
        ),
      ),
    );
  }
}
