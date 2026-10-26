import 'package:flutter/physics.dart';

// Flutter's duration/bounce spring uses the same model as SwiftUI's spring.
final flashCardSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 420),
  bounce: .18,
);
