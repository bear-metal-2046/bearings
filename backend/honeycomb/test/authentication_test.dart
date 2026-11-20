import 'package:grove/grove.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:jose_plus/jose.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Auth0 verifier checks signature, issuer, audience, and token dates',
    () async {
      final key = JsonWebKey.generate('RS256');
      final issuer = Uri.parse('https://example.auth0.com/');
      const audience = 'https://honeycomb.example.com';
      final verifier = Auth0TokenVerifier(
        issuer: issuer,
        audience: audience,
        keys: JsonWebKeyStore()..addKey(key),
      );
      final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final claims = <String, dynamic>{
        'iss': '$issuer',
        'aud': [audience],
        'sub': 'auth0|test-user',
        'exp': seconds + 60,
      };
      String sign(
        Map<String, dynamic> data, {
        JsonWebKey? signingKey,
        String algorithm = 'RS256',
      }) =>
          (JsonWebSignatureBuilder()
                ..jsonContent = data
                ..addRecipient(signingKey ?? key, algorithm: algorithm))
              .build()
              .toCompactSerialization();
      expect((await verifier(sign(claims))).id, 'auth0|test-user');
      final invalid = throwsA(
        isA<GroveException>().having((e) => e.code, 'code', 'unauthenticated'),
      );
      await expectLater(
        verifier(sign({...claims, 'iss': 'https://other.auth0.com/'})),
        invalid,
      );
      await expectLater(
        verifier(
          sign({
            ...claims,
            'aud': ['wrong-audience'],
          }),
        ),
        invalid,
      );
      await expectLater(
        verifier(sign({...claims, 'exp': seconds - 60})),
        invalid,
      );
      await expectLater(
        verifier(sign({...claims, 'nbf': seconds + 30})),
        invalid,
      );
      await expectLater(
        verifier(sign(claims, signingKey: JsonWebKey.generate('RS256'))),
        invalid,
      );
    },
  );
}
