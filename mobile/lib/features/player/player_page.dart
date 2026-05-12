import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/cast/cast_device.dart';
import 'package:animex_mobile/core/cast/cast_manager.dart';
import 'package:animex_mobile/core/pip/pip_controller.dart';
import 'package:animex_mobile/data/dtos/history_entry.dart';
import 'package:animex_mobile/features/player/cast_picker_sheet.dart';
import 'package:animex_mobile/features/player/episode_picker_sheet.dart';
import 'package:animex_mobile/features/player/player_args.dart';
import 'package:animex_mobile/features/player/player_gestures.dart';

class PlayerPage extends ConsumerStatefulWidget {
  final PlayerArgs args;
  const PlayerPage({super.key, required this.args});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player;
  late final VideoController _videoController;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<double>? _rateSub;
  double _rate = 1.0;
  Timer? _sleepTimer;
  bool _sleepEndOfEpisode = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  int _lastReportedSec = -1;
  DateTime _lastReportAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _seekedInitial = false;
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  /// Args of the currently loaded media. Mutable so auto-advance can swap
  /// the source in place without growing the router stack.
  late PlayerArgs _args;

  @override
  void initState() {
    super.initState();
    _args = widget.args;
    _player = Player();
    _videoController = VideoController(_player);

    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();

    _positionSub = _player.stream.position.listen(_onPosition);
    _durationSub = _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playingSub = _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
    _completedSub = _player.stream.completed.listen((done) {
      if (done) _onPlaybackEnded();
    });
    _rateSub = _player.stream.rate.listen((r) {
      if (mounted) setState(() => _rate = r);
    });
    _resetControlsTimer();

    // Auto-enter PiP on home button while a video is loaded. No-op on iOS.
    PipController.setEnabled(enabled: true);

    _open();
  }

  Future<void> _onPlaybackEnded() async {
    if (!mounted) return;
    _maybeReport(force: true);
    // Sleep timer "end of episode" — pause instead of advancing.
    if (_sleepEndOfEpisode) {
      setState(() => _sleepEndOfEpisode = false);
      await _player.pause();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本集结束，已停止播放')),
        );
      }
      return;
    }
    final autoPlay = ref.read(appPreferencesProvider).autoPlayNext;
    final next = _args.next;
    if (!autoPlay || next == null) return;
    setState(() {
      _args = next.copyWithReset();
      _position = Duration.zero;
      _duration = Duration.zero;
      _seekedInitial = false;
      _controlsVisible = true;
    });
    _resetControlsTimer();
    await _open();
  }

  Future<void> _open() async {
    // Apply default-volume preference once per load.
    final preferredVolume = ref.read(appPreferencesProvider).defaultVolume;
    await _player.setVolume(preferredVolume);

    // Prefer the local file if a completed download exists on disk —
    // playback works offline and bypasses redirect/auth.
    final local = _args.localPath;
    if (local != null && local.isNotEmpty) {
      try {
        if (await File(local).exists()) {
          await _player.open(Media(local));
          return;
        }
      } catch (_) {
        // Fall through to network playback.
      }
    }
    final session = await ref.read(sessionStoreProvider).load();
    final headers = <String, String>{};
    if (session != null && session.token.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${session.token}';
    }
    await _player.open(Media(_args.url, httpHeaders: headers));
  }

  void _onPosition(Duration p) {
    if (!mounted) return;
    setState(() => _position = p);

    // Seek to initial position once playback has actually started (player
    // reports first non-zero position when buffering is done).
    if (!_seekedInitial &&
        _args.initialPositionSec > 5 &&
        _duration.inSeconds > 0) {
      _seekedInitial = true;
      _player.seek(Duration(seconds: _args.initialPositionSec));
    }

    _maybeReport();
  }

  void _maybeReport({bool force = false}) {
    final sec = _position.inSeconds;
    final now = DateTime.now();
    final elapsed = now.difference(_lastReportAt);
    if (!force && (sec == _lastReportedSec || elapsed.inSeconds < 10)) return;
    if (_duration.inSeconds == 0) return;
    _lastReportedSec = sec;
    _lastReportAt = now;
    _reportHistory();
  }

  Future<void> _reportHistory() async {
    final repo = await ref.read(historyRepositoryProvider.future);
    final entry = HistoryEntry(
      fileId: _args.fileId,
      url: _args.url,
      bangumiTitle: _args.bangumiTitle,
      episode: _args.episode,
      coverUrl: _args.coverUrl,
      positionSec: _position.inSeconds,
      durationSec: _duration.inSeconds,
      updatedAt: 0,
    );
    try {
      await repo.report(entry);
    } catch (_) {
      // History reporting is best-effort; ignore errors.
    }
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (mounted && _controlsVisible) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _resetControlsTimer();
  }

  @override
  void dispose() {
    _maybeReport(force: true);
    PipController.setEnabled(enabled: false);
    _controlsTimer?.cancel();
    _sleepTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _rateSub?.cancel();
    _player.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _openCastPicker() async {
    final manager = ref.read(castManagerProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CastPickerSheet(
        onPick: (device) => _startCasting(manager, device),
      ),
    );
  }

  Future<void> _openEpisodePicker() async {
    if (_args.playlist.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => EpisodePickerSheet(
        playlist: _args.playlist,
        currentIndex: _args.currentIndex,
        onPick: _jumpToEpisode,
      ),
    );
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndOfEpisode = false;
  }

  Future<void> _pickSleepTimer() async {
    const minuteOptions = <int>[15, 30, 45, 60];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('睡眠定时',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            if (_sleepTimer != null || _sleepEndOfEpisode)
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: const Text('取消定时'),
                onTap: () => Navigator.of(context).pop('off'),
              ),
            for (final m in minuteOptions)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text('$m 分钟后'),
                onTap: () => Navigator.of(context).pop('m:$m'),
              ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('本集结束后'),
              onTap: () => Navigator.of(context).pop('episode'),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == 'off') {
      setState(_cancelSleepTimer);
      return;
    }
    if (picked == 'episode') {
      setState(() {
        _cancelSleepTimer();
        _sleepEndOfEpisode = true;
      });
      return;
    }
    final mins = int.parse(picked.substring(2));
    setState(() {
      _cancelSleepTimer();
      _sleepTimer = Timer(Duration(minutes: mins), () {
        _player.pause();
        if (mounted) {
          setState(() {
            _sleepTimer = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('睡眠定时已到，已暂停播放')),
          );
        }
      });
    });
  }

  bool get _isSleepArmed => _sleepTimer != null || _sleepEndOfEpisode;

  Future<void> _pickRate() async {
    const options = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('播放速度',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            for (final v in options)
              ListTile(
                leading: Icon(
                  (v - _rate).abs() < 0.01
                      ? Icons.check_circle
                      : Icons.speed_outlined,
                  color: (v - _rate).abs() < 0.01
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text('${v}x'),
                onTap: () => Navigator.of(context).pop(v),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await _player.setRate(picked);
    }
  }

  Future<void> _jumpToEpisode(int newIndex) async {
    if (newIndex < 0 || newIndex >= _args.playlist.length) return;
    _maybeReport(force: true);
    final next = _args.playlist[newIndex].copyWithReset();
    setState(() {
      _args = next;
      _position = Duration.zero;
      _duration = Duration.zero;
      _seekedInitial = false;
      _controlsVisible = true;
    });
    _resetControlsTimer();
    await _open();
  }

  Future<void> _startCasting(CastManager manager, CastDevice device) async {
    await _player.pause();
    await manager.cast(
      device: device,
      url: _args.url,
      title: _args.title,
      position: _position,
    );
  }

  Future<void> _stopCasting() async {
    final manager = ref.read(castManagerProvider);
    await manager.stop();
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castManagerProvider);
    final isCasting = cast.activeDevice != null &&
        cast.status != CastSessionStatus.idle &&
        cast.status != CastSessionStatus.error;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Video(
                controller: _videoController,
                controls: NoVideoControls,
              ),
            ),
            // Custom gestures: seek / brightness / volume / ±10s / 2x.
            Positioned.fill(
              child: PlayerGestureOverlay(
                player: _player,
                position: _position,
                duration: _duration,
                onTap: _toggleControls,
              ),
            ),
            // Top + bottom chrome auto-hide after 3s of inactivity.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _controlsVisible ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _PlayerChrome(
                  title: _args.title,
                  position: _position,
                  duration: _duration,
                  playing: _playing,
                  isCasting: isCasting,
                  onClose: () => Navigator.of(context).pop(),
                  onTogglePlay: () {
                    _playing ? _player.pause() : _player.play();
                    _resetControlsTimer();
                  },
                  onSeek: (d) {
                    _player.seek(d);
                    _resetControlsTimer();
                  },
                  onPip: () => PipController.enterNow(),
                  onCast: _openCastPicker,
                  onEpisodes:
                      _args.playlist.length > 1 ? _openEpisodePicker : null,
                  rate: _rate,
                  onPickRate: _pickRate,
                  sleepArmed: _isSleepArmed,
                  onPickSleep: _pickSleepTimer,
                ),
              ),
            ),
            if (isCasting)
              Positioned.fill(
                child: _CastOverlay(
                  device: cast.activeDevice!,
                  status: cast.status,
                  errorMessage: cast.errorMessage,
                  onPause: cast.pause,
                  onResume: cast.resume,
                  onStop: _stopCasting,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CastOverlay extends StatelessWidget {
  final CastDevice device;
  final CastSessionStatus status;
  final String? errorMessage;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;

  const _CastOverlay({
    required this.device,
    required this.status,
    required this.errorMessage,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = status == CastSessionStatus.playing;
    final isConnecting = status == CastSessionStatus.connecting;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isConnecting ? Icons.cast : Icons.cast_connected,
              color: Colors.white70,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isConnecting ? '正在连接…' : '正在投屏到',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              device.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isConnecting)
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 44,
                    ),
                    onPressed: isPlaying ? onPause : onResume,
                  ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.stop_circle_outlined,
                      color: Colors.white),
                  label: const Text('结束投屏',
                      style: TextStyle(color: Colors.white)),
                  onPressed: onStop,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerChrome extends StatelessWidget {
  final String title;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool isCasting;
  final VoidCallback onClose;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPip;
  final VoidCallback onCast;
  final VoidCallback? onEpisodes;
  final double rate;
  final VoidCallback onPickRate;
  final bool sleepArmed;
  final VoidCallback onPickSleep;

  const _PlayerChrome({
    required this.title,
    required this.position,
    required this.duration,
    required this.playing,
    required this.isCasting,
    required this.onClose,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onPip,
    required this.onCast,
    required this.rate,
    required this.onPickRate,
    required this.sleepArmed,
    required this.onPickSleep,
    this.onEpisodes,
  });

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    return Column(
      children: [
        // Top bar.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onClose,
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onEpisodes != null)
                IconButton(
                  icon: const Icon(Icons.video_library_outlined,
                      color: Colors.white),
                  tooltip: '剧集',
                  onPressed: onEpisodes,
                ),
              IconButton(
                icon: Icon(
                  sleepArmed ? Icons.bedtime : Icons.bedtime_outlined,
                  color: Colors.white,
                ),
                tooltip: '睡眠定时',
                onPressed: onPickSleep,
              ),
              IconButton(
                icon: const Icon(Icons.picture_in_picture_alt,
                    color: Colors.white),
                tooltip: '画中画',
                onPressed: onPip,
              ),
              IconButton(
                icon: Icon(
                  isCasting ? Icons.cast_connected : Icons.cast,
                  color: Colors.white,
                ),
                tooltip: '投屏',
                onPressed: onCast,
              ),
            ],
          ),
        ),
        const Spacer(),
        // Bottom bar.
        Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: onTogglePlay,
                  ),
                  Text(
                    _fmt(position),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14),
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: (v) {
                          if (duration.inMilliseconds > 0) {
                            onSeek(Duration(
                                milliseconds:
                                    (v * duration.inMilliseconds).round()));
                          }
                        },
                      ),
                    ),
                  ),
                  Text(
                    _fmt(duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: onPickRate,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    child: Text(
                      rate == 1.0
                          ? '倍速'
                          : '${rate.toStringAsFixed(rate == rate.toInt() ? 0 : 2)}x',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
