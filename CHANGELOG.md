# Changelog

Versions exist so that a reader holding a bundle knows **which** published
release to compare its verifier against. A bundle carries the verifier that
existed when the bundle was made, so an older version in an older bundle is the
ordinary case and never a finding on its own.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this
project uses semantic versioning, where a MAJOR bump means a bundle format this
release can no longer read.

## [1.0.1] — 2026-09-20

### Changed
- The header points readers at `/custody.sha256` instead of `/verifier.sha256`.
  A Forsheur server used to serve this script at `/verifier` and the picture
  comparison tool at `/verif` — three letters apart, with the shorter path
  naming the other tool. The paths now name the question each answers:
  `/custody` for the chain of custody, `/compare` for the picture. The old
  paths are gone, not redirected.

Nothing else changed: this release verifies exactly what 1.0.0 verified, and a
bundle carrying 1.0.0 is not stale for it.

## [1.0.0] — 2026-09-16

First published release. The script itself is older than this version number;
`1.0.0` marks the point at which it became independently checkable rather than
only distributed.

### Added
- `VERIFIER_VERSION`, printed in the report header alongside the script's own
  SHA-256, exposed as `--version`, and emitted in the `--json` summary under
  `verifier.version`.

### Verifies, as of this release
- Device signatures: Ed25519 (chunk format v2) and ECDSA P-256 (v3), both in
  pure Python.
- Notary Merkle seal, block hash chain, and the Bitcoin `.ots` anchor at three
  levels of capability.
- Roughtime signed timestamps.
- Manufacturer attestation chains to Apple and Google, evaluated at the instant
  of sealing rather than at the time of reading.
- Offline decryption of end-to-end encrypted sessions from an X25519 identity
  key or a raw DEK, checked against the device-signed plaintext hash.
