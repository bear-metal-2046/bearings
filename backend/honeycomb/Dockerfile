FROM dart:3.13 AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY . .
RUN dart run dart_frog_cli:dart_frog build
WORKDIR /app/build
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o /app/honeycomb-server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/honeycomb-server /app/honeycomb-server
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/honeycomb-server"]
