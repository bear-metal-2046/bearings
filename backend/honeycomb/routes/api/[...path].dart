import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:honeycomb/src/data_api.dart' as data;
import 'package:honeycomb/src/external_api.dart' as externalApi;
import 'package:honeycomb/src/profile_api.dart';
import 'package:honeycomb/src/rbac_api.dart';
import 'package:honeycomb/src/picklists.dart';
import 'package:honeycomb/src/security.dart';

Future<Response> onRequest(RequestContext context, String path) async {
  final request = context.request;
  final limiter = RateLimiter.instance;
  final suppliedIp = request.headers['x-forwarded-for']?.split(',').last.trim();
  final ip = suppliedIp == null || suppliedIp.isEmpty ? 'unknown' : suppliedIp;
  if (!limiter.allow('pre:$ip', ratePerSecond: 10, burst: 100)) {
    return Response.json(
      statusCode: HttpStatus.tooManyRequests,
      headers: {'retry-after': '1'},
      body: {'error': 'Too many requests'},
    );
  }
  try {
    if (path == 'picklists/realtime' && request.method == HttpMethod.get) {
      return await PicklistRealtime.instance.connect(context);
    }
    final access = await AuthService.instance.fromRequest(
      request,
      allowApiKey:
          path.startsWith('scouting/') &&
          (request.method == HttpMethod.patch ||
              request.method == HttpMethod.delete),
    );
    if (access == null) return reply({'error': 'Unauthorized'}, status: 401);
    if (!limiter.allow('user:' + access.userId, ratePerSecond: 10, burst: 60)) {
      return Response.json(
        statusCode: HttpStatus.tooManyRequests,
        headers: {'retry-after': '1'},
        body: {'error': 'Too many requests'},
      );
    }
    switch (path) {
      case 'auth/me' when request.method == HttpMethod.get:
        return reply({
          'user': {
            'id': access.userId,
            'username': access.username,
            'permissions': access.permissions.toList(),
          },
          'global_config': {'permission_metadata': permissionMetadata},
        });
      case 'picklists/realtime/negotiate' when request.method == HttpMethod.get:
        return await PicklistRealtime.instance.negotiate(request, access);
      case 'picklists':
        return await picklistCollection(request, access);
      case final itemPath
          when itemPath.startsWith('picklists/') &&
              itemPath.length > 'picklists/'.length &&
              !itemPath.substring('picklists/'.length).contains('/'):
        return await picklistItem(
          request,
          access,
          itemPath.substring('picklists/'.length),
        );
      case 'breakdowns' when request.method == HttpMethod.get:
        return await data.breakdowns(request, access);
      case 'device/credentials' when request.method == HttpMethod.get:
        return data.deviceCredentials(access);
      case 'scouts':
        return await data.scouts(request, access);
      case final scoutPath when scoutPath.startsWith('scouts/'):
        return await data.scouts(
          request,
          access,
          scoutPath.substring('scouts/'.length),
        );
      case 'scout/ingest' when request.method == HttpMethod.post:
        return await data.ingest(request, access);
      case 'scouting':
        return await data.scouting(request, access);
      case final scoutingPath when scoutingPath.startsWith('scouting/'):
        return await data.scouting(
          request,
          access,
          scoutingPath.substring('scouting/'.length),
        );
      case final configPath
          when configPath.startsWith('config/') &&
              configPath.split('/').length == 3:
        final parts = configPath.split('/');
        return await data.config(request, access, parts[1], parts[2]);
      case 'events' || 'matches' || 'rankings' || 'teams'
          when request.method == HttpMethod.get:
        return await externalApi.external(request, access, path);
      case 'pits'
          when request.method == HttpMethod.get ||
              request.method == HttpMethod.post:
        return await externalApi.external(request, access, path);
      case final mediaPath
          when request.method == HttpMethod.get &&
              RegExp(
                r'^(event/[^/]+/team_media|team/[^/]+/media/\d+)$',
              ).hasMatch(mediaPath):
        return await externalApi.teamMedia(access, mediaPath);
      case 'profile' || 'profile/password-reset' || 'profile/photo-upload':
        return await profile(request, access, path);
      case final rbacPath when rbacPath.startsWith('rbac/'):
        return await rbac(request, access, rbacPath);
      default:
        return reply({'error': 'Not found'}, status: 404);
    }
  } catch (error, stack) {
    stderr.writeln('Honeycomb error: $error\n$stack');
    return reply({'error': 'Unexpected error'}, status: 500);
  }
}
