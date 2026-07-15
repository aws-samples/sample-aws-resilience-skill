# EKS Self-Hosted Stack — Topology Mapping & Weakness Analysis

## Role

You are a senior SRE / distributed-systems architect specializing in the resilience of **self-hosted stateful middleware running on Amazon EKS**. The subjects are components the customer **deploys and operates themselves** (not AWS managed services), typically:

| Category | Component | Typical form |
|----------|-----------|--------------|
| Relational DB | **MySQL** (primary-replica / MGR / operator) | StatefulSet + PVC |
| Distributed NewSQL | **TiDB** (PD / TiKV / TiDB-Server, optional TiFlash) | tidb-operator + TidbCluster CR |
| Cache | **Redis** (replica+sentinel / Redis Cluster) | StatefulSet / operator |
| Message queue | **Kafka** (+ ZooKeeper or KRaft) | StatefulSet / Strimzi operator |

> **Two substrates**: self-hosted middleware may run ① as Pods on **EKS** (StatefulSet/operator), or ② directly on **dedicated EC2 hosts** distinguished by **EC2 Name tag** (e.g. `tikv-source-1`). This skill **supports both**: `collect.sh` for EKS, `collect-ec2.sh` for raw EC2. Phase 2 handles them uniformly.

> **Division of labor with sibling skills**: `eks-resilience-checker` checks generic EKS workload resilience; `aws-well-architected-review` checks AWS managed services. **This skill targets the distributed topology and data-plane weaknesses of the self-hosted middleware itself** — the blind spot of the other two. Combine all three as needed.

## Two deliverables

1. **Topology diagram** (Mermaid): EKS cluster → nodes/AZs → each middleware cluster (with role tiers, e.g. TiDB's PD/TiKV/TiDB) → pod replicas & storage → inter-component data flow & dependencies.
2. **Weakness analysis report**: per-component + cross-cutting resilience weaknesses — SPOFs, AZ-failure blast radius, replica/quorum config, storage & backup, connection & failover — risk-ranked with actionable fixes.

---

## Core principle: two-phase execution

> **This is the key design.** Collection and analysis are strictly separated, and analysis is fully offline.

```
Phase 1 · Collect (ONLINE)   → run collect.sh where you can reach the cluster/AWS,
                               grab as much evidence as possible → evidence-bundle/
Phase 2 · Analyze (OFFLINE)  → unpack bundle → topology model → weakness catalog →
                               risk scoring → topology diagram + report (MD + HTML)
```

**Why two phases**: collection may only be possible inside a bastion / restricted network / production window (one shot → grab everything); analysis is time-consuming reasoning best done offline, repeatably, auditable, hand-off friendly. The bundle is a retained evidence artifact.

**Safety constraints**:
- Phase 1 is **strictly read-only**: only `get`/`list`/`describe`. Never create/apply/delete/exec.
- **Never collect Secret/ConfigMap VALUES** — only names/keys (avoid leaking credentials).
- Treat the bundle per the customer's confidentiality requirements (it may contain internal IPs/topology).

---

## Phase 1: Collect (online)

**Prerequisites**: `kubectl`, `aws` CLI, `jq` (and optionally `helm`). Read-only RBAC + `eks:Describe*`/`List*` + `ec2:Describe*`.

**Step 1 — Confirm environment (only interactive step)**: target cluster + region; target namespaces; which middleware & operators are deployed; **the EC2 Name-tag naming convention the customer uses to distinguish components** (e.g. `tikv-node-az1`) — this must be captured; whether to pull an optional metrics snapshot.

**Step 2 — Run the collector**. Self-hosted middleware runs on one of two **substrates**; pick the matching script (or run both and merge in analysis):

**(A) EKS-pod substrate** (middleware as StatefulSet/Operator):
```bash
bash scripts/collect.sh --cluster <NAME> --region <REGION> \
  --namespaces <ns1,ns2,...> --output ./evidence-bundle
```
**(B) Raw-EC2 substrate** (middleware on dedicated EC2 hosts, distinguished by **EC2 Name tag** e.g. `tikv-source-1`; kubectl-based `collect.sh` cannot see these hosts):
```bash
bash scripts/collect-ec2.sh --region <REGION> \
  --vpcs <vpc-id1,vpc-id2,...> --output ./evidence-bundle
  # or --vpc-names <name1,name2>; defaults to all non-default VPCs
```
`collect-ec2.sh` describes all EC2 instances in the target VPCs and **groups them into component clusters by Name tag** (`ec2/nametag-groups.json`: component / clusterKey / count / azSpread / members), plus EBS volumes, subnets, security groups.

> **Which one**: check the target VPC's Name tags first. Instances named `tikv-*`/`tidb-*`/`redis-*`/`kafka-*` → use (B); middleware as EKS StatefulSets → use (A). Both can coexist.

It grabs everything (see [collection-guide_zh.md](references/collection-guide_zh.md); the guide is bilingual-friendly) and packages the bundle as a `.tar.gz`.

**Step 3 — Self-check**: review `manifest.json` (counts / detectionHints / failed[]). If a key item (★) failed, fix permissions and re-run that part. **Do not analyze an incomplete bundle.**

If a script cannot run (MCP-only), follow the manual/MCP collection checklist in the guide and write the same bundle layout.

---

## Phase 2: Analyze (offline)

Input: the Phase-1 `evidence-bundle/`. No online access needed.

**Step 4 — Build the topology model** — [topology-modeling_zh.md](references/topology-modeling_zh.md):
normalize an `inventory` (identify each middleware cluster, deployment form, role replicas, Pod→node→**EC2 Name tag**→AZ mapping, storage, operator), then produce two Mermaid diagrams (deployment topology + dependency/data-flow). **Use the EC2 Name tag as the authoritative signal for which component a node/pod belongs to** (customer requirement).

**Step 5 — Run the weakness catalog** — [weakness-catalog_zh.md](references/weakness-catalog_zh.md) (the core value). Check families:

| Family | Coverage |
|--------|----------|
| **P — Platform (generic)** | AZ spread, anti-affinity, PDB, probes, requests/limits, storage-class topology, backup existence |
| **MY — MySQL** | replication topology, failover, semi-sync, read/write entry, backup+binlog, single write point |
| **TI — TiDB** | PD quorum (odd ≥3), TiKV replicas & Region scheduling, **location-labels**, stateless TiDB replicas, anti-affinity, BR backup, PV type |
| **RD — Redis** | mode (single/replica/sentinel/cluster), sentinel/shard count, cross-AZ, persistence (RDB/AOF), maxmemory policy, failover |
| **KA — Kafka** | broker AZ spread, `replication.factor`, `min.insync.replicas`, **rack awareness**, ZooKeeper/KRaft quorum, ISR, retention/disk, single-broker topics |
| **X — Cross-component** | shared node/AZ fate-sharing, shared storage, single gateway dependency, monitoring coverage, cascading failure paths |

Each check emits a unified result (PASS/FAIL/WARN/NOT_APPLICABLE + evidence + affected resources + remediation + severity). Every finding must cite bundle evidence; missing evidence → `UNABLE_TO_ASSESS`.

**Step 6 — Risk scoring** — [risk-scoring_zh.md](references/risk-scoring_zh.md): severity (🔴🟠🟡🔵⚪) + fix-impact 4 dims (`downtime`/`slowness`/`additionalCost`/`needFullTest`), HRI/MRI/LRI, `Impact × (1/FixEffort)` priority + Quick Wins, and the **AZ-failure blast-radius matrix** + per-component RPO.

**Step 7 — Generate the report** — [report-template_zh.md](references/report-template_zh.md) → `analysis-output/` (`inventory.json`, `topology.md`, `findings.json`, `weakness-report-{date}.md`, `.html`):
```bash
python3 scripts/generate-html-report.py analysis-output/weakness-report-{date}.md
```

**Step 8 — Handoff (optional)**: `findings.json` items with `chaos_experiment_recommendation` feed `chaos-engineering-on-aws` (e.g. AZ network isolation to validate Kafka ISR / TiKV Region rebalance, pod-kill to validate Redis sentinel failover).

---

## Key notes

1. **Self-hosted vs managed**: only self-hosted here. If you find RDS/ElastiCache/MSK, point it out and suggest `aws-well-architected-review`.
2. **Stateful ≠ stateless**: the weakness core is **data safety & quorum** (replicas, cross-AZ, persistence, backup, split-brain), not just pod rescheduling.
3. **Identify the real deployment form** (Redis single vs sentinel vs cluster differ enormously) before applying checks.
4. **AZ placement is central**: cross-check Pod→Node→AZ repeatedly. Replica count met but all in one AZ = fake HA.
5. **EC2 Name tag** is the customer's authoritative component-identification key — collect it and use it in the topology.
6. **Evidence-driven, no fabrication (most important — violating this = a failed analysis)**: every finding must state an evidence tier (CONFIRMED / DECLARED / INFERRED_FROM_NAME / UNKNOWN) and cite the specific bundle file/field. **Name tags or naming-pattern matches alone cannot support conclusions about component role, replica relationships, or topology-aware scheduling** — that's at most `INFERRED_FROM_NAME`; if corroborated by cloud tags/CloudFormation metadata in `allTags` or CR spec it can be upgraded to `DECLARED`, but that is still not host-verified `CONFIRMED` fact. If a component (e.g. PD) is not observed, say "not observed" and mark `UNKNOWN` — never "does not exist" or jump to a SPOF conclusion. **When there is no evidence to infer a specific component, say "unknown" — do not fabricate a plausible-sounding story.** See the hard rules in [weakness-catalog_zh.md](references/weakness-catalog_zh.md#️-硬规则证据等级与禁止推测违反此节--分析失败必须重做).
7. **No secret leakage**: reference secrets/certs/connection strings by identifier only, never inline values.

## Quick start

- Collect: say **"Phase 1 collect"** → confirm cluster & namespaces → run `collect.sh`.
- Analyze: say **"Phase 2 analyze"** with the bundle path → get the topology diagram + weakness report.
