# Secrets registry

Every secret this server depends on, named but never valued. This file is
public on purpose: it is a schema, not a payload. See
[ADR-0001](./adr/0001-secrets-live-outside-this-repository.md) for why nothing
encrypted is committed here.

**Adding a secret? Add a row here in the same change.** A secret that is not in
this registry does not exist as far as the rebuild path is concerned, and it is
the reason rotation stays a ten-minute job instead of an archaeology expedition.

## Where secrets live

| Home | Holds | Reached by |
| --- | --- | --- |
| **Secrets Manager** (Bitwarden, organization) | Operational secrets — machine-facing tokens and generated passwords | `bws` CLI on the control node, via a machine account |
| **Individual vault** (Bitwarden, personal) | Succession secrets — logins, TOTP seeds, 2FA recovery codes for load-bearing accounts | The owner; emergency contacts via Emergency Access (Takeover, 30-day wait) |
| **Envelope** (sealed, stored with the trust paperwork) | Roots only: Bitwarden master password + its 2FA recovery code, and the backup encryption key | Physical access |

Nothing lives in more than one home unless this file says so. The envelope's two
items are duplicated deliberately, because they are the roots that unlock
everything else and they do not rotate.

## Registry

| Secret | Role | Home | Consumed by | Issued at | Breaks when changed |
| --- | --- | --- | --- | --- | --- |
| `bws` access token | Authenticates the control node to Secrets Manager | Control node, by hand | Every playbook run | Bitwarden web vault → Secrets Manager → machine accounts | All automation, until replaced. Regenerable in ~30s; deliberately not escrowed |
| Bitwarden master password | Root of the individual vault | Envelope | — | — | Everything. Does not rotate |
| Backup encryption key | Decrypts offsite backups | Individual vault + envelope | Backup + restore jobs | _pending — see backup architecture_ | Every existing backup becomes unrecoverable. **Never rotate without a documented re-encrypt** |
| ESPHome API encryption key | Re-adopting the garage opener | Individual vault | Home Assistant | Captured from the old install | Requires physical serial access to the Shelly |
| ESPHome OTA password | Re-flashing the garage opener over the air | Individual vault | ESPHome | Captured from the old install | As above |

Rows get added as the build proceeds. Cloudflare, the registrar, storage, and
service tokens land here as their tickets resolve.

## Rotation

**Event-driven, not scheduled.** A rotation calendar for a one-person home
server is the first thing to lapse under neglect, and a lapsed schedule is worse
than none because it manufactures confidence. Rotate on real triggers:

- Suspected exposure, or a breach notice from the vendor
- A credential that touched a public place — this repository, an issue body, a
  chat log, an agent transcript, a shared terminal
- Someone's access ending

**One rule with no judgement attached:** anything ever pasted into this public
repository or an issue on it is burned and rotates immediately, regardless of
how briefly it was there. Git history and issue edit history both keep it.
