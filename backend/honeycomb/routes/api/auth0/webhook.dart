import 'package:dart_frog/dart_frog.dart';
import 'package:honeycomb/runtime.dart';

Future<Response> onRequest(RequestContext context) async {
  final directory = auth0Directory();
  return directory == null
      ? Response(statusCode: 503)
      : directory.receive(context.request);
}
