# Home Server

A single-owner home server: Proxmox on an Intel NUC, running Home Assistant and a
first wave of self-hosted services, documented so that it can be rebuilt by a
stranger and wound down by someone who has never logged into it.

## Language

### Secrets

**Operational secret**:
A credential a machine needs in order to run: a service API token, a generated
password, a key a playbook consumes. Rotatable, meaningless to a human, and
never part of what a person inherits.
_Avoid_: machine secret, runtime secret

**Succession secret**:
A credential a person needs in order to take control of an account: the login
to a registrar, a DNS provider, a storage vendor. Tied to an identity rather
than a machine, and the only category that has to survive the owner.
_Avoid_: account credential, personal secret

**Registry**:
The committed, value-free record of which secrets exist, what each is for, where
it lives, and what breaks when it changes. The registry is public; the secrets
it describes are not.
_Avoid_: secrets doc, inventory, manifest

**Envelope**:
The sealed physical escrow stored with the owner's trust paperwork. Holds only
roots — the credentials that unlock other credentials and that never rotate.
_Avoid_: sealed letter, emergency kit, fire safe

**Index note**:
The orientation document a successor reads first, written for a non-technical
reader, naming each load-bearing account and the disposition the owner wants for
it. Lives with the succession secrets, not on the server.
_Avoid_: start-here note, account list, runbook

### Documentation

**Call script**:
The document the owner reads aloud to [Hands](#hands) during a phone call, or
texts them a link to. Written to be spoken, not discovered: it has no reader
who arrives at it unprompted.
_Avoid_: panic page, fridge page, emergency doc

### People and things

**Load-bearing account**:
A third-party account whose loss would break the server, the domain, or the
backups. The distinction is consequence, not usage frequency.
_Avoid_: important account, critical service

**Emergency contact**:
A person granted standing, pre-arranged access to the succession secrets,
exercisable without the owner's participation. Distinct from someone who merely
helps: helping needs no credentials.
_Avoid_: trusted contact, next of kin, beneficiary

**Hands**:
Someone with physical access to the house, phoned by the owner and talked
through a task in real time. Holds no credentials and makes no decisions — the
owner supplies both. Present only while the owner is alive to place the call.
_Avoid_: helper, friend, partner

**Successor**:
Whoever exercises emergency access. Their job is to wind the system down or keep
it running — never to rebuild it.
_Avoid_: heir, executor, inheritor

**Disposition**:
What the owner wants done with a load-bearing account after their death: cancel,
transfer, or leave running. Recorded per account, and the one judgement no
successor can make on the owner's behalf.
_Avoid_: instruction, wish, action
