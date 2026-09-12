# Secrets live outside this repository, split by audience

Status: accepted

This repository is public, because a public repository is the forcing function
that keeps the rebuild-from-zero path honest. That makes committed ciphertext
unacceptable: an `ansible-vault` or SOPS blob in a public repository is an
offline-crackable artifact guarded by a single passphrase, with no rate limit,
and it stays cracked in every fork forever. **No encrypted secret material is
committed here — not ever, not "just this once".** Secrets are split by the
audience that needs them: **operational secrets** live in Bitwarden Secrets
Manager, reached by a machine account at play time; **succession secrets** live
in the owner's individual Bitwarden vault, where Emergency Access can convey
them to the emergency contacts.

## Considered options

- **`ansible-vault`** — the default in almost every Ansible repository, and the
  reason a reader will find this decision surprising. Rejected: it exists to
  make committing ciphertext safe, which is not a problem worth having once the
  repository is public.
- **SOPS + age** — more legible diffs, more machinery. Rejected for the same
  reason; legibility of ciphertext is not the constraint that binds.
- **Making the repository private** — would make committed ciphertext safe, at
  the cost of the Tier-3 rebuild story and an extra access grant a successor
  would have to be given. Rejected.
- **One vault for everything** — simpler, but Bitwarden's Emergency Access
  covers the individual vault *only*. Organization and collection items are not
  conveyed, so filing succession secrets into a tidy shared collection would
  silently break inheritance while looking more organised.

## Consequences

- The split is load-bearing, not cosmetic. Anything an emergency contact must
  reach belongs in the **individual** vault. Resisting the urge to tidy those
  items into an organization collection is a standing rule.
- Secrets Manager sits outside Emergency Access by construction. This is
  intended: a successor's job is to wind down or keep running, never to rebuild,
  so they need account logins and not machine tokens.
- The `bws` access token cannot itself live in Secrets Manager. It is the one
  secret placed on the control node by hand. It is regenerable from the web
  vault, so it is deliberately **not** escrowed on paper.
- Rebuild instructions cannot assume secrets are present in a clone. They must
  reference [the registry](../secrets.md), which is why the registry is
  committed and the values are not.
