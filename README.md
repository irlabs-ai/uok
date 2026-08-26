# uok

<!-- Reserved trust-signal badge slots (keep in place):
     [build provenance verified] [malware-scan verdict]
     The release badge below resolves once the first public release exists.
-->
[![Latest release](https://img.shields.io/github/v/release/irlabs-ai/uok)](https://github.com/irlabs-ai/uok/releases/latest)

**`uok` is the Agentic SQA (software quality assurance) command-line tool. An
automated code review asserts that something specific in your code is wrong;
`uok` re-checks each such claim against the code itself, locally on your
machine, and returns a verdict from its own analysis.**

Every claim comes back as one of three verdicts: **PROVEN** and **REFUTED**
carry evidence from the analysis; **NOT PROVABLE** says exactly that — the
claim could not be decided at this revision. You act on what held up, not
just on what was asserted.

This repository distributes official releases. It carries no source code;
every release is a set of per-architecture tarballs, the public installer,
and the signed documents that record where the bytes came from.

## What a run looks like

A review report attached to your pull request carries findings; each finding
hinges on machine-checkable claims about specific lines. `uok` reads them and
re-checks them (transcript shortened; the claim and verdict below come from
the product's own test fixtures — a historical revision of the upstream Linux
kernel):

```console
$ uok findings 321
Report for commit 734c78e7febf (review PRR_kwDOAbc123, current)
Subject: torvalds/linux @ 734c78e7febf
Findings: 1 (1 with checkable claims); 1 dismissed (hidden; rerun with --include-dismissed)

Finding 1 · bug · 2 claims
  Claim 1.1: index `model` can equal `ARRAY_SIZE(pmic_models)` and exceed the
  extent of fixed array `pmic_models[]` at this subscript.
  Claim 1.2: the same guard admits the out-of-range index on the formatted-output path.
  Why:   `pmic_models` is a fixed global array with valid indices 0..36, while
         the immediately enclosing guard uses `model <= ARRAY_SIZE(pmic_models)`,
         allowing `model == 37` before evaluating `pmic_models[model]`.
  Where: drivers/soc/qcom/socinfo.c:320 (qcom_show_pmic_model_array)
         drivers/soc/qcom/socinfo.c:321 (qcom_show_pmic_model_array)

  Check: uok verify 321 --finding 1

$ uok verify 321 --finding 1
Verification run
Source: torvalds/linux @ 734c78e7febf
Build: flagless
Workers: 1 requested, 1 effective

  Finding MC_MODEL_ARRAY_OFF_BY_ONE [bug]
    Target socinfo_321:0: PROVEN (completed)
      Raw: SUCCEEDED SUPPORTED; association passed
    Assessment proposed a bug; it hinges on claim 1.1. The check proved the
    claim at this revision. Conclusion: supported.
```

## How it works

- Point `uok` at a pull request whose review report is ready: `uok verify
  <pr>`. Your local checkout must sit at the exact commit the review looked
  at; the analysis picks up the tree's `compile_commands.json` when one is
  present, and runs flagless otherwise.
- The claims cover concrete C/C++ defect classes: out-of-bounds indexing,
  length/extent mismatches, missing null checks, missing unlock or cleanup on
  an exit path, uninitialized locals, sentinel mismatches.
- Verdicts are data, not exit codes: `uok verify` exits 0 whatever the
  verdicts say. Exit 1 means the tool itself failed; exit 2 means the input
  state cannot produce the request (wrong checkout revision, invalid
  selector). `--json` emits a documented machine-readable contract for
  scripting.
- An offline mode (`uok verify --targets-file …`) re-checks a saved report
  against a local checkout with no GitHub access at all.

## Install

One command runs the public installer — the `install.sh` shipped as an asset
of every release. It picks the latest release's tarball for your
architecture, refuses it unless its SHA-256 matches the release's signed
`checksums.txt`, places the layout at `~/.local/share/uok/<version>/`,
atomically points the `~/.local/bin/uok` symlink at it, and proves the
install by running `uok --version` through that symlink:

<!-- install-snippet:begin — byte-for-byte copy of the canonical install
     command; the source of truth is the same fenced block in INSTALL.md. -->
```bash
curl -LsSf https://get.irlabs.ai/uok/install.sh | sh
```
<!-- install-snippet:end -->

> [!NOTE]
> Releases target Linux on x86-64 and arm64 (glibc 2.34 or newer, plus the
> GCC runtime: `libstdc++`, `libgcc_s`). Each release ships one tarball per
> architecture; the installer picks yours from `uname -m`. Online use
> additionally needs `git` and the [GitHub CLI](https://cli.github.com)
> (`gh`) on `PATH` — `uok` reuses your existing `gh` authentication.

Versions install side by side under `~/.local/share/uok/`, and the only thing
on `PATH` is the one `~/.local/bin/uok` symlink — so re-running the installer
is the upgrade: a newer release lands in its own versioned directory and the
symlink flips onto it atomically, while a re-run of the current version
byte-verifies the existing layout against the release before re-pointing. If
`~/.local/bin` is not on your `PATH`, the installer prints the one-line
`export` to add it and never edits shell rc files on its own; pass
`sh -s -- --modify-path` to opt in to appending that export to your shell's
rc file, exactly once.

### Installing manually

Prefer not to pipe? Every release asset — the installer itself included — is
downloadable from the [Releases page](https://github.com/irlabs-ai/uok/releases),
and the cosign-signed `checksums.txt` records the SHA-256 of `install.sh`,
both tarballs, and the release's four manifest documents, so you can inspect
the installer and check it against the signed hashes before running it. Or
skip the installer entirely:

```bash
tar -xzf uok-<version>-linux-<arch>.tar.gz
export PATH="$PWD/uok-<version>-linux-<arch>:$PATH"
uok --version
```

The tarball unpacks to one directory holding the CLI and its analysis engine
side by side — keep its contents together. This manual layout is exactly what
the installer's `sh -s -- --dest <dir>` flag produces, verification and
architecture pick included, skipping the symlink and `PATH` handling
entirely. [INSTALL.md](INSTALL.md) — the
same document ships inside every tarball — covers the directory layout,
prerequisites, and the full verification walkthrough.

### First commands

```bash
uok status <pr>     # is a verification report ready for this pull request?
uok findings <pr>   # read the findings and the claims they hinge on
uok verify <pr>     # re-check every claim against your local checkout
```

`uok --help` documents every command and flag.

## Docker image

Every release also ships as a container image: the verified release layout
baked at `/opt/uok`, plus `git` and `gh` for `uok`'s online mode.

```bash
docker pull ghcr.io/irlabs-ai/uok:<version>
```

Tags match release versions exactly (bare `X.Y.Z`; there is no `latest` —
pin a version) and are never overwritten. Each version tag is a multi-arch
manifest list (linux/amd64 + linux/arm64): a plain `docker run`
auto-selects your machine's native image — Apple silicon runs arm64
natively, no `--platform` flag, no emulation.

### Provenance: a mirror, never a rebuild

Nothing is built in this repository. The image is built in the private
release pipeline from signature-verified release bytes and mirrored here
digest-identical, and everything that produces the public image is
committed here for inspection: the [`Dockerfile`](Dockerfile) the pipeline
builds, and the [mirror workflow](.github/workflows/mirror-image.yml) that
copies each version's whole manifest list as-is and hard-asserts, in every
run, that the public list digest and both per-arch child digests byte-equal
the internal ones. To verify an image, compare the digests from
`docker buildx imagetools inspect ghcr.io/irlabs-ai/uok:<version>` against
the release evidence, and read the labels each image carries:

| Label | Value |
| -- | -- |
| `org.opencontainers.image.version` | release version (`X.Y.Z`) |
| `org.opencontainers.image.revision` | git SHA the release was built from |
| `org.opencontainers.image.source` | this repository (images built before this label existed lack it) |
| `ai.irlabs.uok.manifest-sha256` | SHA-256 of the release's signed manifest |
| `ai.irlabs.uok.codeartifact-revision` | internal artifact-store revision the layout was pulled at |

### Running

Online verification of a reviewed PR, from your checkout. `/work` is your
checkout at the reviewed revision; the `uok-cache` volume persists gh auth
and comment drafts. Set `GH_TOKEN` in your environment, or run
`gh auth login` once inside the container (it persists in the volume). On a
Linux host, also add `--user "$(id -u):$(id -g)"` — see the cache rule
below.

```bash
docker run --rm -it \
  -v "$PWD":/work \
  -v uok-cache:/cache \
  -e GH_TOKEN \
  ghcr.io/irlabs-ai/uok:<version> \
  uok verify 123 --jobs 2
```

Offline (no GitHub access, no token):

```bash
docker run --rm -it \
  -v "$PWD":/work -v uok-cache:/cache \
  ghcr.io/irlabs-ai/uok:<version> \
  uok verify --targets-file /work/verification_targets.v1.json --source-root /work
```

Conventions:

* **Your checkout mounts at `/work`** and must sit at the report's exact
  head SHA — a mismatch is exit 2, not a silent substitute.
* **The image is slim**: no compilers, no system headers. It verifies
  prepared, container-valid build contexts (kernel-family / `-nostdinc` /
  in-tree-headers targets and flagless runs); ordinary userspace C targets
  need a toolchain layer of your own on top of this tag.
* **`compile_commands.json` must be container-valid.** Entries carry
  absolute `directory`/`file` paths, so a DB generated on a macOS host is
  useless inside the container. Generate it inside a container, or on a
  Linux machine with the project rooted at the same path (`/work`).
  Resolution order: `--compile-commands`, then
  `/work/compile_commands.json`, then `/work/build/compile_commands.json`,
  then flagless execution.
* **One uid per `/cache` volume.** uok creates private `0700` cache
  directories, so a volume first touched as root breaks later non-root
  runs. Linux hosts pass `--user "$(id -u):$(id -g)"` from the *first* run
  onward; Docker Desktop on Mac maps ownership in its file-sharing layer,
  so omit `--user` there — consistently.
* **Every mounted repository is trusted inside the container.** The image
  sets `git config --system safe.directory '*'` — without it, every git
  call against a bind-mounted checkout fails with "dubious ownership"
  because the mount is owned by a foreign uid. A deliberate tradeoff for a
  single-purpose tool image; don't repurpose it as a general dev
  environment.

## Verifying a release

Every release is verifiable from public material alone; skipping this changes
nothing about the install. The quick check is one command with the
[GitHub CLI](https://cli.github.com) (version 2.49 or later): the
attestation confirms the tarball
you hold is the exact file the release workflow produced (shown for `amd64`;
substitute `arm64` on that architecture):

```bash
gh release download --repo irlabs-ai/uok \
  --pattern 'uok-*-linux-amd64.tar.gz.attestation.sigstore.json'
gh attestation verify uok-*-linux-amd64.tar.gz \
  --bundle uok-*-linux-amd64.tar.gz.attestation.sigstore.json \
  --repo irlabs-ai/foundry
```

Every release additionally carries a cosign-signed provenance chain that ties
each tarball's contents to the build that produced it, byte for byte —
[INSTALL.md](INSTALL.md) walks it end to end.

## Getting help

Something in the install or verification flow not behaving as documented?
[Open an issue](https://github.com/irlabs-ai/uok/issues). This repository
tracks distribution — the installer, the release assets, and these documents
— not the product source.

## License

Use of `uok` is governed by the End User License Agreement that ships as the
`LICENSE` file inside each release tarball, alongside `THIRD-PARTY-NOTICES`
for third-party attributions.
