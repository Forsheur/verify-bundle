# Threat model

Written for people who will try to break this, because those are the people
whose opinion decides whether it is worth anything. The section on **how you
would fool it** is the one to read first; it is deliberately specific.

---

## What this script establishes

Six links, each refusing to stand on the one before it:

1. The payload bytes are the bytes a device hashed and signed (`h_received`).
2. The commitment the notary sealed is derived from those bytes
   (`sha256(H_env ‖ H_received) == H_chunk`).
3. The device's signature over that commitment verifies, against a public key
   read from the envelope — not one supplied alongside it.
4. The commitment is a leaf of a Merkle tree whose root is in a block the
   notary signed.
5. That block links back, hash by hash, to a cover block.
6. The cover block is anchored in the Bitcoin blockchain.

Cut any link and the report says which one, and stops.

**Everything runs on your machine.** There is no HTTP client in this file. Cut
the network and it behaves identically — which is the property that matters if
you are examining material you cannot risk announcing.

## What it does not establish

**Anything about the truth of the scene.** A staged event filmed on a genuine
phone, sealed and anchored, passes every check here. Provenance and truth are
different questions and no verification of bytes answers the second. This is
the largest limit and it is not a defect.

**The identity of the filmer.** The chain ends at an account's public key. That
key is a pseudonym: it links a recording to the same signer as their other
recordings, and to nothing else.

**That the bundle you hold is the bundle it claims to be.** This script reads
whatever archive you point it at. How you obtained it, and whether the person
who gave it to you is who you think, is outside its scope.

**That the media is what the envelope describes.** It proves the payload bytes
are the signed ones. Whether those bytes decode to the picture someone
described to you is a separate question, and the tool for it is
[edit-report](https://github.com/Forsheur/edit-report).

---

## How you would fool it

### Substitute this script

This is the attack this repository exists to answer, and it was real until the
repository existed. The script ships **inside** the bundle it checks. An
attacker who controls the bundle controls the script and can ship one that
prints `VERDICT: PASS` over anything, with a fabricated transcript that looks
exactly like a real one.

Nothing inside the archive can settle this — not a hash the same attacker
wrote, not a signature over a key they chose.

**What defeats it:** the digest of the copy that ran, compared against a
release here. The script prints its own SHA-256 in its header and emits it in
`--json`; the bundle's `manifest.json` and `README.txt` state the version and
digest of the copy they carry; a Forsheur server publishes its embedded copy at
`/verifier.sha256`. These are three statements from two parties, and a
substituted script has to be consistent with all of them, including the one
served by a host the bundle's supplier does not control.

**What it still does not do:** tell you which digest is *right* if they all
disagree. At that point the answer is not arithmetic — it is to run a copy you
fetched yourself from here against the bundle's data, which is a check no
supplied file participates in.

**Why the copy is shipped in the bundle at all**, given this. Because the
alternative is worse: a bundle that requires a download to be checked is a
bundle that cannot be checked on an air-gapped machine, in a country where this
host is blocked, or in ten years when it is gone. The bundled copy is what
makes verification survive us. The published copy is what makes the bundled
copy accountable. Neither replaces the other.

### Supply attestation roots

The Apple and Google attestation roots are pinned **inside this script**, with
the URLs they came from written beside them. A root certificate arriving inside
the archive being checked anchors nothing and is never read — a chain that
validates against a root the attacker supplied is a chain validating against
itself.

`--attest-root` adds a root *you* obtained. It adds; it never replaces.

### Exploit the clock

Certificate validity is evaluated at the instant the notary sealed the bytes —
`first_seal_time` from the notary's own blocks — and never at `now()`. Two
consequences, and they cut in opposite directions:

- an old recording does not become unverifiable because a certificate expired
  since, which is correct and is the point;
- an attacker who can forge a seal time can therefore choose which certificates
  look valid. That forgery is the thing the notary's signature and the Bitcoin
  anchor exist to prevent, so this is not a separate weakness — but it is where
  the weight of the anchor actually falls, and it is worth knowing that is
  where to push.

### Strip the attestation chain

An attestation chain is all-or-nothing: its contents sit inside a certificate a
manufacturer signed, so it cannot be redacted field by field. A bundle that
carries none is **labelled as carrying none**, never silently treated as
equivalent to one that does. `state` distinguishes `published`, `withheld` and
`not_captured`, and conflating the three would be the bug worth reporting.

### Hand it a hostile archive

A bundle comes from a source who may not be a friend, and it is unpacked on a
journalist's machine. Measured on CPython 3.12 rather than assumed:

- a member named `../../escaped.txt` is extracted **inside** the destination as
  `escaped.txt`. `zipfile` drops `..` components; the classic traversal does
  not apply.
- a member with the symlink bit set is written as an ordinary file containing
  the link target as text. `zipfile` does not recreate symlinks, so the
  extract-a-link-then-write-through attack does not apply either.

**What is not defended:** size. `extractall` has no cap here, so a hostile
archive can fill your disk, and extraction goes to a directory beside the `.zip`
you named. Unpack an untrusted bundle where you can afford to.

### Read the output instead of the exit status

The human transcript is the authoritative account and `--json` is the same run
restated. A wrapper that decides `PASS` by grepping the prose for a word is
depending on wording nobody versions; use `--json` and read `verdict` and
`failed_checks`. The schema is `forsheur-verify-bundle/1` and it is versioned
precisely so this stays safe.

---

## Cryptography implemented here

Ed25519 and ECDSA P-256 verification are written out in pure Python in this
file, roughly 250 lines, so that a signature can be checked on a machine with
nothing installed. That is a deliberate trade and both halves of it belong in
the open:

- **against:** hand-written curve arithmetic is exactly the kind of code that
  is subtly wrong, and this copy is not constant-time.
- **for:** every operation here is **verification of public data with public
  keys**. There is no secret to leak through timing. A wrong implementation
  fails by accepting or rejecting a signature, which is a correctness bug, and
  correctness bugs in this file are what the reporting address below is for.

The decryption paths are the exception: they use `cryptography` and `pynacl`
rather than anything hand-written, because those touch key material and the
trade above does not hold there. They are optional, and no verification
requires them.

---

## What it leaks

**Nothing to any network.** No HTTP client exists in this file.

It writes to disk: a `.zip` is unpacked beside itself, and `--extract` writes
decoded media into the bundle directory. On a shared or backed-up machine, that
media therefore lands where a backup agent or another user may reach it. If the
session is end-to-end encrypted, `--extract` with a key writes **plaintext**
there. That is the intended behaviour and it is worth being deliberate about
where you run it.

Keys are prompted for with hidden input and are never accepted on the command
line, so they stay out of shell history and out of the process list.

---

## Reproducibility

There is none to arrange: this is a Python source file with no build step. The
published artefact *is* the source, and its SHA-256 is the whole story. That is
a real advantage over a compiled verifier, where reproducing a published binary
turns out to depend on the compiler, the linker, the directory and the host OS.

Releases carry `SHA256SUMS` and a provenance attestation naming the workflow
and commit that produced them.

---

## Reporting a problem

Open an issue for anything that is not itself a vulnerability. For a
vulnerability — in particular any way to make this script print `PASS` over
material it should have rejected — contact **security@forsheur.com** privately
first, or use the repository's private vulnerability reporting on GitHub.

A report saying "this accepted a bundle it should have rejected" is the most
serious kind there is here. A report saying "this rejected a genuine bundle" is
the second, and it is not cosmetic: a verifier that cries wolf is a verifier
nobody runs.
