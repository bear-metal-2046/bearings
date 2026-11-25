import 'package:flutter/physics.dart';
import 'package:motor/motor.dart';

final navigationSpring = SpringMotion(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: .72),
  snapToEnd: true,
);
