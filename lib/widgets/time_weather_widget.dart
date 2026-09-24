import 'dart:async';
import 'dart:ui';
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
  late Timer _timer;
  DateTime _currentTime = DateTime.now();
  WeatherData? _weatherData;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
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
    return GestureDetector(
      onLongPress: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Time & Weather?'),
            content: const Text(
              'You can re-enable this later in Home Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onRemove();
                },
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Time (stacked on top)
            Text(
              '${_currentTime.hour}:${_currentTime.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 64,
                fontWeight: FontWeight.w900,
                letterSpacing: -3,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            // Date and Weather (stacked under time, next to each other)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _formatDate(_currentTime),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                if (_weatherData != null) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WeatherPage()),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WeatherIcon(
                          weatherCode: _weatherData!.weatherCode,
                          size: 20,
                          isNight: _currentTime.hour < 6 || _currentTime.hour >= 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_weatherData!.temperature.round()}°',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),

    );
  }
}
