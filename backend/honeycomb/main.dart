import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:honeycomb/runtime.dart';

Future<void> init(InternetAddress ip, int port) async {
  startUpstreamImports();
}

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) =>
    serve(handler, ip, port);
