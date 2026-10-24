import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:swavoti/services/launcher_service.dart';
import 'package:swavoti/services/lightweight_mode.dart';

enum _MusicSortOrder { recent, title, artist, size }

/// Opens the physics-driven floating Now Playing & Local Music dropdown
/// anchored directly below [anchorRect] on the home screen (never a bottom sheet).
Future<void> showNowPlayingDropdown({
  required BuildContext context,
  required Rect anchorRect,
  MediaPlaybackInfo? initialMedia,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context).push<void>(
    _SpringDropdownPopupRoute(
      anchorRect: anchorRect,
      initialMedia: initialMedia,
    ),
  );
}

class _SpringDropdownPopupRoute extends PopupRoute<void> {
  final Rect anchorRect;
  final MediaPlaybackInfo? initialMedia;

  _SpringDropdownPopupRoute({
    required this.anchorRect,
    required this.initialMedia,
  });

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.28);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss music dropdown';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _NowPlayingDropdownOverlay(
      anchorRect: anchorRect,
      routeAnimation: animation,
      initialMedia: initialMedia,
    );
  }
}

class _NowPlayingDropdownOverlay extends StatefulWidget {
  final Rect anchorRect;
  final Animation<double> routeAnimation;
  final MediaPlaybackInfo? initialMedia;

  const _NowPlayingDropdownOverlay({
    required this.anchorRect,
    required this.routeAnimation,
    required this.initialMedia,
  });

  @override
  State<_NowPlayingDropdownOverlay> createState() =>
      _NowPlayingDropdownOverlayState();
}

class _NowPlayingDropdownOverlayState extends State<_NowPlayingDropdownOverlay>
    with TickerProviderStateMixin {
  static const SpringDescription _morphSpring = SpringDescription(
    mass: 0.82,
    stiffness: 350.0,
    damping: 25.0,
  );
  static const SpringDescription _dragSpring = SpringDescription(
    mass: 0.75,
    stiffness: 420.0,
    damping: 28.0,
  );

  late final AnimationController _openSpringController;
  late final AnimationController _stageSpringController;
  late final AnimationController _dragSpringController;

  MediaPlaybackInfo? _media;
  StreamSubscription<MediaPlaybackInfo?>? _mediaSub;
  Timer? _livePositionTimer;

  bool _isExpandedViewAll = false;
  bool _hasAudioPermission = false;
  bool _loadingTracks = true;
  List<LocalMusicTrack> _allTracks = const <LocalMusicTrack>[];
  String _searchQuery = '';
  _MusicSortOrder _sortOrder = _MusicSortOrder.recent;
  final TextEditingController _searchController = TextEditingController();
  double? _seekPreviewMs;

  @override
  void initState() {
    super.initState();
    _media = widget.initialMedia;

    _openSpringController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    );
    _stageSpringController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    );
    _dragSpringController = AnimationController.unbounded(
      vsync: this,
      value: 0.0,
    );

    _openSpringController.animateWith(
      SpringSimulation(_morphSpring, 0.0, 1.0, 2.2),
    );

    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery && mounted) {
        setState(() => _searchQuery = q);
      }
    });

    _mediaSub = LauncherService.mediaPlaybackStream.listen((event) {
      if (!mounted) return;
      setState(() => _media = event);
      _syncRealtimeTicker();
    });
    _syncRealtimeTicker();
    unawaited(_initLocalMusic());
  }

  void _syncRealtimeTicker() {
    final playing = _media?.isPlaying == true;
    if (playing && _livePositionTimer == null) {
      _livePositionTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) {
          if (mounted && _media?.isPlaying == true && _seekPreviewMs == null) {
            setState(() {});
          }
        },
      );
    } else if (!playing && _livePositionTimer != null) {
      _livePositionTimer?.cancel();
      _livePositionTimer = null;
    }
  }

  Future<void> _initLocalMusic({bool forceRefresh = false}) async {
    final perm = await LauncherService.hasAudioPermission();
    if (!mounted) return;
    if (!perm) {
      setState(() {
        _hasAudioPermission = false;
        _loadingTracks = false;
      });
      return;
    }
    setState(() {
      _hasAudioPermission = true;
      _loadingTracks = true;
    });
    final tracks = await LauncherService.getLocalMusicTracks(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() {
      _allTracks = tracks;
      _loadingTracks = false;
    });
  }

  Future<void> _requestPermissionAndLoad() async {
    final granted = await LauncherService.requestAudioPermission();
    if (!mounted) return;
    if (granted) {
      await _initLocalMusic(forceRefresh: true);
    } else {
      setState(() => _hasAudioPermission = false);
    }
  }

  void _switchToStage(bool viewAll, {double initialVelocity = 0.0}) {
    if (_isExpandedViewAll == viewAll) return;
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isExpandedViewAll = viewAll);
    _stageSpringController.animateWith(
      SpringSimulation(
        _morphSpring,
        _stageSpringController.value,
        viewAll ? 1.0 : 0.0,
        initialVelocity,
      ),
    );
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.primaryDelta ?? 0.0;
    // Physical rubber-band damping
    final current = _dragSpringController.value;
    final resistance = 1.0 / (1.0 + (current.abs() / 180.0));
    _dragSpringController.value = current + dy * resistance;
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final vy = details.primaryVelocity ?? 0.0;
    final offset = _dragSpringController.value;

    // Flick down fast or pull far down: collapse Stage 2 -> Stage 1, or dismiss Stage 1
    if (offset > 95 || vy > 950) {
      if (_isExpandedViewAll) {
        _dragSpringController.animateWith(
          SpringSimulation(_dragSpring, offset, 0.0, vy * 0.002),
        );
        _switchToStage(false, initialVelocity: -1.8);
        return;
      } else {
        Navigator.of(context).maybePop();
        return;
      }
    }

    // Flick up on Stage 1: spring-expand into Stage 2 (View All)!
    if (!_isExpandedViewAll && (offset < -65 || vy < -800)) {
      _dragSpringController.animateWith(
        SpringSimulation(_dragSpring, offset, 0.0, 0.0),
      );
      _switchToStage(true, initialVelocity: 2.0);
      return;
    }

    // Spring back to resting position
    _dragSpringController.animateWith(
      SpringSimulation(_dragSpring, offset, 0.0, vy * 0.001),
    );
  }

  Future<void> _controlMedia(String action, {int? positionMs}) async {
    HapticFeedback.selectionClick();
    await LauncherService.controlMedia(action, positionMs: positionMs);
  }

  Future<void> _playLocalTrack(LocalMusicTrack track) async {
    HapticFeedback.lightImpact();
    final filtered = _filteredAndSortedTracks;
    final queueIds = filtered.map((t) => t.id).toList(growable: false);
    await LauncherService.playLocalTrack(track.id, queueIds: queueIds);
  }

  List<LocalMusicTrack> get _filteredAndSortedTracks {
    final q = _searchQuery.toLowerCase();
    Iterable<LocalMusicTrack> result = _allTracks;
    if (q.isNotEmpty) {
      result = result.where(
        (t) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q) ||
            t.album.toLowerCase().contains(q) ||
            t.format.toLowerCase().contains(q),
      );
    }
    final list = result.toList();
    switch (_sortOrder) {
      case _MusicSortOrder.recent:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case _MusicSortOrder.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _MusicSortOrder.artist:
        list.sort(
          (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        );
      case _MusicSortOrder.size:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    }
    return list;
  }

  String _formatMs(int ms) {
    final sec = (ms ~/ 1000).clamp(0, 359999);
    final m = sec ~/ 60;
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _livePositionTimer?.cancel();
    _mediaSub?.cancel();
    _searchController.dispose();
    _openSpringController.dispose();
    _stageSpringController.dispose();
    _dragSpringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final topSafe = mq.padding.top + 8.0;
    final bottomSafe = mq.padding.bottom + 14.0;
    final cs = Theme.of(context).colorScheme;

    // Anchor directly below TimeWeatherWidget in Stage 1, smoothly rising
    // toward comfortable top margin when expanding into Stage 2 (View All)
    final stage1Top = (widget.anchorRect.bottom + 8.0).clamp(
      topSafe,
      screenH * 0.34,
    );
    final stage2Top = (topSafe + 12.0).clamp(topSafe, stage1Top);

    final stage1Width = (screenW * 0.92).clamp(280.0, 520.0);
    final stage2Width = (screenW * 0.96).clamp(300.0, 560.0);

    final stage1MaxHeight = (screenH - stage1Top - bottomSafe).clamp(
      280.0,
      490.0,
    );
    final stage2Height = (screenH - stage2Top - bottomSafe - mq.viewInsets.bottom)
        .clamp(320.0, screenH * 0.80);

    return PopScope(
      canPop: !_isExpandedViewAll,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isExpandedViewAll) {
          _switchToStage(false);
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            widget.routeAnimation,
            _openSpringController,
            _stageSpringController,
            _dragSpringController,
          ]),
          builder: (context, _) {
            final routeT = widget.routeAnimation.value.clamp(0.0, 1.0);
            final openSpringT = _openSpringController.value;
            final morphT = _stageSpringController.value;
            final clampedMorphT = morphT.clamp(0.0, 1.0);
            final dragDy = _dragSpringController.value;

            final currentTop =
                lerpDouble(stage1Top, stage2Top, morphT)! + dragDy;
            final currentWidth = lerpDouble(
              stage1Width,
              stage2Width,
              morphT,
            )!.clamp(260.0, screenW - 8.0);

            final entranceScale =
                0.88 + 0.12 * (routeT * openSpringT).clamp(0.0, 1.06);
            final opacity = routeT.clamp(0.0, 1.0);

            Widget cardBody = Container(
              width: currentWidth,
              constraints: BoxConstraints(
                maxHeight: lerpDouble(
                  stage1MaxHeight,
                  stage2Height,
                  clampedMorphT,
                )!.clamp(260.0, screenH - topSafe - 12.0),
                minHeight: _isExpandedViewAll
                    ? stage2Height.clamp(280.0, screenH * 0.78)
                    : 0.0,
              ),
              decoration: BoxDecoration(
                color: LightweightMode.isEnabled
                    ? cs.surfaceContainerHigh
                    : cs.surfaceContainerHigh.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(
                  lerpDouble(26, 28, clampedMorphT)!,
                ),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.42),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.36),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _isExpandedViewAll
                  ? _buildStage2ExpandedLibrary(cs)
                  : _buildStage1CompactDropdown(cs),
            );

            if (!LightweightMode.isEnabled) {
              cardBody = ClipRRect(
                borderRadius: BorderRadius.circular(
                  lerpDouble(26, 28, clampedMorphT)!,
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: cardBody,
                ),
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Positioned(
                  top: currentTop,
                  left: (screenW - currentWidth) / 2.0,
                  width: currentWidth,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: entranceScale,
                      alignment: Alignment.topCenter,
                      child: cardBody,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDragPillHandle(ColorScheme cs) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: SizedBox(
        width: double.infinity,
        height: 22,
        child: Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  /// STAGE 1: Wide Anchored Dropdown with Real-Time Now Playing + Small-Height
  /// Local Music Cards + "View All" Switcher Button.
  Widget _buildStage1CompactDropdown(ColorScheme cs) {
    final media = _media;
    final hasActiveMedia = media != null && media.title.isNotEmpty;
    final previewTracks = _allTracks.take(3).toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragPillHandle(cs),
        Flexible(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasActiveMedia)
                  _buildNowPlayingHeroCard(media, cs)
                else
                  _buildIdleMediaBanner(cs),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 10),
                // Local Device Music Header + View All Pill
                Row(
                  children: [
                    Icon(
                      Icons.library_music_rounded,
                      size: 16,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _hasAudioPermission && _allTracks.isNotEmpty
                            ? 'LOCAL DEVICE MUSIC (${_allTracks.length})'
                            : 'LOCAL DEVICE MUSIC',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_hasAudioPermission)
                      FilledButton.tonalIcon(
                        onPressed: () => _switchToStage(true, initialVelocity: 1.8),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          minimumSize: const Size(0, 30),
                        ),
                        icon: const Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        label: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!_hasAudioPermission)
                  _buildPermissionCard(cs)
                else if (_loadingTracks)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  )
                else if (previewTracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No local music files found on device storage.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else ...[
                  for (final track in previewTracks)
                    _CompactLocalTrackCard(
                      track: track,
                      isPlayingThis:
                          media != null &&
                          media.isLocalPlayer &&
                          media.localTrackId == track.id &&
                          media.isPlaying,
                      onTap: () {
                        if (media != null &&
                            media.isLocalPlayer &&
                            media.localTrackId == track.id) {
                          _controlMedia('playPause');
                        } else {
                          _playLocalTrack(track);
                        }
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNowPlayingHeroCard(MediaPlaybackInfo media, ColorScheme cs) {
    final livePos = (_seekPreviewMs ?? media.livePositionMs().toDouble()).clamp(
      0.0,
      media.durationMs > 0 ? media.durationMs.toDouble() : 1.0,
    );
    final maxDur = media.durationMs > 0 ? media.durationMs.toDouble() : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: media.isLocalPlayer
                    ? () => _switchToStage(true, initialVelocity: 1.8)
                    : () => LauncherService.openMediaApp(media.packageName),
                child: _AlbumArtworkBox(bytes: media.albumArt, size: 62),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                media.isPlaying
                                    ? Icons.graphic_eq_rounded
                                    : Icons.pause_circle_outline_rounded,
                                size: 12,
                                color: cs.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                media.isLocalPlayer ? 'Device Audio' : 'Live Session',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                          tooltip: 'Audio output',
                          onPressed: LauncherService.showMediaOutputSwitcher,
                          icon: Icon(
                            Icons.speaker_group_outlined,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (!media.isLocalPlayer && media.packageName.isNotEmpty)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 30,
                            ),
                            tooltip: 'Open player app',
                            onPressed: () {
                              Navigator.of(context).maybePop();
                              LauncherService.openMediaApp(media.packageName);
                            },
                            icon: media.appIcon != null
                                ? _AlbumArtworkBox(
                                    bytes: media.appIcon,
                                    size: 20,
                                  )
                                : Icon(
                                    Icons.open_in_new_rounded,
                                    size: 17,
                                    color: cs.onSurfaceVariant,
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      media.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    if (media.artist.isNotEmpty)
                      Text(
                        media.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (media.durationMs > 0) ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: livePos,
                max: maxDur,
                onChanged: (v) => setState(() => _seekPreviewMs = v),
                onChangeEnd: (v) {
                  setState(() => _seekPreviewMs = null);
                  _controlMedia('seek', positionMs: v.round());
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatMs(livePos.round()),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    _formatMs(media.durationMs),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _controlMedia('previous'),
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 30,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: () => _controlMedia('playPause'),
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                child: Icon(
                  media.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () => _controlMedia('next'),
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 30,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIdleMediaBanner(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.music_note_rounded,
              color: cs.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nothing playing right now',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Tap any local track below to play directly on your home screen.',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_special_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Allow audio access to load and manage local songs from your device.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _requestPermissionAndLoad,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Allow', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// STAGE 2: Expanded In-Dropdown Local Music Manager (search, sort, play,
  /// queue next, share, delete from device, + sticky Now Playing mini-bar).
  Widget _buildStage2ExpandedLibrary(ColorScheme cs) {
    final tracks = _filteredAndSortedTracks;
    final media = _media;
    final hasActiveMedia = media != null && media.title.isNotEmpty;

    return Column(
      children: [
        _buildDragPillHandle(cs),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 6),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Back to Now Playing',
                onPressed: () => _switchToStage(false, initialVelocity: -1.8),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
              Expanded(
                child: Text(
                  'Local Music (${_allTracks.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
              PopupMenuButton<_MusicSortOrder>(
                tooltip: 'Sort tracks',
                initialValue: _sortOrder,
                onSelected: (order) => setState(() => _sortOrder = order),
                icon: Icon(
                  Icons.sort_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _MusicSortOrder.recent,
                    child: Text('Recently added'),
                  ),
                  PopupMenuItem(
                    value: _MusicSortOrder.title,
                    child: Text('Title (A–Z)'),
                  ),
                  PopupMenuItem(
                    value: _MusicSortOrder.artist,
                    child: Text('Artist (A–Z)'),
                  ),
                  PopupMenuItem(
                    value: _MusicSortOrder.size,
                    child: Text('File size'),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Rescan device music',
                onPressed: () => _initLocalMusic(forceRefresh: true),
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Search Bar Pill inside Popup
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: 13.5, color: cs.onSurface),
              decoration: InputDecoration(
                hintText: 'Search device songs, artists, formats...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close_rounded, size: 17),
                        onPressed: _searchController.clear,
                      )
                    : null,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        Divider(
          height: 1,
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
        Expanded(
          child: !_hasAudioPermission
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildPermissionCard(cs),
                  ),
                )
              : _loadingTracks
              ? const Center(child: CircularProgressIndicator())
              : tracks.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty
                        ? 'No audio files found on your device.'
                        : 'No tracks match "$_searchQuery".',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isCurrent =
                        media != null &&
                        media.isLocalPlayer &&
                        media.localTrackId == track.id;
                    return _ManageableTrackTile(
                      track: track,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && media.isPlaying,
                      onPlayPause: () {
                        if (isCurrent) {
                          _controlMedia('playPause');
                        } else {
                          _playLocalTrack(track);
                        }
                      },
                      onPlayNext: () async {
                        final ok = await LauncherService.queueLocalTrackNext(
                          track.id,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(milliseconds: 1400),
                            content: Text(
                              ok
                                  ? 'Playing "${track.title}" next'
                                  : 'Could not queue track',
                            ),
                          ),
                        );
                      },
                      onShare: () {
                        LauncherService.shareLocalTrack(
                          track.contentUri,
                          track.title,
                        );
                      },
                      onDelete: () async {
                        final deleted = await LauncherService.deleteLocalTrack(
                          track.id,
                          track.contentUri,
                        );
                        if (!mounted || !deleted) return;
                        setState(() {
                          _allTracks = _allTracks
                              .where((t) => t.id != track.id)
                              .toList(growable: false);
                        });
                      },
                    );
                  },
                ),
        ),
        if (hasActiveMedia) _buildStickyMiniPlayer(media, cs),
      ],
    );
  }

  Widget _buildStickyMiniPlayer(MediaPlaybackInfo media, ColorScheme cs) {
    final dur = media.durationMs;
    final livePos = media.livePositionMs();
    final progress = dur > 0 ? (livePos / dur).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dur > 0)
            LinearProgressIndicator(
              value: progress,
              minHeight: 2.2,
              backgroundColor: cs.primary.withValues(alpha: 0.15),
              color: cs.primary,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _switchToStage(false, initialVelocity: -1.8),
                  child: _AlbumArtworkBox(bytes: media.albumArt, size: 38),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _switchToStage(false, initialVelocity: -1.8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          media.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          media.artist.isNotEmpty
                              ? '${media.artist} • ${_formatMs(livePos)}'
                              : _formatMs(livePos),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _controlMedia('previous'),
                  icon: const Icon(Icons.skip_previous_rounded, size: 22),
                ),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _controlMedia('playPause'),
                  icon: Icon(
                    media.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _controlMedia('next'),
                  icon: const Icon(Icons.skip_next_rounded, size: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small-height (`46dp`) music card used in Stage 1 compact dropdown.
class _CompactLocalTrackCard extends StatelessWidget {
  final LocalMusicTrack track;
  final bool isPlayingThis;
  final VoidCallback onTap;

  const _CompactLocalTrackCard({
    required this.track,
    required this.isPlayingThis,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isPlayingThis
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _LocalTrackArtwork(
                    albumId: track.albumId,
                    trackId: track.id,
                    size: 32,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '${track.title}  •  ${track.durationLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isPlayingThis
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isPlayingThis
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                    color: isPlayingThis ? cs.primary : cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManageableTrackTile extends StatelessWidget {
  final LocalMusicTrack track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onPlayNext;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _ManageableTrackTile({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onPlayNext,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: isCurrent
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPlayPause,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                _LocalTrackArtwork(
                  albumId: track.albumId,
                  trackId: track.id,
                  size: 42,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isCurrent
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isCurrent ? cs.primary : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${track.artist} • ${track.durationLabel} • ${track.sizeLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onPlayPause,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 26,
                    color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 19,
                    color: cs.onSurfaceVariant,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case 'play':
                        onPlayPause();
                      case 'next':
                        onPlayNext();
                      case 'share':
                        onShare();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'play',
                      child: Row(
                        children: [
                          Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Text(isPlaying ? 'Pause' : 'Play now'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'next',
                      child: Row(
                        children: [
                          Icon(Icons.queue_music_rounded, size: 19),
                          SizedBox(width: 10),
                          Text('Play next'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_outlined, size: 19),
                          SizedBox(width: 10),
                          Text('Share audio file'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: cs.error,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Delete from device',
                            style: TextStyle(color: cs.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalTrackArtwork extends StatelessWidget {
  final int albumId;
  final int trackId;
  final double size;

  const _LocalTrackArtwork({
    required this.albumId,
    required this.trackId,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cached = LauncherService.getCachedLocalAlbumArt(albumId, trackId);
    if (cached != null) {
      return _AlbumArtworkBox(bytes: cached, size: size);
    }
    return FutureBuilder<Uint8List?>(
      future: LauncherService.getLocalAlbumArt(albumId, trackId),
      builder: (context, snapshot) {
        return _AlbumArtworkBox(bytes: snapshot.data, size: size);
      },
    );
  }
}

class _AlbumArtworkBox extends StatelessWidget {
  final Uint8List? bytes;
  final double size;

  const _AlbumArtworkBox({required this.bytes, required this.size});

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
                  size: size * 0.54,
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
