import 'dart:async';
import 'package:flutter/material.dart';
import 'package:swavoti/services/weather_service.dart';
import 'package:swavoti/widgets/weather_icon.dart';
import 'package:swavoti/screens/weather_page.dart';

class TimeWeatherWidget extends StatefulWidget {
  final VoidCallback onRemove;

  const TimeWeatherWidget({super.key, required this.onRemove});

  @override
  State<TimeWeatherWidget> createState() => _TimeWeatherWidgetState();
}

class _TimeWeatherWidgetState extends State<TimeWeatherWidget> {
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();
  WeatherData? _weatherData;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.minute != _currentTime.minute || now.hour != _currentTime.hour) {
        setState(() => _currentTime = now);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    return '$day, ${dt.day} $month';
  }

  Future<void> _loadWeather() async {
    final weather = await WeatherService.getCurrentWeather();
    if (mounted && weather != null) {
      setState(() => _weatherData = weather);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hourStr = _currentTime.hour.toString().padLeft(2, '0');
    final minStr = _currentTime.minute.toString().padLeft(2, '0');

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
          final maxH = constraints.maxHeight.isFinite ? constraints.maxHeight : 240.0;

          // Dynamically scale stacked clock so it fits nicely inside any cell span
          final clockFontSize = (maxH * 0.36).clamp(32.0, 72.0);

          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxW.clamp(100.0, 600.0),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Centered Double Clock: Hours on top, Minutes on bottom
                  Text(
                    hourStr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: clockFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                      height: 0.90,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    minStr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.92),
                      fontSize: clockFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                      height: 0.90,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Centered Date and Weather
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _formatDate(_currentTime),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.82),
                          fontSize: (clockFontSize * 0.22).clamp(12.0, 15.0),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (_weatherData != null)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WeatherPage(),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              WeatherIcon(
                                weatherCode: _weatherData!.weatherCode,
                                size: (clockFontSize * 0.26).clamp(15.0, 20.0),
                                isNight:
                                    _currentTime.hour < 6 ||
                                    _currentTime.hour >= 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_weatherData!.temperature.round()}°',
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: (clockFontSize * 0.23).clamp(12.5, 15.5),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
