# tastebase

Postgres + pgvector for [tastebase](https://github.com/mia-cx/tastebase): an
embedding database of music — CLAP audio embeddings and lyrics embeddings,
one vector per audio window. CNPG `Cluster` `tastebase-db`, two instances on
`workloads/critical` nodes, 50 GiB each on single-replica Longhorn
(`longhorn-single`): CNPG already replicates between its instances.

## LAN endpoint

The ingest worker on Athena (10.0.3.2) connects over the LAN. CNPG's
`managed.services.additional` creates a `LoadBalancer` Service
`tastebase-db-lan` on the read-write endpoint, pinned by kube-vip:

```txt
10.0.128.6:5432
```

## Secret

CNPG writes the `tastebase` owner's credentials to Secret `tastebase-db-app`
in namespace `tastebase`. Read the connection URI, then swap the in-cluster
host for the LAN IP:

```bash
kubectl get secret -n tastebase tastebase-db-app \
  -o jsonpath='{.data.uri}' | base64 -d
# postgresql://tastebase:<password>@tastebase-db-rw.tastebase:5432/tastebase
# -> postgresql://tastebase:<password>@10.0.128.6:5432/tastebase
```
