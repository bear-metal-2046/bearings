import 'package:grove/grove.dart';
import 'package:jose_plus/jose.dart';

import 'authorization.dart';

typedef AuthenticateToken = Future<AuthenticatedActor> Function(String token);

class Auth0TokenVerifier {
  Auth0TokenVerifier({
    required this.issuer,
    required this.audience,
    JsonWebKeyStore? keys,
  }) : keys =
           keys ??
           (JsonWebKeyStore()
             ..addKeySetUrl(issuer.resolve('.well-known/jwks.json'))) {
    if (issuer.scheme != 'https' ||
        !issuer.path.endsWith('/') ||
        audience.isEmpty) {
      throw ArgumentError(
        'Configure an HTTPS Auth0 issuer ending in / and a nonempty API audience',
      );
    }
  }
  final Uri issuer;
  final String audience;
  final JsonWebKeyStore keys;
  Future<AuthenticatedActor> call(String token) async {
    try {
      final jwt = await JsonWebToken.decodeAndVerify(
        token,
        keys,
        allowedArguments: ['RS256'],
      );
      final claims = jwt.claims;
      final expiry = claims.expiry;
      final subject = claims.subject;
      final now = DateTime.now().toUtc();
      if (jwt.isVerified != true ||
          claims.issuer != issuer ||
          !(claims.audience?.contains(audience) ?? false) ||
          expiry == null ||
          !expiry.isAfter(now) ||
          (claims.notBefore?.isAfter(now) ?? false) ||
          subject == null ||
          subject.isEmpty) {
        throw const GroveException('unauthenticated', 'Invalid access token');
      }
      return AuthenticatedActor(
        subject,
        expiresAt: expiry,
        clientId: claims['azp'] as String? ?? claims['client_id'] as String?,
      );
    } catch (_) {
      throw const GroveException('unauthenticated', 'Invalid access token');
    }
  }
}
