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
import 'package:animex_mobile/data/dtos/history_entry.dart';
import 'package:animex_mobile/features/player/cast_picker_sheet.dart';
import 'package:animex_mobile/features/player/player_args.dart';

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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _lastReportedSec = -1;
  DateTime _lastReportAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _seekedInitial = false;

  @override
  void initState() {
    super.initState();
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

    _open();
  }

  Future<void> _open() async {
    // Prefer the local file if a completed download exists on disk —
    // playback works offline and bypasses redirect/auth.
    final local = widget.args.localPath;
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
    await _player.open(Media(widget.args.url, httpHeaders: headers));
  }

  void _onPosition(Duration p) {
    if (!mounted) return;
    setState(() => _position = p);

    // Seek to initial position once playback has actually started (player
    // reports first non-zero position when buffering is done).
    if (!_seekedInitial &&
        widget.args.initialPositionSec > 5 &&
        _duration.inSeconds > 0) {
      _seekedInitial = true;
      _player.seek(Duration(seconds: widget.args.initialPositionSec));
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
      fileId: widget.args.fileId,
      url: widget.args.url,
      bangumiTitle: widget.args.bangumiTitle,
      episode: widget.args.episode,
      coverUrl: widget.args.coverUrl,
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

  @override
  void dispose() {
    _maybeReport(force: true);
    _positionSub?.cancel();
    _durationSub?.cancel();
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

  Future<void> _startCasting(CastManager manager, CastDevice device) async {
    await _player.pause();
    await manager.cast(
      device: device,
      url: widget.args.url,
      title: widget.args.title,
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
            Center(
              child: Video(
                controller: _videoController,
                controls: AdaptiveVideoControls,
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(
                  isCasting ? Icons.cast_connected : Icons.cast,
                  color: Colors.white,
                ),
                tooltip: '投屏',
                onPressed: _openCastPicker,
              ),
            ),
            Positioned(
              top: 12,
              left: 56,
              right: 56,
              child: Text(
                widget.args.title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
