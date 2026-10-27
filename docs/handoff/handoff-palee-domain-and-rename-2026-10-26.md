# Handoff: move Palee to palee.app and purge "milos" from the app and gitops (2026-10-26)

## Για τον ANR: πώς το ξεκινάς

1. **Πρώτα κάνεις εσύ** τα βήματα του §0 (αγορά domain, DNS, Brevo, ερωτήσεις στον sysadmin). Χωρίς αυτά το Claude Code θα σταματήσει στην αρχή.
2. Άνοιξε το Claude Code **στον Mac σου**, μέσα στον φάκελο που έχει και τα δύο repos (π.χ. `~/MyApps`), γιατί χρειάζεται το `kubectl` σου (tenant-m4), push στο Gitea και `sops`.
3. Γράψε: `Διάβασε το /mnt/project-files/milos/handoff-palee-domain-and-rename-2026-10-26.md και εκτέλεσέ το.` Αν ο φάκελος του project δεν φαίνεται από τον Mac, κατέβασε πρώτα το αρχείο και δώσε τη δική σου διαδρομή.
4. Θα σταματήσει **μόνο** στις πύλες που λένε 🛑 (για βήματα που δεν αναιρούνται), και θα σου εξηγεί στα ελληνικά κάθε εντολή που πρέπει να τρέξεις εσύ.

**Τι να περιμένεις:** ένα PR κώδικα στο `milos`, μία μετάβαση gitops με **διακοπή συντήρησης περίπου 15–30 λεπτών** (ανακοίνωσέ τη), και μία ακόμα **επανασύνδεση όλων των χρηστών** (αλλάζει το domain, άρα και τα cookies). Τα παλιά δεδομένα σβήνονται μόνο αφού το επιβεβαιώσεις εσύ.

---

## Brief for Claude Code (English, so it is unambiguous)

### ⚠️ Scope change v2 (2026-10-27 14:40 Greece, overrides the 12:35 note and everything below)

ANR confirmed the app is **not released**: prod holds no real data, only ANR's own vendor (SaaS-owner) account `prod_owner_regas`. ANR dropped the "don't rename the DB" constraint and said: **only keep the vendor's account**. So this is a **clean slate with a full rename**, much simpler than the original §2:
- **Full rename, no backwards compatibility.** Do all TD-109 items, including crypto AAD/key derivation and every HMAC context (QR posters, NFC tags, member codes, Wallet tokens), Wallet class suffix, geofence ids, DB roles `palee_runtime`/`palee_migrations`, buckets `palee-*`, JWT issuer `palee` + cookie `palee_refresh`, bundle id `app.palee.member`. **No v1 fallbacks, no backfills, no dual-read code** (nothing was printed, published or issued). Remove any v1-fallback code you already wrote.
- **The customer org "Milos Training" is not kept** (ANR: only the vendor account). Drop the out-of-scope note about it below.
- **Fresh state stores, no data copy.** New empty CNPG cluster `palee-db` (no replica/promote), fresh `palee-minio`, `palee-meilisearch`, `palee-redis`. No `mc mirror`, no maintenance window for data. All `milos-*` objects in gitops are renamed/replaced by `palee-*`.
- **Safety copy first (🛑 before deleting anything):** one `pg_dump` of `milos-db` database `app` to ANR's laptop (via `kubectl exec` into the primary pod or `port-forward`), then old objects are pruned in §3.
- **Vendor account on the new DB:** after cutover, ANR signs up again on https://palee.app with handle `prod_owner_regas`, then grant vendor with
  `kubectl -n tenant-m4 exec deploy/palee-api -c api -- ./bin/palee rpc 'u = Palee.Identity.find_by_nickname("prod_owner_regas"); IO.inspect(Palee.Organizations.grant_vendor(u.id))'`
  (adjust the release binary name to what the code PR produces; explain the command to ANR in Greek per the standing rules). Do not add an env bootstrap.
- **Quota:** check `kubectl -n tenant-m4 describe resourcequota` before creating `palee-db` next to `milos-db`. If space is short, take the pg_dump, then remove `milos-db` first (🛑).
- **Sysadmin already did (2026-10-27, per ANR):** renamed the Harbor project(s), renamed the Gitea org, updated the CI/CD workflows, renamed the Flux GitRepository references. Seen by ANR at 14:55 Greece: Gitea org **`proj-palee`**, repos **`proj-palee/gitops`** (commit b83edee "images: pull from the proj-palee_palee Harbor project") and **`proj-palee/palee`** (commit c64dd1a "ci: push images to the proj-palee_palee Harbor project", CI was running); Harbor project **`proj-palee_palee`**; ANR browses Gitea at `src.time-albacore.ts.net`. Update local remotes (`origin-gittea`, gitops `origin`) to the new paths. Still verify exact image paths: before any registry/gitops change, read the current values from Gitea (`.gitea/workflows/build.yml` image paths, gitops `milos/milos-repo.yaml`, `milos-image-automation.yaml` URL) and from `kubectl -n tenant-m4 get deploy milos-api -o jsonpath='{.spec.template.spec.containers[0].image}'`. Do NOT redo or override his work; adopt his names. The GitHub mirrors of gitops stopped updating after 2026-10-26 07:35 UTC (probably broken by the rename), so never read gitops state from GitHub. Prod was healthy at 14:53 Greece (all pods Running, api/web rolled 13 min earlier).
- **HMAC/crypto decision:** move data-at-rest AND all HMAC contexts (QR posters, NFC, member codes, Wallet tokens, check-in) to `palee:` with no v1 fallback. Keep the data-at-rest backfill migration you already wrote (harmless on an empty DB, needed if ANR picks "keep milos-db and purge").
- **DB decision (ANR, 2026-10-27 14:56 Greece): option A.** Fresh empty CNPG `palee-db` next to `milos-db`; switch the app to it; after it works, `pg_dump` of `milos-db` to ANR's laptop, then delete `milos-db` (🛑 ask ANR before deleting). Not chosen: keeping `milos-db` and emptying it with `CleanSlatePurge`. You may now do the database/gitops part, following the phases and 🛑 gates.
- **Cleanup (§3) under option A:** no data is kept, so §3 does not need the 24–72 h wait: once palee.app works and ANR's vendor account is set up again, ask ANR (🛑) and then remove all old `milos-*` state objects from gitops (DB, MinIO + its PVC and files, Meilisearch, Redis, old Deployments/Services/Secrets, the old purge Job). ANR does nothing by hand in MinIO or the DBs. For verification ANR cannot list `clusters.postgresql.cnpg.io` (Forbidden); use `kubectl -n tenant-m4 get pods,pvc,svc,secret,ingress | grep -i milos` instead.
- **Photon (added 2026-10-27 at ANR's request):** also deploy the self-hosted Photon geocoder (tier 2 of ADR-188; **ANR 2026-10-27: Greece + Cyprus only for now, no France**; index ~0.5 GB, ~0.4 GB RAM) in the same gitops work, under the palee names: `milos/palee-photon.yaml` (or wherever the renamed files live), Service `palee-photon:2322`, a line in the root kustomization, `storageClassName: gp`, no namespace, and `PHOTON_BASE_URL=http://palee-photon:2322` in the api env. Follow `/mnt/project-files/milos/photon-deploy-guide-2026-10-26.md` and the repo's `ops/photon/` + `docs/handoff/2026-10-23-photon-k8s-handoff.md`, translating milos → palee names. Check the quota first. The app works without Photon, so it must not block the cutover.
- **Sysadmin:** nothing new for him. He already renamed the Gitea project on 2026-10-27 (details pending from ANR); verify current Gitea URLs and that Flux still reconciles before any gitops push. Do not ask him for anything; ANR handles communication.

### Ordering (updated 2026-10-27, overrides anything below)

Follow `/mnt/project-files/milos/palee-rollout-plan-2026-10-27.md`: Phase 2 = §1 code PR only (no gitops, no prod), keep it open until the Harbor robot creds arrive; Phase 3 = merge + build to `client-palee`; Phase 4 = §2 cutover; **Phase 5 = Gitea org/repo rename + sysadmin's one-line Flux URL change, AFTER the cutover**. During §2 the gitops repo URL stays `client-milos-method/gitops` (do not touch `milos-gitops-writer`'s URL until Phase 5; only rename the object if needed). Phase 6 = §3 + §4. Before any phase, confirm prod is healthy (`kubectl -n tenant-m4 get pods -l app=milos-api`: all Running 1/1); the people-search migration fix (PR #125) must be deployed first.

### Goal

1. Serve Palee at **https://palee.app** (+ `www.palee.app` → apex, media at `media.palee.app`). `milos.4kq.net` and `s3-milos.4kq.net` end up redirect-only, then removed.
2. Send email as **`Palee <no-reply@palee.app>`** through Brevo SMTP.
3. **Purge "milos"** from everything the product owns: the `milos` repo code and config, and every name in the gitops repo (files, Kubernetes object names, secrets, image paths, DB cluster/roles, buckets). Nothing a user can see may say milos: hostnames, URLs, email headers (HELO, Message-ID, From), cookies, certificates, app ids, store listings.
4. Do it as **one coordinated cutover** (ANR asked for "all at once"), but sequenced inside your session so there is no window without HTTPS and no data loss.

Out of scope and kept on purpose: the **customer** organisation "Milos Training" / slug `legacy-milos-training` (it is a real gym's name and customer data, not the product). Historical records (ADRs, old handoffs, audits, discussions) stay as written; living docs are updated.

### Read first

- `docs/technical_debt.md` → **TD-109**: the complete inventory of remaining milos names and why each was kept. This handoff resolves all ten items.
- `/mnt/project-files/milos/gitops-k8s-guide-2026-10-26.md`: how the gitops repo and Flux work (Gitea is the source; GitHub `AnrPg/gitops` is only a mirror; no `namespace:` fields; image automation markers).
- `/mnt/project-files/milos/palee-domain-and-email-guide-2026-10-26.md`: DNS, Ingress, redirect, Brevo, SPF/DKIM/DMARC decisions (DNS only, 308 redirect, `from-to-www-redirect`).
- Repo `.claude/CLAUDE.md` (vexp pipeline, multi-agent rules), and project memory `gitops-layout`, `palee-domain-and-email`, `tests-with-every-change`, `milos-cloud-toolchain`, `gitea-build-workflow`, `anr-command-teaching-standard`.

### Standing rules

- ANR is a junior with no k8s/bash background. **Every command you ask ANR to run** is explained in Greek: general syntax, each flag and its default, what the output looks like and which fields matter, where to look things up (`kubectl explain`, `--help`), how it generalises. Commands you run yourself need a one-line Greek note.
- Every code change updates all relevant tests (API, vitest, Playwright specs and their stubs). Run `mix precommit` incl. dialyzer before merging API changes (the Gitea CI does; red CI = no image = nothing deploys).
- gitops: push to **Gitea** `main` (origin = `src.4kq.net`), `git pull --no-rebase` before every push (Flux commits to main). Validate with `kubectl kustomize .` and `kubectl kustomize . | grep -n "namespace:"` (must be empty). Never push plaintext secrets: new secrets are new SOPS files encrypted with `.sops.yaml`'s public age key.
- milos repo: branch `feat/palee-infra-rename` off `main`, PR on GitHub, merge, then push `main` to the Gitea remote `origin-gittea` (never `--tags`).
- `kubectl` reaches only `tenant-m4`; no `flux` CLI. Never `kubectl apply/edit/set` to change state (Flux reverts it); kubectl is for observing, plus read-only checks and, where allowed, `exec`/`port-forward`/`rollout restart`.
- Times for ANR in Greece time (Europe/Athens).
- 🛑 = stop and get ANR's explicit go-ahead in the conversation. Do not pass a 🛑 on your own judgement.

---

### §0. Prerequisites (ANR does these before you start; verify each, stop if missing)

| # | What | How you verify |
|---|---|---|
| 0.1 | `palee.app` bought at Cloudflare Registrar, 2FA on | `dig +short NS palee.app` → `*.ns.cloudflare.com` |
| 0.2 | DNS (DNS only/grey): `@`, `www`, `media` CNAME `prod.gata.4kq.net` | `dig +short palee.app`, `media.palee.app` → the 5 cluster IPs |
| 0.3 | ✅ Done 2026-10-26: Brevo domain `palee.app` authenticated (brevo-code, DKIM `brevo1`/`brevo2`, branded `img`/`r` CNAMEs), one DMARC `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com`, SMTP login `c01399001@smtp-brevo.com`, app key named `palee@smtp-brev…` (Gmail has its own key `gmail-send-as`; never use that one in the cluster). Still check: sender `Palee <no-reply@palee.app>` exists under Senders and is green | `dig +short TXT _dmarc.palee.app` → exactly one line; ANR pastes the key **value** only into the sops step (§2e), never into chat |
| 0.4 | ✅ Done 2026-10-26 (MX route1-3, SPF merged; forwarding of hello@ still being verified): Cloudflare Email Routing on, one merged SPF `v=spf1 include:_spf.mx.cloudflare.net include:spf.brevo.com ~all` | `dig +short TXT palee.app` shows exactly one `v=spf1` |
| 0.5 | Custom-domain Ingress + `letsencrypt-production` HTTP-01 allowed in tenant-m4 | ✅ confirmed by ANR 2026-10-26 |
| 0.6 | **Sysadmin:** registry project `oci.4kq.net/client-palee` with push creds for the Gitea runner and pull creds for tenant-m4 | `docker login` / `crane ls` with the new creds |
| 0.7 | **Phase 5, after the cutover (not a prerequisite):** Gitea org/repo rename (`client-milos-method` → e.g. `client-palee`) **and** the tenant's Flux `GitRepository` URL updated in the cluster repo (`manifests/cluster/flux-system/tenants/m4/`) at the same moment; image-automation deploy key re-added if needed | `git ls-remote` on the new URL; a gitops change still reconciles |
| 0.8 | **Sysadmin:** egress TCP 587 from tenant-m4 pods to `smtp-relay.brevo.com` | `exec` + `:gen_tcp.connect` check (guide §10δ) |
| 0.9 | **Sysadmin (only if they apply):** real-IP from Cloudflare not needed (we stay DNS only); external Grafana/alert rules that query `milos_*` metrics renamed to `palee_*` | ask |
| 0.10 | Mobile app **not yet published** to App Store / Play (expected: native wrapper timing was still open) | ask ANR; if it is published, 🛑 the bundle-id change becomes a new store listing |

**Division of work (updated 2026-10-27, keep the sysadmin's part minimal; he is new to this too).** The sysadmin only (1) creates Harbor project `client-palee` (Harbor at oci.4kq.net, OIDC login) with robot `robot$client-palee+ci` (push+pull) and hands ANR the token, and (2) after ANR renames the Gitea org, changes one line in the cluster repo (`manifests/cluster/flux-system/tenants/m4/`: `client-milos-method/gitops` → `client-palee/gitops`) and reconciles. See `sysadmin-request-palee-2026-10-26.md` and `anr-prechecks-2026-10-27.md`. Everything else is ours: ANR renames the Gitea org/repo (Gitea 1.27.3; if ANR is not org owner, the sysadmin does that rename too), ANR sets the Gitea Actions secrets `REGISTRY_USERNAME`/`REGISTRY_PASSWORD` to the robot creds, you create `palee/palee-pull-secret.yaml` from the robot creds (`kubectl create secret docker-registry ... --dry-run=client -o yaml`, then sops; ANR types the token locally), you update the `GitRepository milos-gitops-writer` URL (→ `palee-gitops-writer`, `.../client-palee/gitops.git`). Backups for `palee-db` go to **ANR's Cloudflare R2** (bucket `palee-db-backups`, EU), via an `ObjectStore` `palee-db-backup-store` + SOPS secret in `palee/`, if `objectstores.barmancloud.cnpg.io` exists and tenant-m4 may create it (prechecks §4); else ask ANR to ask the sysadmin. Only escalate egress 587 or quota if ANR's prechecks show a need.

If 0.6 or 0.7 are not ready, you may still do everything else and leave the registry path and Gitea URL as the last small follow-up commit; say so plainly.

---

### §1. Code PR in `milos` (branch `feat/palee-infra-rename`)

Resolve TD-109 item by item. Design for zero data loss and backward compatibility during the cutover; remove the compatibility shims in §4.

1. **Release entrypoint:** keep `bin/milos_training` link and `MilosTraining.Release` for now (the running gitops still calls them); gitops will switch to `bin/palee eval "Palee.Release.migrate()"` in §2. Add `Palee.Release.reindex_search/0` (rebuild all Meilisearch indexes from Postgres: member index, PR index, any others in `infrastructure/search/`) and `Palee.Release.copy_buckets/0` if you choose app-driven bucket copy (see 5).
2. **Image path:** `.gitea/workflows/build.yml` → `oci.4kq.net/client-palee/{api,web}` (needs 0.6). Pass the `NEXT_PUBLIC_*` values the browser needs as build args (`NEXT_PUBLIC_MEDIA_ORIGIN=https://media.palee.app`, `NEXT_PUBLIC_SITE_URL=https://palee.app`, map vars as today) and verify in the built client bundle that no `4kq.net`/`milos` string remains.
3. **Email headers:** configure gen_smtp `hostname:` from a new env `SMTP_HELO_HOST` (prod `palee.app`), and set an explicit `Message-ID` `<uuid@palee.app>` (domain from `MAIL_FROM_ADDRESS`) on every Swoosh email. `MAIL_FROM_*` defaults must never fall back to a `4kq.net` host: default the address to `no-reply@<public host>` only when the host is not internal, otherwise raise at boot in prod. Every app email also gets `Reply-To: Palee <support@palee.app>` (new env `MAIL_REPLY_TO`, prod `support@palee.app`), so a user who presses Reply reaches support instead of the unrouted `no-reply@`. Test: render each mailer and assert headers contain no `milos` and no pod hostname.
4. **Auth names (everyone re-logs in anyway because the domain changes):** JWT issuer default `palee`; prod sets `GUARDIAN_ISSUER=palee` in §2. Refresh cookie `palee_refresh`; for one release also accept `milos_refresh` on read (never set it), then drop in §4.
5. **Buckets:** defaults `palee-invoices`, `palee-avatars`, `palee-media`. Plan the data move: (a) copy objects old → new bucket (MinIO `mc mirror` Job or `Palee.Release.copy_buckets/0`), (b) an Ecto migration/backfill that rewrites any stored bucket names/URLs/keys that embed `milos-*` (check `legacy_object_migration.ex` and every schema that stores object refs), (c) the app reads only new buckets after cutover. Idempotent and resumable.
6. **Crypto contracts (TD-109 item 7):** introduce versioned contexts: AES-GCM AAD `palee:data-at-rest:v2` and key-derivation `"palee:" <> purpose` for **new** writes; reads try v2 then fall back to v1 (`milos:` AAD / derivation). Add an Oban backfill job that re-encrypts every v1 ciphertext to v2 (batched, resumable, idempotent, observable count of remaining v1 rows). Keep the v1 read path until the backfill reports zero, then remove it in §4. Property tests: v1 data still decrypts; after backfill everything is v2.
7. **Mobile + app links:** bundle/package id `app.palee.member` (reverse of the owned domain), app group `group.app.palee.member`, move Android sources from `java/app/milos/member` to `java/app/palee/member`, `apps/mobile/config/environments.json` production URL `https://palee.app`, iOS associated-domains/app-links entitlement `palee.app`, `native_push_credentials.ex` default topic, `app-links.ts` defaults + tests. (Gate: 0.10.)
8. **Google Wallet:** class suffix `palee_member_card`. Existing issued passes reference the old class: create the new class, issue new passes for new saves, and if any old passes exist in prod, keep the old class readable until they are re-issued (check prod count first).
9. **Geofence ids:** `palee-<location>`; on app start, unregister any `milos-*` region before registering the new ones.
10. **DB role names:** runtime role `palee_runtime` (`ops/postgres/init`, `scripts/provision_postgres_runtime_role.sh`, docker-compose, `.env.example`, `privilege_guard.ex` docs). Migrations role in prod becomes `palee_migrations` (§2). Make sure no migration or RLS policy hard-codes a role name; if one does, add a migration that handles both names.
11. **Everything else:** `git grep -in milos` must return only: historical docs, the legacy customer org, the v1 crypto fallback, the `milos_refresh` read fallback, the `bin/milos_training` link + legacy entrypoint, and the rename migration's data constants. List each remaining hit in the PR body with its removal step. Update TD-109 (status, what remains for §4), `docs/product/ontology.md`, the SEO feature catalog/llms.txt if they name hosts, and the deploy docs.
12. **Tests + gate:** full gate per `milos-cloud-toolchain` (API `mix precommit` incl. dialyzer and credo, web `tsc`/eslint/vitest/i18n, Playwright per project). Fix what breaks. Merge only green.

After merge: push `main` to `origin-gittea`, watch the Gitea run, confirm both images exist at the new registry path with a timestamp tag. **Do not** let the new image roll out before §2: the old ImagePolicy watches the old path, so it will not pick up the new images (good), and the code is backward compatible either way.

---

### §2. gitops cutover (one session, sequenced)

Prepare everything as **one branch of commits locally**, validate, then push in the order below, waiting at each check. Rename files `milos/*.yaml` → `palee/*.yaml` and every object name `milos-*` → `palee-*`; update the root `kustomization.yaml` and README (drop the stale `hello/` section).

**2a. Pre-flight (read-only):**
- Record current state: images, pod list, `get clusters.postgresql.cnpg.io`, PVC sizes, MinIO bucket sizes (`exec` + `mc du` if available), counts of key tables.
- 🛑 **Backup gate.** CNPG backups are not enabled. Take a logical dump before anything: `kubectl -n tenant-m4 exec milos-db-1 -c postgres -- pg_dump -Fc -d app > ~/palee-backup-<date>.dump` (on the primary, find it with `-L role`), plus a MinIO copy if storage allows. Verify the dump with `pg_restore --list | head`. ANR confirms the files exist on their Mac.

**2b. Additive objects (no traffic change, push #1):**
- Secrets as new SOPS files: `palee` (same keys as `milos`; ANR or sysadmin decrypts the old one with the private age key, or re-generate new values where safe: new `MEILI_MASTER_KEY`, new MinIO keys for the new MinIO; keep `SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY` unchanged so v1 ciphertexts stay decryptable; set `GUARDIAN_ISSUER=palee`), `palee-gemini`, `palee-smtp` (Brevo login/key), `palee-pull-secret` (new registry creds), `palee-db-migrations(-credentials)` for role `palee_migrations`, image-automation git secret if the Gitea URL changed.
- New stateful copies:
  - **DB:** CNPG `Cluster palee-db` as a **replica cluster** of `milos-db` (`spec.replica.enabled: true`, `externalClusters` → `milos-db-rw` using the source's streaming-replication/CA secrets, `bootstrap.pg_basebackup`), same image/instances/storage (`gp`), and **enable backups on the new cluster** if the sysadmin provides an ObjectStore (ask; recommend strongly). `DatabaseRole palee_migrations` (same flags as `milos_migrations`), `Database` for `app` with postgis (and `pg_trgm` if the people-search fix needs it; check the thread "Fix failing prod migration for people search" outcome first). Read the CNPG docs for replica clusters and promotion before writing it: https://cloudnative-pg.io/documentation/current/replica_cluster/ . Check `kubectl explain cluster.spec.replica --api-version=postgresql.cnpg.io/v1` for the installed version's fields.
  - **MinIO:** new PVC/Deployment/Service `palee-minio` (same size or larger) + a one-off `Job` that `mc mirror`s `milos-*` buckets from `milos-minio` into `palee-*` buckets on `palee-minio`. Re-runnable.
  - **Meilisearch:** new `palee-meilisearch` (empty; reindexed in 2d). **Redis:** new HelmRelease `palee-redis` (holds only rate-limit counters; starting empty is fine; verify that is still true).
  - `ImageRepository`/`ImagePolicy` `palee-api`/`palee-web` on `oci.4kq.net/client-palee/*`, `ImageUpdateAutomation palee` with `update.path: ./palee`; markers `{"$imagepolicy": "tenant-m4:palee-api"}` / `palee-web`. Remove the old automation objects in the same push so two automations never fight.
  - Ingress `palee` for `palee.app` + `www` (`from-to-www-redirect`) and `media.palee.app` → **old** services for now (`milos-api`/`milos-web`/`milos-minio`), so certificates issue before the switch.
- Check: secrets exist (`get secret`), `palee-db` healthy and streaming (`get clusters.postgresql.cnpg.io`, replica lag in `status`), mirror Job `Complete` and object counts match, certificates `READY True`, `curl -sI https://palee.app` 200 (still old app).

**2c. 🛑 Maintenance window (ANR picks the time; tell users).** Then, push #2 (the switch):
- Old API/web `replicas: 0` (stop writes) → wait until no `milos-api` pods → re-run the MinIO mirror Job (catch the last writes) → promote `palee-db` (`replica.enabled: false`; follow the CNPG promotion procedure exactly) → wait for `palee-db` primary ready.
- New `palee-api`/`palee-web` Deployments: image `oci.4kq.net/client-palee/...:<new tag>` with markers; initContainer `migrate` command `["./bin/palee", "eval", "Palee.Release.migrate()"]`; env: `PHX_HOST=palee.app`, `MINIO_ENDPOINT=http://palee-minio:9000`, `MINIO_PUBLIC_ENDPOINT=https://media.palee.app`, `REDIS_URL=redis://palee-redis-master:6379`, `MEILI_URL=http://palee-meilisearch:7700`, `DATABASE_URL` from `palee-db-app`, `MIGRATION_DATABASE_URL` from `palee-db-migrations`, `MINIO_BUCKET`/`MINIO_AVATAR_BUCKET`/`MINIO_MEDIA_BUCKET` = `palee-*`, `SMTP_RELAY=smtp-relay.brevo.com`, `SMTP_PORT=587`, `SMTP_HELO_HOST=palee.app`, `MAIL_FROM_NAME=Palee`, `MAIL_FROM_ADDRESS=no-reply@palee.app`, `PHOTON_*` if Photon is deployed by then; `envFrom` `palee`, `palee-gemini`, `palee-smtp`. Web: `API_PROXY_TARGET=http://palee-api:4000`, `NEXT_PUBLIC_SITE_URL=https://palee.app`, media vars `https://media.palee.app`. MinIO: `MINIO_API_CORS_ALLOW_ORIGIN=https://palee.app`.
- Ingress `palee` → `palee-api`/`palee-web`/`palee-minio`. Ingress `milos` → `permanent-redirect: https://palee.app$request_uri`, code `308` (keep its TLS). Keep `s3-milos.4kq.net` serving `palee-minio` read-only for a few days so already-rendered links keep working, then remove.
- Check: `rollout status` both, `logs -c migrate`, `/api/health`, login works on palee.app, an image loads from `media.palee.app`, websockets connect (`/socket`, `/live`), `curl -sI https://milos.4kq.net/x` → 308 to `https://palee.app/x`.
- Run `Palee.Release.reindex_search()` (exec `bin/palee rpc` or a one-off Job) and confirm member/PR search works. Start the crypto v1→v2 backfill and the bucket-reference backfill; report remaining counts.
- Send a real email (owner invitation to ANR's Gmail): Gmail "Show original" must show SPF/DKIM/DMARC PASS, `From: Palee <no-reply@palee.app>`, and no `milos` or pod hostname anywhere in the headers. mail-tester.com ≥ 9/10.
- Post the end of the window to ANR.

**2e. Email through Brevo (part of push #1 and #2 above; spelled out here so nothing is missed). Source: guide §10.**

- Push #1 adds `palee/palee-smtp-secret.yaml` (SOPS-encrypted, listed in the root `kustomization.yaml`):
  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: palee-smtp
  type: Opaque
  stringData:
    SMTP_USERNAME: "c01399001@smtp-brevo.com"
    SMTP_PASSWORD: "<value of the Brevo key named palee@smtp-brev…; ANR pastes it into the file locally>"
  ```
  Write the file with a placeholder, let ANR replace the placeholder in their editor, then `sops --encrypt --in-place palee/palee-smtp-secret.yaml` and verify with `grep -c "ENC\[" ...` (≥ 2) and `git diff --staged` (no plaintext). Explain each step to ANR in Greek (guide §10α is the model).
- Push #2 wires it into the **`api` container only** (not `migrate`): env `SMTP_RELAY=smtp-relay.brevo.com`, `SMTP_PORT="587"` (STARTTLS; `SMTP_SSL` unset), `SMTP_HELO_HOST=palee.app`, `MAIL_FROM_NAME=Palee`, `MAIL_FROM_ADDRESS=no-reply@palee.app`, `MAIL_REPLY_TO=support@palee.app`, and `envFrom: - secretRef: {name: palee-smtp}`.
- Before 2c, check egress from the current API pod: `kubectl -n tenant-m4 exec deploy/milos-api -c api -- ./bin/milos_training rpc ':gen_tcp.connect(~c"smtp-relay.brevo.com", 587, [], 5000) |> IO.inspect()'` → `{:ok, _}`; `{:error, :timeout}` = sysadmin item 0.8 not done.
- After 2c: trigger a real email (owner invitation or support request) to ANR's Gmail. Required: Brevo → Transactional → Logs shows it delivered; Gmail "Show original" has SPF/DKIM/DMARC **PASS**, `From: Palee <no-reply@palee.app>`, HELO/`Received` and `Message-ID` contain `palee.app` and no `milos`/pod hostname; mail-tester.com ≥ 9/10. Logs: `kubectl -n tenant-m4 logs -l app=palee-api -c api --since=15m --prefix | grep -iE "smtp|mailer|swoosh"`.
- ⚠️ Both Brevo SMTP keys expire **2027-10-26**. Add a line to the gitops README ("rotate `palee-smtp` before 2027-10-26") and remind ANR to set a calendar reminder for September 2027.

**2d. Rollback plan (write it before 2c, keep it ready):** old objects still exist with `replicas: 0`, old DB `milos-db` untouched since the stop, old MinIO untouched. Rollback = revert push #2 (old replicas back to 2, `milos` Ingress back to normal). Only valid until new writes land on `palee-db`; after that, rolling back loses those writes, so decide within the window.

---

### §3. 🛑 Remove the old world (ANR approves after ≥ 24–72 h of healthy running and a fresh backup of `palee-db`)

Pruning deletes PVCs and the old CNPG cluster: irreversible.
- Remove from gitops: `milos-db*` (Cluster, Database, DatabaseRole, secrets), `milos-minio`, `milos-meilisearch`, `milos-redis`, old Deployments/Services, the completed `milos-clean-slate-purge` Job, old secrets, `s3-milos.4kq.net` Ingress.
- Keep the `milos.4kq.net` 308 redirect Ingress (it only redirects; it is the one remaining "milos" object and exists so old links keep working). ANR decides when to drop it (suggest ≥ 6 months, after Search Console shows the move done).
- Verify after prune: `kubectl -n tenant-m4 get all,pvc,secret,ingress,clusters.postgresql.cnpg.io | grep -i milos` → only the redirect Ingress and its TLS secret.

### §4. Follow-up code PR (after the backfills report zero)

Remove: v1 crypto read path, `milos_refresh` read fallback, `bin/milos_training` link in the Dockerfile, `legacy_release_entrypoint.ex`, any temporary dual-bucket reads. Close TD-109. Final `git grep -in milos` lists only historical docs, the legacy customer org, and migration data constants.

### §5. Manual items for ANR (list them at the end, with Greek instructions)

- GitHub: rename `AnrPg/milos` → `AnrPg/palee` (Settings → Repository name; GitHub keeps redirects). Update the local remote (`git remote set-url`), the Claude project's repository list, and the Gitea mirror if one pushes to GitHub.
- Google Search Console: Domain property `palee.app` (TXT in Cloudflare), submit `https://palee.app/sitemap.xml`; Change of Address from `milos.4kq.net` if the sysadmin can verify it.
- External services that know the old host: OAuth/Sign in with Apple/Google callbacks (if enabled), payment webhooks, Gemini key restrictions, Brevo sender list.
- DMARC to `p=quarantine` after 2–4 weeks of clean reports.

### Deliverables

- PR #1 (code) merged, PR #2 (cleanup) after backfills; gitops commits pushed to Gitea; a short Greek report for ANR at the end: what changed, what was checked (with the command output that proves it), what remains (§3/§4/§5) and when.
- Update project memory `gitops-layout` and `palee-domain-and-email` with the new names, and mark TD-109 resolved in memory too.
