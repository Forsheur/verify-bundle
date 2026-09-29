# Changelog

Versions exist so that a reader holding a bundle knows **which** published
release to compare its verifier against. A bundle carries the verifier that
existed when the bundle was made, so an older version in an older bundle is the
ordinary case and never a finding on its own.

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this
project uses semantic versioning, where a MAJOR bump means a bundle format this
release can no longer read.

## [1.2.0] — 2026-09-27

### Added
- **The lower bound is checked.** Every chunk carries, inside its device
  signature, the notary chain head the phone had last seen. A block hash cannot
  be known before the block is sealed, so when that `(index, hash)` is a block
  of the verified chain segment, the chunk was provably signed after it. A new
  section reports the earliest such bound, fails any chunk that names a block
  with the wrong hash, and notes a head that goes backwards between chunks.
  The bound's clock is the notary's seal time, and the report says so.
- Bundles made by an up-to-date server start the chain segment at the earliest
  head a chunk claims, usually one block before the first sealing block. With
  an older bundle the claim falls outside the segment and is reported as not
  checkable — a note, never a failure.

## [1.1.0] — 2026-09-24

### Fixed
- The App Attest chain is judged at the **attestation**, not at the seal.
  Apple issues the attestation leaf for a few days only and never renews it,
  while the key it vouches for keeps signing for months; judged at the seal,
  every iPhone recording made more than a few days after enrolment failed with
  "certificate #0 was not valid at the sealing time", all of them genuine. The
  instant is now the leaf's `notBefore` (set and signed by Apple), and a new
  check fails if the key was attested **after** the bytes were sealed.
- A session carrying motion streams no longer crashes the verifier
  (`NameError: seq`).

### Added
- Motion streams (`gyro.v1`, `accel.v1`, `mag.v1`, `camera.v1`) are read from
  the signed envelopes and reported.

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
