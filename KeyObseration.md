# CBDC System Key Observations and Improvement Areas

## Key Observations

- High latency outliers: APP.ReqCreateDevice avg ~5.4s (max ~85s), APP.ReqGetSign ~4.1s, PSO.RespListKeys.GetWalletKey ~3.9s, PSO.RespPay.PAY ~3.2s; these dominate the Top 10 by duration.
- Heavy, frequent calls with significant cost: APP.ReqGetAllTxn (426) avg ~3.2s, APP.ReqGetMeta (347) ~3.3s, APP.ReqGetLinkedAccounts (126) ~3.4s — large totals make these prime optimization targets.
- Capacity saturation: active-sessions often at 1000/1000 (APP) or 1500/1500 (PSO); pools likely maxed, adding queueing delay before work begins.
- Bursty load: peak TPS hits 151–612 while min/avg TPS are far lower; spikes likely cause head-of-line blocking and longer tails.
- Large in-transit queues: ratios spike (e.g., up to 2129), implying deep queues under load that contribute to long elapsed times.
- Payment path cost: PSO.RespPay.PAY (538) avg ~3.2s with max >15s; critical hot path for end‑to‑end latency.
- Key/metadata services expensive: PSO.RespListKeys.GetWalletKey and APP.ReqGetMeta are both numerous and slow; likely heavy crypto/IO or chatty downstreams.
- Reliability watch: some APP flows historically showed lower success% (e.g., ValAdd, Pay LOAD); even if current sample looks mostly successful, these endpoints warrant monitoring.

## Improvement Areas

- Capacity and concurrency: increase/rebalance thread and connection pools for APP/PSO; consider separate pools per endpoint class to isolate slow from fast.
- Queueing and backpressure: cap in‑transit depth, add adaptive backoff, tune batch sizes; prefer shorter queues with admission control to reduce tail latencies.
- Hot‑path optimization:
  - Payments (PSO.RespPay.PAY): profile DB locks, idempotency checks, and external calls; reduce synchronous hops; enable async persistence where safe.
  - Key ops (RespListKeys.GetWalletKey): cache/verifier‑side material where allowed, enable HSM/KMS acceleration, reuse sessions to avoid repeated handshakes.
  - Metadata/listing (GetMeta, GetAllTxn, GetLinkedAccounts): add pagination and server-side limits; cache static data (bank list, metadata); ensure indexes match filters/sorts.
- Tail latency reduction: enforce timeouts and hedged requests for slow downstreams; fast‑lane short read‑only calls; isolate long transactions to dedicated workers/queues.
- Burst smoothing: rate limit per channel and use token buckets to keep TPS closer to steady state; schedule non‑urgent jobs off‑peak.
- Database performance: EXPLAIN slow queries, add missing composite indexes, eliminate N+1 patterns; consider read replicas for heavy reads.
- Crypto/perf hygiene: ensure AES/GCM/SHA acceleration, HTTP/TLS connection reuse, and minimal per‑request key ops; pool HSM/KMS connections.
- Logging and telemetry: add per‑endpoint success%, P95/P99 latency, downstream call breakdowns, and pool utilization; use TXN_ID to stitch traces.
- Reliability hardening: for endpoints with lower success% under load, add circuit breakers, retries with jitter, and idempotent semantics (especially payments).
- Operational levers: scale out stateless tiers; separate APP and PSO worker pools; only raise pool ceilings alongside proper backpressure to avoid runaway queues.

