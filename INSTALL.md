# Installing uok


`uok` (product CLI), `uok-verify` (verdict policy), `uok-analyzer` (analysis
engine), and the engine's Clang builtin headers ship as **one release unit**:
one version, one build hash. They work installed together or not at all — a
mixed-version layout fails at the first lockstep check.

## Download

One command runs the public installer — the `install.sh` shipped as an asset
of every release (the install URL redirects to the latest release's copy). It
picks the latest release's tarball for your architecture (`uname -m`),
refuses it unless its SHA-256 matches the release's `checksums.txt` and every
archive member stays inside the versioned directory, places the layout at
`~/.local/share/uok/<version>/`, atomically points the `~/.local/bin/uok`
symlink at it, and proves the install by running `uok --version` through that
symlink. The installer checks hashes; `checksums.txt` is itself
cosign-signed, and the signature checks below are how you verify identities
too:

```bash
curl -LsSf https://get.irlabs.ai/uok/install.sh | sh
```

Versions install side by side under `~/.local/share/uok/`, and the only thing
on `PATH` is the one `~/.local/bin/uok` symlink — so **re-running the
installer is the upgrade**: a newer release lands in its own versioned
directory and the symlink flips onto it atomically (built at a temp name,
renamed over the old); a re-run of the current version byte-verifies the
existing layout against the release before re-pointing. Older layouts stay in
place until you remove them, which makes rollback re-pointing the symlink at
a previous layout — the same temp-name-then-rename shape the installer uses:

```bash
ln -s ~/.local/share/uok/<version>/uok ~/.local/bin/.uok.new
mv -f ~/.local/bin/.uok.new ~/.local/bin/uok
```

The link must stay a symlink: the binaries locate each other adjacent to the
fully resolved executable path, which a symlink preserves and a copy or
hardlink would not.

If `~/.local/bin` is not on your `PATH`, the installer prints the one-line
`export` to add it — and nothing more: it never edits shell rc files and
never prompts. Flags pass through the pipe after `sh -s --`:

- `sh -s -- --modify-path` opts in to appending the `PATH` export to your
  shell's rc file (`.zshrc`/`.bashrc` by `$SHELL`, `~/.profile` as the
  fallback), exactly once — a re-run that finds the line leaves the file
  alone.
- `sh -s -- --dest <dir>` skips the symlink and `PATH` handling entirely and
  extracts the self-contained versioned directory into `<dir>` — the manual
  layout described under [Install](#install).

Prefer not to pipe, or no browser-grade trust in the URL? Every release asset
— the installer itself included — is downloadable from the Releases page, and
the cosign-signed `checksums.txt` records the SHA-256 of `install.sh` and
both tarballs, so you can inspect the installer and check it against the
signed hashes before running it.

## Install

Each release ships one tarball per architecture: `uok-<version>-linux-amd64.tar.gz`
(x86-64) and `uok-<version>-linux-arm64.tar.gz` (arm64/aarch64). Pick the one
matching your machine (`uname -m`: `x86_64` → `amd64`, `aarch64` → `arm64`),
extract it, and put the extracted directory on your `PATH` (or invoke `./uok`
directly — the binaries find each other by sitting side by side). This manual
flow is exactly what the installer's `--dest <dir>` produces, verification and
architecture pick included; the installer's default instead keeps the layout
under `~/.local/share/uok/` behind the `~/.local/bin/uok` symlink:

```bash
tar -xzf uok-<version>-linux-<arch>.tar.gz
export PATH="$PWD/uok-<version>-linux-<arch>:$PATH"
uok --version
```

The extracted directory contains:

```text
uok-<version>-linux-<arch>/
├── uok                    product CLI
├── uok-verify             verdict policy
├── uok-analyzer           analysis engine
├── clang-headers/         the engine's builtin headers
├── LICENSE                the End User License Agreement
├── THIRD-PARTY-NOTICES    third-party attributions
└── INSTALL.md             this file
```

Keep the four tool items together: `uok` resolves `uok-verify` adjacent to
its own executable before falling back to `PATH`, `uok-verify` resolves the
analyzer the same way, and the analyzer probes the adjacent `clang-headers/`
for the builtin headers it needs to parse a translation unit. The adjacent
unit outranks anything earlier on `PATH`, so a stale install elsewhere cannot
skew versions.

## Prerequisites

**To run the unit:** Linux on x86-64 or arm64 (aarch64), with glibc ≥ 2.34
and the GCC runtime (`libstdc++`, `libgcc_s`). Nothing else is dynamically
linked.

`uok`'s online mode additionally shells out to **`gh`** and **`git`** (it
carries no embedded TLS stack). Offline verification against a local checkout
needs neither.

## Verifying what you downloaded

Every release carries a self-contained provenance chain; verifying it needs
[cosign](https://github.com/sigstore/cosign) and `sha256sum`, and no access to
anything private. The release assets, alongside the two tarballs:

- `checksums.txt` + `checksums.txt.sigstore.json` — SHA-256 of both platform
  tarballs, the four manifest documents below, and `install.sh` (never
  itself or its own signature bundle, and not the attestation bundles, which
  are minted after this file is signed), signed by the public release
  workflow.
- `install.sh` — the public installer the one-line install command pipes to,
  shipped verbatim with every release and covered by `checksums.txt`.
- `public-manifest.json` + `public-manifest.sigstore.json` — the public
  release record (schema `uok-public-manifest.v2`): source commit, internal
  package revision, and a platforms map binding each architecture's payload
  hash table and tarball hash — signed by the public release workflow.
- `release-manifest.json` + `release-manifest.sigstore.json` — the internal
  build manifest (schema `uok-release-manifest.v2`) and its signature from
  the internal release workflow. Its per-platform payload hashes are the
  hashes of the binaries and headers inside each tarball: nothing on the
  public path is rebuilt.
- `uok-<version>-linux-<arch>.tar.gz.attestation.sigstore.json` — a GitHub
  build-provenance attestation per tarball, verified with the GitHub CLI
  instead of cosign (see below).

The quick check — one command with the [GitHub CLI](https://cli.github.com)
(version 2.49 or later), after downloading the attestation bundle alongside
the tarball (shown for `amd64`; substitute `arm64` on that architecture):

```bash
gh release download --repo irlabs-ai/uok \
  --pattern 'uok-*-linux-amd64.tar.gz.attestation.sigstore.json'
gh attestation verify uok-*-linux-amd64.tar.gz \
  --bundle uok-*-linux-amd64.tar.gz.attestation.sigstore.json \
  --repo irlabs-ai/foundry
```

This proves the tarball you hold is the exact file the release workflow
produced, signed with the workflow's identity. The cosign chain below is the
full verification — it additionally ties the tarball's contents to the
internal build record, byte for byte.

Step 1 — verify the signed checksum file, then everything it covers
(`--ignore-missing` because `checksums.txt` lists both architectures'
tarballs; download both to check every asset):

```bash
cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    '^https://github.com/irlabs-ai/foundry/\.github/workflows/release-uok-public\.yml@refs/heads/main$' \
  checksums.txt
sha256sum --check --ignore-missing checksums.txt
```

Step 2 — verify the public manifest (same identity as the checksum file),
then the internal manifest against the internal release identity:

```bash
cosign verify-blob \
  --bundle public-manifest.sigstore.json \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    '^https://github.com/irlabs-ai/foundry/\.github/workflows/release-uok-public\.yml@refs/heads/main$' \
  public-manifest.json
cosign verify-blob \
  --bundle release-manifest.sigstore.json \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp \
    '^https://github.com/irlabs-ai/foundry/\.github/workflows/release-lib\.yml@(refs/tags/libs/rust/uok/v.+|refs/heads/main)$' \
  release-manifest.json
```

Step 3 — tie the layers together: `public-manifest.json`'s
`internal_manifest_sha256` and `signature_bundle_sha256` must match
`sha256sum release-manifest.json` and `sha256sum release-manifest.sigstore.json`;
its `platforms["linux-<arch>"].tarball.sha256` must match the tarball you
downloaded; and the three binaries you extracted must hash to that platform's
`assets` entries (copied verbatim from the internal manifest's `platforms`
map): `sha256sum uok` against `uok-linux-<arch>`, and likewise for
`uok-verify` and `uok-analyzer`. The `clang-headers/` directory ships
extracted, so its internal archive hash is not re-computable here — it is
covered by the signed tarball hash instead.

The release **tag is a distribution label, not source provenance**: this
repository holds no product source. Source provenance is the `git_sha`
recorded in both manifests.

## License

Use of the Software is governed by the `LICENSE` file in this directory (the
End User License Agreement). Third-party attributions and license texts are
reproduced in `THIRD-PARTY-NOTICES`.
