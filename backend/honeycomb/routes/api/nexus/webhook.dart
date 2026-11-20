import 'package:dart_frog/dart_frog.dart';
import 'package:honeycomb/runtime.dart';

Future<Response> onRequest(RequestContext context) async {
  final nexus = honeycombService()?.nexus;
  return nexus == null
      ? Response(statusCode: 503)
      : nexus.receive(context.request);
}
