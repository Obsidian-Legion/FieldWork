# FIELDWORK

A dark, nonlinear course atlas for systems architecture, engineering, and design. Sponsored by [Obsidian Legion](https://github.com/Obsidian-Legion).

The server is written in **Unison**. The browser uses native HTML, CSS, and JavaScript. The first real offering is **Systems Architecture for Vibe Coders**, free and online every Tuesday from November 17 through December 15, 2026, at 5:00 PM Eastern.

## Accounts

Members sign up or sign in with GitHub. Their GitHub identity is attached automatically to their FIELDWORK profile. There is no separate password to manage.

- **Admins:** upload, edit, connect, and archive courses; open or close registration; view students under **Your account → Students**, with course and username filters.
- **Members:** register for courses, read materials, and keep private notes, progress, and map positions.
- **Everyone:** PDF, MP4, WebM, TXT, and Markdown lesson viewing; search and a spatial atlas.

Admin access is assigned through an allowlist of immutable GitHub user IDs, never through the sign-up form. Uploads are limited to 100 MB per file. Course files require authentication.

Visitors can see the course schedule before signing in. **Register free** takes them through GitHub and back to the course overview, where they confirm registration. Account creation alone does not enroll a student. The admin roster lists the verified GitHub username, course, and registration time; no separate admin account is needed. Registrations persist in private storage and duplicate submissions are idempotent. Closing or archiving a course retains its roster.

`content/launch-course.json` contains the supplied launch offering, not demo data. Startup adds it once by stable ID, preserving existing courses and subsequent admin edits. No lesson files or meeting URL have been supplied yet. Add course materials through the existing admin controls.

## Run locally

Install [Unison UCM 1.3.0](https://www.unison-lang.org/docs/install-instructions/), then run:

```powershell
.\start.ps1
```

Open http://127.0.0.1:8787. Local mode is a development workspace with admin access, restricted to loopback. It does not simulate a GitHub login. Data stays in `data/`; back up that directory with the server stopped. Use `.\start.ps1 -Build` after changing Unison source.

## Deploy to Azure

Prerequisites: Azure CLI signed in, Docker running, Bicep installed, and permission to create resources and role assignments in the target subscription.

```powershell
.\infra\deploy.ps1 -AdminGitHubIds 'YOUR_NUMERIC_GITHUB_ID'
```

This creates a dedicated resource group, a consumption Container Apps environment, a private container registry, private Blob storage with versioning, and a managed identity scoped to the app's storage and image registry. The app uses 0.5 vCPU / 1 GiB, one replica at most, and scales to zero. These are billable Azure resources. No local courses, notes, credentials, or compiler database are included in the image or repository.

If the dependency registry is temporarily unavailable, `-DependencyCache .unison` reuses the local UCM dependencies and still compiles the current source inside Linux. The compiler database is never copied into the final app image.

New deployments stay locked until GitHub authentication is configured. The deploy script prints the app URL and exact OAuth callback URL, and saves nonsecret deployment details to ignored `infra/deployment.local.json`.

1. Register an organization-owned OAuth app under **Obsidian Legion → Settings → Developer settings → OAuth Apps**.
2. Set its homepage to the deployed URL and its callback to `https://YOUR_APP/.auth/login/github/callback`.
3. Run `.\infra\enable-github.ps1 -ClientId 'YOUR_CLIENT_ID'`. Enter the client secret at the secure local prompt, never in a commit or chat.
4. Complete a real GitHub sign-in and verify both member and administrator access.

The script configures Azure Easy Auth before allowing the Unison server to trust its identity headers. GitHub access is used for identity only; repository scopes are not requested. Authentication secrets stay in Azure, and Blob access uses managed identity without storage account keys. Re-running the deploy script preserves configured authentication.

## Verification

```powershell
# Isolated test store; keep this bound to loopback.
$env:FIELDWORK_AUTH='azure'
$env:FIELDWORK_ADMIN_IDS='101'
$env:FIELDWORK_ORIGIN='http://127.0.0.1:8788'
.\start.ps1 -Port 8788 -DataDirectory .runtime-test

# A second terminal:
node scripts/verify-auth.mjs
node scripts/verify-registration.mjs
```

These tests simulate Azure's verified headers to check anonymous denial, admin-only mutation and rosters, member isolation, course-file access, archived content, byte ranges, optimistic concurrency, registration identity, duplicate/concurrent enrollments, the published schedule, and origin checks. They do not verify GitHub OAuth itself. GitHub Actions also builds the Linux container from source and verifies that an unconfigured deployment fails closed.

After test-server use, clear those three environment variables before restarting normal local mode. Test stores and generated files are ignored by Git.

## Layout

- `src/main.u` — Unison HTTP server, role enforcement, private learning state, local and Azure Blob persistence.
- `ui/` — neon atlas, GitHub entry screen, reader, and account controls.
- `infra/` — Azure infrastructure and deployment/configuration scripts.
- `scripts/` — pinned Unison setup/build and isolated verification.
- [Security design](SECURITY.md) — trust boundary, storage, and current limits.
