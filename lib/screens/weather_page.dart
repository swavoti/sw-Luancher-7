import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:swavoti/services/weather_service.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/widgets/weather_icon.dart';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  FullWeatherData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await WeatherService.getFullWeather();
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load weather.\nCheck your internet connection.';
      });
    } else {
      setState(() {
        _loading = false;
        _data = data;
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

    // Gradient background based on time of day
    final bgColors = isNight
        ? [const Color(0xFF0D1B2A), const Color(0xFF1A2F45)]
        : [const Color(0xFF1E6FAD), const Color(0xFF5BB8F5)];

    return Scaffold(
      backgroundColor: bgColors[0],
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bgColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _WeatherContent(
                  data: _data!,
                  descriptionFor: _descriptionFor,
                  weekdayShort: _weekdayShort,
                  hourLabel: _hourLabel,
                  isNightTime: _isNight,
                  isCurrentlyNight: isNight,
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
            const Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
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

  const _WeatherContent({
    required this.data,
    required this.descriptionFor,
    required this.weekdayShort,
    required this.hourLabel,
    required this.isNightTime,
    required this.isCurrentlyNight,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Back button + location ──────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    data.locationName.isNotEmpty
                        ? '${data.locationName}, ${data.country}'
                        : 'Your Location',
                    style: const TextStyle(
                      color: Colors.white,
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
                                final query = Uri.encodeComponent(
                                  '${value.trim()} weather',
                                );
                                LauncherService.openUrlInBrowser(
                                  'https://www.google.com/search?q=$query',
                                );
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
                                  final query = Uri.encodeComponent(
                                    '${value.trim()} weather',
                                  );
                                  LauncherService.openUrlInBrowser(
                                    'https://www.google.com/search?q=$query',
                                  );
                                }
                              },
                              child: const Text('Search'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 80,
                            fontWeight: FontWeight.w200,
                            height: 1.0,
                            letterSpacing: -2,
                          ),
                        ),
                        Text(
                          descriptionFor(data.currentWeatherCode),
                          style: const TextStyle(
                            color: Colors.white70,
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
                    const Icon(
                      Icons.air_rounded,
                      size: 14,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${data.windSpeed.round()} km/h wind',
                      style: const TextStyle(
                        color: Colors.white54,
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

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
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
    return Container(
      width: 68,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withOpacity(0.2)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: highlight ? Border.all(color: Colors.white30, width: 1) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            time,
            style: TextStyle(
              color: highlight ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          WeatherIcon(weatherCode: weatherCode, size: 30, isNight: isNight),
          Text(
            '${temperature.round()}°',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (precipitationProbability > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.water_drop_rounded,
                  size: 10,
                  color: Color(0xFF7DD3FC),
                ),
                const SizedBox(width: 2),
                Text(
                  '${precipitationProbability.round()}%',
                  style: const TextStyle(
                    color: Color(0xFF7DD3FC),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Day name
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
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
            const Icon(
              Icons.water_drop_rounded,
              size: 13,
              color: Color(0xFF7DD3FC),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 36,
              child: Text(
                '${precipProbability.round()}%',
                style: const TextStyle(
                  color: Color(0xFF7DD3FC),
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
              style: const TextStyle(
                color: Colors.white54,
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
              style: const TextStyle(
                color: Colors.white,
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
