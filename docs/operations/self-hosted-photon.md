# Self-hosted Photon geocoder

Palee geocodes through [Photon](https://github.com/komoot/photon), komoot's geocoder for
OpenStreetMap data (`apps/api/lib/palee/infrastructure/facility/photon_geocoder.ex`). The
base URL comes from `PHOTON_BASE_URL` (`apps/api/config/runtime.exs`). Its default,
`https://photon.komoot.io`, is a public fair-use demo server and must not carry production
traffic. This guide runs Photon inside the cluster: no paid service, no public endpoint.

Facts checked on 2026-10-23. Re-check the download listing before sizing a new volume.

## 1. Why Photon

| Option | Why not, or why |
|---|---|
| Nominatim (public) | Its usage policy forbids autocomplete. Self-hosted Nominatim is not built for search-as-you-type either, and it needs a full PostGIS import. |
| Pelias | Several services (Elasticsearch, API, placeholder, PIP, libpostal, importers). Too heavy for one geocoder. |
| Bundled GeoNames | Covers cities only, with no districts, streets or house numbers. Data goes stale inside the release. |
| **Photon** | Built for type-ahead. `layer` filters `city/district/locality/street/house` on `/api` and `/reverse` (since 0.4.0). One JVM with embedded OpenSearch. Prebuilt planet index you download, no import. |

ADR-188 sends two requests per search (`lang=default` and `lang=en`) plus reverse lookups.
That doubles per-keystroke load, which is why the public server is out of the question.
Prebuilt dumps carry local names plus `en/de/fr/it`, which matches the client's `@languages`.

## 2. Sizing

Use the current release: Photon **1.3.0** (Java 21+, embedded OpenSearch; 1.x indexes are
incompatible with 0.7). Dumps are published at `download1.graphhopper.com/public/`. New
`release-YYMMDD` dumps appear weekly, and the `*-1.0-latest` aliases serve the 1.x series.

| Extract | Download (`photon-db-…-1.0-latest.tar.bz2`) | Unpacked |
|---|---|---|
| planet | 62.9 GB (2026-10-20) | ~95 GB (README, "grows ~10 %/year") |
| europe | 32.0 GB | ~50 GB (estimated at the planet ratio) |
| single country | `public/<continent>/<country>/`, only some countries | small |

**Recommendation: `planet`**, because members can search any country. A region index returns
nothing outside the region, and the app would fall back to its gazetteer there.

- **PVC: 320 Gi SSD.** With `UPDATE_STRATEGY=PARALLEL`, the peak is the old index (~95), plus the
  archive (63), plus the new index (~95), about 255 GB. 320 Gi adds headroom for a year of growth.
  `SEQUENTIAL` fits in ~200 Gi but takes geocoding down for hours at every refresh. Europe
  with `PARALLEL`: 160 Gi.
- **Memory.** Photon recommends at least 64 GB RAM for a planet server under load. A small API
  gets by with less, as long as the index fits mostly in page cache. Start with a 12 GiB heap,
  `requests.memory: 24Gi` and `limits.memory: 32Gi`, on a node with 64 GB or more. Raise both
  if p95 latency is high or the pod is OOM-killed. **CPU:** request 1 core and set no limit
  (queries are bursty).

## 3. Manifest

`ops/photon/photon.yaml` is a namespace-agnostic **StatefulSet** (1 replica, volumeClaimTemplate
`data` of 320 Gi) plus a **ClusterIP Service `photon:2322`**, with **no Ingress**. It uses the
community image [`rtuszik/photon-docker`](https://github.com/rtuszik/photon-docker), pinned to
`2.4.0@sha256:21549c60…`, which bundles Photon 1.3.0 on Temurin 21. On first start the image
downloads and unpacks the index into `/photon/data`, then serves on 2322. Key env:

| Var | Value | Note |
|---|---|---|
| `REGION` | `planet` | Or `europe`, or a country with a prebuilt DB index. |
| `BASE_URL` | `https://download1.graphhopper.com/public` | The image default is a community mirror with no integrity guarantees. MD5 is verified either way. |
| `UPDATE_STRATEGY` | `PARALLEL` | `SEQUENTIAL` (default) and `DISABLED` are the other values. |
| `UPDATE_INTERVAL` | `30d` | The minimum index age before the image checks for a newer dump, then hourly. |
| `ENABLE_METRICS` | `TRUE` | Prometheus at `/metrics`. |
| `JAVA_PARAMS` | `-Xms12g -Xmx12g` | Heap size. |

Security: the pod runs as uid/gid 9011 (non-root, supported since image 2.4.0). It sets
`fsGroup: 9011` with `OnRootMismatch` and drops all capabilities. The root filesystem stays
writable because read-only support is unverified. Probes: a `startupProbe` on `/status` allows
up to 24 h for the first download; readiness and liveness use `/api?q=berlin&limit=1`.

In the gitops repo, add the file to the tenant kustomization (`namespace: tenant-m4`), set
`storageClassName` to an SSD class, and let Flux reconcile. Expect several hours before the pod
becomes Ready on first install.

## 4. Wiring the API

On the api Deployment in the gitops repo:

```yaml
env:
  - name: PHOTON_BASE_URL
    value: http://photon.tenant-m4.svc.cluster.local:2322
```

Verify from inside the namespace:

```bash
kubectl -n tenant-m4 get pod -l app.kubernetes.io/name=photon
kubectl -n tenant-m4 run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- sh -c '
  B=http://photon.tenant-m4.svc.cluster.local:2322
  curl -s "$B/status"; echo
  curl -s "$B/api?q=berlin&limit=1&lang=en&layer=city"; echo
  curl -s "$B/api?q=kolonaki&limit=3&lang=default&layer=district&layer=locality"; echo
  curl -s "$B/reverse?lat=37.9755&lon=23.7348&layer=house&layer=street"; echo'
```

Also check the api logs: they should have no `photon geocoder failed` or `answered 5xx` warnings.

**NetworkPolicy.** If `tenant-m4` uses default-deny, allow:
- ingress to `photon:2322` from the api pods only;
- api egress to `photon:2322`;
- photon egress to DNS and to `download1.graphhopper.com:443` (needed for index updates).

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: photon-from-api}
spec:
  podSelector: {matchLabels: {app.kubernetes.io/name: photon}}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {matchLabels: {app.kubernetes.io/name: api}}}]  # match the api's real labels
      ports: [{port: 2322, protocol: TCP}]
```

## 5. Updates, monitoring, degradation

- **Refresh.** The image checks once the index is 30 days old. It downloads the newest dump,
  builds it beside the live one (`PARALLEL`), swaps, and restarts Photon. Monthly is plenty for
  places. Weekly costs about 63 GB of download per week. Photon's own continuous updates need a
  Nominatim database, so we don't use them.
- **Force a refresh:** set `FORCE_UPDATE=TRUE` for one rollout, then remove it.
- **Upgrading the image:** read the release notes first. A Photon major bump (e.g. 0.7 to 1.0)
  needs a new index, which means a full re-download.
- **Monitoring.** Scrape `/metrics` (request timers). Alert when the pod is not Ready for more
  than 15 min, when PVC usage is above 85 %, and when the data date in `/status` is older than
  45 days. Graph the api's `photon geocoder` warnings.
- **Graceful degradation.** The client uses a 5 s timeout and no retries. Any failure maps to
  `{:error, :geocoder_unavailable}`, and member search falls back to places already stored in
  Palee's own gazetteer. An outage hides new streets and addresses but never breaks search or
  existing pages. During the first download, keep `PHOTON_BASE_URL` on its old value. Switch it
  once the pod is Ready.
