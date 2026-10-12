import 'package:flutter_test/flutter_test.dart';
import 'package:swavoti/services/weather_alerts.dart';
import 'package:swavoti/services/weather_service.dart';

FullWeatherData _data({
  int currentCode = 0,
  double currentTemp = 20,
  double uvIndex = 1,
  double windSpeed = 5,
  double windGusts = 8,
  double visibility = 10000,
  List<DailyForecast>? daily,
  List<HourlyForecast>? hourly,
}) {
  return FullWeatherData(
    currentTemperature: currentTemp,
    currentWeatherCode: currentCode,
    feelsLikeTemperature: currentTemp,
    relativeHumidity: 50,
    uvIndex: uvIndex,
    windSpeed: windSpeed,
    windDirection: 90,
    windGusts: windGusts,
    pressure: 1013,
    visibility: visibility,
    updatedAt: DateTime(2026, 1, 1, 12),
    locationName: 'Test',
    country: 'TC',
    hourly: hourly ?? const <HourlyForecast>[],
    daily: daily ?? const <DailyForecast>[],
  );
}

void main() {
  group('WeatherAlerts.evaluate', () {
    test('returns no warnings for calm clear weather', () {
      expect(WeatherAlerts.evaluate(_data()), isEmpty);
    });

    test('flags thunderstorms as severe', () {
      final storm = WeatherAlerts.evaluate(
        _data(currentCode: 95),
      ).firstWhere((a) => a.id == 'thunderstorm');
      expect(storm.severity, WeatherAlertSeverity.severe);
      expect(storm.type, WeatherAlertType.thunderstorm);
    });

    test('flags severe thunderstorm code as extreme', () {
      final storm = WeatherAlerts.evaluate(
        _data(currentCode: 96),
      ).firstWhere((a) => a.id == 'thunderstorm');
      expect(storm.severity, WeatherAlertSeverity.extreme);
    });

    test('flags high wind', () {
      final alerts = WeatherAlerts.evaluate(
        _data(windSpeed: 42, windGusts: 65),
      );
      expect(alerts.any((a) => a.type == WeatherAlertType.wind), isTrue);
    });

    test('flags extreme heat from the daily maximum', () {
      final heat = WeatherAlerts.evaluate(
        _data(
          daily: [
            DailyForecast(
              date: DateTime(2026, 1, 1),
              tempMax: 41,
              tempMin: 28,
              weatherCode: 0,
              precipitationProbabilityMax: 0,
            ),
          ],
        ),
      ).firstWhere((a) => a.id == 'heat');
      expect(heat.severity, WeatherAlertSeverity.extreme);
    });

    test('flags low visibility as a warning', () {
      final alerts = WeatherAlerts.evaluate(_data(visibility: 600));
      expect(alerts.any((a) => a.id == 'fog'), isTrue);
    });

    test('sorts warnings most urgent first', () {
      final alerts = WeatherAlerts.evaluate(_data(currentCode: 95, uvIndex: 6.2));
      expect(alerts.length, greaterThan(1));
      expect(
        alerts.first.severity.weight,
        greaterThanOrEqualTo(alerts.last.severity.weight),
      );
    });
  });
}
