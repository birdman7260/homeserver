# Debrid-backed \*arr with no local library (TorBox)

Research for the ticket **Debrid-backed \*arr with no local library** on the map *Home server on Proxmox: build it, document it, make it rebuildable*.

Every source was read on **2026-09-11** unless another date is given; "updated" dates are the ones shown on the page. Repository maintenance figures (latest release, latest commit on the default branch, archived flag) come from the GitHub API on that day. Anything not confirmed from a primary source is marked **Unverified** or *inference*.

## Answer

**Orchestration-only works. It is a real architecture, but it degrades rather than looking after itself.**

- **How it works.** Sonarr and Radarr have no debrid download client ([Sonarr supported clients][sonarr-supported]). A bridge therefore pretends to be qBittorrent: it adds the release to TorBox, mounts TorBox as a filesystem, and hands the \*arr a symlink.
- **Why nothing is stored.** When Sonarr and Radarr import a symlink, their Unix disk provider creates a new symlink instead of copying the file ([Sonarr][sonarr-diskprovider], [Radarr][radarr-diskprovider]). The "library" is a tree of symlinks, and no media bytes live on the NUC.
- **The costs:**
  - TorBox removes anything nobody has downloaded for 30 days ([TorBox][tb-inactive]).
  - The recommended bridge has an open cluster of TorBox-specific bugs.
  - TorBox had multi-hour total outages in April and June 2026 ([April post-mortem][tb-pm-april], [June post-mortem][tb-pm-june]).

**Components (minimum set):**

| Role | Pick | Notes |
|---|---|---|
| Indexers | Prowlarr | No native TorBox indexer exists; public indexers or TorBox's own custom definition |
| Orchestration | Sonarr + Radarr | Unchanged from a normal setup |
| Bridge, mount, repair | **decypharr** | The only actively maintained tool that supports TorBox, emulates qBittorrent, and mounts, all in one process |
| Debrid | TorBox, paid plan, API key | |
| Player (optional) | Jellyfin reading the symlink tree | Only if a self-hosted player is wanted at all |

**Rough local storage:**

- **~20–50 GB lean:** no Jellyfin, a small mount cache.
- **~150–250 GB with Jellyfin:** its database and metadata, a 50–100 GB read cache, and transcode headroom.

None of it is irreplaceable media; the caches are disposable.

**Upgrade path to a local library:**

- Keep Prowlarr, Sonarr and Radarr as they are.
- Flip decypharr's per-Arr `download_action` from `symlink` to `download`, or add a real qBittorrent/SABnzbd client, so new grabs land on disk.
- Existing items have to be re-grabbed, or copied through the mount with link dereferencing. Sonarr and Radarr's own move and copy keep them as symlinks.

**Stremio is a parallel system.** Its addons call TorBox directly and never touch the \*arr stack. TorBox disabled its own Stremio addon on 2026-05-20 ([changelog][tb-changelog]), but community addons still support TorBox.

---

## 1. How debrid plugs into Prowlarr, Sonarr and Radarr

```
Prowlarr --indexers--> Sonarr / Radarr --qBittorrent API--> decypharr --REST API--> TorBox
                             ^                                  |
                             | import (re-creates symlink)      v FUSE mount, e.g. /mnt/decypharr
                        library folder <--symlinks-- download folder
                             |
                        Jellyfin reads through symlinks --> mount --> TorBox CDN
```

- **No native debrid client.** Sonarr's supported download clients are ordinary torrent and usenet clients plus Torrent/Usenet Blackhole; the page has no debrid entry ([Servarr wiki: Sonarr supported][sonarr-supported]). Every bridge either emulates a client (qBittorrent, sometimes SABnzbd) or uses a blackhole folder.
- **decypharr** provides a "Mock Qbittorent and Sabnzbd API that supports the Arrs" and lists TorBox as a supported provider ([README][dx-readme]).
  - **Connecting an Arr:** add a qBittorrent client on port 8282. The username is the Arr's URL, the password is its API token, and the category is `sonarr`/`radarr` ([Connecting Sonarr & Radarr][dx-arrs]).
  - **`download_action`** is set per Arr: `symlink` (default), `download`, `strm` or `none` ([same page][dx-arrs]).
  - **Mount type:** DFS (its own VFS), embedded rclone, external rclone, or none ([Setup Wizard][dx-quick]).
  - **Paths:** the Arr and decypharr must see the mount at the same path ([Connecting Sonarr & Radarr → Downloads Not Importing][dx-arrs]).
  - **TorBox config:** just `"provider": "torbox"` and an API key; the Real-Debrid options (rate limits, workers) also apply ([TorBox setup][dx-torbox]).
- **Only cached releases succeed by default.** `download_uncached` defaults to `false`. Uncached downloads "use Debrid provider's cache slots and may take time to download" ([arrs][dx-arrs], [configuration][dx-config]).
- **Imports stay symlinks.** In both Sonarr (`main`) and Radarr (`develop`), the Unix `DiskProvider` checks `IsSymbolicLink` in `CopyFileInternal` and `MoveFileInternal`. For a symlink it calls `CreateSymbolicLinkTo` on the same target rather than copying bytes ([Sonarr DiskProvider.cs][sonarr-diskprovider], [Radarr DiskProvider.cs][radarr-diskprovider]). So the hardlink-or-copy fallback described in the wiki ([Sonarr settings][sonarr-settings]) does not pull whole files through the mount. *Read from source; not run end-to-end here.*
- **Scans can read media.** "Analyse video files … requires Sonarr to read parts of the file which may cause high disk or network activity during scans" ([Sonarr settings][sonarr-settings]). On a debrid mount, every such read is a fetch from TorBox.
- **Prowlarr has no TorBox indexer.** Neither Prowlarr's YAML definitions (`Prowlarr/Indexers`, `definitions/v11`) nor its native C# indexers contain one (checked 2026-09-11).
  - **TorBox's own definition.** TorBox publishes a Cardigann YAML ([TorBox-App/torbox-prowlarr-indexers][tb-prowlarr]). You load it by placing it in Prowlarr's `Definitions/Custom` folder ([Prowlarr FAQ][prowlarr-faq]). It targets `https://search-api.torbox.app`, is described as "300 requests/min", and was last committed 2024-11-21.
  - **Unverified: the search host may be gone.** `search-api.torbox.app` did not resolve via 1.1.1.1, 8.8.8.8 or the local resolver on 2026-09-11, while `api.torbox.app` did. AIOStreams' current code still uses the host ([search-api.ts][aio-search]), so the outage may be temporary.
  - **Public indexers work too.** decypharr only needs the magnet/hash.

### Bridge and mount tools: maintenance and TorBox support

| Tool | What it is | TorBox support | Latest release | Latest commit | Archived | Verdict |
|---|---|---|---|---|---|---|
| [decypharr][gh-decypharr] | qBittorrent + SABnzbd mock; DFS or rclone mount; health checker/repair; optional NFS/SMB shares | **Yes** ([README][dx-readme], [TorBox guide][dx-torbox]) | v2.5, 2026-08-11 | 2026-08-11 (pushed 2026-09-04) | No | **Use this.** MIT, 885 stars. |
| [rdt-client][gh-rdt] | qBittorrent mock, plus partial SABnzbd for TorBox and Premiumize. Downloads locally, or in symlink mode over an rclone mount you run yourself | **Yes** ([README][gh-rdt]). TorBox's help centre has a guide ([updated 2025-01-02][tb-rdt]) | v2.0.142, 2026-08-03 | 2026-08-03 | No | Viable fallback; needs a separate rclone mount of TorBox WebDAV. |
| [DebriDav][gh-debridav] | qBittorrent + SABnzbd mock exposing virtual files over WebDAV | **Yes** ([README][gh-debridav]) | v0.11.0, 2026-02-18 | 2026-03-02 | No | Quiet for six months. Fork [jtdevops/debridav][gh-debridav-fork] released v0.11.17 on 2026-04-13. |
| [TorBox Media Center][gh-tbmc] (official) | FUSE or `.strm` mount of the whole TorBox account | TorBox only. **Paid plan required**, **no Sonarr/Radarr integration** ([README][gh-tbmc]) | v2.0.0, 2026-01-16 | 2026-01-16 | No | Official, but no commit for ~8 months. 23 open issues, including rate-limit flooding ([#67][tbmc-67]). |
| [TorBoxarr][gh-torboxarr] | qBittorrent + SABnzbd mock that **downloads finished files to local disk** | TorBox only ([README][gh-torboxarr]) | none | 2026-08-21 | No | Not orchestration-only. A candidate for the upgrade path. 19 stars. |
| [zurg][gh-zurg] (`zurg-testing` now redirects to `zurg-public`) | WebDAV server over the debrid library, meant for rclone; no \*arr API | Stable build is Real-Debrid only. TorBox is in **sponsor-only nightlies** ([README][gh-zurg]) | v1.0.0, 2026-08-09 | 2026-09-04 | No | Not usable with TorBox without a sponsorship. |
| [westsurname/scripts][gh-blackhole] | Blackhole-folder and repair scripts | **Yes** ([README][gh-blackhole]) | v1.5.5, 2026-07-10 | 2026-07-10 | No | The older blackhole pattern; decypharr covers it. |
| [DUMB][gh-dumb] | All-in-one container bundling decypharr, zurg, rclone, the Arrs, Jellyfin and more; also a native Proxmox LXC install | Through the bundled decypharr. The README does not name TorBox (*inference*) | 2.22.1, 2026-09-10 | 2026-09-10 | No | Very active, but one opaque container sits badly with an Ansible-described build. |
| [rclone][gh-rclone] | Generic WebDAV/S3 client and FUSE mount | Works against TorBox WebDAV and T3; TorBox lists rclone for T3 ([T3][tb-t3]) | v1.75.1, 2026-09-04 | 2026-09-11 | No | A building block, not a bridge. TorBox's own [rclone fork][gh-tb-rclone] has no releases (last commit 2026-02-04); its purpose is **unverified**. |
| [Riven][gh-riven] | Request → debrid → symlink pipeline | **No.** The README lists Real Debrid and All Debrid. TorBox's [fork][gh-tb-riven] was last committed 2025-05-03 | v0.23.6, 2025-08-24 | 2026-06-27 | No | Not for TorBox. |
| [cli_debrid][gh-clidebrid] | Replaces the \*arrs | **No.** Real-Debrid only ([README][gh-clidebrid]) | v0.7.23, 2025-12-23 | 2026-06-16 | No | Not for TorBox. |
| [plex_debrid][gh-plexdebrid] | Plex-centric predecessor | n/a | none | 2023-12-15 | **Yes** | Dead. |
| [Zilean][gh-zilean] | Indexer built from DMM hashlists | n/a | v3.5.0, 2025-04-21 | 2025-05-26 | No | Stale for ~16 months. |
| [nzbdav][gh-nzbdav] | Usenet WebDAV + SABnzbd mock | n/a (usenet) | v0.6.4, 2026-04-08 | 2026-09-03 | No | README: "This project is no longer maintained." Only relevant if usenet is added. |

Seen but not evaluated:

- [nordicnode/TorBox-Media-Server][gh-tbms]: turn-key scripts around a TorBox WebDAV mount; v1.1.0, 2026-06-16; judged from its repository description only.
- [elfhosted/krantorbox][gh-krantorbox]: last commit 2024-08-21.
- [asylumexp/rdt-client-torbox][gh-rdt-torbox]: a fork last committed 2025-03-07, made redundant now that rdt-client supports TorBox upstream.

## 2. What TorBox offers

TorBox has **no native \*arr integration**. Its help centre's *Integrations* collection lists Google Drive, OneDrive, WebDAV and T3 ([Integrations][tb-integrations]). The only \*arr material is the RDTClient guide in *Guides* ([Guides][tb-guides]).

| Interface / policy | Facts | Source |
|---|---|---|
| REST API | `https://api.torbox.app`, v1. Official SDKs for Python, TypeScript, Go, .NET, Java and PHP | [API docs][tb-api], [TorBox-App repositories][gh-tb-org] |
| Rate limits | 300/min per API key. `createtorrent` is 60/hour for **uncached** items; `createusenetdownload` and `createwebdownload` are 60/hour. "Subject to change." Updated 2026-07-01 | [API Rate Limits][tb-ratelimits] |
| WebDAV | `https://webdav.torbox.app`, username `torbox` with the API key. Refreshes every 15 min (manual `/refresh/`), read-only, served through Cloudflare, tags shown as folders. Updated 2026-07-08 | [WebDAV][tb-webdav], [changelog v9][tb-changelog] |
| T3 | S3-compatible at `https://t3.nexus`: Auth ID as access key, API key as secret. Read-only, refreshes every 15 min, rclone listed as compatible. Updated 2026-07-02 | [T3][tb-t3] |
| TorBox Media Center | Official FUSE/STRM mounter; paid plan required | [README][gh-tbmc] |
| Stremio addon | Launched in v3.6 (2024-03-04). **"Disables the Stremio Addon"** in v8.4.4 (2026-05-20). `stremio.torbox.app` does not resolve (2026-09-11) | [changelog v3.6][tb-v36], [changelog][tb-changelog] |
| Active download slots | Free 1 (10 downloads a month), Essential 3, Standard 5, Pro 10. "Cached items … do not count toward your active slot limit." The Free plan also has a 24 h cooldown, a 10 GB maximum, and no usenet or web downloads | [Account Restrictions][tb-restrictions] |
| Retention | "Any downloads not downloaded within 30 days of being cached are removed"; "Downloading the files will reset the timer on them" (updated 2025-09-20). Files are kept "at least 30 days", but not guaranteed under DMCA, abuse or migrations (updated 2024-10-15) | [Why is my download inactive?][tb-inactive], [How long are files stored?][tb-stored] |
| AirLock | Permanent storage exempt from the 30-day rule: Essential 300 GB, Standard 500 GB, Pro 1 TB, Free 0. Updated 2026-07-04 | [AirLock][tb-airlock] |

**Unverified:** which plans include WebDAV or T3. Neither article says.

## 3. What is stored locally

In this mode the \*arr stack stores **metadata, not media**. The only media bytes on disk are bounded, disposable read caches in the mount layer, plus Jellyfin transcodes if Jellyfin is used.

| Item | Size | Source |
|---|---|---|
| Library tree (symlinks) | Bytes per item | decypharr `symlink` action ([arrs][dx-arrs]) |
| `.strm` alternative | "less than 1GB for libraries of any size" | [TorBox Media Center README][gh-tbmc] |
| DFS mount read cache | Streaming guidance is 50–100 GB. Default `disk_cache_size` is `0`, meaning unlimited, **so set it** | [DFS][dx-dfs], [configuration][dx-config] |
| Embedded rclone read cache | Example 10 GB. Default `vfs_cache_max_size` is `0` (unlimited) | [rclone (internal)][dx-rclone], [configuration][dx-config] |
| NFS/SMB share cache | Off by default; 10 GB budget when on. On ZFS the limit "becomes advisory and the directory can grow past it" | [configuration][dx-config] |
| Sonarr, Radarr, Prowlarr app data (SQLite, posters, logs, backups) | **Unverified estimate:** hundreds of MB to a few GB | No primary figure found |
| Jellyfin database and metadata | "A database for a moderate-sized library can grow anywhere from 10 to 100 GB." | [Jellyfin: Storage][jf-storage] |
| Jellyfin transcode folder | About the size of what is being transcoded; one 50 GB remux comes to ~15–60 GB | [Jellyfin: Storage][jf-storage] |

**Order of magnitude:** ~20–50 GB lean, ~150–250 GB with Jellyfin. Both fit the ~2 TB second drive.

**What to back up:** the \*arr databases, decypharr config and the symlink tree. Caches and transcodes are disposable.

## 4. Where Stremio fits

- **Where streams come from.** Stremio gets playable streams from **addons**. A Stream object carries a `url`, `infoHash`, `nzbUrl` and so on; Stremio does not host media ([Stremio addon SDK: Stream][stremio-stream]).
- **Debrid addons call TorBox directly** with the user's API key. TorBox disabled its own addon on 2026-05-20 ([changelog][tb-changelog]).
  - **AIOStreams** (v2.34.0, 2026-09-04) lists TorBox support ([README][gh-aiostreams]).
  - **Comet** (v2.58.0, 2026-07-27) lists TorBox support ([README][gh-comet]).
  - **MediaFusion** has a TorBox search scraper in current code ([torbox_search.rs][mf-torbox]). TorBox's 2024 changelog named it as compatible ([v3.6][tb-v36]); its current debrid playback support was not re-checked.
- **Stremio and the \*arr stack are parallel systems that do not talk.** The only thing they share is the TorBox account: its slots, the per-key rate limit, and the 30-day timer.
- **Stremio survives the server being down.** Hosted addon instances do not depend on the NUC, so Stremio is the only viewing path here that meets the map's graceful-degradation requirement.

## 5. Replacing Stremio with self-hosted Jellyfin

There are three shapes:

1. **\*arr + decypharr + Jellyfin.** A curated library; Jellyfin reads the symlink tree. This is the orchestration-only design above.
2. **TorBox Media Center → Jellyfin.** Mirrors the whole TorBox account as `.strm` files, with no \*arr and no curation ([README][gh-tbmc]). No commits since 2026-01-16.
3. **[Gelato][gh-gelato] Jellyfin plugin.** Puts Stremio-addon search and catalogs inside Jellyfin. Streams are resolved on demand and proxied through Jellyfin. It needs Jellyfin 12 and supports **only AIOStreams** ([README][gh-gelato]). Maintenance and successor:
   - v0.26.17.0 was released 2026-09-11.
   - The README points to the author's Remux, a full Jellyfin replacement, as the next step; not evaluated here.
   - Jellyfin 12.0 itself was released 2026-09-08 ([releases][gh-jellyfin]).

What breaks:

- **Image extraction reads whole files.** "When using cloud storage, it is recommended to disable image extraction as it requires downloading the entire file" ([Jellyfin: Storage][jf-storage]). Chapter images are enabled per library and "computationally intensive" ([Chapter Images][jf-chapters]). Disable chapter images for these libraries, and trickplay too by the same logic (*inference*).
- **Metadata probes and the 30-day timer.** Accounts of what resets the timer differ:
  - **ElfHosted's claim:** probes reset it. ElfHosted sells this stack and says "The arr stack and STRM don't integrate cleanly at scale" because metadata probes reset TorBox's 30-day expiry and bloat accounts. Its fix is a layer that only adds items to TorBox at playback ([ElfHosted Jellyfin + TorBox guide, updated 2026-08-10][elf-jellyfin]).
  - **TorBox's own statement:** only that *downloading* resets the timer ([Why is my download inactive?][tb-inactive]).
  - **Unverified:** whether reads through the mount count.
- **Unwatched items expire from the account.** The result is a dangling symlink.
  - **Repair.** decypharr's health checker finds broken entries. With `auto_repair` on, a sweep "deletes the broken Arr file records and triggers a search for replacements" ([Health Checker & Repair][dx-repair]).
  - **Avoiding expiry.** AirLock exempts pinned items, up to 300 GB–1 TB depending on plan ([AirLock][tb-airlock]).
- **Rate limits and TorBox-specific bugs in decypharr.** Open issues filed against TorBox:
  - [#302][dx-302]: `torrents/add` blocks until the \*arr times out.
  - [#308][dx-308]: an \*arr re-grab loop re-submitted the same hash repeatedly and triggered an account-wide TorBox cooldown of about 24 h.
  - [#300][dx-300]: 429 errors while streaming.
  - [#364][dx-364]: a repair sweep selects 0 candidates on TorBox.
  - [#400][dx-400]: a TorBox "queued" status is treated as a hard error and the torrent is deleted.

  v2.5 added a proactive 300/min limiter and Retry-After backoff for TorBox ([v2.5 release][dx-v25]).
- **Key rotation footgun.** In [#401][dx-401], a rotated API key left a stale entry in `download_api_keys`. Listings kept working while every read failed.
- **Container privileges.** decypharr's compose example needs `/dev/fuse`, `SYS_ADMIN` and `apparmor:unconfined` ([README][dx-readme]). That is awkward in an unprivileged LXC.
- **Load lands on the NUC.** Transcodes run locally and need scratch space ([Jellyfin: Storage][jf-storage]). A remote viewer's stream is fetched from TorBox and then pushed back out through the home uplink.
- **Video through Cloudflare.** Cloudflare may limit Free, Pro and Business customers who use the CDN without paid services "to serve video or a disproportionate percentage of pictures, audio files, or other large files" ([Cloudflare service-specific terms, updated 2026-06-02][cf-terms]). **Unverified:** whether Cloudflare Tunnel traffic falls under that clause. Viewing over Tailscale avoids the question.

## 6. Failure modes

### TorBox unreachable

- **It happens.** From TorBox's own post-mortems:
  - **April 2026** ([post-mortem][tb-pm-april]): full API outages on 15 and 23 April, the second lasting "several hours"; a WebDAV outage on 18 April; CDN link invalidation that forced device restarts.
  - **June 2026** ([post-mortem][tb-pm-june]): network attacks and repeated API outages.
- **Mount:** reads fail while listings stay up. In [#401][dx-401], failed download-link requests made every byte read return `input/output error`, while listings, sizes and timestamps stayed correct. That case was a stale key, but an outage should present the same way (*inference*).
- **\*arr grabs fail or time out.** decypharr's queue cleanup defaults "Failed download" to **Blacklist + research** ([arrs][dx-arrs]). During an outage that can blocklist good releases (*inference*).
- **Repair can do damage.** A sweep during an outage could mark healthy entries broken. With `auto_repair: true` it then deletes the Arr file records and re-searches ([repair][dx-repair]) (*inference, untested*). Safer options: `auto_repair: false` with `notify_on_complete`, and/or a `stop_schedule`.
- **Unmonitor-on-delete.** Sonarr's "Unmonitor Deleted Episodes" and Radarr's "Unmonitor Deleted Movies" unmonitor anything that looks deleted from disk ([Sonarr settings][sonarr-settings]). Leave them off.
- **Jellyfin:** playback fails. **Unverified:** whether a library scan during an outage drops items.
- **Blast radius.** Home Assistant is unaffected. Stremio fails the same way, since it too depends on TorBox.

### Account lapses

- **AirLock:** 7 days to get under the new limit, then *all* AirLock files become normal files on the 30-day clock ([AirLock][tb-airlock]).
- **Normal files** are removed 30 days after the last download ([inactive][tb-inactive]). **The library decays into broken symlinks within about a month.**
- **On the Free plan:**
  - Limits: 1 slot, 10 downloads a month, a 24 h cooldown, a 10 GB maximum ([Account Restrictions][tb-restrictions]).
  - TorBox Media Center stops, because it requires a paid plan ([README][gh-tbmc]).
  - **Unverified:** whether WebDAV, T3 or API download links work on Free.
- **What survives:** everything the \*arrs know. That is the wanted list, quality profiles and history. After re-subscribing, repair plus "search missing" re-acquires whatever is still obtainable. No media is lost, because none was local.

**Six-month-neglect verdict:** it will not look after itself. Treat it as non-load-bearing: keep it out of auto-update health gates and page nobody about it.

## 7. Upgrade path to a local library

1. **Keep the orchestration layer.** Prowlarr, Sonarr, Radarr, their profiles, lists and history carry over unchanged.
2. **Send new grabs to disk.** Set decypharr's per-Arr `download_action` to `download` ([arrs][dx-arrs]), or add a real qBittorrent/SABnzbd client. TorBoxarr is a TorBox-only alternative that keeps TorBox's fast cached download but writes to local disk ([repo][gh-torboxarr]).
3. **Materialise existing items.** Sonarr and Radarr's own move and copy re-create symlinks ([Sonarr][sonarr-diskprovider], [Radarr][radarr-diskprovider]). Changing root folders in the Mass Editor ([Sonarr library][sonarr-library]) therefore does **not** fetch media. The ways to do it:
   - re-grab through the local client;
   - copy through the mount with a link-dereferencing copy, such as `cp -L` or `rsync -L` (*untested here*);
   - pull from TorBox read-only over T3 or WebDAV with rclone ([T3][tb-t3]).
4. **Point Jellyfin's library at the new root.** Storage beyond the second drive is out of scope for this map; the map's easy-expansion constraint covers it.

## Unverified / open

- The disk footprint of Sonarr, Radarr and Prowlarr app data.
- Which TorBox plans include WebDAV and T3.
- Whether reads through a mount, WebDAV or T3 reset TorBox's 30-day timer. TorBox says downloads do; ElfHosted says probes do.
- How Jellyfin behaves when a library scan runs against an unavailable mount.
- How decypharr repair behaves during a full TorBox outage.
- Whether Cloudflare's CDN video clause applies to Cloudflare Tunnel.
- Whether `search-api.torbox.app` is gone or only temporarily unresolvable.
- The purpose of TorBox's rclone fork.
- The quality of zurg's TorBox backend, which is sponsor-only and was not inspected.
- DUMB's TorBox support, inferred only from its bundled decypharr.
- End-to-end symlink import behaviour, which was read from source but not run.

## Sources

TorBox (first party):

- [tb-api]: https://api-docs.torbox.app/
- [tb-ratelimits]: https://support.torbox.app/en/articles/13726368-api-rate-limits
- [tb-webdav]: https://support.torbox.app/en/articles/14662867-torbox-webdav
- [tb-t3]: https://support.torbox.app/en/articles/15531689-torbox-t3
- [tb-integrations]: https://support.torbox.app/en/collections/10369620-integrations
- [tb-guides]: https://support.torbox.app/en/collections/10369621-guides
- [tb-rdt]: https://support.torbox.app/en/articles/10167535-how-to-setup-rdtclient-with-torbox-docker
- [tb-restrictions]: https://support.torbox.app/en/articles/9836418-account-restrictions
- [tb-inactive]: https://support.torbox.app/en/articles/10333785-why-is-my-download-inactive
- [tb-stored]: https://support.torbox.app/en/articles/9961332-how-long-are-torbox-files-stored-for
- [tb-airlock]: https://support.torbox.app/en/articles/15417147-torbox-airlock
- [tb-changelog]: https://feedback.torbox.app/changelog
- [tb-v36]: https://feedback.torbox.app/changelog/v36
- [tb-pm-april]: https://github.com/TorBox-App/torbox-post-mortems/blob/main/2026/27%20April.md
- [tb-pm-june]: https://github.com/TorBox-App/torbox-post-mortems/blob/main/2026/23%20June.md
- [tb-prowlarr]: https://github.com/TorBox-App/torbox-prowlarr-indexers
- [gh-tb-org]: https://github.com/TorBox-App
- [gh-tbmc]: https://github.com/TorBox-App/torbox-media-center
- [tbmc-67]: https://github.com/TorBox-App/torbox-media-center/issues/67
- [gh-tb-rclone]: https://github.com/TorBox-App/rclone
- [gh-tb-riven]: https://github.com/TorBox-App/riven

Servarr (Sonarr, Radarr, Prowlarr):

- [sonarr-supported]: https://wiki.servarr.com/sonarr/supported#download-clients
- [sonarr-settings]: https://wiki.servarr.com/sonarr/settings (source: https://github.com/Servarr/Wiki/blob/master/sonarr/settings.md; Radarr equivalents in `radarr/settings.md`)
- [sonarr-library]: https://wiki.servarr.com/sonarr/library#mass-editor
- [prowlarr-faq]: https://wiki.servarr.com/prowlarr/faq#adding-a-custom-yml-definition
- [sonarr-diskprovider]: https://github.com/Sonarr/Sonarr/blob/main/src/NzbDrone.Mono/Disk/DiskProvider.cs
- [radarr-diskprovider]: https://github.com/Radarr/Radarr/blob/develop/src/NzbDrone.Mono/Disk/DiskProvider.cs
- Versions on 2026-09-11: Sonarr v4.0.19.2979 (2026-06-26), Radarr v6.3.0.10514 (2026-07-12), Prowlarr v2.5.2.5491 (2026-07-22).

decypharr:

- [gh-decypharr]: https://github.com/sirrobot01/decypharr
- [dx-readme]: https://github.com/sirrobot01/decypharr/blob/main/README.md
- [dx-arrs]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/arrs.mdx
- [dx-torbox]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/debrid/torbox.md
- [dx-quick]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/quick-start.mdx
- [dx-dfs]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/mounting/dfs.md
- [dx-rclone]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/mounting/rclone-internal.md
- [dx-repair]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/repair.mdx
- [dx-config]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/configuration.md
- [dx-v25]: https://github.com/sirrobot01/decypharr/releases/tag/v2.5
- Issues: [dx-300] https://github.com/sirrobot01/decypharr/issues/300 · [dx-302] https://github.com/sirrobot01/decypharr/issues/302 · [dx-308] https://github.com/sirrobot01/decypharr/issues/308 · [dx-364] https://github.com/sirrobot01/decypharr/issues/364 · [dx-400] https://github.com/sirrobot01/decypharr/issues/400 · [dx-401] https://github.com/sirrobot01/decypharr/issues/401

Other bridge, mount and addon repositories:

- [gh-rdt]: https://github.com/rogerfar/rdt-client
- [gh-debridav]: https://github.com/skjaere/DebriDav
- [gh-debridav-fork]: https://github.com/jtdevops/debridav
- [gh-torboxarr]: https://github.com/MrJoiny/TorBoxarr
- [gh-zurg]: https://github.com/debridmediamanager/zurg-public
- [gh-blackhole]: https://github.com/westsurname/scripts
- [gh-dumb]: https://github.com/I-am-PUID-0/DUMB
- [gh-rclone]: https://github.com/rclone/rclone
- [gh-riven]: https://github.com/rivenmedia/riven
- [gh-clidebrid]: https://github.com/godver3/cli_debrid
- [gh-plexdebrid]: https://github.com/itsToggle/plex_debrid
- [gh-zilean]: https://github.com/iPromKnight/zilean
- [gh-nzbdav]: https://github.com/nzbdav-dev/nzbdav
- [gh-tbms]: https://github.com/nordicnode/TorBox-Media-Server
- [gh-krantorbox]: https://github.com/elfhosted/krantorbox
- [gh-rdt-torbox]: https://github.com/asylumexp/rdt-client-torbox
- [gh-aiostreams]: https://github.com/Viren070/AIOStreams
- [aio-search]: https://github.com/Viren070/AIOStreams/blob/main/packages/core/src/builtins/torbox-search/search-api.ts
- [gh-comet]: https://github.com/g0ldyy/comet
- [mf-torbox]: https://github.com/mhdzumair/MediaFusion/blob/main/backend/src/scrapers/torbox_search.rs
- [gh-gelato]: https://github.com/lostb1t/Gelato

Stremio, Jellyfin, Cloudflare, ElfHosted:

- [stremio-stream]: https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md
- [jf-storage]: https://jellyfin.org/docs/general/administration/storage/
- [jf-chapters]: https://jellyfin.org/docs/general/server/metadata/chapter-images/
- [gh-jellyfin]: https://github.com/jellyfin/jellyfin/releases
- [cf-terms]: https://www.cloudflare.com/service-specific-terms-application-services/
- [elf-jellyfin]: https://docs.elfhosted.com/guides/media/jellyfin-torbox-aars/ (a commercial host of this stack; a secondary source, used only where marked)

[tb-api]: https://api-docs.torbox.app/
[tb-ratelimits]: https://support.torbox.app/en/articles/13726368-api-rate-limits
[tb-webdav]: https://support.torbox.app/en/articles/14662867-torbox-webdav
[tb-t3]: https://support.torbox.app/en/articles/15531689-torbox-t3
[tb-integrations]: https://support.torbox.app/en/collections/10369620-integrations
[tb-guides]: https://support.torbox.app/en/collections/10369621-guides
[tb-rdt]: https://support.torbox.app/en/articles/10167535-how-to-setup-rdtclient-with-torbox-docker
[tb-restrictions]: https://support.torbox.app/en/articles/9836418-account-restrictions
[tb-inactive]: https://support.torbox.app/en/articles/10333785-why-is-my-download-inactive
[tb-stored]: https://support.torbox.app/en/articles/9961332-how-long-are-torbox-files-stored-for
[tb-airlock]: https://support.torbox.app/en/articles/15417147-torbox-airlock
[tb-changelog]: https://feedback.torbox.app/changelog
[tb-v36]: https://feedback.torbox.app/changelog/v36
[tb-pm-april]: https://github.com/TorBox-App/torbox-post-mortems/blob/main/2026/27%20April.md
[tb-pm-june]: https://github.com/TorBox-App/torbox-post-mortems/blob/main/2026/23%20June.md
[tb-prowlarr]: https://github.com/TorBox-App/torbox-prowlarr-indexers
[gh-tb-org]: https://github.com/TorBox-App
[gh-tbmc]: https://github.com/TorBox-App/torbox-media-center
[tbmc-67]: https://github.com/TorBox-App/torbox-media-center/issues/67
[gh-tb-rclone]: https://github.com/TorBox-App/rclone
[gh-tb-riven]: https://github.com/TorBox-App/riven
[sonarr-supported]: https://wiki.servarr.com/sonarr/supported#download-clients
[sonarr-settings]: https://wiki.servarr.com/sonarr/settings
[sonarr-library]: https://wiki.servarr.com/sonarr/library#mass-editor
[prowlarr-faq]: https://wiki.servarr.com/prowlarr/faq#adding-a-custom-yml-definition
[sonarr-diskprovider]: https://github.com/Sonarr/Sonarr/blob/main/src/NzbDrone.Mono/Disk/DiskProvider.cs
[radarr-diskprovider]: https://github.com/Radarr/Radarr/blob/develop/src/NzbDrone.Mono/Disk/DiskProvider.cs
[gh-decypharr]: https://github.com/sirrobot01/decypharr
[dx-readme]: https://github.com/sirrobot01/decypharr/blob/main/README.md
[dx-arrs]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/arrs.mdx
[dx-torbox]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/debrid/torbox.md
[dx-quick]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/quick-start.mdx
[dx-dfs]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/mounting/dfs.md
[dx-rclone]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/mounting/rclone-internal.md
[dx-repair]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/repair.mdx
[dx-config]: https://github.com/sirrobot01/decypharr/blob/main/docs/src/content/docs/guides/configuration.md
[dx-v25]: https://github.com/sirrobot01/decypharr/releases/tag/v2.5
[dx-300]: https://github.com/sirrobot01/decypharr/issues/300
[dx-302]: https://github.com/sirrobot01/decypharr/issues/302
[dx-308]: https://github.com/sirrobot01/decypharr/issues/308
[dx-364]: https://github.com/sirrobot01/decypharr/issues/364
[dx-400]: https://github.com/sirrobot01/decypharr/issues/400
[dx-401]: https://github.com/sirrobot01/decypharr/issues/401
[gh-rdt]: https://github.com/rogerfar/rdt-client
[gh-debridav]: https://github.com/skjaere/DebriDav
[gh-debridav-fork]: https://github.com/jtdevops/debridav
[gh-torboxarr]: https://github.com/MrJoiny/TorBoxarr
[gh-zurg]: https://github.com/debridmediamanager/zurg-public
[gh-blackhole]: https://github.com/westsurname/scripts
[gh-dumb]: https://github.com/I-am-PUID-0/DUMB
[gh-rclone]: https://github.com/rclone/rclone
[gh-riven]: https://github.com/rivenmedia/riven
[gh-clidebrid]: https://github.com/godver3/cli_debrid
[gh-plexdebrid]: https://github.com/itsToggle/plex_debrid
[gh-zilean]: https://github.com/iPromKnight/zilean
[gh-nzbdav]: https://github.com/nzbdav-dev/nzbdav
[gh-tbms]: https://github.com/nordicnode/TorBox-Media-Server
[gh-krantorbox]: https://github.com/elfhosted/krantorbox
[gh-rdt-torbox]: https://github.com/asylumexp/rdt-client-torbox
[gh-aiostreams]: https://github.com/Viren070/AIOStreams
[aio-search]: https://github.com/Viren070/AIOStreams/blob/main/packages/core/src/builtins/torbox-search/search-api.ts
[gh-comet]: https://github.com/g0ldyy/comet
[mf-torbox]: https://github.com/mhdzumair/MediaFusion/blob/main/backend/src/scrapers/torbox_search.rs
[gh-gelato]: https://github.com/lostb1t/Gelato
[stremio-stream]: https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md
[jf-storage]: https://jellyfin.org/docs/general/administration/storage/
[jf-chapters]: https://jellyfin.org/docs/general/server/metadata/chapter-images/
[gh-jellyfin]: https://github.com/jellyfin/jellyfin/releases
[cf-terms]: https://www.cloudflare.com/service-specific-terms-application-services/
[elf-jellyfin]: https://docs.elfhosted.com/guides/media/jellyfin-torbox-aars/
