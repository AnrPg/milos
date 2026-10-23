# Area and address search: operations (ADR-188)

How worldwide area search is served, what it needs from the cluster, and how to run the
optional in-cluster Photon. The step-by-step task for an agent is
`docs/handoff/2026-10-23-photon-k8s-handoff.md`.

## Three tiers

| Tier | What it answers | Runs where | Needs |
|---|---|---|---|
| 1. GeoNames towns | Every town of 500+ people and their sections, worldwide (~200k), typo-tolerant | Postgres (`places_neighbourhoods`, `source = 'geonames'`) | API egress to `download.geonames.org` once a month (~10 MB) |
| 2. Our Photon | Neighbourhoods, streets, addresses in Greece, Cyprus, France/Monaco | `ops/photon/photon.yaml`, cluster-internal | A 30 Gi volume, ~1.5–3 GiB RAM, egress to graphhopper.com + github.com while building |
| 3. Public Photon | The same for the rest of the world | photon.komoot.io | API egress; capped at 60 calls/min app-wide |

Tier 1 and 3 work with no cluster changes. Tier 2 is optional; without it tier 3 answers
for Greece too. The API caches geocoder answers in Redis for a day and skips a tier that is
down or over its cap, so a Photon outage only hides address suggestions.

## API settings (all optional)

| Env | Default | Meaning |
|---|---|---|
| `PHOTON_BASE_URL` | `https://photon.komoot.io` | Tier 2 (our Photon), e.g. `http://photon.<ns>.svc.cluster.local:2322` |
| `PHOTON_FALLBACK_BASE_URL` | `https://photon.komoot.io` | Tier 3; `""` turns it off |
| `PHOTON_FALLBACK_MAX_PER_MINUTE` | `60` | App-wide cap for the public Photon |
| `PHOTON_CACHE_TTL_SECONDS` | `86400` | How long answers are cached in Redis |
| `GEONAMES_BASE_URL` | `https://download.geonames.org/export/dump` | Mirror for the town dump |

The towns import runs from the `WorldGazetteerJob` (hourly check; works when the gazetteer
has no GeoNames rows or they are 30+ days old). Check it with
`SELECT count(*), max(updated_at) FROM places_neighbourhoods WHERE source = 'geonames';`
(about 200k rows after the first run).

## Our Photon (tier 2)

Photon 1.3.0 (komoot, OpenStreetMap). There is no prebuilt index for a set of countries, so
the init container builds one from the official per-country JSON dumps
(`download1.graphhopper.com/public/<continent>/<country>/photon-dump-<country>-1.0-latest.jsonl.zst`),
concatenated in country-code order with the repeated header lines removed, into one index
with Greek, English, French, German and Italian names.

Measured on 2026-10-23:

| Countries | Download | Index on disk | RAM serving | Build time (4 cores) |
|---|---|---|---|---|
| Greece + Cyprus | 93 MB | 0.49 GB | ~0.4 GB | ~8 min |
| + France/Monaco | +1.6 GB | ~9 GB (estimated at the same ratio) | ~1.5–2.5 GB | ~1–2 h |
| All of Europe (for comparison) | 13.3 GB dump / 32 GB index archive | ~70 GB | 8+ GB | many hours |

A rebuild keeps the old index until the new one is ready, so the volume needs about twice the
index (30 Gi for the three countries; 5 Gi is plenty for Greece + Cyprus alone). OpenSearch
stops writing above 95 % disk use, so keep headroom.

Changing countries is one line: `REGIONS` in the `photon-build` ConfigMap (paths from the
listing at `download1.graphhopper.com/public/europe/`, in country-code order). The next pod
start rebuilds because the marker no longer matches.

Refresh: the `photon-refresh` CronJob deletes the pod on the 2nd of each month; the init
container sees a 30-day-old index and rebuilds while the API falls back to the public Photon.

### Verify

```sh
kubectl -n <ns> logs photon-0 -c build-index | tail
kubectl -n <ns> run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -s 'http://photon:2322/api?q=kypseli&layer=district&layer=locality&layer=city&limit=1'
kubectl -n <ns> run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -s 'http://photon:2322/reverse?lat=38.0005&lon=23.7345&layer=district&limit=1'
```

Expect a `FeatureCollection` naming «Κυψέλη». Then in the app, typing «Φωκίωνος Νέγρη 1»
in the area picker should offer the address and save Κυψέλη.

### Attribution

Lists of places show "© OpenStreetMap contributors, GeoNames (CC BY 4.0)" (ODbL and CC BY ask
for credit). Keep it if the picker is redesigned.
