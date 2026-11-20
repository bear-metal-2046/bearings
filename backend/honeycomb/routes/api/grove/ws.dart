import 'package:dart_frog/dart_frog.dart';
import 'package:honeycomb/runtime.dart';

Future<Response> onRequest(RequestContext context) async {
  final service = honeycombService();
  if (service == null) {
    return Response.json(
      statusCode: 503,
      body: {'error': 'Honeycomb entity service is not configured'},
    );
  }
  return service.handler(context);
}
