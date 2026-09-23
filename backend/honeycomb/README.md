# Honeycomb (Dart Frog)

This server replaces the Honeycomb Azure Functions API and Web PubSub relay. It
keeps the active /api HTTP paths, Auth0 roles, Cosmos DB MongoDB collections,
Azure Blob profile photos, and TBA/Nexus integrations. Picklists use direct
WebSockets with short-lived tickets from /api/picklists/realtime/negotiate.

The backend has independent Dart package resolution inside Bearings. The
Flutter workspace pins excel to archive 3 while the MongoDB driver needs
archive 4. Run Dart commands from backend/honeycomb.

## Local verification

Use Dart 3.13 or newer. In PowerShell:

    cd C:\Users\Jack\IdeaProjects\bearings\backend\honeycomb
    dart pub get
    dart test
    dart analyze --no-fatal-warnings .
    dart run dart_frog_cli:dart_frog build
    dart compile exe build/bin/server.dart -o build/bin/honeycomb.exe
    .\build\bin\honeycomb.exe

GET http://localhost:8080/health returns {"status":"ok"}. Authenticated
routes require the settings below. The private .env file is ignored by Git.
Do not use a production Cosmos database for mutation tests.

## Manual deployment for testing

1. Install Docker Desktop and Azure CLI; sign in with az login. In Azure, use
   West US 2 and create a resource group and Container Apps environment on
   Consumption. Keep the existing Cosmos DB, Auth0 tenant, and Blob Storage.
2. Ensure the existing profile photo Blob container exists. This server signs
   upload URLs but does not create the container.
3. Build and push an image to GHCR. A private package needs a GitHub token
   with package read permission for Container Apps and package write permission
   for your Docker push:

       cd C:\Users\Jack\IdeaProjects\bearings\backend\honeycomb
       docker build -t ghcr.io/YOUR_OWNER/bearings-honeycomb:test .
       $env:GHCR_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
       docker push ghcr.io/YOUR_OWNER/bearings-honeycomb:test

4. In Azure Portal, create a Container App in that environment using the GHCR
   image. For a private image, configure its registry username and token. Set
   CPU to 0.25, memory to 0.5 GiB, minimum replicas to 1, maximum replicas to
   1, and revision mode to single. Enable external HTTP ingress on port 8080.
5. Add the settings below under Secrets and Containers → Environment
   variables. Add secrets first, then reference them as environment variables.
   Use the same Auth0 audience and Cosmos database as the old Functions
   service. Set PUBLIC_BASE_URL to the HTTPS FQDN assigned by Azure, then
   save to create a new revision.

| Environment variable | Value |
| --- | --- |
| COSMOS_CONNECTION_STRING | Secret: existing Cosmos MongoDB connection URI |
| COSMOS_DATABASE_NAME | Existing Honeycomb database name |
| AUTH0_DOMAIN | Tenant host only, without https:// |
| AUTH0_AUDIENCE | API identifier used by Beariscope and devices |
| REALTIME_TICKET_SECRET | Secret: random string of at least 32 characters |
| PUBLIC_BASE_URL | https://YOUR_CONTAINER_APP_FQDN |
| CORS_ALLOWED_ORIGINS | Comma-separated exact Beariscope web origins |
| TBA_API_KEY, NEXUS_API_KEY | Secrets: existing API keys |
| INTEGRATION_API_KEY | Optional secret for scouting correction integrations using the x-api-key header |
| AUTH0_M2M_CLIENT_ID, AUTH0_M2M_CLIENT_SECRET, AUTH0_M2M_AUDIENCE | Existing Auth0 Management API machine credentials; secret for client secret |
| AUTH0_APP_CLIENT_ID, AUTH0_DB_CONNECTION | Existing Auth0 password reset configuration |
| PAWFINDER_DEVICE_CLIENT_ID, PAWFINDER_DEVICE_CLIENT_SECRET | Existing device credentials; secret for client secret |
| AZURE_STORAGE_CONNECTION_STRING | Secret: existing Blob Storage account connection string |
| PROFILE_PHOTO_CONTAINER, PROFILE_PHOTO_PUBLIC_BASE_URL | Existing photo container and public URL |
| MAX_PROFILE_PHOTO_SIZE_BYTES | Optional; defaults to 1048576 |

6. Check https://YOUR_CONTAINER_APP_FQDN/health. An unauthenticated
   GET /api/auth/me should return 401. In Beariscope, open Settings →
   Advanced → Honeycomb endpoint → Custom URL and enter
   https://YOUR_CONTAINER_APP_FQDN/api. Sign in and verify auth/me,
   event/team views, scout uploads, and picklists. Open a picklist on two
   devices to check edits, presence, and reconnect after a client restart.
   Test photo upload and device login before your full rollout.
7. Follow logs:

       az containerapp logs show --name YOUR_APP --resource-group YOUR_GROUP --follow

   If auth/me returns 500, check Cosmos connectivity, Auth0 audience, and
   Cosmos role indexes. /health checks the process only.

Keep the old Functions endpoint running during testing. Old Web PubSub clients
and direct-WebSocket clients cannot broadcast edits to each other. Plan a
client upgrade window before moving the default app URL and retiring Web
PubSub. Deploying the single replica drops sockets briefly; clients reconnect
and reload changes from Cosmos.

The new relay limits each uncompacted room log to 12 MiB. Before cutover,
open and compact any legacy picklist whose stored change log exceeds that
size; the server cannot produce a CRDT snapshot on its own.

The production build and unauthenticated smoke tests run locally. A real
Cosmos connection, Auth0 token, Azure Blob SAS upload, and match-day load
still need verification against your Azure account before cutting over.
