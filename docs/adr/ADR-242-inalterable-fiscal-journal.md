# ADR-242: Inalterable fiscal journal, signed period closings and audit archive
Date: 2026-10-29
Status: Accepted

## Context
France's NF525 rules (BOI-TVA-DECLA-30-10-30) ask that sales data be
inalterable, secured, kept and archived, and that the tax administration can
read it. The 2026 finance law restored the publisher's self-attestation as an
alternative to certification. Germany's GoBD and the Greek and Swiss record
rules ask for the same in weaker words. Palee runs one code base for every
country, so the strictest rule becomes the rule.

## Decision
1. **Journal** (`fiscal_journal_entries`, insert-only like ADR-241): every
   fiscal event (document issued, identity changed, period closed, archive
   exported, journal verified) appends one entry with a gapless `position`
   per organization, the event type, subject, actor, time, a canonical JSON
   payload, the previous entry's hash and its own hash:
   `hash = SHA-256(previous_hash ‖ "\n" ‖ canonical_json(entry))`. The first
   entry's previous hash is 64 zeros. Appends are serialised per
   organization by locking its head row (`fiscal_journal_heads`) in the same
   transaction as the document, so a document never exists without its entry.
2. **Canonical JSON** (`Fiscal.Domain.CanonicalJson`): keys sorted, no
   whitespace, integers and strings only (money is already integers), UTF-8.
   Two machines always produce the same bytes for the same entry.
3. **Signatures**: each entry's hash and each closing are signed with
   Ed25519 through the port `Fiscal.Ports.JournalSigner`. Production reads
   the key from `FISCAL_JOURNAL_SIGNING_KEY` (base64 32-byte seed, with a key
   id); the public key is shipped in every archive, so an auditor can verify
   without Palee. Without a key, issuing is refused
   (`journal_signing_unavailable`) instead of writing unsigned records.
4. **Period closings** (`fiscal_period_closings`, insert-only): a daily,
   monthly and yearly closing per organization in the gym's own time zone,
   with counts and totals per currency, kind and VAT rate, the perpetual
   grand total (NF525 "grand total perpétuel"), and the journal position and
   hash it seals. Closings are themselves journal entries. An hourly job closes
   every finished day, then the month and year when they end.
5. **Verification**: `GET /admin/fiscal/journal/verification` recomputes the
   chain and the signatures and reports the first broken position, if any.
   The verification itself is journaled.
6. **Audit archive**: `GET /admin/fiscal/archive?from=&to=` returns a ZIP with
   documents, lines, journal entries and closings as JSON Lines, a
   `manifest.json` (SHA-256, size and rows per file, the journal head), its
   Ed25519 signature and the public key. The export is journaled.

## Rationale
- A hash chain makes any edit, deletion or insertion visible; signatures make
  rebuilding the chain after an edit visible too.
- Ed25519 is in OTP's `:crypto`, fast, and its public key can be published.
- Period closings with a perpetual grand total are what NF525 auditors check
  first.

## Alternatives Considered
- **HMAC**: needs the secret to verify, so an auditor would have to trust
  Palee. Rejected.
- **A blockchain or external timestamping service**: adds a dependency that
  can fail at the till. A trusted timestamp (RFC 3161) on yearly closings can
  be added later through the same port.
- **Database audit triggers only**: they do not survive a dump-and-restore
  edit. Rejected.

## Consequences
- Prod needs a `FISCAL_JOURNAL_SIGNING_KEY` secret before any box issues
  documents (gitops change, done with the sysadmin).
- The NF525 self-attestation is a legal statement ANR signs; this ADR is the
  technical basis for it.
- Rotating the key starts using a new key id; old entries keep verifying with
  the old public key, which stays in the archive.

## Implementation Notes
- Migration `20270201000000_create_fiscal.exs`, worker
  `Palee.Workers.CloseFiscalPeriodsJob` (hourly at :20, idempotent; closes every gym-local day that has ended, so US time zones close on their own clock).
