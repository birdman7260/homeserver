# The documentation corpus is public

Status: accepted

All three documentation tiers are published openly, with no authentication in
front of any of them. Nothing about the home network is protected by making the
documentation hard to reach; it is protected by choosing what gets written down.

The site is generated from this repository, and [this repository is
public](0001-secrets-live-outside-this-repository.md). Anything rendered on the
site is therefore already world-readable in `main`, permanently, in history.
Putting Cloudflare Access in front of the rendered copy would protect nothing
that the source does not already disclose, while taxing the one reader who can
least afford it: [Hands](../../CONTEXT.md), phoned mid-incident, standing in
someone else's house, holding a phone.

So access is not the control. **The redaction rule is the control**, and it is
this:

**Belongs in the corpus** — hostnames, service names, ports, architecture,
procedures, and room-level locations inside the house.

**Never in the corpus** — secret values of any kind (ADR-0001 already forbids
these), the street address or anything else that geolocates the house, the WAN
IP, and any third party's name or phone number.

## Considered options

- **Cloudflare Access in front of tiers 2 and 3** — the intuitive answer, and
  the one charting assumed. Rejected: it is theatre over a public source
  repository, and the login it adds lands on stressed readers during incidents.
- **Making the repository private** — would make gated docs coherent. Already
  rejected in ADR-0001 for the rebuild story; nothing here reopens it.
- **A public tier 1 with tiers 2 and 3 gated** — the seemingly careful
  compromise. Rejected for the same reason: the gated content is in the public
  repository regardless, so the gate buys nothing and costs a login.

## Consequences

- The redaction rule is a **writing-time** rule, not a review-time one. Once a
  fact is committed it is public forever, so the rule has to hold on the first
  draft.
- "Who to call" cannot live in the corpus. The list of people with house access
  is third-party personal data, so it lives in the individual Bitwarden vault
  beside the succession secrets. The call script points at *where the list is*,
  never at who is on it.
- Room-level locations are in scope deliberately: "the NUC is in the upstairs
  closet" is useless to anyone who cannot already find the house, and it is
  exactly what Hands needs.
- Tier 2 and tier 3 can link freely to each other and to the Ansible tree, since
  no boundary runs between them.
