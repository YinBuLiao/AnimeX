import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/history_entry.dart';
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
    final session =
        await ref.read(sessionStoreProvider).load();
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

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
      ),
    );
  }
}
