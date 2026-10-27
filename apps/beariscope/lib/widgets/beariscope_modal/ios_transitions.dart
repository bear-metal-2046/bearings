// Adapted from Flutter's Cupertino sheet transitions and stupid_simple_sheet
// 0.9.1+1 (cupertino_sheet_copy.dart, clamped_animation.dart, optimized_clip.dart).
// Copyright 2014 The Flutter Authors. All rights reserved.
// Copyright (c) 2025 Tim Lehmann for whynotmake.it.
// See LICENSE.ios-transitions for the BSD and MIT license notices.
part of '../beariscope_modal.dart';

// Smoothing factor applied to the device's top padding (which approximates the corner radius)
// to achieve a smoother end to the corner radius animation.  A value of 1.0 would use
// the full top padding. Values less than 1.0 reduce the effective corner radius, improving
// the animation's appearance.  Determined through empirical testing.
const double _iosDeviceCornerRadiusSmoothingFactor = 0.9;

// Threshold in logical pixels. If the calculated device corner radius (after applying
// the smoothing factor) is below this value, the corner radius transition animation will
// start from zero. This prevents abrupt transitions for devices with small or negligible
// corner radii.  This value, combined with the smoothing factor, corresponds roughly
// to double the targeted radius of 12.  Determined through testing and visual inspection.
const double _iosRoundedDeviceCornersThreshold = 20.0;

// Amount the sheet in the background scales down. Found by measuring the width
// of the sheet in the background and comparing against the screen width on the
// iOS simulator showing an iPhone 16 pro running iOS 18.0. The scale transition
// will go from a default of 1.0 to 1.0 - _iosSheetScaleFactor.
const double _iosSheetScaleFactor = 0.0835;

const _iosSheetPaddingToPrevious = 11.0;

final Animatable<double> _iosScaleTween = Tween<double>(
  begin: 1.0,
  end: 1.0 - _iosSheetScaleFactor,
);

double _iosRelativeTopPadding(
  BuildContext context, {
  double extraPadding = 0,
  double minFraction = 0.05,
}) {
  final safeArea = MediaQuery.paddingOf(context);
  final height = MediaQuery.sizeOf(context).height;

  if (height == 0) {
    return minFraction;
  }
  // Ensure that the sheet moves down by at least 5% of the screen height if
  // the safe area is very small (e.g. no notch).
  return math.max((safeArea.top + extraPadding) / height, minFraction);
}

// Backdrop colors are owned here rather than layered over the package's tint.
const _iosLightBackdropOpacity = 0.20;
const _iosDarkBackdropOpacity = 0.10;
const _iosDarkBackdropColor = Color(0xffc8c8c8);

Widget _iosBackdrop(
  BuildContext context,
  Widget? child,
  Animation<double> animation,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final color = isDark ? _iosDarkBackdropColor : Colors.black;
  final opacity = isDark ? _iosDarkBackdropOpacity : _iosLightBackdropOpacity;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      ?child,
      IgnorePointer(
        child: FadeTransition(
          opacity: animation.drive(Tween(begin: 0.0, end: opacity)),
          child: ColoredBox(color: color, child: const SizedBox.expand()),
        ),
      ),
    ],
  );
}

ShapeBorder _iosDeviceShape({
  required ShapeBorder sheetShape,
  required double deviceCornerRadius,
}) {
  switch (sheetShape) {
    case RoundedSuperellipseBorder():
      return RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(deviceCornerRadius),
        ),
      );
    default:
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(deviceCornerRadius),
        ),
      );
  }
}

abstract class _IosModalTransitions {
  /// The primary delegated transition. Will slide a non sheet page down.
  ///
  /// Provided to the previous route to coordinate transitions between routes.
  static Widget? secondarySlideDownTransition(
    BuildContext context, {
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required (double, double) opacityRange,
    required (double, double) slideBackRange,
    required ShapeBorder primaryShape,
    Widget? child,
  }) {
    final Animatable<Offset> topDownTween = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(0, _iosRelativeTopPadding(context)),
    );

    final double deviceCornerRadius =
        (MediaQuery.maybeViewPaddingOf(context)?.top ?? 0) *
        _iosDeviceCornerRadiusSmoothingFactor;
    final bool roundedDeviceCorners =
        deviceCornerRadius > _iosRoundedDeviceCornersThreshold;

    final deviceShape = _iosDeviceShape(
      sheetShape: primaryShape,
      deviceCornerRadius: roundedDeviceCorners ? deviceCornerRadius : 0,
    );

    final decorationTween = ShapeBorderTween(
      begin: deviceShape,
      end: primaryShape.scale(1 / 1.5),
    );

    final shapeAnimation = secondaryAnimation
        .remapped(start: slideBackRange.$1, end: slideBackRange.$2)
        .drive(decorationTween);

    final Animation<Offset> slideAnimation = secondaryAnimation
        .remapped(start: slideBackRange.$1, end: slideBackRange.$2)
        .drive(topDownTween);
    final Animation<double> scaleAnimation = secondaryAnimation
        .remapped(start: slideBackRange.$1, end: slideBackRange.$2)
        .drive(_iosScaleTween);

    final contrastedChild = _iosBackdrop(
      context,
      child,
      secondaryAnimation.remapped(start: opacityRange.$1, end: opacityRange.$2),
    );

    final double topGapHeight =
        MediaQuery.sizeOf(context).height * _iosRelativeTopPadding(context);

    return Stack(
      children: <Widget>[
        AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
          ),
          child: SizedBox(height: topGapHeight, width: double.infinity),
        ),
        SlideTransition(
          position: slideAnimation,
          child: ScaleTransition(
            scale: scaleAnimation,
            filterQuality: FilterQuality.medium,
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: shapeAnimation,
              child: contrastedChild,
              builder: (BuildContext context, Widget? child) {
                return _IosModalClip(
                  shape: shapeAnimation.value,
                  child: child!,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static Widget secondarySlideUpTransition(
    BuildContext context, {
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Animation<ShapeBorder?> shapeAnimation,
    required (double, double) opacityRange,
    required (double, double) slideBackRange,
    required Color backgroundColor,
    Widget? child,
  }) {
    return SlideTransition(
      position: secondaryAnimation
          .remapped(start: slideBackRange.$1, end: slideBackRange.$2)
          .drive(
            Tween<Offset>(
              begin: Offset(0, 0),
              end: Offset(
                0,
                -_iosSheetPaddingToPrevious / MediaQuery.sizeOf(context).height,
              ),
            ),
          ),
      transformHitTests: false,
      child: ScaleTransition(
        scale: secondaryAnimation
            .remapped(start: slideBackRange.$1, end: slideBackRange.$2)
            .drive(_iosScaleTween),
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        child: AnimatedBuilder(
          animation: shapeAnimation,
          builder: (context, child) => SheetBackground(
            shape: shapeAnimation.value!,
            backgroundColor: CupertinoDynamicColor.resolve(
              backgroundColor,
              context,
            ),
            child: child!,
          ),
          child: _iosBackdrop(
            context,
            child,
            secondaryAnimation.remapped(
              start: opacityRange.$1,
              end: opacityRange.$2,
            ),
          ),
        ),
      ),
    );
  }

  static Widget fullTransition(
    BuildContext context, {
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required (double, double) opacityRange,
    required (double, double) slideBackRange,
    required Color backgroundColor,
    ShapeBorder shape = const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    Widget? child,
  }) {
    final offsetTween = Tween<Offset>(begin: Offset(0, 1), end: Offset(0, 0));

    final shapeTween = ShapeBorderTween(
      begin: shape,
      end: shape.scale(1 / 1.5),
    );

    final shapeAnimation = secondaryAnimation
        .remapped(start: slideBackRange.$1, end: slideBackRange.$2)
        .drive(shapeTween);

    final Animation<Offset> positionAnimation = animation.drive(offsetTween);

    return Builder(
      builder: (context) {
        return SafeArea(
          left: false,
          right: false,
          bottom: false,
          minimum: EdgeInsets.only(
            top: MediaQuery.sizeOf(context).height * 0.05,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: _iosSheetPaddingToPrevious),
            child: SlideTransition(
              position: positionAnimation,
              child: secondarySlideUpTransition(
                context,
                animation: animation,
                secondaryAnimation: secondaryAnimation,
                shapeAnimation: shapeAnimation,
                opacityRange: opacityRange,
                slideBackRange: slideBackRange,
                backgroundColor: backgroundColor,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IosClampedAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _IosClampedAnimation(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value => parent.value.clamp(0.0, 1.0);
}

extension _IosClampedAnimationX on Animation<double> {
  Animation<double> get clamped => _IosClampedAnimation(this);
}

class _IosRemappedAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _IosRemappedAnimation(this.parent, {this.start = 0.0, this.end = 1.0});

  @override
  final Animation<double> parent;

  final double start;

  final double end;

  @override
  double get value => Interval(start, end).transform(parent.value);
}

extension _IosRemappedAnimationX on Animation<double> {
  Animation<double> remapped({double start = 0.0, double end = 1.0}) =>
      _IosRemappedAnimation(this, start: start, end: end);
}

/// Clips its child using the given [shape].
///
/// Compared to using [ClipPath] directly, this widget optimizes for
/// performance by using more efficient clipping methods when possible.
///
/// If [shape] is null, no clipping is applied.
class _IosModalClip extends StatelessWidget {
  const _IosModalClip({required this.shape, required this.child});

  final ShapeBorder? shape;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = this.shape;
    return switch (shape) {
      null => child,
      RoundedSuperellipseBorder(:final borderRadius) => ClipRSuperellipse(
        clipBehavior: Clip.antiAlias,
        borderRadius: borderRadius,
        child: child,
      ),
      RoundedRectangleBorder(:final borderRadius) => ClipRRect(
        clipBehavior: Clip.antiAlias,
        borderRadius: borderRadius,
        child: child,
      ),
      OvalBorder() => ClipOval(clipBehavior: Clip.antiAlias, child: child),
      LinearBorder() => ClipRect(clipBehavior: Clip.antiAlias, child: child),
      _ => ClipPath(
        clipBehavior: Clip.antiAlias,
        clipper: ShapeBorderClipper(shape: shape),
        child: child,
      ),
    };
  }
}
