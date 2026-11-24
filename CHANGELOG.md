# Changelog

Breaking changes are listed first in each entry. Read the entry before you apply an update from your Railway dashboard.

## 1.16.57 (2026-11-24)

First release of the template.

- JT Doc Tools v1.16.57 (upstream commit `74c2a2f0`), built CPU-only on `python:3.12.16-slim-bookworm@sha256:82836454…`, with LibreOffice and Tesseract OCR (English, Traditional Chinese).
- The admin account is created from `ADMIN_USERNAME` / `ADMIN_PASSWORD` and login is switched on before the web port opens; the service refuses to start without a working login.
- Threads and job concurrency are sized from the service's CPU and memory limits, so it runs at 0.5 GB / 1 vCPU.
- Data on a Railway volume at `/data`; health check `/healthz`.
