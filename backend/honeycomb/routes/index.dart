import 'package:dart_frog/dart_frog.dart';

/// Process health. The Grove route separately checks deployment configuration.
Response onRequest(RequestContext context) => Response.json(
  body: {'service': 'honeycomb', 'status': 'ok'},
);
