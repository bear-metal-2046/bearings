import 'package:dart_frog/dart_frog.dart';
import 'package:honeycomb/runtime.dart';

Response onRequest(RequestContext context, String id) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, headers: {'allow': 'GET'});
  }
  final photo = honeycombService()?.accounts?.photo(id);
  if (photo == null) return Response(statusCode: 404);
  return Response.bytes(
    body: photo,
    headers: {
      'content-type': 'image/jpeg',
      'access-control-allow-origin': '*',
      'x-content-type-options': 'nosniff',
      'cache-control': 'public, max-age=300',
    },
  );
}
