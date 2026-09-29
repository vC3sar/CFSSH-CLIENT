import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ResizableSplit extends StatefulWidget {
  final Widget child1;
  final Widget child2;
  final bool isVertical; // true = Column (top/bottom), false = Row (left/right)
  final double initialRatio;

  const ResizableSplit({
    super.key,
    required this.child1,
    required this.child2,
    this.isVertical = false,
    this.initialRatio = 0.5,
  });

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  late double _ratio;

  @override
  void initState() {
    super.initState();
    _ratio = widget.initialRatio;
  }

  @override
  void didUpdateWidget(ResizableSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVertical != widget.isVertical) {
      // Re-balance when switching layout direction
      _ratio = widget.initialRatio;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSize = widget.isVertical ? constraints.maxHeight : constraints.maxWidth;
        if (maxSize == 0 || maxSize.isInfinite) {
          // Fallback if unbounded
          return widget.isVertical
              ? Column(children: [Expanded(child: widget.child1), Expanded(child: widget.child2)])
              : Row(children: [Expanded(child: widget.child1), Expanded(child: widget.child2)]);
        }

        final size1 = (maxSize * _ratio).clamp(50.0, maxSize - 50.0);
        final size2 = maxSize - size1 - 8; // 8 is divider size

        if (widget.isVertical) {
          return Column(
            children: [
              SizedBox(height: size1, child: widget.child1),
              _buildDivider(true, maxSize),
              SizedBox(height: size2, child: widget.child2),
            ],
          );
        } else {
          return Row(
            children: [
              SizedBox(width: size1, child: widget.child1),
              _buildDivider(false, maxSize),
              SizedBox(width: size2, child: widget.child2),
            ],
          );
        }
      },
    );
  }

  Widget _buildDivider(bool isVertical, double maxSize) {
    return MouseRegion(
      cursor: isVertical ? SystemMouseCursors.resizeUpDown : SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) {
          setState(() {
            double delta = isVertical ? details.delta.dy : details.delta.dx;
            _ratio += delta / maxSize;
            _ratio = _ratio.clamp(0.1, 0.9);
          });
        },
        child: Container(
          width: isVertical ? double.infinity : 8,
          height: isVertical ? 8 : double.infinity,
          color: AppColors.canvasBase, 
          child: Center(
            child: Container(
              width: isVertical ? 40 : 2,
              height: isVertical ? 2 : 40,
              decoration: BoxDecoration(
                color: AppColors.textDisabled.withAlpha(128),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
