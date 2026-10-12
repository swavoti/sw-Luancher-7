import 'dart:math' as math;

import 'package:swavoti/services/weather_service.dart';

/// Ordered from least to most urgent. [weight] exposes the ordering for sorting.
enum WeatherAlertSeverity {
  info,
  minor,
  moderate,
  severe,
  extreme;

  /// Short human readable label shown on the warning chip.
  String get label {
    switch (this) {
      case WeatherAlertSeverity.info:
        return 'Info';
      case WeatherAlertSeverity.minor:
        return 'Minor';
      case WeatherAlertSeverity.moderate:
        return 'Moderate';
      case WeatherAlertSeverity.severe:
        return 'Severe';
      case WeatherAlertSeverity.extreme:
        return 'Extreme';
    }
  }

  /// Higher value == more urgent.
  int get weight => index;
}

/// The kind of hazard. Used by the UI to pick an icon / accent colour.
enum WeatherAlertType {
  thunderstorm,
  heavyRain,
  flooding,
  snow,
  ice,
  wind,
  heat,
  cold,
  fog,
  lowVisibility,
  uv,
  general,
}

/// A single weather warning derived from the forecast.
class WeatherAlert {
  final String id;
  final String title;
  final String description;
  final WeatherAlertType type;
  final WeatherAlertSeverity severity;

  const WeatherAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.severity,
  });
}

/// Derives a prioritised list of weather warnings from [FullWeatherData].
///
/// Open-Meteo's free forecast endpoint does not ship official government
/// alerts, so warnings are computed deterministically from the WMO weather
/// codes and current/daily metrics the app already fetches. This keeps the
/// feature working offline and unit-testable.
class WeatherAlerts {
  WeatherAlerts._();

  static List<WeatherAlert> evaluate(FullWeatherData data) {
    final alerts = <WeatherAlert>[];

    // Every weather code present across current + hourly + daily.
    final codes = <int>{
      data.currentWeatherCode,
      for (final h in data.hourly) h.weatherCode,
      for (final d in data.daily) d.weatherCode,
    };
    bool anyCode(bool Function(int) test) => codes.any(test);

    final maxDailyTemp = data.daily.isEmpty
        ? data.currentTemperature
        : data.daily.map((d) => d.tempMax).reduce(math.max);
    final minDailyTemp = data.daily.isEmpty
        ? data.currentTemperature
        : data.daily.map((d) => d.tempMin).reduce(math.min);
    final maxPrecip = data.daily.isEmpty
        ? data.hourly.fold<double>(
            0,
            (prev, h) => math.max(prev, h.precipitationProbability),
          )
        : data.daily
              .map((d) => d.precipitationProbabilityMax)
              .reduce(math.max);

    // ── Thunderstorm ────────────────────────────────────────────────────
    if (anyCode((c) => c >= 95 && c <= 99)) {
      final severe = anyCode((c) => c == 96 || c == 99);
      alerts.add(
        WeatherAlert(
          id: 'thunderstorm',
          type: WeatherAlertType.thunderstorm,
          severity: severe
              ? WeatherAlertSeverity.extreme
              : WeatherAlertSeverity.severe,
          title: severe
              ? 'Severe thunderstorm warning'
              : 'Thunderstorm warning',
          description: severe
              ? 'Severe thunderstorms with possible hail are forecast. Stay indoors, away from windows, and avoid open ground.'
              : 'Thunderstorms are expected in your area. Move indoors and stay clear of tall trees and open ground.',
        ),
      );
    }

    // ── Freezing rain / ice ─────────────────────────────────────────────
    if (anyCode((c) => c == 66 || c == 67)) {
      alerts.add(
        const WeatherAlert(
          id: 'freezing-rain',
          type: WeatherAlertType.ice,
          severity: WeatherAlertSeverity.severe,
          title: 'Freezing rain warning',
          description:
              'Freezing rain may create dangerous icy surfaces on roads and walkways. Avoid unnecessary travel.',
        ),
      );
    }

    // ── Snow ────────────────────────────────────────────────────────────
    if (anyCode((c) => (c >= 71 && c <= 77) || c == 85 || c == 86)) {
      final heavy = anyCode((c) => c == 75 || c == 86);
      alerts.add(
        WeatherAlert(
          id: 'snow',
          type: WeatherAlertType.snow,
          severity: heavy
              ? WeatherAlertSeverity.severe
              : WeatherAlertSeverity.moderate,
          title: heavy ? 'Heavy snow warning' : 'Snow warning',
          description: heavy
              ? 'Heavy snowfall is expected. Travel may become difficult — allow extra time and drive with caution.'
              : 'Snow is expected. Take care on roads and pavements and dress warmly.',
        ),
      );
    }

    // ── Heavy rain ──────────────────────────────────────────────────────
    final heavyRain = anyCode((c) => c == 65 || c == 82);
    if (heavyRain) {
      alerts.add(
        const WeatherAlert(
          id: 'heavy-rain',
          type: WeatherAlertType.heavyRain,
          severity: WeatherAlertSeverity.moderate,
          title: 'Heavy rain warning',
          description:
              'Heavy rain may cause localised flooding and reduced visibility. Drive carefully and avoid flooded areas.',
        ),
      );
    }

    // ── Fog / low visibility ────────────────────────────────────────────
    final foggy = anyCode((c) => c == 45 || c == 48);
    if (foggy || data.visibility < 2000) {
      final moderate = anyCode((c) => c == 48) || data.visibility < 1000;
      alerts.add(
        WeatherAlert(
          id: 'fog',
          type: data.visibility < 1000
              ? WeatherAlertType.lowVisibility
              : WeatherAlertType.fog,
          severity: moderate
              ? WeatherAlertSeverity.moderate
              : WeatherAlertSeverity.minor,
          title: 'Fog / low visibility',
          description: data.visibility < 1000
              ? 'Visibility is reduced to under 1 km. Slow down and use fog lights when driving.'
              : 'Fog patches may reduce visibility. Allow extra distance when travelling.',
        ),
      );
    }

    // ── Wind ────────────────────────────────────────────────────────────
    final gust = data.windGusts;
    final wind = data.windSpeed;
    if (gust >= 90 || wind >= 60) {
      alerts.add(
        WeatherAlert(
          id: 'wind-severe',
          type: WeatherAlertType.wind,
          severity: WeatherAlertSeverity.severe,
          title: 'Severe wind warning',
          description:
              'Damaging winds with gusts up to ${gust.round()} km/h are possible. Secure loose objects and avoid exposed areas.',
        ),
      );
    } else if (gust >= 60 || wind >= 40) {
      alerts.add(
        WeatherAlert(
          id: 'wind-high',
          type: WeatherAlertType.wind,
          severity: WeatherAlertSeverity.moderate,
          title: 'High wind warning',
          description:
              'Strong winds with gusts up to ${gust.round()} km/h are expected. Take care outdoors.',
        ),
      );
    } else if (gust >= 45 || wind >= 30) {
      alerts.add(
        WeatherAlert(
          id: 'wind-advisory',
          type: WeatherAlertType.wind,
          severity: WeatherAlertSeverity.minor,
          title: 'Wind advisory',
          description:
              'Breezy conditions with winds around ${wind.round()} km/h. Secure light items outdoors.',
        ),
      );
    }

    // ── Heat ────────────────────────────────────────────────────────────
    if (maxDailyTemp >= 30) {
      final severity = maxDailyTemp >= 40
          ? WeatherAlertSeverity.extreme
          : maxDailyTemp >= 35
          ? WeatherAlertSeverity.severe
          : WeatherAlertSeverity.moderate;
      alerts.add(
        WeatherAlert(
          id: 'heat',
          type: WeatherAlertType.heat,
          severity: severity,
          title: severity == WeatherAlertSeverity.moderate
              ? 'Heat advisory'
              : 'Extreme heat warning',
          description:
              'Highs of ${maxDailyTemp.round()}° are forecast. Stay hydrated, avoid the midday sun and check on vulnerable people.',
        ),
      );
    }

    // ── Cold ────────────────────────────────────────────────────────────
    if (minDailyTemp <= 0) {
      final severity = minDailyTemp <= -15
          ? WeatherAlertSeverity.extreme
          : minDailyTemp <= -5
          ? WeatherAlertSeverity.severe
          : WeatherAlertSeverity.moderate;
      alerts.add(
        WeatherAlert(
          id: 'cold',
          type: WeatherAlertType.cold,
          severity: severity,
          title: severity == WeatherAlertSeverity.moderate
              ? 'Frost advisory'
              : 'Extreme cold warning',
          description:
              'Lows of ${minDailyTemp.round()}° are forecast. Cover exposed skin, layer up and beware of icy surfaces.',
        ),
      );
    }

    // ── UV ──────────────────────────────────────────────────────────────
    if (data.uvIndex >= 6) {
      final severity = data.uvIndex >= 11
          ? WeatherAlertSeverity.severe
          : data.uvIndex >= 8
          ? WeatherAlertSeverity.moderate
          : WeatherAlertSeverity.minor;
      alerts.add(
        WeatherAlert(
          id: 'uv',
          type: WeatherAlertType.uv,
          severity: severity,
          title: 'UV advisory',
          description:
              'UV index is ${data.uvIndex.toStringAsFixed(1)}. Use sunscreen and sunglasses, and seek shade around midday.',
        ),
      );
    }

    // ── Rain likely (only when no rain warning already covers it) ────────
    if (maxPrecip >= 80 && !heavyRain && !anyCode((c) => c >= 51 && c <= 67)) {
      alerts.add(
        WeatherAlert(
          id: 'rain-likely',
          type: WeatherAlertType.heavyRain,
          severity: WeatherAlertSeverity.info,
          title: 'Rain likely',
          description:
              'Up to ${maxPrecip.round()}% chance of precipitation. Keep an umbrella handy.',
        ),
      );
    }

    alerts.sort((a, b) {
      final bySeverity = b.severity.weight.compareTo(a.severity.weight);
      if (bySeverity != 0) return bySeverity;
      return a.title.compareTo(b.title);
    });
    return alerts;
  }
}
