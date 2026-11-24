[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/jt-doc-tools?utm_medium=integration&utm_source=button&utm_campaign=jt-doc-tools)

# JT Doc Tools on Railway

One-click Railway template for [JT Doc Tools](https://github.com/jasoncheng7115/jt-doc-tools) (Jason Tools Document Toolbox) **v1.16.57**: a self-hosted web app with 50 PDF and Office tools: merge, split, rotate, convert Office files to and from PDF, OCR, watermark, stamp and sign, redact (de-identify), compare, fill forms, encrypt and more. Everything runs on your own server; no document leaves it.

## What it deploys

| Service | Source | What it does |
|---|---|---|
| **JT Doc Tools** | this repo (`Dockerfile`) | The web app and REST API on Railway's `PORT`, with LibreOffice (Office ↔ PDF) and Tesseract OCR (English and Traditional Chinese). All data (users, settings, jobs, results, audit log, fonts) lives on a Railway volume at `/data`. |

Upstream publishes no container image, so the `Dockerfile` builds the pinned release tag `v1.16.57` (commit `74c2a2f0`, tarball checked by SHA-256) on `python:3.12.16-slim-bookworm` pinned by digest, the same way upstream's own Dockerfile does, **CPU only**: the GPU packages (PyTorch, EasyOCR, NVIDIA libraries) are left out, so OCR uses Tesseract.

## Login is on from the first deploy

Upstream starts with login **off** and lets the first visitor create the admin on `/setup-admin`. This template doesn't: before the web port opens, the start script creates the admin account and switches the local login on, and it refuses to start if that fails.

- **Username:** `ADMIN_USERNAME` (default `jtdt-admin`)
- **Password:** `ADMIN_PASSWORD`, generated for you. Find it in the service's **Variables** tab.

To change or recover the password, change `ADMIN_PASSWORD` and redeploy: the start script sets it again on every boot. You can add more users, roles, LDAP/AD, OIDC or SAML sign-in, 2FA and API tokens in the app's admin pages.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `ADMIN_PASSWORD` | `${{secret(24)}}` | Admin password (16–128 characters). |
| `ADMIN_USERNAME` | `jtdt-admin` | Admin username created on the first boot. |
| `PORT` | `8765` | Port the app listens on; the Railway domain points here. |

No other settings are needed. Optional features are set up in the admin pages after you sign in: an OpenAI-compatible LLM for the 13 "AI assist" options, SMTP or chat notifications, SSO, the API token "enforce" mode.

## Memory and CPU

It runs on Railway's smallest plan (0.5 GB RAM, 1 vCPU). The start script reads the service's CPU and memory limits and caps OCR and math-library threads and job concurrency to match (one job at a time below 1.6 GB, two below 3.2 GB, upstream's defaults above that). Tested at 0.5 GB / 1 vCPU: Word → PDF in about 3 s, a 36-page scan OCR'd at 300 dpi in about 4.5 minutes (peak about 390 MB, no out-of-memory kill). More RAM and CPU lets it run several jobs at once and makes big OCR jobs faster.

Railway's edge closes an HTTP request after 5 minutes. The web tools run as background jobs, so long jobs are fine in the browser; for very large files over the API, use the job endpoints (`/api/jobs/...`) described in upstream's [API.md](https://github.com/jasoncheng7115/jt-doc-tools/blob/v1.16.57/API.md) rather than waiting on one request.

## Updates

This template builds from this GitHub repo. When a new upstream release is tested here, the version pin in the `Dockerfile` is bumped on `main` and Railway shows an **update available** notice on your project. Read [`CHANGELOG.md`](CHANGELOG.md) first, then apply it from your Railway dashboard. Your data stays on the volume. Upstream's own `jtdt update` command is for script installs and doesn't apply to this container.

## Licence

JT Doc Tools is © Jason Cheng, licensed under the [AGPL-3.0](https://github.com/jasoncheng7115/jt-doc-tools/blob/v1.16.57/LICENSE). The files in this repo (Dockerfile, start script, bootstrap) are under the same licence.
