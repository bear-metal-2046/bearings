import 'dart:io';

import 'package:core/core.dart';
import 'package:honeycomb/honeycomb.dart';
import 'package:honeycomb/src/auth0_directory_sync.dart';
import 'package:honeycomb/src/tba_importer.dart';
import 'package:sqlite3/sqlite3.dart';

EntityService? _service;
TbaImporter? _tbaImporter;
Auth0DirectorySync? _auth0Directory;

/// Start the upstream imports even if no Grove clients are connected.
void startUpstreamImports() {
  final service = honeycombService();
  auth0Directory()?.start();
  service?.nexus?.start();
  final store = service?.store;
  final key = Platform.environment['TBA_API_KEY'];
  if (store == null || key == null || key.isEmpty) return;
  (_tbaImporter ??= TbaImporter(store: store, apiKey: key)).start();
}

/// Shares the account client across the background worker and webhook route.
Auth0DirectorySync? auth0Directory() {
  final accounts = honeycombService()?.accounts;
  if (accounts == null) return null;
  return _auth0Directory ??= Auth0DirectorySync(
    accounts: accounts,
    webhookToken: Platform.environment['AUTH0_WEBHOOK_TOKEN'],
  );
}

/// A single entity store is shared by the WebSocket and public photo route.
EntityService? honeycombService() {
  final issuer = Platform.environment['AUTH0_ISSUER'];
  final audience = Platform.environment['AUTH0_AUDIENCE'];
  final path = Platform.environment['HONEYCOMB_DATABASE'];
  if (issuer == null || audience == null || path == null || path.isEmpty)
    return null;
  if (_service case final running?) return running;

  final issuerUri = Uri.parse(issuer);
  final verifier = Auth0TokenVerifier(issuer: issuerUri, audience: audience);
  final store = EntityStore(sqlite3.open(path), bearingsEntityRegistry());
  final photoBase = Platform.environment['HONEYCOMB_PUBLIC_API_URL'];
  final deviceId = Platform.environment['BEARIMETRIC_AUTH0_CLIENT_ID'];
  final deviceSecret = Platform.environment['BEARIMETRIC_AUTH0_CLIENT_SECRET'];
  return _service = EntityService(
    store: store,
    authenticate: verifier.call,
    nexus: NexusSync(
      store: store,
      apiKey: Platform.environment['NEXUS_API_KEY'],
      webhookToken: Platform.environment['NEXUS_WEBHOOK_TOKEN'],
    ),
    competitionSources: CompetitionSources(
      store: store,
      tbaKey: Platform.environment['TBA_API_KEY'],
      nexusKey: Platform.environment['NEXUS_API_KEY'],
    ),
    accounts: AccountService(
      store: store,
      issuer: issuerUri,
      managementClientId: Platform.environment['AUTH0_MANAGEMENT_CLIENT_ID'],
      managementClientSecret:
          Platform.environment['AUTH0_MANAGEMENT_CLIENT_SECRET'],
      publicApiUrl: photoBase == null ? null : Uri.parse(photoBase),
      deviceCredentials:
          deviceId == null ||
              deviceId.isEmpty ||
              deviceSecret == null ||
              deviceSecret.isEmpty
          ? null
          : {
              'clientId': deviceId,
              'clientSecret': deviceSecret,
              'domain': issuerUri.host,
              'audience': audience,
            },
    ),
    bootstrapSubject: Platform.environment['HONEYCOMB_BOOTSTRAP_SUBJECT'],
  );
}
