import 'package:auto_size_text/auto_size_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';

import 'form_style.dart';

class CustomSlider extends StatefulWidget {
  const CustomSlider({
    super.key,
    required this.onChanged,
    required this.title,
    required this.width,
    required this.height,
    this.scale = 1,
    this.segmentLength,
    required this.minValue,
    required this.maxValue,
    this.initialValue,
    this.isVertical = false,
  });

  final String title;
  final double width;
  final double height;
  final double scale;
  final int? segmentLength;
  final int minValue;
  final int maxValue;
  final double? initialValue;
  final ValueChanged<double> onChanged;
  final bool isVertical;

  @override
  State<CustomSlider> createState() => _CustomSliderState();
}

class _CustomSliderState extends State<CustomSlider> {
  late double _sliderValue = widget.initialValue ?? 0;

  double _normalizedValue(double value) {
    final normalized = (value * 1000).roundToDouble() / 1000;
    if ((normalized - normalized.roundToDouble()).abs() < 0.000001) {
      return normalized.roundToDouble();
    }
    return normalized;
  }

  String _formatValue(double value) {
    final normalized = _normalizedValue(value);
    if ((normalized - normalized.roundToDouble()).abs() < 0.000001) {
      return normalized.round().toString();
    }
    final fixed = normalized.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  String _formatDynamicValue(dynamic value) {
    if (value is num) {
      return _formatValue(value.toDouble());
    }
    return value.toString();
  }

  @override
  void didUpdateWidget(covariant CustomSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != null) {
      _sliderValue = _normalizedValue(widget.initialValue!);
    }
  }

  String get _displayValue => _formatValue(_sliderValue);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final min = widget.minValue.toDouble();
    final max = widget.maxValue.toDouble();
    final range = (max - min).abs();
    final interval = widget.segmentLength != null && widget.segmentLength! > 0
        ? widget.segmentLength!.toDouble()
        : (range <= 0 ? 1.0 : (range / 5).clamp(1.0, range));

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void handleSliderChange(dynamic value) {
            if (value is! num) return;
            final normalized = _normalizedValue(value.toDouble());
            widget.onChanged(normalized);
            setState(() => _sliderValue = normalized);
          }

          Widget buildSlider({required bool vertical}) {
            if (vertical) {
              return SfSlider.vertical(
                min: min,
                max: max,
                value: _sliderValue,
                onChanged: handleSliderChange,
                interval: interval,
                showTicks: true,
                showLabels: true,
                enableTooltip: true,
                tooltipTextFormatterCallback: (actualValue, _) =>
                    _formatDynamicValue(actualValue),
                stepSize: 1.0,
                activeColor: theme.colorScheme.primary,
                inactiveColor: theme.colorScheme.surfaceContainerHighest,
              );
            }

            return SfSliderTheme(
                data: SfSliderThemeData(
                  activeTrackHeight: 8 * widget.scale,
                  inactiveTrackHeight: 7.5 * widget.scale,
                  thumbRadius: 10 * widget.scale,
                  overlayRadius: 24 * widget.scale,
                  tickSize: Size(2.5, 12 * widget.scale),
                  labelOffset: Offset(0, 10 * widget.scale),
                ),
                child: SfSlider(
                  min: min,
                  max: max,
                  value: _sliderValue,
                  onChanged: handleSliderChange,
                  interval: interval,
                  showTicks: true,
                  showLabels: true,
                  enableTooltip: true,
                  tooltipTextFormatterCallback: (actualValue, _) =>
                      _formatDynamicValue(actualValue),
                  stepSize: 1.0,
                  activeColor: theme.colorScheme.primary,
                  inactiveColor: theme.colorScheme.surfaceContainerHighest,
                ),
            );
          }

          return DecoratedBox(
            decoration: FormWidgetStyle.panelDecoration(context),
            child: Padding(
              padding: FormWidgetStyle.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AutoSizeText(
                        widget.title,
                        minFontSize: 1,
                        overflow: TextOverflow.ellipsis,

                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 4.5 * widget.scale),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _displayValue,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: FormWidgetStyle.controlGap * widget.scale),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 2 * widget.scale),
                      child: buildSlider(vertical: widget.isVertical),
                    ),
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
