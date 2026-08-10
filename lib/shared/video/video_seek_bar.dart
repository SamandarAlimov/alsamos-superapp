import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoSeekBar extends StatefulWidget {
  final VideoPlayerController controller;
  final List<double>? heatmapData;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;
  final double barHeight;
  final double expandedBarHeight;

  const VideoSeekBar({
    super.key,
    required this.controller,
    this.heatmapData,
    this.onDragStart,
    this.onDragEnd,
    this.activeColor = Colors.white,
    this.bufferedColor = const Color(0x55FFFFFF),
    this.inactiveColor = const Color(0x33FFFFFF),
    this.barHeight = 3.0,
    this.expandedBarHeight = 5.0,
  });

  @override
  State<VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<VideoSeekBar> {
  bool _hovering = false;
  bool _dragging = false;
  double _hoverFraction = 0;
  double _dragFraction = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  @override
  void didUpdateWidget(covariant VideoSeekBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onUpdate);
      widget.controller.addListener(_onUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  double get _progress {
    final value = widget.controller.value;
    if (!value.isInitialized || value.duration.inMilliseconds <= 0) return 0;
    return (value.position.inMilliseconds / value.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  double get _buffered {
    final value = widget.controller.value;
    if (!value.isInitialized || value.duration.inMilliseconds <= 0) return 0;
    if (value.buffered.isEmpty) return 0;
    final end = value.buffered.last.end.inMilliseconds;
    return (end / value.duration.inMilliseconds).clamp(0.0, 1.0);
  }

  void _onHover(PointerHoverEvent event, BoxConstraints constraints) {
    final fraction =
        (event.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    setState(() {
      _hovering = true;
      _hoverFraction = fraction;
    });
  }

  void _onHoverExit(PointerExitEvent _) {
    setState(() => _hovering = false);
  }

  void _onDragStart(DragStartDetails details, BoxConstraints constraints) {
    final fraction =
        (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    setState(() {
      _dragging = true;
      _dragFraction = fraction;
    });
    widget.onDragStart?.call();
  }

  void _onDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final fraction =
        (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    setState(() => _dragFraction = fraction);
    final duration = widget.controller.value.duration;
    widget.controller.seekTo(duration * fraction);
  }

  void _onDragEnd(DragEndDetails _) {
    setState(() => _dragging = false);
    widget.onDragEnd?.call();
  }

  void _onTapUp(TapUpDetails details, BoxConstraints constraints) {
    final fraction =
        (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final duration = widget.controller.value.duration;
    widget.controller.seekTo(duration * fraction);
  }

  String _formatTime(double fraction) {
    final duration = widget.controller.value.duration;
    final ms = (duration.inMilliseconds * fraction).round();
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isExpanded = _hovering || _dragging;
    final currentHeight =
        isExpanded ? widget.expandedBarHeight : widget.barHeight;
    final displayFraction = _dragging ? _dragFraction : _progress;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hover time preview tooltip
            if (_hovering && !_dragging)
              _buildHoverPreview(width),

            // Seek bar
            MouseRegion(
              onHover: (e) => _onHover(e, constraints),
              onExit: _onHoverExit,
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onHorizontalDragStart: (d) => _onDragStart(d, constraints),
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, constraints),
                onHorizontalDragEnd: _onDragEnd,
                onTapUp: (d) => _onTapUp(d, constraints),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  height: 24,
                  width: width,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      height: currentHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(currentHeight / 2),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Background / heatmap
                            if (widget.heatmapData != null &&
                                widget.heatmapData!.isNotEmpty)
                              CustomPaint(
                                painter: _HeatmapPainter(
                                  data: widget.heatmapData!,
                                  baseColor: widget.inactiveColor,
                                  highlightColor:
                                      widget.activeColor.withValues(alpha: 0.25),
                                ),
                              )
                            else
                              ColoredBox(color: widget.inactiveColor),

                            // Buffered
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _buffered,
                              child: ColoredBox(color: widget.bufferedColor),
                            ),

                            // Progress
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: displayFraction,
                              child: ColoredBox(color: widget.activeColor),
                            ),

                            // Hover indicator line
                            if (_hovering)
                              Positioned(
                                left: width * _hoverFraction - 0.5,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 1,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Thumb dot (visible on drag or hover)
            if (isExpanded)
              Transform.translate(
                offset: Offset(
                  width * displayFraction - 6 +
                      (constraints.maxWidth > width
                          ? (constraints.maxWidth - width) / 2
                          : 0),
                  -14,
                ),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: widget.activeColor,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHoverPreview(double barWidth) {
    final timeText = _formatTime(_hoverFraction);
    const tooltipWidth = 54.0;
    final leftOffset =
        (_hoverFraction * barWidth - tooltipWidth / 2).clamp(0.0, barWidth - tooltipWidth);

    return SizedBox(
      height: 28,
      child: Stack(
        children: [
          Positioned(
            left: leftOffset,
            child: Container(
              width: tooltipWidth,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xE6212121),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                timeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<double> data;
  final Color baseColor;
  final Color highlightColor;

  _HeatmapPainter({
    required this.data,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final segmentWidth = size.width / data.length;
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    if (maxVal <= 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = baseColor,
      );
      return;
    }

    for (int i = 0; i < data.length; i++) {
      final normalized = (data[i] / maxVal).clamp(0.0, 1.0);
      final color = Color.lerp(baseColor, highlightColor, normalized)!;
      final barHeight = size.height * (0.4 + 0.6 * normalized);
      final top = size.height - barHeight;

      canvas.drawRect(
        Rect.fromLTWH(i * segmentWidth, top, segmentWidth + 0.5, barHeight),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.data != data || old.baseColor != baseColor;
}
