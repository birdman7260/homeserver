# Coding remotely from laptop and phone

Research for the ticket "Coding remotely from laptop and phone" on the Proxmox home server map.
Researched 2026-09-11. Every source was fetched that day. Claude Code docs match release v2.1.268 (2026-09-10) ([CC-release]).
Sources are listed at the end. **Unverified** marks anything I could not confirm against a primary source.

> **Public-surface flag (read first)**
>
> - **Nothing in the recommended setup needs a public inbound surface.** No router port forwards, no Cloudflare Tunnel, no Tailscale Funnel.
> - **One path goes around Tailscale:** the recommended phone path, Claude Code **Remote Control**. It is relayed through Anthropic.
>   - What stays private: the dev box makes outbound HTTPS requests only and never opens inbound ports ([CC-rc]).
>   - What doesn't: anyone signed in to the claude.ai account can drive the session from claude.ai or the Claude app. The transcript is stored on Anthropic servers while connected ([CC-rc]).
>   - So it is not a port, but it is an off-tailnet control path gated only by the claude.ai login. If "private-only" must mean "tailnet-only", drop it and use the terminal fallback on the phone.
> - **These choices would force a public surface. Avoid them:**
>   - code-server's Let's Encrypt + Caddy/NGINX recipes, which its guide says "requires that the remote machine be exposed to the internet" ([cs-guide]).
>   - `tailscale funnel`, which shares "a local server on the internet" ([ts-serve]).
>   - A Cloudflare Tunnel in front of any web terminal or IDE.
>   - Forwarding SSH or mosh UDP ports on the router.
> - **Claude Code on the web** (the hosted alternative) adds no surface at home. It moves execution to Anthropic VMs and needs GitHub access to your repos ([CC-web]).

## Answer

### Laptop

1. Tailscale on the laptop and on the dev-box VM, with Tailscale SSH enabled on the dev box (`tailscale set --ssh`, which runs "an SSH server, permitting access per tailnet admin's declared policy" ([ts-set])).
2. SSH in, run `tmux`, and run `claude` inside it.
   - tmux exists to "protect running programs on a remote server from connection drops" ([tmux-wiki]).
   - Claude Code's own docs say to use tmux or screen to keep a session alive after SSH disconnects ([CC-rc]).
3. Add the three tmux lines Claude Code documents, so Shift+Enter and notifications work inside tmux ([CC-term]):
   ```
   set -g allow-passthrough on
   set -s extended-keys on
   set -as terminal-features 'xterm*:extkeys'
   ```
4. Optional: use mosh instead of plain SSH on flaky networks ([mosh-site]).
5. Optional: Claude Code background sessions (`claude --bg`, `claude agents`) as the persistence layer instead of tmux. They "keep running without a terminal attached" under a supervisor process ([CC-agents]).

A browser IDE is not needed on the laptop.

### Phone

- **Primary: the Claude app (iOS/Android), Code tab, driving a Remote Control session on the dev box.**
  - Start it inside tmux with `claude --remote-control`. Or set `remoteControlAtStartup: true` in `~/.claude/settings.json` so every interactive session connects ([CC-rc]).
  - Execution stays on the dev box. The app is "a window into that local session" ([CC-rc]).
  - You get push notifications when a task finishes or needs a decision, plus photo and file attachments ([CC-rc], [CC-mobile]).
  - No Esc, Shift+Tab or Ctrl keys needed on a soft keyboard.
- **Fallback, tailnet-only: an SSH client with mosh.** Blink Shell on iOS ([blink-ts]); Termius on iOS/Android ([termius-connect]); Termux on Android ([termux-mosh]). Connect over Tailscale and run `tmux attach`.
- **Not recommended on a phone:** code-server and openvscode-server (see [From a phone specifically](#1-from-a-phone-specifically)).
- **Hosted complement:** Claude Code on the web, started from the same app, for GitHub repos when the NUC is off ([CC-mobile], [CC-web]).

### Maintenance cost

No scheduled chores. Everything is event-driven.

| Item | What it costs | Source |
| :-- | :-- | :-- |
| Claude Code | The native installer "automatically update[s] in the background"; apt/dnf installs do not | [CC-setup] |
| Tailscale | `tailscale set --auto-update` | [ts-set] |
| tmux, mosh | Distro packages; OS patching belongs to the neglect ticket | — |
| claude.ai login | Renew with `/login` when it expires. Warning shows 3 days ahead. An unattended background or Remote Control session "that outlives the login stops making progress". Over SSH, login uses a paste-the-code flow. Login lifetime is not documented (**unverified**). | [CC-auth] |
| `claude setup-token` | Not a shortcut: its one-year token "can't establish Remote Control sessions" | [CC-auth] |
| GitHub credential | Rotate the fine-grained token when it expires (expiry is chosen at creation) | [gh-pat] |
| After a dev-box reboot | Restart tmux and `claude --remote-control`. `claude remote-control` brings server-mode sessions back for about 4 hours after stopping; otherwise `claude --continue` resumes the conversation | [CC-rc], [CC-sessions] |
| Phone app | Blink+ is an annual subscription (price **unverified**). Termux is free from F-Droid/GitHub. Whether Termius's free tier includes mosh is **unverified**. | [blink-faq], [termux-app] |

### What it exposes

| Surface | Reachable from | Notes |
| :-- | :-- | :-- |
| SSH (Tailscale SSH) on the dev box | Tailnet only | Access decided by tailnet policy ([ts-set]) |
| mosh UDP 60000–61000 on the dev box | Tailnet only | mosh's default port range ([mosh-readme]) |
| `api.anthropic.com:443`, GitHub | Outbound only | Remote Control "never opens inbound ports" ([CC-rc]) |
| Remote Control session | **Off-tailnet**: anyone signed in to your claude.ai account | Transcript stored on Anthropic servers while connected, retained under the data-usage policy ([CC-rc], [CC-data]) |
| Credentials on the dev box | Whoever controls the box or the agent | claude.ai login in `~/.claude/.credentials.json` (mode 0600) ([CC-auth]); fine-grained GitHub token ([gh-pat]) |

## Findings by question

### 1. From a phone specifically

**Claude app + Remote Control is the first-party, purpose-built answer.**

- The Claude app "is a client for Claude Code sessions rather than a place where code runs". It reaches cloud sessions, a session on your own machine through Remote Control, or Desktop through Dispatch ([CC-mobile]).
- **Requirements** ([CC-rc]):
  - A claude.ai subscription: available on Pro, Max, Team and Enterprise. Team/Enterprise need an Owner toggle ([CC-features]).
  - No API key, and no custom `ANTHROPIC_BASE_URL`.
  - None of `DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` or `DISABLE_GROWTHBOOK` set. Worth knowing before an Ansible role sets "privacy" env vars.
  - Workspace trust accepted once per project directory.
- **What works from the phone:**
  - Push notifications, photo/file attachments, the diff pane, `/model`, `/effort`, `/compact`, `/clear` ([CC-rc]).
  - Local-only commands such as `/plugin` and `/resume` do not ([CC-rc]).
  - From the app, Remote Control sessions offer Manual, Accept edits and Plan. "You can't select Auto or Bypass permissions from the app" ([CC-perm]).
  - The starting mode can be set on the host, e.g. `claude remote-control --permission-mode acceptEdits` ([CC-perm]).
- **Server mode vs interactive** ([CC-rc]):
  - `claude remote-control` (server mode) serves many sessions (default capacity 32) and can give each a git worktree (`--spawn worktree`). During a network outage it "gives up after roughly 10 minutes" and exits.
  - An interactive `claude --remote-control` session "retries for as long as the outage lasts".
  - For a home server that will see ISP outages, run interactive sessions inside tmux (my reasoning from those two statements).
- **Third-party equivalent:** Happy (`slopus/happy`), an open-source mobile/web client that wraps `claude` and claims end-to-end encryption ([happy]). It is another off-tailnet relay, and it duplicates a first-party feature. Not evaluated further.

**SSH apps with a keyboard: workable, not pleasant.**

- **Blink Shell (iOS)**
  - Has mosh built in. Its Tailscale guide runs `mosh --install-static` and notes "no authentication was required, as Tailscale is automatically using your tailnet identity" ([blink-ts]).
  - Keys can be generated in the Secure Enclave, which "cannot be extracted" ([blink-keys]).
  - Blink+ is sold as an annual plan ([blink-faq]).
  - I found no Blink doc on backgrounding behaviour ([blink-mosh], [blink-faq]).
- **Termius (iOS, Android, desktop)**
  - Supports mosh on mobile ("Enable the `Use Mosh` setting"), with mosh 1.3.0+ through its own library ([termius-connect]).
  - Its own May 2026 post on "AI agents on mobile" recommends:
    - running the agent in tmux, plus mosh;
    - a customised shortcut bar (e.g. for Shift+Tab);
    - dictation, and gestures instead of arrow keys;
    - iOS Live Activities to keep sessions alive in the background ([termius-blog]). This is a vendor claim.
- **Termux (Android)**
  - Packages `mosh` 1.4.0 and `openssh` 10.5p1 ([termux-mosh], [termux-ssh]).
  - Its README warns: "Termux may be unstable on Android 12+. Android OS will kill any (phantom) processes greater than 32" ([termux-app]).
  - The stable build comes from F-Droid/GitHub; the Play Store build is experimental ([termux-app]).
- **a-Shell (iOS):** I could not confirm SSH or mosh client support from its README (**unverified**). Not recommended on that basis.

**What driving a terminal agent from a phone is actually like:**

- **The TUI leans on keys phones lack** ([CC-keys], [CC-agents], [CC-term]):
  - Shift+Tab cycles permission modes.
  - Esc, Ctrl+C, Ctrl+O and Ctrl+R are core.
  - `←` backgrounds or detaches in agent view.
  - Shift+Enter needs the tmux `extended-keys` config.
- **Scrollback is awkward:**
  - mosh syncs only the visible screen, not scrollback ([mosh-site]).
  - Attached background sessions always render fullscreen, where "tmux copy mode show[s] only the current viewport" ([CC-agents]).
- **The tailnet on iOS may itself be the weak link:** an open Tailscale issue (filed 2026-07-11, no maintainer response yet) reports the iOS network extension stalling SSH and mosh for 3–9 s about 3.5 times a minute on an iPad, with LAN traffic unaffected ([ts-20410]). It is one report on one device, so treat it as a risk, not a fact. Remote Control doesn't go through the tailnet, so it wouldn't be affected.

**Browser IDEs: poor on a phone, and they add a surface.**

- **code-server**
  - Its own guide recommends SSH port forwarding, which "you can't [use] … on machines without SSH clients (such as iPads)" ([cs-guide]).
  - Its iPad page lists known issues: "The keyboard disappear[s] sometimes", no Escape key on the Magic Keyboard, and self-signed certificates that are "an involved process" ([cs-ipad]).
  - It uses Open VSX, not Microsoft's marketplace ([cs-faq]).
- **openvscode-server:** "scoped at only making VS Code available as-is in the web browser" ([cs-faq]). Since v1.64 it has no authentication unless you pass `--connection-token` ([ovs]).
- **Blink Code** can open code-server or Codespaces inside Blink. It needs a `blink-fs` extension on the server, and private IPs must go through an SSH tunnel ([blink-code]).

**zellij web client: the tailnet-only browser terminal option.**

- zellij v0.43.0 (2025-08-05) added an opt-in built-in web server "to share their existing terminal sessions in the browser" ([zellij-0.43]).
- It detects mobile browsers and switches to a mobile interface ([zellij-web]).
- Security details ([zellij-web]):
  - Auth uses login tokens, stored hashed and shown once. Read-only tokens also exist.
  - It listens on `127.0.0.1:8082` by default.
  - HTTPS is "a hard requirement if listening on any interface that is not `127.0.0.1`".
  - It has no rate limiting.
- A `zellij-no-web` binary ships without it ([zellij-0.43]).
- Fronting it with `tailscale serve` keeps it inside the tailnet ([ts-serve]). I have not tested that combination (**unverified** in practice).

### 2. Persistent sessions: what survives what

| Option | Network drop | Phone or laptop reboot | Dev-box reboot |
| :-- | :-- | :-- | :-- |
| SSH + tmux | Survives: programs keep running in the tmux server; reattach ([tmux-wiki]) | Survives: reattach | **Lost**: tmux keeps all state in one server process ([tmux-wiki]). See note A. |
| mosh (+ tmux) | Survives roaming and drops; "the connection resumes when network service comes back" ([mosh-site]) | mosh client state is lost; reconnect and `tmux attach` (see note B) | Lost, as above |
| zellij | Survives: detach and reattach, like tmux (**unverified**: no zellij detach doc fetched) | Survives | Resurrection re-creates the layout from a snapshot taken every 1 s. Commands wait behind "Press `ENTER` to run…"; processes are not restored ([zellij-resurrect]). |
| zellij web client | Survives browser disconnect; sessions can be reopened by URL ([zellij-web]) | Survives | As zellij |
| code-server | A client can stay disconnected for the reconnection grace time, default 10800 s (3 h), then "must reload the window" ([cs-faq], [cs-cli]) | Same | Terminal processes end. VS Code's "process revive" relaunches the shell with restored content, not the program ([vscode-term]). |
| Claude Code background sessions (`claude agents`) | Survive: run under a supervisor with no terminal attached ([CC-agents]) | Survive | "Shutting down or restarting your machine stops running background sessions." Within 48 h they show as failed and "restart from where [they] left off" when you attach or reply ([CC-agents]). See note C. |
| Remote Control | Phone drop: messages queue and the session reconnects. Dev-box outage: interactive sessions retry indefinitely; server mode exits after ~10 min ([CC-rc]) | Survives: the session lives on the dev box, the transcript on Anthropic's side ([CC-rc]) | Process stops and the session goes offline. `claude remote-control` in the same directory brings sessions back for about 4 hours; after that, `claude --continue` ([CC-rc], [CC-sessions]) |
| Claude Code on the web | Unaffected: runs in an Anthropic VM ([CC-mobile]) | Unaffected | n/a. Idle sessions have their VM reclaimed; reopening restores the conversation, "background work … isn't restored" ([CC-web]) |

Notes:

- **A. Getting a tmux setup back after a dev-box reboot.**
  - tmux-continuum saves the tmux environment every 15 minutes, can start tmux at boot, and restores automatically ([continuum]).
  - tmux-resurrect restores only "a conservative list of programs" (`vi vim nvim emacs man less more tail top htop …`) by default. Others are configured with `@resurrect-processes`, which accepts a `->` restore command ([resurrect]).
  - So `"~claude->claude --continue"` should restart Claude on its last conversation. **Untested.**
  - tmux-resurrect was last pushed 2024-08-13 ([resurrect]).
- **B. mosh after a client reboot.**
  - mosh bootstraps over SSH, then runs a `mosh-server` process that talks UDP to that client ([mosh-readme]).
  - mosh.org promises survival across sleep ("put your laptop to sleep and wake it up later, keeping your connection intact"). For long-running sessions it shows `mosh host -- screen -dr`, which "reattaches to a long-running screen session" ([mosh-site]).
  - That a rebooted client can't pick its old mosh session back up is my reasoning, not a documented statement (**unverified**). Either way, tmux underneath makes the question moot.
- **C. Claude Code conversations survive any process death.**
  - They are saved continuously to local transcripts: plaintext under `~/.claude/projects/`, kept for 30 days by default ([CC-sessions], [CC-data]).
  - A tool that was mid-run when the process died "doesn't finish or run again when you resume" ([CC-sessions]).
  - Whether the background-session supervisor survives SSH logout under systemd-logind, and whether it can start at boot, is not documented. The docs mention being "installed as an OS service" without describing setup ([CC-agents]). **Unverified: test on the box.**

### 3. Claude Code on a headless box

- **Install:**
  - Supported on Ubuntu 20.04+ and Debian 10+, with 4 GB+ RAM ([CC-setup]).
  - The native installer auto-updates. Linux package-manager installs don't ([CC-setup]).
- **Login:**
  - `/login` prints a URL. Over SSH, "the browser shows a login code instead of redirecting back". Paste it at `Paste code here if prompted`, or use `claude auth login`, which reads it from stdin ([CC-auth], [CC-troubleshoot]).
  - On Linux the credential lands in `~/.claude/.credentials.json`, mode 0600 ([CC-auth]).
  - Do the login once over SSH from the laptop.
- **`claude setup-token` / `CLAUDE_CODE_OAUTH_TOKEN`:**
  - A one-year token for "environments where interactive browser login isn't available".
  - It "can only make model requests, so it can't establish Remote Control sessions" ([CC-auth]). Remote Control rejects it with "requires a full-scope login token" ([CC-rc]).
  - For this setup, use `/login`, not setup-token.
- **Expiry:** an unattended background or Remote Control session "that outlives the login stops making progress once the credential expires and can't recover until you sign in again" ([CC-auth]).
- **Interactive-terminal assumptions:**
  - First-run login and the workspace-trust dialog are interactive ([CC-auth], [CC-rc]).
  - `claude remote-control` asks `Enable Remote Control? (y/n)` once ([CC-rc]).
  - The TUI keybindings above assume a real keyboard ([CC-keys]).
  - Remote Control removes those assumptions for day-to-day phone use. Do the one-time interactive steps from the laptop.
- **Background-session support:**
  - Headless Linux is supported. The supervisor health-checks session host processes "on Linux and WSL" ([CC-agents]).
  - Idle, unattached sessions have their process stopped after about an hour and resume on attach. Pin with `Ctrl+T` to keep one running ([CC-agents]).
- **Claude Desktop "SSH sessions":** they run Claude Code on a remote Linux or macOS machine with Desktop as the interface, installing Claude Code there automatically ([CC-desktop]). This is a laptop GUI option. Whether the remote session keeps running with the laptop closed is not documented (**unverified**).

### 4. Security posture and minimum exposure

**The threat.** The box holds git credentials and runs an agent that executes commands and reads untrusted content. Anthropic's security page treats prompt injection as a live risk and recommends VMs for running scripts and tool calls ([CC-security]).

**Isolation of the dev box:**

- **Use a full VM.**
  - "A dedicated virtual machine provides the strongest separation, with its own kernel" ([CC-isolation]).
  - Unattended `--dangerously-skip-permissions` runs should always sit inside a container, VM or sandbox runtime. Claude Code refuses that flag as root on Linux ([CC-isolation]).
  - The built-in Bash sandbox on its own "is not sufficient for fully unattended runs" ([CC-isolation]).
- **Inside the VM, turn on the Bash sandbox as defence in depth.**
  - On Linux it needs `bubblewrap` and `socat`, plus an AppArmor profile on Ubuntu 24.04+ ([CC-sandbox]).
  - Unprivileged containers need an extra nested-sandbox setting ([CC-isolation]), one more reason for a VM over an LXC.
- **Mask credential files.** The sandbox can mask e.g. the `gh` token in `~/.config/gh/hosts.yml`: sandboxed commands see a sentinel, and the proxy substitutes the real token only on egress to allowed hosts such as `api.github.com` ([CC-sandbox]).

**Credentials:**

- **GitHub token:** use a fine-grained token limited "to only access specific repositories", with specific permissions and an expiry. GitHub recommends these over classic tokens ([gh-pat]). On a headless box without a credential store, `gh` "will fallback to writing the token to a plain text file" ([gh-cli]), which is why masking matters.
- **SSH agent:** don't forward the laptop's SSH agent into the dev box. My reasoning: a forwarded agent lets anything on the box use your laptop keys while you're connected. code-server's guide lists agent forwarding only as a convenience ([cs-guide]).
- **Phone SSH keys:** with Tailscale SSH the phone needs no SSH key at all ([blink-ts]). If you use keys, Blink's Secure Enclave keys are non-extractable ([blink-keys]).

**Network exposure by option:**

| Option | Minimum exposure | Needs a public surface? |
| :-- | :-- | :-- |
| SSH + tmux (+ mosh) | Tailscale SSH on the tailnet address. mosh needs UDP 60000–61000 between client and server ([mosh-readme]); keep it on the tailnet. | No |
| Remote Control | None inbound. Outbound HTTPS only ([CC-rc]). Control path runs through Anthropic and is gated by the claude.ai account. Can be switched off with `disableRemoteControl` ([CC-rc]). Trusted Devices (device enrolment + 18 h re-auth) is Team/Enterprise only ([CC-rc]). | No, but off-tailnet |
| zellij web client | Bind to `127.0.0.1` and front with `tailscale serve`, which shares "a local server securely within your tailnet" ([ts-serve], [zellij-web]). HTTPS on serve needs tailnet cert provisioning enabled ([ts-serve]). | No |
| code-server / openvscode-server | code-server: "**Never** expose code-server directly to the internet"; defaults to `localhost` with password auth, rate-limited to 2 attempts/min + 12/hour ([cs-guide]). openvscode-server: no auth without `--connection-token` ([ovs]). Front with `tailscale serve`. | No, unless you follow code-server's Let's Encrypt recipe ([cs-guide]) |
| Claude Code on the web | Nothing at home. Code is cloned into an Anthropic VM with a default network allowlist ("Trusted") ([CC-cloudenv]); GitHub access via the Claude GitHub App or your `gh` token ([CC-web]). | No |

**Tailscale specifics:**

- Tailscale SSH builds for Linux (not Android), macOS (not iOS), FreeBSD, OpenBSD and Plan 9 ([ts-tailssh]). The phone is always the client, never the server.
- mosh over Tailscale SSH had bugs in 2022 (1.26.x), fixed in later releases ([ts-4919]).
- Blink's current guide uses mosh over Tailscale ([blink-ts]).
- Check mode (periodic re-authentication for SSH) and its default period: **unverified**. tailscale.com's KB was unreachable from this network (TLS connection reset), so all Tailscale claims here come from the `tailscale/tailscale` source and issue tracker.

### 5. Hosted and hybrid alternatives

- **Claude Code on the web (cloud sessions)**
  - Research preview for Pro, Max, Team, and Enterprise seats that include Claude Code ([CC-web]).
  - Runs in an isolated Anthropic-managed VM ([CC-security]).
  - Starts from the Claude app's Code tab or `claude --cloud` ([CC-mobile], [CC-web]).
  - Needs GitHub, either through the Claude GitHub App or `/web-setup` using your `gh` token. `claude --cloud` can instead upload a local repo under 100 MB ([CC-web]).
  - No separate compute charge; it shares your plan's rate limits ([CC-web]).
  - Idle VMs are reclaimed ([CC-web]).
  - **Verdict:** makes this ticket unnecessary for GitHub-hosted work that doesn't need home-network access, and is the fallback when the NUC is down. It doesn't replace the dev box for anything that needs local tools, the LAN, or non-GitHub repos.
- **Self-hosted environments:** public beta on Team/Enterprise plans only, GitHub repos only. Anthropic's own page says that to run on "your own always-on machine and drive it from other devices, use Remote Control, which is also available on Pro and Max plans" ([CC-selfhost]). Not a fit.
- **Dispatch:** messages a task to the Desktop app on your computer. Pro/Max only ([CC-mobile], [CC-features]). Desktop on Linux is beta ([CC-desktop]). It is a GUI app, so it's a poor fit for a headless VM (my reasoning).
- **GitHub Codespaces**
  - Browser VS Code on GitHub's VMs.
  - Idle timeout defaults to 30 minutes, configurable 5–240 minutes. "Terminal activity, either input or output, also resets the idle timeout period" ([cs-timeout]).
  - Included usage on GitHub Free: 120 hours of compute and 15 GB-month of storage. On Pro: 180 hours and 20 GB-month. A 2-core machine is $0.18/hour after that ([cs-billing]).
  - Viable, but it adds a second hosted environment, and a browser IDE on a phone has the problems described above.

## Effects on other tickets

- **The remote access architecture**
  - The dev box needs no public entries.
  - It needs Tailscale SSH and an ACL: your devices → dev box on 22/tcp and 60000–61000/udp.
  - Add Remote Control to the service table as an off-tailnet control path, or rule it out.
  - Decide whether the dev box may reach any other host on the tailnet at all.
- **The service platform shape**
  - Make the dev box a full VM, not an LXC: Anthropic's isolation guidance ranks VMs strongest, and the Bash sandbox needs extra setup in unprivileged containers ([CC-isolation]).
  - Minimum 4 GB RAM for Claude Code ([CC-setup]).
- **Secrets, and who can reach them if I can't:** dev-box credentials (claude.ai login, fine-grained GitHub token) are personal and not load-bearing. Keep them out of the succession set. Their expiry is a rotation item, not an emergency.
- **Surviving six months of neglect** and **Monitoring and alerting:** the dev box's login and token will lapse under neglect. That's acceptable. Don't alert the second person about the dev box.
- **How the rebuild runs:**
  - An Ansible role can install Tailscale, tmux (with the three config lines above), mosh, and Claude Code via the native installer.
  - `/login` and the Remote Control confirmation are human steps, which makes them wizard candidates.
- **Backup architecture:** the dev box can be treated as disposable if every repo has a remote. Only local transcripts (30-day retention) would be lost ([CC-data]).

## Open questions for the user

1. Is an Anthropic-relayed control path (Remote Control) acceptable under the private-only default? The phone recommendation hinges on this.
2. Which Claude plan is in use? Remote Control works on Pro/Max as-is; on Team/Enterprise an Owner must enable it ([CC-rc]).
3. iPhone or Android? That decides Blink vs Termux/Termius for the fallback.
4. Are all personal repos on GitHub? That decides how far cloud sessions can stand in when the box is down.

## Could not verify

- Everything on tailscale.com's KB (SSH, Serve, Funnel, iOS pages): the connection was reset from this network. Claims were sourced to Tailscale's source code and issue tracker instead. Check-mode behaviour and period remain unverified.
- The claude.ai login lifetime (only the 3-day warning is documented).
- Whether Claude Code's background-session supervisor survives SSH logout under systemd-logind, or can start at boot.
- Whether Claude Desktop SSH sessions keep running with the laptop closed.
- Blink and Termius background behaviour on iOS, apart from Termius's own Live Activities claim; Blink+ price; whether Termius's free tier includes mosh.
- a-Shell SSH/mosh client support.
- Whether a mosh client can resume its old session after the phone or laptop reboots (not stated on mosh.org).
- zellij detach/reattach specifics, and zellij web behind `tailscale serve` in practice.
- The tmux-resurrect `claude --continue` restore recipe.
- Tailscale issue #20410 is a single unconfirmed report.

## Sources

All fetched 2026-09-11. Release dates are from each project's GitHub releases.

**Anthropic — Claude Code docs** (current release v2.1.268, 2026-09-10)

- [CC-release] Claude Code releases — https://github.com/anthropics/claude-code/releases
- [CC-auth] Authentication — https://code.claude.com/docs/en/authentication
- [CC-rc] Remote Control — https://code.claude.com/docs/en/remote-control
- [CC-mobile] Claude Code on mobile — https://code.claude.com/docs/en/mobile
- [CC-agents] Agent view (background sessions) — https://code.claude.com/docs/en/agent-view
- [CC-sessions] Manage sessions — https://code.claude.com/docs/en/sessions
- [CC-troubleshoot] Troubleshoot installation and login — https://code.claude.com/docs/en/troubleshoot-install
- [CC-perm] Permission modes — https://code.claude.com/docs/en/permission-modes
- [CC-term] Terminal configuration (tmux) — https://code.claude.com/docs/en/terminal-config
- [CC-keys] Interactive mode (keybindings) — https://code.claude.com/docs/en/interactive-mode
- [CC-setup] Advanced setup — https://code.claude.com/docs/en/setup
- [CC-sandbox] Sandboxing — https://code.claude.com/docs/en/sandboxing
- [CC-isolation] Sandbox environments — https://code.claude.com/docs/en/sandbox-environments
- [CC-security] Security — https://code.claude.com/docs/en/security
- [CC-data] Data usage — https://code.claude.com/docs/en/data-usage
- [CC-web] Claude Code on the web — https://code.claude.com/docs/en/claude-code-on-the-web
- [CC-cloudenv] Cloud environments — https://code.claude.com/docs/en/cloud-environments
- [CC-selfhost] Self-hosted environments — https://code.claude.com/docs/en/self-hosted-environments
- [CC-desktop] Desktop (SSH sessions, Dispatch) — https://code.claude.com/docs/en/desktop
- [CC-features] Feature availability — https://code.claude.com/docs/en/feature-availability

**Terminal multiplexers**

- [tmux-wiki] tmux Getting Started wiki — https://github.com/tmux/tmux/wiki/Getting-Started (tmux 3.7c, 2026-08-17)
- [resurrect] tmux-resurrect, restoring programs — https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_programs.md (last push 2024-08-13)
- [continuum] tmux-continuum — https://github.com/tmux-plugins/tmux-continuum
- [zellij-web] zellij web client — https://zellij.dev/documentation/web-client.html
- [zellij-resurrect] zellij session resurrection — https://zellij.dev/documentation/session-resurrection.html
- [zellij-0.43] zellij v0.43.0 release notes — https://github.com/zellij-org/zellij/releases/tag/v0.43.0 (2025-08-05; latest v0.45.1, 2026-08-28)

**mosh**

- [mosh-site] mosh.org — https://mosh.org/
- [mosh-readme] mosh README — https://github.com/mobile-shell/mosh (latest release 1.4.0, October 2022; repo last pushed 2026-03-22)

**Browser IDEs**

- [cs-guide] code-server guide — https://github.com/coder/code-server/blob/main/docs/guide.md
- [cs-faq] code-server FAQ — https://github.com/coder/code-server/blob/main/docs/FAQ.md
- [cs-ipad] code-server on iPad — https://github.com/coder/code-server/blob/main/docs/ipad.md
- [cs-cli] code-server CLI source — https://github.com/coder/code-server/blob/main/src/node/cli.ts (v4.137.0, 2026-09-11)
- [ovs] openvscode-server README — https://github.com/gitpod-io/openvscode-server (openvscode-server-v1.109.5, 2026-02-20)
- [vscode-term] VS Code terminal persistent sessions — https://code.visualstudio.com/docs/terminal/advanced

**Tailscale** (v1.102.4, 2026-09-10)

- [ts-set] `tailscale set` flags — https://github.com/tailscale/tailscale/blob/main/cmd/tailscale/cli/set.go
- [ts-serve] `tailscale serve` / `funnel` help text — https://github.com/tailscale/tailscale/blob/main/cmd/tailscale/cli/serve_v2.go
- [ts-tailssh] Tailscale SSH server build constraints — https://github.com/tailscale/tailscale/blob/main/ssh/tailssh/tailssh.go
- [ts-20410] Issue #20410, iOS extension stalls SSH/mosh (open) — https://github.com/tailscale/tailscale/issues/20410
- [ts-4919] Issue #4919, mosh with Tailscale SSH (closed 2022) — https://github.com/tailscale/tailscale/issues/4919

**Phone clients**

- [blink-ts] Blink + Tailscale + mosh — https://docs.blink.sh/integrations/tailscale+mosh
- [blink-keys] Blink SSH keys — https://docs.blink.sh/basics/ssh-keys
- [blink-code] Blink Code — https://docs.blink.sh/advanced/code
- [blink-mosh] Blink advanced mosh — https://docs.blink.sh/advanced/advanced-mosh
- [blink-faq] Blink FAQ — https://docs.blink.sh/faq
- [termius-connect] Termius, connecting to a server (Mosh) — https://docs.termius.com/organize-and-connect-to-hosts/connecting-to-a-server
- [termius-blog] Termius, 8 tips for using AI agents on mobile (2026-05-11) — https://termius.com/blog/8-tips-for-using-ai-agents-on-mobile-in-termius
- [termux-app] Termux app README — https://github.com/termux/termux-app (v0.118.3, 2025-05-22)
- [termux-mosh] Termux mosh package — https://github.com/termux/termux-packages/blob/master/packages/mosh/build.sh
- [termux-ssh] Termux openssh package — https://github.com/termux/termux-packages/blob/master/packages/openssh/build.sh
- [happy] Happy (third-party Claude Code mobile client) — https://github.com/slopus/happy (cli-1.2.3, 2026-09-05)

**GitHub**

- [gh-pat] Managing personal access tokens — https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- [gh-cli] `gh auth login` manual — https://cli.github.com/manual/gh_auth_login
- [cs-timeout] Codespaces timeout period — https://docs.github.com/en/codespaces/setting-your-user-preferences/setting-your-timeout-period-for-github-codespaces
- [cs-billing] Codespaces billing — https://docs.github.com/en/billing/concepts/product-billing/github-codespaces

[CC-release]: https://github.com/anthropics/claude-code/releases
[CC-auth]: https://code.claude.com/docs/en/authentication
[CC-rc]: https://code.claude.com/docs/en/remote-control
[CC-mobile]: https://code.claude.com/docs/en/mobile
[CC-agents]: https://code.claude.com/docs/en/agent-view
[CC-sessions]: https://code.claude.com/docs/en/sessions
[CC-troubleshoot]: https://code.claude.com/docs/en/troubleshoot-install
[CC-perm]: https://code.claude.com/docs/en/permission-modes
[CC-term]: https://code.claude.com/docs/en/terminal-config
[CC-keys]: https://code.claude.com/docs/en/interactive-mode
[CC-setup]: https://code.claude.com/docs/en/setup
[CC-sandbox]: https://code.claude.com/docs/en/sandboxing
[CC-isolation]: https://code.claude.com/docs/en/sandbox-environments
[CC-security]: https://code.claude.com/docs/en/security
[CC-data]: https://code.claude.com/docs/en/data-usage
[CC-web]: https://code.claude.com/docs/en/claude-code-on-the-web
[CC-cloudenv]: https://code.claude.com/docs/en/cloud-environments
[CC-selfhost]: https://code.claude.com/docs/en/self-hosted-environments
[CC-desktop]: https://code.claude.com/docs/en/desktop
[CC-features]: https://code.claude.com/docs/en/feature-availability
[tmux-wiki]: https://github.com/tmux/tmux/wiki/Getting-Started
[resurrect]: https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_programs.md
[continuum]: https://github.com/tmux-plugins/tmux-continuum
[zellij-web]: https://zellij.dev/documentation/web-client.html
[zellij-resurrect]: https://zellij.dev/documentation/session-resurrection.html
[zellij-0.43]: https://github.com/zellij-org/zellij/releases/tag/v0.43.0
[mosh-site]: https://mosh.org/
[mosh-readme]: https://github.com/mobile-shell/mosh
[cs-guide]: https://github.com/coder/code-server/blob/main/docs/guide.md
[cs-faq]: https://github.com/coder/code-server/blob/main/docs/FAQ.md
[cs-ipad]: https://github.com/coder/code-server/blob/main/docs/ipad.md
[cs-cli]: https://github.com/coder/code-server/blob/main/src/node/cli.ts
[ovs]: https://github.com/gitpod-io/openvscode-server
[vscode-term]: https://code.visualstudio.com/docs/terminal/advanced
[ts-set]: https://github.com/tailscale/tailscale/blob/main/cmd/tailscale/cli/set.go
[ts-serve]: https://github.com/tailscale/tailscale/blob/main/cmd/tailscale/cli/serve_v2.go
[ts-tailssh]: https://github.com/tailscale/tailscale/blob/main/ssh/tailssh/tailssh.go
[ts-20410]: https://github.com/tailscale/tailscale/issues/20410
[ts-4919]: https://github.com/tailscale/tailscale/issues/4919
[blink-ts]: https://docs.blink.sh/integrations/tailscale+mosh
[blink-keys]: https://docs.blink.sh/basics/ssh-keys
[blink-code]: https://docs.blink.sh/advanced/code
[blink-mosh]: https://docs.blink.sh/advanced/advanced-mosh
[blink-faq]: https://docs.blink.sh/faq
[termius-connect]: https://docs.termius.com/organize-and-connect-to-hosts/connecting-to-a-server
[termius-blog]: https://termius.com/blog/8-tips-for-using-ai-agents-on-mobile-in-termius
[termux-app]: https://github.com/termux/termux-app
[termux-mosh]: https://github.com/termux/termux-packages/blob/master/packages/mosh/build.sh
[termux-ssh]: https://github.com/termux/termux-packages/blob/master/packages/openssh/build.sh
[happy]: https://github.com/slopus/happy
[gh-pat]: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
[gh-cli]: https://cli.github.com/manual/gh_auth_login
[cs-timeout]: https://docs.github.com/en/codespaces/setting-your-user-preferences/setting-your-timeout-period-for-github-codespaces
[cs-billing]: https://docs.github.com/en/billing/concepts/product-billing/github-codespaces
