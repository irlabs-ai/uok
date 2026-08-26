# The uok runtime image — one Dockerfile for both child architectures of
# the published manifest list (linux/amd64 + linux/arm64).
#
# This file is published for transparency and reproduction. It is NOT the
# build source of the shipped image: ghcr.io/irlabs-ai/uok is built in the
# private release pipeline from signature-verified release bytes and
# mirrored here digest-identical by .github/workflows/mirror-image.yml —
# every mirror run asserts that the public manifest-list digest and both
# per-arch child digests byte-equal the internal ones.
#
# The build context is a directory holding layout/ — the verified four-item
# release layout (uok, uok-verify, uok-analyzer, clang-headers/) for ONE
# architecture. Each child of the manifest list is built natively on a
# machine of its own architecture from that platform's own layout, which is
# why the COPY below needs no arch switch; only the gh pin selects on
# TARGETARCH. There is deliberately no LLVM here: the analyzer statically
# embeds it at release build, and the builtin headers ride the unit as
# clang-headers/. Provenance labels (version, source revision, release
# manifest sha256) are applied per child by the release pipeline; this file
# carries none.
#
# The FROM pin is the multi-arch INDEX digest — each native build resolves
# its own architecture's child from it.
FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241
# glibc 2.36 ≥ the unit's decided 2.34 runtime floor.

# git and gh are uok's online-mode shell-out set (the CLI carries no embedded
# TLS stack); uok-verify and the analyzer are self-contained. gh is a second
# release cadence riding this image — bump the pin deliberately: version and
# BOTH per-arch checksums together, from the upstream release's
# checksums.txt. TARGETARCH (amd64|arm64, supplied by buildx) selects the
# .deb and its pin.
ARG GH_CLI_VERSION=2.97.0
ARG GH_CLI_DEB_SHA256_AMD64=7c7fa3bb890db0934baf65910d97b8c0fa437b2e590f7f7daf6bdf82c5c486d7
ARG GH_CLI_DEB_SHA256_ARM64=0ba7a76739c865d82ebde24667d875d9b8caa55db47c7597c24accdd4defd2bb
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && case "${TARGETARCH}" in \
      amd64) gh_sha="${GH_CLI_DEB_SHA256_AMD64}" ;; \
      arm64) gh_sha="${GH_CLI_DEB_SHA256_ARM64}" ;; \
      *) echo "TARGETARCH '${TARGETARCH}' is not a shipped architecture (amd64, arm64)" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/gh.deb \
      "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${TARGETARCH}.deb" \
 && echo "${gh_sha}  /tmp/gh.deb" | sha256sum -c - \
 && apt-get install -y /tmp/gh.deb \
 && apt-get purge -y curl && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/* /tmp/gh.deb

# The verified four-item layout: uok, uok-verify, uok-analyzer, clang-headers/
# — this platform's own. Adjacency is the install contract — each executable
# resolves the next, and the analyzer its builtin headers, relative to its
# own location.
COPY layout/ /opt/uok/

# Mounted checkouts are near-always owned by a uid other than the container
# user; this is a single-purpose tool image, so trust every mounted directory
# rather than failing each git call with "dubious ownership" (the tradeoff is
# stated in README.md). /work is where the user's checkout mounts; /cache
# (world-writable, sticky) backs HOME and the XDG dirs so one named volume
# persists uok comment drafts and gh config across runs — one uid per volume,
# see README.md.
RUN git config --system safe.directory '*' \
 && install -d -m 1777 /work /cache

ENV PATH="/opt/uok:${PATH}" \
    HOME=/cache/home \
    XDG_CACHE_HOME=/cache \
    XDG_CONFIG_HOME=/cache/config

WORKDIR /work
CMD ["uok", "--help"]
