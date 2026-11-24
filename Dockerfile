# JT Doc Tools for Railway
# Upstream: https://github.com/jasoncheng7115/jt-doc-tools (AGPL-3.0)
# Upstream publishes no container image, so this builds the pinned release
# (tag v1.16.57, commit 74c2a2f0) the same way upstream's own Dockerfile does:
# CPU-only (no torch / EasyOCR / NVIDIA packages), Tesseract OCR and
# LibreOffice included.

ARG PYTHON_IMAGE=python:3.12.16-slim-bookworm@sha256:82836454a795d9d75549a9e157fd08dbac6c383292cf89e99f4248a97ce6b2ff

# ---- source: download the pinned release and verify its checksum ----
FROM ${PYTHON_IMAGE} AS src
ARG JTDT_VERSION=1.16.57
ARG JTDT_COMMIT=74c2a2f0865eee372c3b4aa9978af1fc8f8e0928
ARG JTDT_SHA256=2de2b40a65c4d2200b140f099b726e98b33043f8aef952016ec9964b16781953
RUN python -c "import hashlib,sys,tarfile,urllib.request; \
url='https://github.com/jasoncheng7115/jt-doc-tools/archive/${JTDT_COMMIT}.tar.gz'; \
urllib.request.urlretrieve(url,'/tmp/src.tgz'); \
h=hashlib.sha256(open('/tmp/src.tgz','rb').read()).hexdigest(); \
print('sha256', h); \
sys.exit(0) if h=='${JTDT_SHA256}' else sys.exit('checksum mismatch')" \
 && mkdir /src && tar -xzf /tmp/src.tgz -C /src --strip-components=1 \
 && grep -q '^version = "'"${JTDT_VERSION}"'"' /src/pyproject.toml \
 && rm -r /src/tests /src/packaging /tmp/src.tgz

# ---- uv (pinned) ----
FROM ghcr.io/astral-sh/uv:0.13.9@sha256:d3b601f0c7b118bc1753febf7c41cc80981df678445e0254284eecf84db79a7d AS uv

# ---- app ----
FROM ${PYTHON_IMAGE}
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    JTDT_DATA_DIR=/data \
    JTDT_HOST=0.0.0.0 \
    JTDT_PORT=8765

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl fonts-noto-cjk fonts-noto-color-emoji \
        libgl1 libglib2.0-0 zbar-tools \
        tesseract-ocr tesseract-ocr-chi-tra tesseract-ocr-eng \
        libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw \
        default-jre-headless \
    && rm -r /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv
WORKDIR /app
COPY --from=src /src/pyproject.toml /src/uv.lock /src/README.md /src/docker-gpu-excl.py ./
RUN mkdir -p app && touch app/__init__.py \
    && GPU_EXCL=$(python docker-gpu-excl.py) \
    && uv sync --no-dev --no-install-project \
         --no-install-package torch --no-install-package torchvision \
         --no-install-package easyocr $GPU_EXCL \
    && uv cache clean

COPY --from=src /src/ /app/
RUN GPU_EXCL=$(python docker-gpu-excl.py) \
    && uv sync --no-dev \
         --no-install-package torch --no-install-package torchvision \
         --no-install-package easyocr $GPU_EXCL \
    && uv cache clean \
    && if ls /app/.venv/lib/python3.12/site-packages/nvidia >/dev/null 2>&1; then \
         echo "NVIDIA packages found in the image"; exit 1; fi \
    && /app/.venv/bin/python -c "import fastapi, fitz, PIL, pillow_heif, pdfplumber, docx, odf, openpyxl, pyzipper, httpx, psutil, pyotp, qrcode, pdf2docx, rapidfuzz, fontTools, numpy, lxml, pymupdf4llm, markdown_it, jwt, onelogin.saml2.auth, xmlsec, truststore, ldap3; print('deps OK')"

# Non-root runtime user (same uid as upstream). The start script runs as root
# only to fix ownership of the Railway volume, then drops to this user.
RUN useradd --system --uid 10001 --create-home --home-dir /home/jtdt jtdt \
    && mkdir -p /data && chown -R jtdt:jtdt /data /app

COPY start.sh /usr/local/bin/jtdt-start
COPY bootstrap.py /opt/jtdt/bootstrap.py
RUN chmod 0755 /usr/local/bin/jtdt-start && chmod 0644 /opt/jtdt/bootstrap.py

EXPOSE 8765
ENTRYPOINT ["/usr/local/bin/jtdt-start"]
