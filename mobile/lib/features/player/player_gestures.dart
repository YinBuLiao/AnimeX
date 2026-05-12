import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';

enum _GestureKind { none, seek, brightness, volume }

class _Feedback {
  final IconData icon;
  final String label;
  final double? progress;
  const _Feedback({required this.icon, required this.label, this.progress});
}

/// Overlays a transparent gesture detector on top of the video. Handles:
///
/// - Horizontal drag anywhere → seek (left:rewind / right:forward)
/// - Vertical drag on left half → screen brightness
/// - Vertical drag on right half → media volume
/// - Double-tap on left/right → ±10s
/// - Long-press → temporary 2x playback rate
class PlayerGestureOverlay extends StatefulWidget {
  final Player player;
  final Duration duration;
  final Duration position;
  final VoidCallback? onTap;

  const PlayerGestureOverlay({
    super.key,
    required this.player,
    required this.duration,
    required this.position,
    this.onTap,
  });

  @override
  State<PlayerGestureOverlay> createState() => _PlayerGestureOverlayState();
}

class _PlayerGestureOverlayState extends State<PlayerGestureOverlay> {
  _GestureKind _kind = _GestureKind.none;
  _Feedback? _feedback;
  Timer? _hideTimer;

  // Seek state.
  Duration _seekStart = Duration.zero;
  Duration _seekTarget = Duration.zero;

  // Vertical drag baselines.
  double _startBrightness = 0.5;
  double _startVolume = 100.0;
  double _dragDy = 0.0;
  double _dragHeight = 1.0;
  bool _dragLeft = true;

  // Long-press 2x.
  double _savedRate = 1.0;
  bool _longPressActive = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showFeedback(_Feedback fb, {Duration ttl = const Duration(milliseconds: 700)}) {
    _hideTimer?.cancel();
    setState(() => _feedback = fb);
    _hideTimer = Timer(ttl, () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  // ─── Horizontal seek ───────────────────────────────────────────────────────

  void _onHorizDragStart(DragStartDetails _) {
    _kind = _GestureKind.seek;
    _seekStart = widget.position;
    _seekTarget = widget.position;
  }

  void _onHorizDragUpdate(DragUpdateDetails details) {
    if (_kind != _GestureKind.seek) return;
    final width = context.size?.width ?? 1.0;
    // Full screen swipe = 90 seconds.
    final deltaSec = (details.delta.dx / width) * 90.0;
    final newSec = (_seekTarget.inMilliseconds / 1000.0 + deltaSec)
        .clamp(0.0, widget.duration.inSeconds.toDouble())
        .toDouble();
    _seekTarget = Duration(milliseconds: (newSec * 1000).round());
    final diff = _seekTarget.inSeconds - _seekStart.inSeconds;
    _showFeedback(
      _Feedback(
        icon: diff >= 0 ? Icons.fast_forward : Icons.fast_rewind,
        label:
            '${_fmt(_seekTarget)} / ${_fmt(widget.duration)}  '
            '(${diff >= 0 ? '+' : ''}${diff}s)',
      ),
      ttl: const Duration(seconds: 5),
    );
  }

  void _onHorizDragEnd(DragEndDetails _) {
    if (_kind != _GestureKind.seek) return;
    widget.player.seek(_seekTarget);
    _kind = _GestureKind.none;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  // ─── Vertical brightness/volume ────────────────────────────────────────────

  Future<void> _onVertDragStart(DragStartDetails details) async {
    final size = context.size ?? Size.zero;
    _dragLeft = details.localPosition.dx < size.width / 2;
    _dragHeight = size.height;
    _dragDy = 0.0;
    if (_dragLeft) {
      _kind = _GestureKind.brightness;
      try {
        _startBrightness = await ScreenBrightness().application;
      } catch (_) {
        _startBrightness = 0.5;
      }
    } else {
      _kind = _GestureKind.volume;
      _startVolume = widget.player.state.volume;
    }
  }

  Future<void> _onVertDragUpdate(DragUpdateDetails details) async {
    if (_kind != _GestureKind.brightness && _kind != _GestureKind.volume) return;
    _dragDy += details.delta.dy;
    // Up = increase, full swipe height = full range.
    final delta = -_dragDy / _dragHeight;
    if (_kind == _GestureKind.brightness) {
      final v = (_startBrightness + delta).clamp(0.0, 1.0);
      try {
        await ScreenBrightness().setApplicationScreenBrightness(v);
      } catch (_) {}
      _showFeedback(_Feedback(
        icon: v < 0.05
            ? Icons.brightness_low
            : v > 0.66
                ? Icons.brightness_high
                : Icons.brightness_medium,
        label: '${(v * 100).round()}%',
        progress: v,
      ));
    } else {
      final v = (_startVolume + delta * 100.0).clamp(0.0, 100.0);
      await widget.player.setVolume(v);
      _showFeedback(_Feedback(
        icon: v == 0
            ? Icons.volume_off
            : v < 50
                ? Icons.volume_down
                : Icons.volume_up,
        label: '${v.round()}%',
        progress: v / 100.0,
      ));
    }
  }

  void _onVertDragEnd(DragEndDetails _) {
    _kind = _GestureKind.none;
  }

  // ─── Double-tap ±10s ───────────────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails details) {
    final size = context.size ?? Size.zero;
    final left = details.localPosition.dx < size.width / 2;
    final target = left
        ? Duration(
            seconds: (widget.position.inSeconds - 10).clamp(0, 1 << 30))
        : Duration(
            seconds: (widget.position.inSeconds + 10).clamp(
                0,
                widget.duration.inSeconds > 0
                    ? widget.duration.inSeconds
                    : 1 << 30));
    widget.player.seek(target);
    _showFeedback(_Feedback(
      icon: left ? Icons.replay_10 : Icons.forward_10,
      label: left ? '快退 10s' : '快进 10s',
    ));
  }

  // ─── Long-press 2x ─────────────────────────────────────────────────────────

  Future<void> _onLongPressStart(LongPressStartDetails _) async {
    if (_longPressActive) return;
    _longPressActive = true;
    _savedRate = widget.player.state.rate;
    await widget.player.setRate(2.0);
    _showFeedback(
      const _Feedback(icon: Icons.fast_forward, label: '2x 倍速播放中'),
      ttl: const Duration(seconds: 30),
    );
  }

  Future<void> _onLongPressEnd(LongPressEndDetails _) async {
    if (!_longPressActive) return;
    _longPressActive = false;
    await widget.player.setRate(_savedRate);
    _hideTimer?.cancel();
    setState(() => _feedback = null);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onTap,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: () {},
          onHorizontalDragStart: _onHorizDragStart,
          onHorizontalDragUpdate: _onHorizDragUpdate,
          onHorizontalDragEnd: _onHorizDragEnd,
          onVerticalDragStart: _onVertDragStart,
          onVerticalDragUpdate: _onVertDragUpdate,
          onVerticalDragEnd: _onVertDragEnd,
          onLongPressStart: _onLongPressStart,
          onLongPressEnd: _onLongPressEnd,
          child: const SizedBox.expand(),
        ),
        if (_feedback != null)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_feedback!.icon, color: Colors.white, size: 32),
                    const SizedBox(height: 6),
                    Text(_feedback!.label,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                    if (_feedback!.progress != null) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 120,
                        height: 3,
                        child: LinearProgressIndicator(
                          value: _feedback!.progress,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
