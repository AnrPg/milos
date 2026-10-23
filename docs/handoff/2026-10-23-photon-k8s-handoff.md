# Handoff: deploy the in-cluster Photon and wire area search (ADR-188)

For a code agent working in the **gitops repo** (Flux; tenant namespace `tenant-m4`, nginx ingress,
CNPG Postgres `milos-db`). The application side is already merged in `AnrPg/milos`; nothing in the
app repo needs changing. Read first: `docs/adr/ADR-188-worldwide-area-and-address-search.md`,
`docs/operations/self-hosted-photon.md`, `ops/photon/photon.yaml` (all in `AnrPg/milos`).

**The owner does not have full cluster access.** Every step lists what to do when it is refused.
Never work around a refusal by widening permissions yourself; take the sidestep or stop and report.
Nothing here is required for the app to work: without it, towns come from Postgres and addresses
from the public Photon (capped, cached).

## Goal

1. A cluster-internal Photon (Service `photon:2322`) holding Greece, Cyprus and France/Monaco.
2. The API pointed at it with `PHOTON_BASE_URL`.
3. Egress the API and Photon need is allowed.

## Steps

### 0. Discover what you may do

```sh
kubectl auth can-i create statefulsets -n tenant-m4
kubectl auth can-i create persistentvolumeclaims -n tenant-m4
kubectl auth can-i create cronjobs -n tenant-m4
kubectl auth can-i create roles -n tenant-m4
kubectl get ns tenant-m4 -o jsonpath='{.metadata.labels}'   # Pod Security level?
kubectl get resourcequota,limitrange -n tenant-m4
kubectl get networkpolicy -n tenant-m4
kubectl get storageclass
```

If `kubectl` itself is unavailable, work only through gitops commits and read Flux status
(`flux get kustomizations`) or ask the owner to paste it. Record the answers in the PR description.

### 1. Add the manifest to gitops

Copy `ops/photon/photon.yaml` into the tenant's app directory (next to the API manifests) and add it
to that directory's `kustomization.yaml`. Set the namespace through kustomize, not in the file.
Match the repo's labelling conventions; keep `app.kubernetes.io/name: photon` (the Service selects it).

Sidesteps:
- **Quota too small / no 30 Gi of storage:** set `REGIONS: "europe/cyprus europe/greece"` and the
  volume to `5Gi`, memory request `768Mi` / limit `1536Mi`, serve `JAVA_OPTS=-Xms256m -Xmx768m`,
  build `-Xmx2g`. France can be added later by editing `REGIONS` and the volume size.
- **No storage class / PVCs refused:** replace the volumeClaimTemplate with an `emptyDir`
  (`sizeLimit: 5Gi`) and Greece + Cyprus only. Every pod start then rebuilds (~8 min); the API falls
  back to the public Photon meanwhile. Drop the CronJob (a restart is the refresh).
- **Pod Security "restricted" refuses the root init container** (it runs `apt-get` and `chown`):
  build a small image instead and run the init container as uid 1000 without `apt-get`:

  ```dockerfile
  FROM eclipse-temurin:21.0.12_8-jre-noble
  RUN apt-get update && apt-get install -y --no-install-recommends zstd curl ca-certificates \
      && rm -rf /var/lib/apt/lists/* \
      && curl -fsSL -o /opt/photon.jar \
         https://github.com/komoot/photon/releases/download/1.3.0/photon-1.3.0.jar
  USER 1000
  ```

  Push it to the registry the API image uses (Gitea), point both containers at it, remove the
  `apt-get` lines and the jar download from `build.sh` (use `/opt/photon.jar`), drop
  `chown`, and set `runAsUser: 1000` on the init container. If you cannot push images, stop and
  report: the app runs without Photon.

### 2. Allow traffic

- Photon egress while building: `download1.graphhopper.com:443`, `github.com:443` and
  `objects.githubusercontent.com:443` (the jar), plus Ubuntu mirrors for `apt-get` unless you used
  the custom image.
- API egress: `download.geonames.org:443` (monthly towns import), `photon.komoot.io:443` (public tier).
- API → Photon: TCP 2322 inside the namespace.

If NetworkPolicies are default-deny, add one allowing ingress to `app.kubernetes.io/name: photon` on
2322 from the API pods (copy the API's real labels) and the egress rules above. If you cannot
create NetworkPolicies, report which flows are blocked; the API still works on the tiers it can reach.

### 3. Point the API at Photon

On the API Deployment (where its other env vars live, ConfigMap or `env:`):

```yaml
- name: PHOTON_BASE_URL
  value: http://photon.tenant-m4.svc.cluster.local:2322
```

Leave `PHOTON_FALLBACK_BASE_URL` unset (the public Photon covers the rest of the world, capped at
60/min). Only add this **after** Photon's readiness probe is green, otherwise every search pays a
failed call first (it still works, just slower until the 5 s timeout).

### 4. Monthly refresh

The `photon-refresh` ServiceAccount, Role, RoleBinding and CronJob delete `photon-0` once a month.
**If creating Roles or CronJobs is refused,** delete those four objects from the manifest; the
index stays usable, and anyone may refresh it later with `kubectl delete pod photon-0` (or by
bumping an annotation on the pod template through gitops).

### 5. Verify

```sh
flux get kustomizations                  # reconciled
kubectl -n tenant-m4 logs photon-0 -c build-index | tail -3      # "index built"
kubectl -n tenant-m4 run curl --rm -it --restart=Never --image=curlimages/curl:8.10.1 -- \
  curl -s 'http://photon:2322/api?q=kypseli&layer=district&layer=city&limit=1'   # «Κυψέλη»
```

Then check the API: `SELECT count(*) FROM places_neighbourhoods WHERE source = 'geonames';` should
reach ~200k within an hour of the new API version running, and the app's area picker should offer
«Φωκίωνος Νέγρη 1» as an address.

### Rollback

Remove `PHOTON_BASE_URL` from the API first, then the Photon objects (and its PVC if you want the
disk back). The app keeps working on the other tiers.

## Report back

In the gitops PR: which steps applied as written, which sidesteps were taken and why (with the
`can-i` answers), measured index size and pod memory after a day, and anything left blocked.
