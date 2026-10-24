import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:swavoti/services/weather_service.dart';
import 'package:swavoti/widgets/weather_icon.dart';
import 'package:swavoti/screens/weather_page.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/widgets/now_playing_dropdown.dart';

class TimeWeatherWidget extends StatefulWidget {
  final VoidCallback onRemove;

  const TimeWeatherWidget({super.key, required this.onRemove});

  @override
  State<TimeWeatherWidget> createState() => _TimeWeatherWidgetState();
}

class _TimeWeatherWidgetState extends State<TimeWeatherWidget> {
  final GlobalKey _anchorKey = GlobalKey();
  late Timer _clockTimer;
  Timer? _realtimeMediaTicker;
  DateTime _currentTime = DateTime.now();
  WeatherData? _weatherData;
  MediaPlaybackInfo? _media;
  StreamSubscription<MediaPlaybackInfo?>? _mediaSubscription;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _mediaSubscription = LauncherService.mediaPlaybackStream.listen(
      (media) {
        if (!mounted) return;
        setState(() => _media = media);
        _updateMediaTicker();
      },
      onError: (Object error) {
        debugPrint('TimeWeatherWidget: media session stream failed: $error');
      },
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.minute != _currentTime.minute || now.hour != _currentTime.hour) {
        setState(() => _currentTime = now);
      }
    });

    // Defer local music check until after first frame so home startup is zero-jank
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        unawaited(LauncherService.getLocalMusicTracks());
      });
    });
  }

  void _updateMediaTicker() {
    final isPlaying = _media?.isPlaying == true;
    if (isPlaying && _realtimeMediaTicker == null) {
      _realtimeMediaTicker = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) {
          if (mounted && _media?.isPlaying == true) {
            setState(() {});
          }
        },
      );
    } else if (!isPlaying && _realtimeMediaTicker != null) {
      _realtimeMediaTicker?.cancel();
      _realtimeMediaTicker = null;
    }
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _realtimeMediaTicker?.cancel();
    _mediaSubscription?.cancel();
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

  void _openMusicDropdown() {
    final renderBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect anchorRect;
    if (renderBox != null && renderBox.hasSize) {
      final topLeft = renderBox.localToGlobal(Offset.zero);
      anchorRect = topLeft & renderBox.size;
    } else {
      anchorRect = const Rect.fromLTWH(16, 88, 320, 96);
    }
    showNowPlayingDropdown(
      context: context,
      anchorRect: anchorRect,
      initialMedia: _media,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasActiveMedia = _media != null && _media!.title.isNotEmpty;

    return Container(
      key: _anchorKey,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactWidth = constraints.maxWidth < 190;
          final clockFontSize = compactWidth
              ? 40.0
              : (hasActiveMedia ? 52.0 : 58.0);

          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth.isFinite
                    ? constraints.maxWidth.clamp(90.0, 600.0)
                    : 360.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_currentTime.hour}:${_currentTime.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: clockFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2.5,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _formatDate(_currentTime),
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.84),
                          fontSize: compactWidth ? 13 : 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
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
                                size: compactWidth ? 17 : 20,
                                isNight:
                                    _currentTime.hour < 6 ||
                                    _currentTime.hour >= 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_weatherData!.temperature.round()}°',
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: compactWidth ? 13.5 : 15.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (hasActiveMedia)
                    _CompactNowPlayingPill(
                      media: _media!,
                      compact: compactWidth,
                      onTap: _openMusicDropdown,
                    )
                  else
                    ValueListenableBuilder<List<LocalMusicTrack>>(
                      valueListenable: LauncherService.localTracksNotifier,
                      builder: (context, localTracks, _) {
                        return _CompactLocalMusicChip(
                          trackCount: localTracks.length,
                          compact: compactWidth,
                          onTap: _openMusicDropdown,
                        );
                      },
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

class _CompactNowPlayingPill extends StatelessWidget {
  final MediaPlaybackInfo media;
  final bool compact;
  final VoidCallback onTap;

  const _CompactNowPlayingPill({
    required this.media,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = media.durationMs;
    final livePos = media.livePositionMs();
    final progress = duration > 0
        ? (livePos / duration).clamp(0.0, 1.0).toDouble()
        : null;

    return Material(
      color: cs.surfaceContainer.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MediaArtworkThumb(bytes: media.albumArt, size: 22),
              const SizedBox(width: 7),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 105 : 165),
                  child: Text(
                    media.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: compact ? 22 : 30,
                child: M3EProgressIndicator.linearWavy(
                  value: progress ?? (media.isPlaying ? null : 0),
                  color: cs.primary,
                  trackColor: cs.primary.withValues(alpha: 0.18),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactLocalMusicChip extends StatelessWidget {
  final int trackCount;
  final bool compact;
  final VoidCallback onTap;

  const _CompactLocalMusicChip({
    required this.trackCount,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = trackCount > 0
        ? (compact ? '$trackCount songs' : 'Music • $trackCount local')
        : 'Music';

    return Material(
      color: cs.surfaceContainer.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note_rounded, size: 15, color: cs.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaArtworkThumb extends StatelessWidget {
  final Uint8List? bytes;
  final double size;

  const _MediaArtworkThumb({required this.bytes, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null || bytes!.isEmpty
            ? ColoredBox(
                color: cs.secondaryContainer,
                child: Icon(
                  Icons.music_note_rounded,
                  size: size * 0.56,
                  color: cs.onSecondaryContainer,
                ),
              )
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).ceil(),
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
