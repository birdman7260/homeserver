# The dev box is a VM on the services host

Status: accepted

The always-on development box runs as a full virtual machine on the same
Proxmox host as Home Assistant and every other service. "Separate blast radius"
— the property the dev box was always required to have — is provided by the
hypervisor boundary, not by separate hardware.

This reverses an assumption made while charting, which held the dev box on
different hardware from the services host on the grounds that it is the one
machine routinely running unreviewed code. There is exactly one machine, it has
32 GB of RAM and that is its permanent maximum, and buying a second box to hold
a terminal and a `tmux` session is a poor use of both money and the six-month
neglect budget.

## Considered options

- **Separate hardware.** The charting assumption. Rejected: it costs a second
  machine to maintain, patch, back up and document, in a project whose stated
  destination is one box a stranger can rebuild. A second box is a second
  rebuild story.
- **An LXC container instead of a VM.** Tempting on a 32 GB budget, and
  explicitly rejected. Anthropic's isolation guidance ranks a full VM strongest
  for a host running an agent that executes commands, and Claude Code's Bash
  sandbox needs extra nesting setup inside an unprivileged container. The
  container saves a few hundred megabytes and spends the isolation this ADR is
  entirely about.
- **No dev box on the server; develop only on the laptop.** Rejected because it
  loses the property that makes the dev box worth having: a long agent run that
  survives closing the lid.

## Consequences

- **The isolation now has to be stated, because it is no longer physical.**
  Three clauses carry it, and all three are load-bearing:
  1. **Personal repos only.** This was a preference while the dev box was
     separate hardware. It is a security boundary now that unreviewed code runs
     one hypervisor away from Home Assistant.
  2. **A full VM, never an LXC container.**
  3. **The dev VM is not trusted by the rest of the estate.** What it may
     actually reach is decided by the remote-access architecture, not here.
- **The dev VM is disposable, deliberately.** It is rebuilt by Ansible, never
  restored from a backup; excluded from the backup set except for a committed
  list of what belongs on it; excluded from monitoring alerts; and never
  load-bearing for anything in the house. Its credentials — a claude.ai login
  and a GitHub token — will lapse under neglect, and that is the designed
  outcome rather than a failure.
- **This is the one guest guaranteed to rot**, so the neglect drill must pass
  with it in a broken state. A dev VM that has quietly become a pet is a failed
  drill, not an inconvenience.
- **No graphical session exists anywhere on the host**, dev VM included. Access
  is Tailscale SSH plus `tmux`; a browser that needs to point at the dev VM runs
  on the laptop. Adding a desktop later touches one guest and no other decision,
  which is precisely why it is not built in advance.
