# How the Qidi Plus 4 exposes itself

Research for the ticket "How the Qidi Plus 4 exposes itself" on the home server map. Researched 2026-09-11. Claims cite the sources listed at the end as [S#]. Anything I could not confirm directly is marked **Unverified** or **Inferred**.

## Authentication out of the box: effectively none

**The printer's web UI (Fluidd) and its Moonraker API do not protect anything from other devices on the home network.**

- Moonraker gives full API access, with no credentials, to any client listed in `trusted_clients` [S10]. Qidi's `moonraker.conf`:
  - trusts every private IPv4 range, plus loopback and link-local: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`, `169.254.0.0/16`, `FE80::/10`, `::1/128`
  - listens on `0.0.0.0:7125`
  - sets no `force_logins`

  Qidi publishes this exact block for the Q1 Pro, Q2 and Max 4 [S14]. It has not published the Plus 4 file, but the community Plus 4 wiki shows the same list [S29a]. **Inferred** to be the same on the Plus 4.
- Fluidd has no login of its own. It uses Moonraker's, and trusted clients skip the login screen [S30a].
- Qidi's Moonraker fork adds a check that lets any request from a loopback IP straight through. That check runs **before** the JWT, API-key and `force_logins` checks [S5]. Upstream Moonraker has no such check [S9].
- The fork also takes the client IP from the `X-Real-Ip` / `X-Forwarded-For` request headers [S6, S13]. So by the published source, a request to port 7125 carrying `X-Real-Ip: 127.0.0.1` skips authentication even after logins are forced. **Inferred from source, not tested on a printer.** Qidi has published no source for any firmware after V1.7.1 [S28].
- SSH is on, with Qidi's own documented default login `mks` / `makerbase` [S20, S21]. The community reports that `root` has the same password and can log in directly [S29b]. Qidi does not document this (**Unverified**).

**Consequence:** anything that can send traffic from a private address controls the printer. That includes a tunnel connector or reverse proxy running on the home server. Control means heaters, motion, G-code, files and the printer's own config. Turning on logins in Fluidd is not a reliable fix on stock firmware.

## Recommendation

1. **Reach the printer remotely only over Tailscale, never through Cloudflare Tunnel.** Route the printer's LAN address from the home-server side (a Tailscale subnet route), so nothing is installed on the printer. That makes remote printer access a thin tunnelling problem, not an extra service. It also matches the map's standing rule that every admin surface goes through Tailscale.
2. **Leave the printer stock, in LAN-only mode.** No agents on the printer, no vendor cloud. Stock is what Qidi supports, and what its updates keep working [S7, S8, S25].
3. **Connect Home Assistant with the HACS "Moonraker" custom integration** on port 7125 [S37].
4. **Do not host Mainsail or Fluidd separately.** It adds no protection (section 5c).
5. **Treat self-hosted Obico as an optional service, not as the remote-access answer.** It adds AI failure detection and a login in front of monitoring. The cost is a Docker service running an ML model, plus an unsupported agent on the printer [S33 to S36].

**Why:** the printer has no security boundary of its own, so the only safe design keeps it off every path a stranger's request can reach. Tailscale is already on the map for exactly that. Putting Cloudflare Access in front of a tunnel would make Access the only lock on a device that gives any trusted LAN client full control. Mainsail's docs warn against exposing Moonraker to the internet at all [S32].

## 1. Software stack

| Layer | What ships | Sources |
|---|---|---|
| Printer firmware | Klipper, Qidi's fork `QIDITECH/klipper` (branch `PLUS4`). Its newest upstream change is dated 2023-12-16, just after Klipper v0.12.0 (2023-11-10). Upstream Klipper is at v0.13.0 (2025-04-11). | [S1, S2, S8, S41] |
| API server | Moonraker, Qidi's fork `QIDITECH/moonraker` (branch `PLUS4`; last commit 2025-07-22, "update v1.7.0"). Its changelog lists as "Unreleased" features that upstream shipped in v0.9.0 (2024-07-25), so the fork predates v0.9.0. Upstream Moonraker is at v0.11.0 (2026-08-25). | [S2, S5, S12] |
| Web UI | Fluidd v1.30.4 with a Qidi theme; upstream released v1.30.4 on 2024-09-12 and is now at v1.37.5. No Mainsail. nginx serves it on port 80. | [S4, S31, S29f] |
| Touchscreen | `xindi`: Qidi's closed-source screen daemon, which also handles USB storage, networking and firmware updates. Runs as root from `/root/xindi`. | [S4, S29f] |
| Vendor cloud client | `QIDILink-client`: a closed-source binary run as root from `/root/QIDILink-client/udp_server`. Its strings show a small embedded HTTP server. | [S4, S29d] |
| OS / hardware | Rockchip quad-core, max 1.2 GHz; kernel `5.16.20-rockchip64`; Klipper runs in a Python 3.7 virtualenv; 32 GB eMMC; 2.4 GHz Wi-Fi and Ethernet. Python 3.7 points to a Debian 10 base, whose LTS support ended 2024-06-30 (**Inferred**). | [S4, S24, S29f, S40] |

**Firmware versions.**
- The newest release on GitHub is V1.7.1 (2025-08-06) [S3].
- Owners report 1.7.2, 1.7.3 and 1.8.2 arriving through the touchscreen's online update, with no matching GitHub release or source. Issues asking for the code run from 2025-10 to 2026-06 [S28].
- Qidi's wiki (updated 2026-09-05) says only firmware up to V1.7.1 supports QIDI Link, and later firmware supports only QIDI Maker [S15].

All source analysis in this document is of the published V1.7.0 / V1.7.1 code.

## 2. What the printer exposes on the LAN

| Port | Service | Auth | Sources |
|---|---|---|---|
| 80/tcp | nginx: the Fluidd UI, which talks to Moonraker | Moonraker's (above) | [S29a, S29f] |
| 7125/tcp | Moonraker HTTP and websocket API, on all interfaces | Trusted clients = all private ranges | [S4] (the update script calls `127.0.0.1:7125`), [S14] |
| 8080/tcp | `mjpg_streamer` camera: `/?action=stream`, `/?action=snapshot` | None set in the documented options (**Unverified** beyond that) | [S29e, S29f] |
| 22/tcp | SSH with password login, `mks` / `makerbase` | Default password | [S20, S21, S29b] |
| unknown | `QIDILink-client` `udp_server` | Unknown | [S4]; port and protocol **Unverified** |
| outbound | QIDI Link / QIDI Maker cloud: AWS outside China, Aliyun in China | Qidi account | [S19] |

- **nginx and client IPs:** whether nginx passes the real client IP on to Moonraker is **Unverified**. The nginx config lives in the base system image, not in the update package.
- **What full API access means:**
  - Qidi's wiki says Fluidd moves the print head, monitors and sets temperatures, and starts and stops prints [S18].
  - The community wiki edits `moonraker.conf` through Fluidd's config editor [S29a].
  - Fluidd can restart services such as `webcamd` [S29e].

## 3. Authentication in detail

- Moonraker always loads its authorization component: `authorization` is in `CORE_COMPONENTS` in both upstream and Qidi's fork [S11]. Upstream defaults are:
  - `trusted_clients`: empty
  - `force_logins`: `False`
  - API keys: enabled [S10]
- Qidi's fork checks each request in this order (`authenticate_request`) [S5]:
  1. `OPTIONS` requests pass.
  2. **Qidi's addition:** a loopback client IP passes, with no user attached:
     ```python
     # Allow local request
     ip = ipaddress.ip_address(request.remote_ip)
     if ip.is_loopback:
         return None
     ```
  3. JWT, one-shot token, then the `X-Api-Key` header.
  4. If `force_logins` is on and at least one user exists, the request gets 401.
  5. A trusted client IP passes.
  6. Anything else gets 401.
- Upstream's version of this function has no loopback step [S9]. Since v0.11.0 (2026-08-25) upstream also checks that any proxy in front of Moonraker is itself trusted [S12].
- The HTTP handlers only reject a request if that function raises an error. When it returns `None`, the request goes through [S6]. The websocket handlers call the same function [S6].
- The fork runs Tornado with `xheaders=True` [S6]. Tornado then replaces the client IP with the `X-Real-Ip` (or `X-Forwarded-For`) header value whenever that value is a valid IP [S13]. Upstream v0.11.0 added a `use_xheaders` switch to turn this off for direct access [S12].
- **Result:** anyone who can reach port 7125 can claim to be `127.0.0.1` and skip step 4. **Inferred from source only.** It has not been tested on a printer, and I did not check which Tornado version the printer runs.
- **Knock-on effect of adding a Fluidd user:** QIDI Studio then needs the Moonraker API key to send prints [S18].

**Confirming on the real printer** (read-only; for whichever task first touches it):
- `ssh mks@<printer>`, then `cat ~/printer_data/config/moonraker.conf`, to see the actual `[authorization]` block.
- From another LAN machine, `curl http://<printer>:7125/access/info`. Moonraker reports `"trusted"` and `"login_required"` for the caller [S5].

## 4. Camera

- **Built in.** Qidi lists a "Low Framerate Camera (Up to 1080P)" with timelapse support [S24]. The community confirms one built-in USB camera and shows how to add more [S29e].
- **How it is served.** `mjpg_streamer` is configured in `webcam.txt` and restarted through the `webcamd` service [S17, S29e, S29f]. Qidi sets resolution and frame rate there (example `-r 1080x720 -f 10`) and warns not to exceed 10 fps, because a higher rate affects printing [S17].
- **Stream format.** MJPEG over HTTP on port 8080 (`/?action=stream`, `/?action=snapshot`); Fluidd's default camera entry uses a relative URL through nginx [S29e]. The documented options set no credentials; beyond that, whether the stream has any auth is **Unverified**.
- **Where else it shows up.** The HACS Moonraker integration can show it in Home Assistant [S37]. QIDI Link and QIDI Maker show it through Qidi's cloud [S19, S22, S27].

## 5. Remote access options

### a. Tunnel the printer's own UI as-is

- **Cloudflare Tunnel: not recommended.**
  - The connector reaches the printer from a private LAN address. Every request that clears Cloudflare Access therefore arrives as a trusted client with full control, and Access becomes the only lock.
  - A connector running on the printer itself would arrive as loopback and skip forced logins as well [S5].
  - Mainsail's docs: "Please do not open ports of Mainsail/Moonraker in your router to the rest of the world." [S32]
- **Tailscale: recommended.**
  - The community guide installs Tailscale on the printer and adds `100.64.0.0/10` to `trusted_clients`. It also notes that a subnet router avoids touching the printer's firmware [S29a].
  - The subnet-router form keeps the printer stock.
  - Open detail: tailnet traffic may arrive from a LAN address and need no Moonraker change. That depends on the subnet router's source-NAT setting, which is **Unverified here** and belongs to the remote access architecture ticket.

### b. Obico, self-hosted (optional)

- **Server.** Needs Docker and Docker Compose, at least 4 GB RAM and a CPU from about the last decade; an NVIDIA GPU is optional. It also needs an SMTP account for email [S34, S35]. Licensed AGPL-3.0; last pushed 2026-09-10 [S35].
- **Printer side.** The `moonraker-obico` agent has to be installed on the printer. Obico's Plus 4 guide does this over SSH with `mks` / `makerbase` and KIAUH, then points the agent at your server URL [S33, S36].
- **Gains.** AI failure detection, and remote monitoring behind the Obico server's own accounts [S33, S35].
- **Costs:**
  - another always-on service running an ML model on the NUC
  - an unsupported agent on the printer. Qidi warns that manual changes may affect after-sales service, and not to update Klipper or Moonraker with KIAUH [S7, S8].
  - the Obico server still needs its own remote access path
  - it does nothing about the printer being open to the LAN
- **Verdict.** Decide it on its own merits in the service platform shape ticket.

### c. Mainsail or Fluidd hosted separately (not recommended)

- **How it works.** Both are static web apps: the browser talks straight to the printer's Moonraker, which must allow the UI's origin in `cors_domains` [S30b]. Qidi's published configs already allow `my.mainsail.xyz` and `app.fluidd.xyz` [S14].
- **What it adds.** No authentication and no new network path; the only gain is a newer UI than the bundled Fluidd 1.30.4.

### d. Vendor cloud: QIDI Link / QIDI Maker (not recommended)

- **Which app.** QIDI Link covers firmware up to V1.7.1 and QIDI Maker covers later firmware. QIDI Maker currently supports the Max 4, Q2 and Plus 4 [S15, S26].
- **Setup.** Needs a Qidi account, and the printer is bound to it by scanning a QR code on its screen. Outside China the service runs on AWS [S19, S22].
- **Features.** Remote control, live view and timelapse. "Expert mode enables Fluidd control" from the app [S19, S27].
- **On the printer.** The client is a closed-source binary running as root [S4, S29d].
  - Qidi: in LAN-only mode "the printer cannot connect to QIDI cloud services" [S18].
  - The update package re-enables the client only when the printer is not in LAN-only mode [S4].
- **Privacy.**
  - App Store labels: QIDI Link may use identifiers to track you, and QIDI Maker collects your email address [S27].
  - A community post claims QIDI Link put the printer on an unencrypted public URL (**Unverified**) [S29d].
  - Owners describe the remote features as unreliable (anecdotal) [S28].
- **Verdict.** It contradicts the map's private-biased access posture.

## 6. Firmware updates, modifications and support

**What an official update does.** In the V1.7.1 package, `QD_Plus4_SOC` is a Debian package named `QIDI-X-Plus4` [S4]:
- **Before installing (`preinst`):** stops and disables `QIDILink-client`, and backs up `printer.cfg` and `gcode_macro.cfg` with a timestamp.
- **Overwrites:** `printer.cfg`, `gcode_macro.cfg`, `box*.cfg`, the filament list, the whole `~/fluidd` directory, parts of Klipper (`klippy.py`, `gcode.py`) and of Moonraker (`metadata.py`), `xindi`, the QIDI Link binary, and the Wi-Fi drivers.
- **After installing (`postinst`):** runs `chmod 777 -R` on the config directory and restarts Klipper and Moonraker. If the printer is not in LAN-only mode, it enables and starts `QIDILink-client`.
- **Qidi's release note:** "After updating, the Klipper configuration file will be replaced … printer recalibration will be required." [S1, S3]

**What survives an update.**
- The package does not contain `moonraker.conf`, the nginx config, `webcam.txt`, SSH settings or any third-party services. Changes to those survive **this** package. That is **Inferred** from its contents; the later online-update packages are unpublished and I did not check them.
- A replacement Fluidd, or anything else installed at `~/fluidd`, would be overwritten.
- Reflashing the eMMC image (Qidi's recovery path) wipes everything [S23].

**Support and warranty.**
- Qidi's Moonraker fork says: "Please note that manual updates may affect normal after-sales service." [S7]
- Qidi's Klipper fork says: "Please avoid using Kiauh or git to manually update Klipper, Moonraker, as this may cause the printer to malfunction." [S8]
- The warranty (updated 2026-06-04) runs one year for consumers, up to two in the EU. It excludes "Unauthorized modification, disassembly, or repair" and "Damage caused by use of third-party accessories, unofficial firmware, or unofficial modification tools" [S25].
- Yet Qidi's own wiki tells owners to SSH in with the default login to replace Fluidd or delete Moonraker's database [S20, S21]. So SSH access itself is a documented path. How Qidi would treat an added agent such as Obico or Tailscale is **Unverified**.
- FreeDi is a community replacement firmware with mainline Klipper, Moonraker and Mainsail. It supports the Plus 4 (v2.10, 2026-06-14), and its README warns that modifications may void the warranty [S39]. Nothing on this map needs it.

## 7. Home Assistant

- **No core integration.** Home Assistant core has no `moonraker` integration (checked 2026-09-11) [S38].
- **The usual route** is the HACS custom integration "Moonraker" (`marcolivierarsenault/moonraker-home-assistant`). Its docs call it non-official. Latest release 1.13.4 on 2026-07-13; last pushed 2026-09-07 [S37].
- **Setup.** Asks for host, port (default 7125), TLS, an optional API key, and a printer name. It polls every 30 s by default and keeps retrying when the printer is powered off [S37].
- **What it provides.** Sensors, the camera, print thumbnails, an emergency-stop button and buttons that run macros [S37].
- **Auth.** With Qidi's config, a Home Assistant VM on the LAN is a trusted client, so no key is needed. If the printer is ever locked down, give Home Assistant an API key [S10, S37].
- **Alternative (not evaluated).** Moonraker's own MQTT component, using the example Home Assistant YAML in Moonraker's docs. Both `components/mqtt.py` and `docs/example-home-assistant.yaml` are present in Qidi's fork [S5].

## What this changes elsewhere on the map

- **The remote access architecture.**
  - Treat the printer as unauthenticated: keep it off Cloudflare Tunnel, and give it a Tailscale-only path.
  - New question: should the printer also be firewalled from the rest of the LAN, since being on the LAN is enough to control it?
- **Surviving six months of neglect.** The printer cannot take part in the auto-update design. Its updates are started by hand from the touchscreen and rewrite its config. The source Qidi publishes lags the firmware owners actually run.
- **Secrets, and who can reach them if I can't.** The printer's SSH password (still the default today) and any Moonraker API key become secrets.
- **The service platform shape.** Obico is an optional extra service, and the printer's Home Assistant integration needs HACS.
- **Whichever task first touches the printer.** Record the installed firmware version, and run the read-only checks in section 3.

## Not verified

- The Plus 4's actual `moonraker.conf`; Qidi publishes it for the Q1 Pro, Q2 and Max 4 only.
- Whether nginx on the Plus 4 passes the real client IP to Moonraker.
- Whether the loopback and header bypass works on real hardware, including on firmware 1.7.2 and later.
- The Tornado version on the printer.
- The QIDI Link client's listening port and protocol.
- Whether the camera stream has any auth.
- What firmware 1.7.2 through 1.8.2 contain, and whether their updates keep changes made on the printer.
- How Qidi's warranty treats added agents.
- The community claim that QIDI Link exposed an unencrypted public URL.

## Sources

All accessed 2026-09-11.

- **S1** QIDI Plus 4 repo README. https://github.com/QIDITECH/QIDI_PLUS4
- **S2** QIDI Plus 4 submodules (`klipper` and `moonraker`, branch `PLUS4`). https://github.com/QIDITECH/QIDI_PLUS4/blob/main/.gitmodules
- **S3** QIDI Plus 4 releases; V1.7.1 published 2025-08-06. https://github.com/QIDITECH/QIDI_PLUS4/releases
- **S4** V1.7.1 update package, downloaded and unpacked: `QD_Update/QD_Plus4_SOC`, a Debian package (`control`, `preinst`, `postinst`, payload listing, `root/xindi/version`, `home/mks/fluidd/.version`). https://github.com/QIDITECH/QIDI_PLUS4/releases/download/Plus4_v1.7.1/PLUS4_V1.7.1.rar
- **S5** Qidi's Moonraker fork, branch `PLUS4`: `authorization.py` (`authenticate_request`, `/access/info` handler), commit history, file tree. https://github.com/QIDITECH/moonraker/blob/PLUS4/moonraker/components/authorization.py
- **S6** Qidi's Moonraker fork, branch `PLUS4`: `application.py` (`xheaders=True`, request handlers) and `websockets.py`. https://github.com/QIDITECH/moonraker/blob/PLUS4/moonraker/components/application.py
- **S7** Qidi's Moonraker fork README. https://github.com/QIDITECH/moonraker
- **S8** Qidi's Klipper fork README, and `docs/Config_Changes.md` on branch `PLUS4`. https://github.com/QIDITECH/klipper, https://github.com/QIDITECH/klipper/blob/PLUS4/docs/Config_Changes.md
- **S9** Upstream Moonraker `authorization.py`. https://github.com/Arksine/moonraker/blob/HEAD/moonraker/components/authorization.py
- **S10** Moonraker configuration docs, `[authorization]` and `[server]`. https://moonraker.readthedocs.io/en/latest/configuration/
- **S11** Upstream Moonraker `server.py` (`CORE_COMPONENTS`); same list in Qidi's fork. https://github.com/Arksine/moonraker/blob/HEAD/moonraker/server.py
- **S12** Upstream Moonraker changelog (v0.9.0 2024-07-25, v0.11.0 2026-08-25). https://github.com/Arksine/moonraker/blob/HEAD/docs/changelog.md
- **S13** Tornado `httpserver.py`, `_apply_xheaders`. https://github.com/tornadoweb/tornado/blob/HEAD/tornado/httpserver.py
- **S14** Qidi's published `moonraker.conf` files:
  - Q1 Pro: https://github.com/QIDITECH/QIDI_Q1_Pro/blob/HEAD/config/moonraker.conf
  - Q2: https://github.com/QIDITECH/QIDI_Q2/blob/HEAD/config/moonraker.conf
  - Max 4 (last changed 2026-08-06): https://github.com/QIDITECH/QIDI_MAX4/blob/HEAD/config/moonraker.conf
- **S15** QIDI Wiki, X-Plus 4 index (updated 2026-09-05). https://wiki.qidi3d.com/en/X-Plus4
- **S16** QIDI Wiki, X-Plus 4 firmware update (updated 2026-09-05). https://wiki.qidi3d.com/en/X-Plus4/Manual/firmware-update
- **S17** QIDI Wiki, X-Plus 4 camera settings (updated 2026-09-05). https://wiki.qidi3d.com/en/X-Plus4/Manual/camera
- **S18** QIDI Wiki, Wi-Fi / network guide: LAN-only mode, API key, Fluidd (updated 2026-09-05). https://wiki.qidi3d.com/en/X-Plus4/Manual/WIFI
- **S19** QIDI Wiki, QIDI Link (updated 2026-09-05). https://wiki.qidi3d.com/en/app
- **S20** QIDI Wiki, Replacing Fluidd (`mks` / `makerbase`). https://wiki.qidi3d.com/en/X-Plus4/Manual/Replacing-Fluidd
- **S21** QIDI Wiki, blank login or Fluidd page (`mks` / `makerbase`). https://wiki.qidi3d.com/en/software/qidi-studio/troubleshooting/blank-page
- **S22** QIDI Wiki, QIDI Maker quick start (updated 2026-09-05). https://wiki.qidi3d.com/en/QIDIMaker/quick-guide1
- **S23** QIDI Wiki, flashing the eMMC system image. https://wiki.qidi3d.com/en/Memo/flash-emmc
- **S24** QIDI Plus 4 tech specs. https://qidi3d.com/pages/qidi-plus-4-techspecs
- **S25** QIDI warranty statement (updated 2026-06-04). https://qidi3d.com/pages/warranty-statement
- **S26** QIDI Maker page. https://qidi3d.com/pages/qidi-maker
- **S27** App Store listings:
  - QIDI Link (v1.1.9, 2025-08-20): https://apps.apple.com/us/app/qidi-link/id6476657588
  - QIDI Maker (v1.1.1): https://apps.apple.com/us/app/qidi-maker/id6757949896
- **S28** Issues on QIDI's Plus 4 repo about unpublished firmware 1.7.2 to 1.8.2:
  - #98 (2025-09-09): https://github.com/QIDITECH/QIDI_PLUS4/issues/98
  - #102 (2025-10-11): https://github.com/QIDITECH/QIDI_PLUS4/issues/102
  - #105 (2025-10-23): https://github.com/QIDITECH/QIDI_PLUS4/issues/105
  - #123 (2026-04-02): https://github.com/QIDITECH/QIDI_PLUS4/issues/123
  - #127 (2026-06-08): https://github.com/QIDITECH/QIDI_PLUS4/issues/127
  - #130 (2026-06-27): https://github.com/QIDITECH/QIDI_PLUS4/issues/130
- **S29** Community Plus 4 wiki (not Qidi):
  - **a** Secure remote access: https://github.com/qidi-community/Plus4-Wiki/blob/main/content/secure-remote-access/README.md
  - **b** SSH security: https://github.com/qidi-community/Plus4-Wiki/blob/main/content/ssh-security/README.md
  - **c** SSH access: https://github.com/qidi-community/Plus4-Wiki/blob/main/content/ssh-access/README.md
  - **d** Disabling the QIDI Link client: https://github.com/qidi-community/Plus4-Wiki/blob/main/content/disable%20QIDILink-client/README.md
  - **e** Adding cameras: https://github.com/qidi-community/Plus4-Wiki/blob/main/content/add-cameras-to-qidi-plus4/README.md
  - **f** System tuning: https://github.com/qidi-community/Plus4-Wiki/blob/main/content/system-tuning/README.md
- **S30** Fluidd docs:
  - **a** Authorization: https://github.com/fluidd-core/fluidd/blob/HEAD/docs/docs/features/authorization.md
  - **b** Configuration (CORS, multiple printers): https://github.com/fluidd-core/fluidd/blob/HEAD/docs/docs/configuration.md
- **S31** Fluidd v1.30.4 release (2024-09-12). https://github.com/fluidd-core/fluidd/releases/tag/v1.30.4
- **S32** Mainsail docs, remote access FAQ. https://docs.mainsail.xyz/faq/remote-access/
- **S33** Obico, "QIDI Plus4 - Klipper Remote Access and AI" (no date shown). https://www.obico.io/blog/qidi-plus4-klipper-remote-access-and-ai/
- **S34** Obico server hardware requirements. https://obico.io/docs/server-guides/hardware-requirements/
- **S35** Obico server README. https://github.com/TheSpaghettiDetective/obico-server
- **S36** `moonraker-obico` agent README. https://github.com/TheSpaghettiDetective/moonraker-obico
- **S37** Moonraker Home Assistant integration: repo, releases, docs (`connection.rst`, index).
  - https://github.com/marcolivierarsenault/moonraker-home-assistant
  - https://github.com/marcolivierarsenault/moonraker-home-assistant/blob/HEAD/docs/connection.rst
  - https://moonraker-home-assistant.readthedocs.io/
- **S38** Home Assistant core integrations; no `moonraker` directory as of 2026-09-11. https://github.com/home-assistant/core/tree/dev/homeassistant/components
- **S39** FreeDi README and releases. https://github.com/Phil1988/FreeDi
- **S40** Debian LTS schedule (Debian 10 LTS ended 2024-06-30). https://wiki.debian.org/LTS
- **S41** Upstream Klipper `Config_Changes.md` (v0.13.0 released 2025-04-11). https://github.com/Klipper3d/klipper/blob/master/docs/Config_Changes.md
