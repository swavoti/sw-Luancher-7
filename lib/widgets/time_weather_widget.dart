import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:swavoti/services/weather_service.dart';
import 'package:swavoti/widgets/weather_icon.dart';
import 'package:swavoti/screens/weather_page.dart';
import 'package:swavoti/services/launcher_service.dart';

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
  MediaPlaybackInfo? _media;
  StreamSubscription<MediaPlaybackInfo?>? _mediaSubscription;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _mediaSubscription = LauncherService.mediaPlaybackStream.listen(
      (media) {
        if (mounted) setState(() => _media = media);
      },
      onError: (Object error) {
        debugPrint('TimeWeatherWidget: media session stream failed: $error');
      },
    );
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
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

  Future<void> _showMediaPlayer() {
    final media = _media;
    if (media == null) return Future<void>.value();
    FocusManager.instance.primaryFocus?.unfocus();
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surfaceContainerHigh,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 500),
        reverseDuration: Duration(milliseconds: 400),
        curve: Curves.easeInOutCubicEmphasized,
        reverseCurve: Curves.easeInOutCubicEmphasized,
      ),
      builder: (context) => _ExpandedMusicPlayer(initialMedia: media),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        showDialog(
          context: context,
          builder: (context) {
            final errorColor = Theme.of(context).colorScheme.error;
            return AlertDialog(
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
                  child: Text('Remove', style: TextStyle(color: errorColor)),
                ),
              ],
            );
          },
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: _media == null ? 8 : 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Time (stacked on top)
            Text(
              '${_currentTime.hour}:${_currentTime.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: _media == null ? 64 : 56,
                fontWeight: FontWeight.w900,
                letterSpacing: -3,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            // Date and Weather (stacked under time, next to each other)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _formatDate(_currentTime),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.8),
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
                          isNight:
                              _currentTime.hour < 6 || _currentTime.hour >= 20,
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
            if (_media != null && _media!.title.isNotEmpty) ...[
              const SizedBox(height: 6),
              _CompactNowPlaying(media: _media!, onTap: _showMediaPlayer),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactNowPlaying extends StatelessWidget {
  final MediaPlaybackInfo media;
  final VoidCallback onTap;

  const _CompactNowPlaying({required this.media, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = media.durationMs;
    final progress = duration > 0
        ? (media.positionMs / duration).clamp(0.0, 1.0).toDouble()
        : null;
    return Material(
      color: cs.surfaceContainer.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MediaArtwork(bytes: media.albumArt, size: 24),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 30,
                child: M3EProgressIndicator.linearWavy(
                  value: progress ?? (media.isPlaying ? null : 0),
                  color: cs.primary,
                  trackColor: cs.primary.withValues(alpha: 0.18),
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedMusicPlayer extends StatefulWidget {
  final MediaPlaybackInfo initialMedia;

  const _ExpandedMusicPlayer({required this.initialMedia});

  @override
  State<_ExpandedMusicPlayer> createState() => _ExpandedMusicPlayerState();
}

class _ExpandedMusicPlayerState extends State<_ExpandedMusicPlayer> {
  late MediaPlaybackInfo _media = widget.initialMedia;
  StreamSubscription<MediaPlaybackInfo?>? _subscription;
  double? _seekPreview;

  @override
  void initState() {
    super.initState();
    _subscription = LauncherService.mediaPlaybackStream.listen(
      (media) {
        if (mounted && media != null) setState(() => _media = media);
      },
      onError: (Object error) {
        debugPrint('ExpandedMusicPlayer: media stream failed: $error');
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _control(String action, {int? positionMs}) async {
    try {
      final success = await LauncherService.controlMedia(
        action,
        positionMs: positionMs,
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The media player is not responding.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not control media playback: $error')),
      );
    }
  }

  String _timeLabel(int milliseconds) {
    final seconds = (milliseconds ~/ 1000).clamp(0, 359999);
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxPosition = _media.durationMs > 0 ? _media.durationMs : 1;
    final position = (_seekPreview ?? _media.positionMs.toDouble())
        .clamp(0, maxPosition.toDouble())
        .toDouble();
    final progress = _media.durationMs > 0
        ? position / _media.durationMs
        : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Now playing',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Audio output',
                onPressed: () async {
                  try {
                    await LauncherService.showMediaOutputSwitcher();
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not open audio output: $error'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.speaker_group_rounded),
              ),
              if (_media.appIcon != null)
                IconButton(
                  tooltip: 'Open music app',
                  onPressed: () async {
                    try {
                      final opened = await LauncherService.openMediaApp(
                        _media.packageName,
                      );
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open the music app.'),
                          ),
                        );
                      }
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Could not open music app: $error'),
                        ),
                      );
                    }
                  },
                  icon: _MediaArtwork(bytes: _media.appIcon, size: 28),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Center(child: _MediaArtwork(bytes: _media.albumArt, size: 184)),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _media.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (_media.artist.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _media.artist,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 14),
          if (_media.durationMs > 0)
            Slider(
              value: position,
              max: maxPosition.toDouble(),
              onChanged: (value) => setState(() => _seekPreview = value),
              onChangeEnd: (value) {
                setState(() => _seekPreview = null);
                _control('seek', positionMs: value.round());
              },
            )
          else
            M3EProgressIndicator.linearWavy(
              value: progress ?? (_media.isPlaying ? null : 0),
              color: cs.primary,
              trackColor: cs.primary.withValues(alpha: 0.18),
            ),
          if (_media.durationMs > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_timeLabel(position.round())),
                  Text(_timeLabel(_media.durationMs)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous track',
                onPressed: () => _control('previous'),
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 36,
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: () => _control('playPause'),
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(18),
                ),
                child: Icon(
                  _media.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: 'Next track',
                onPressed: () => _control('next'),
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 36,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaArtwork extends StatelessWidget {
  final Uint8List? bytes;
  final double size;

  const _MediaArtwork({required this.bytes, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.16),
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null
            ? ColoredBox(
                color: cs.secondaryContainer,
                child: Icon(
                  Icons.music_note_rounded,
                  size: size * 0.55,
                  color: cs.onSecondaryContainer,
                ),
              )
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                cacheWidth: size.ceil() * 2,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
