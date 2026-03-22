# Redis Sentinel + HAProxy on OpenShift (RHEL8 RPM-based)

This package provides a practical starter implementation for deploying **Redis OSS 7.2 + Sentinel + HAProxy** on **OpenShift** using a **custom image built from your organization's RPM**.

## Architecture

- `redis-0` starts as the initial primary
- `redis-1`, `redis-2` start as replicas of `redis-0`
- 3 Sentinel pods monitor the primary and coordinate failover
- 2 HAProxy pods expose a **stable internal service endpoint** for applications
- Applications connect only to the HAProxy service
- Redis data persists on PVCs

## Recommended app endpoint

Applications should connect to:

- `redis-proxy.<namespace>.svc.cluster.local:6379`

This keeps client changes minimal while HAProxy routes traffic to the current Redis primary.

## What is included

- `Dockerfile` for RHEL8/UBI8-based Redis image
- `conf/redis.conf`
- `conf/sentinel.conf`
- `conf/haproxy.cfg`
- `scripts/entrypoint.sh`
- Raw OpenShift/Kubernetes manifests in `k8s/`
- A Helm chart in `helm/redis-sentinel-openshift-proxy/`

## Important behavior

This is **single-writer Redis HA**, not Redis Cluster sharding.

- Writes go to the current primary
- Replicas copy the primary's dataset
- Replication is asynchronous, so brief lag is possible
- HAProxy does **not** make Redis multi-writer; it only gives apps a stable endpoint

## Build image

Put your internal Redis RPM in the project root and adjust the Dockerfile `COPY` line if needed.

Example:

```bash
docker build -t your-registry/redis-sentinel-rhel8:7.2 .
podman build -t your-registry/redis-sentinel-rhel8:7.2 .
```

Then push it to your internal registry.

## Deploy with raw manifests

1. Update image reference in `k8s/redis-statefulset.yaml` and `k8s/sentinel-statefulset.yaml`
2. Update `haproxy.cfg` backend hostnames if you rename services
3. Update storage class if needed in `k8s/redis-statefulset.yaml`
4. Apply manifests:

```bash
oc apply -f k8s/namespace.yaml
oc apply -f k8s/configmap.yaml
oc apply -f k8s/services.yaml
oc apply -f k8s/redis-statefulset.yaml
oc apply -f k8s/sentinel-statefulset.yaml
oc apply -f k8s/haproxy-deployment.yaml
oc apply -f k8s/validate-job.yaml
```

## Deploy with Helm

```bash
helm upgrade --install redis-sentinel helm/redis-sentinel-openshift-proxy \
  -n redis-sentinel --create-namespace \
  --set image.repository=your-registry/redis-sentinel-rhel8 \
  --set image.tag=7.2
```

## Validate

```bash
oc -n redis-sentinel get pods
oc -n redis-sentinel get svc
oc -n redis-sentinel logs statefulset/redis
oc -n redis-sentinel logs statefulset/sentinel
oc -n redis-sentinel logs deploy/redis-haproxy
```

Quick checks:

```bash
oc -n redis-sentinel run redis-cli --rm -it --restart=Never --image=redis:7.2 -- bash
redis-cli -h redis-proxy -p 6379 INFO replication
redis-cli -h sentinel -p 26379 SENTINEL get-master-addr-by-name mymaster
redis-cli -h redis-proxy -p 6379 SET xyz hello
redis-cli -h redis-proxy -p 6379 GET xyz
```

## Failover test

```bash
oc -n redis-sentinel delete pod redis-0
oc -n redis-sentinel logs statefulset/sentinel --tail=200
oc -n redis-sentinel logs deploy/redis-haproxy --tail=200
```

Then query again:

```bash
redis-cli -h sentinel -p 26379 SENTINEL get-master-addr-by-name mymaster
redis-cli -h redis-proxy -p 6379 INFO replication
```

## App examples

### Spring Boot

```yaml
spring:
  data:
    redis:
      host: redis-proxy.redis-sentinel.svc.cluster.local
      port: 6379
      timeout: 2s
```

### Python

```python
import redis

r = redis.Redis(
    host="redis-proxy.redis-sentinel.svc.cluster.local",
    port=6379,
    decode_responses=True,
    socket_timeout=2,
)

r.set("xyz", "hello")
print(r.get("xyz"))
```

## Notes for OpenShift

- Security context is kept compatible with restricted SCC-style environments
- Containers avoid fixed root execution at runtime
- Ensure your image registry and StorageClass are valid for your cluster
- If your RPM installs Redis binaries in a different path, adjust `entrypoint.sh`
