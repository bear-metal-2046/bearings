import 'package:grove/grove.dart';

String groveLoadMessage(Object error) => switch (error) {
  IncompleteQuery(updateRequired: true) =>
    'Update Beariscope to view this data.',
  GroveOffline() => 'Connect to the server to load this data.',
  IncompleteQuery(offline: true) =>
    'Connect to the server for a complete result.',
  GroveException(code: 'forbidden') =>
    'You do not have permission to view this data.',
  GroveException(code: 'unauthenticated') => 'Sign in to access this data.',
  _ => 'The server could not load this data.',
};
