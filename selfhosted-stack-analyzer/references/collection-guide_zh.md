# 阶段一 · 采集指南（Collection Guide）

> **范围**：本文件说明阶段一"尽可能抓全"要采集**什么**、**怎么采集**、以及 evidence-bundle 的**目录结构**。
> 首选运行 `scripts/collect.sh`；若环境无法运行脚本（MCP-only、受限 shell），按本文"手动 / MCP 采集清单"逐项落盘为相同结构。

---

## 采集原则

1. **一次抓全**：阶段一往往在受限网络/生产窗口内进行，机会有限。宁可多抓，不可漏抓。
2. **只读**：仅 `get` / `list` / `describe`。禁止任何写操作、禁止 `kubectl exec` 进容器。
3. **不落密文**：Secret 只记 `name/type/keys`；ConfigMap 只记 `keys`。**永远不导出其 value**。
   - 例外：中间件配置（如 `my.cnf`、`redis.conf`、Kafka `server.properties`、TiDB `config`）常放在 ConfigMap 里且**不含密码**——这些配置对分析至关重要。采集时可保留这类明确的**配置类** ConfigMap 的 value，但先人工确认其中无凭证；如不确定，只留 keys 并在分析时向用户单独索取脱敏配置。
4. **可复核**：每个采集项落成独立 JSON 文件，保留原始结构，分析阶段只读不改。

---

## evidence-bundle 目录结构

```
evidence-bundle/
└── <cluster>-<date>/
    ├── manifest.json                    # 采集清单 + 自检 + 检测提示
    ├── cluster/                         # 平台层
    │   ├── version.json                 # k8s 版本
    │   ├── nodes.json                   # 节点(含 AZ/instance-type/容量标签)  ★关键
    │   ├── namespaces.json
    │   ├── storageclasses.json          # 存储类(含 volumeBindingMode/allowedTopologies) ★
    │   ├── persistentvolumes.json       # PV(含 AZ 亲和 nodeAffinity)  ★
    │   ├── crds.json                     # 用于识别 Operator
    │   └── priorityclasses.json
    ├── aws/                             # AWS 层(可选)
    │   ├── caller-identity.json
    │   ├── eks-cluster.json             # endpoint/logging/version/vpc
    │   ├── eks-nodegroups.json
    │   ├── eks-addons.json
    │   ├── eks-fargate-profiles.json
    │   ├── ebs-volumes.json             # 持久卷底层 EBS(含 AZ/类型/大小/加密) ★
    │   ├── ec2-instances.json           # 节点 → AZ 交叉校验
    │   └── node-nametag-map.json         # ★★ EC2 Name tag → 节点身份映射(组件识别关键键)
    ├── k8s/                             # 工作负载层(目标 namespace)
    │   ├── pods.json                     # ★ Pod→节点映射、容器、探针、资源
    │   ├── statefulsets.json             # ★ 中间件主体，副本数/亲和/存储模板
    │   ├── deployments.json
    │   ├── daemonsets.json
    │   ├── replicasets.json
    │   ├── services.json                 # ★ headless/ClusterIP/NLB
    │   ├── endpoints.json                # ★ Service 实际后端
    │   ├── persistentvolumeclaims.json   # ★ 存储绑定
    │   ├── poddisruptionbudgets.json     # ★ PDB
    │   ├── horizontalpodautoscalers.json
    │   ├── configmaps.json               # 仅 keys(已脱敏)
    │   ├── secrets-index.json            # 仅 name/type/keys(无 value)
    │   ├── serviceaccounts.json
    │   └── networkpolicies.json
    ├── components/                      # 组件专属 CR(存在才有)
    │   ├── tidb-tidbclusters.json        # ★ TiDB: PD/TiKV/TiDB 副本、config、label
    │   ├── tidb-backups.json / backupschedules.json
    │   ├── kafka-kafkas.json             # ★ Strimzi: replicas、config、rack、storage
    │   ├── kafka-topics.json             # ★ 每 topic 的 RF / min.insync.replicas
    │   ├── redis-*.json                  # ★ Redis operator CR
    │   ├── mysql-*.json                  # ★ MySQL operator CR
    │   └── mon-servicemonitors.json / prometheusrules.json  # 监控覆盖
    ├── operators/
    │   ├── helm-releases.json
    │   └── all-deployments.json          # 找 operator 部署
    ├── events/
    │   └── events.json                   # 近期事件(OOMKilled/FailedScheduling/Evicted)
    └── metrics/                         # 可选(--metrics)
        ├── top-nodes.txt
        └── top-pods-<ns>.txt
```

★ = 薄弱点分析的关键输入，务必确保采集成功。

---

## 裸 EC2 底座的 bundle 结构（collect-ec2.sh）

当自建中间件跑在**专用 EC2 主机**上（非 EKS pod）、按 **Name tag** 区分组件时，用 `collect-ec2.sh` 采集，产出：

```
evidence-bundle/
└── ec2-<region>-<date>/
    ├── manifest.json                    # 计数 + componentSummary + natGatewayPerVpc + apiErrors
    ├── ec2/
    │   ├── instances.json               # ★ 归一化实例(nameTag/az/type/vols/sg/allTags)
    │   ├── nametag-groups.json          # ★★ 按 Name tag 归组的组件集群
    │   │                                #    (component/clusterKey/count/running/azSpread/instanceTypes/members)
    │   ├── volumes.json                 # ★ EBS(类型/大小/IOPS/吞吐/加密/AZ/挂载实例)
    │   ├── snapshots.json               # ★ EBS 快照(volumeId/startTime/加密) — 备份存在性直接证据
    │   ├── backup-coverage.json         # ★★ 每个卷是否有快照(volumesWithBackup/volumesWithoutBackup/latestSnapshotPerVolume)
    │   └── instances-raw.json / volumes-raw.json / snapshots-raw.json  # 原始 describe 输出
    ├── network/                          # ★★ 完整网络层证据(所有网络信息)
    │   ├── vpcs.json                     # VPC 名/CIDR
    │   ├── subnets.json                  # 子网 → AZ 映射
    │   ├── security-groups.json          # 安全组入站规则(proto/端口/CIDR/SG 引用)
    │   ├── nat-gateways.json             # ★ NAT Gateway(含 AZ、公网 IP) — 单 NAT/VPC 是出网 AZ 单点
    │   ├── internet-gateways.json        # IGW 及其挂载的 VPC
    │   ├── route-tables.json             # 路由表(每子网路由目标：NAT/IGW/peering/TGW/黑洞)
    │   ├── vpc-endpoints.json            # ★ VPC Endpoints(判断 SSM/S3 等服务的私有可达性)
    │   ├── eips.json                     # Elastic IP 及其关联的实例/网卡
    │   ├── enis.json                     # 网络接口(ENI)明细
    │   ├── nacls.json                    # 网络 ACL(子网级访问控制规则)
    │   ├── vpc-peering.json              # ★ VPC Peering 连接(跨 VPC 隐藏依赖)
    │   ├── tgw-attachments.json          # Transit Gateway VPC 挂载(跨 VPC/跨账户依赖)
    │   ├── load-balancers.json           # ★★ ALB/NLB(名称/类型/scheme/AZ 分布)
    │   ├── target-groups.json            # ★ Target Group(端口/协议/挂载的 LB)
    │   └── target-health.json            # ★ 每个 TG 的注册目标与健康状态 — 判断某实例是否真的挂在 LB 后面
    └── (无 secret/configmap — 主机内配置需另行只读采集)
```

**新增字段用途说明**：
- `nat-gateways.json` 的 `az` 字段来自 NAT 所在子网的 AZ（脚本内部做了 subnetId→az 的 join）。**一个 VPC 只有 1 个 NAT Gateway，是该 VPC 出网能力的 AZ 级单点**——该 AZ 故障后，所有依赖这个 NAT 出网的私有子网都无法访问外网/S3/其它区域服务，即使应用本身在其它 AZ 有副本。
- `load-balancers.json`/`target-groups.json`/`target-health.json` 三者联合使用，可以**确定性地**判断"某个自建中间件实例是否真的挂在负载均衡器后面"——如果 `target-health.json` 里找不到任何 tikv/tidb/redis/kafka 实例的 instanceId，说明这些组件目前没有 LB 前置（连接层检查 MY5/RD7 等的直接证据来源）。
- `vpc-peering.json`/`tgw-attachments.json` 用于发现"看起来独立的 VPC 实际有跨 VPC 网络连通"——这类隐藏依赖会扩大故障爆炸半径（一个 VPC 出问题可能通过 peering 影响另一个）。
- `vpc-endpoints.json` 里出现 `com.amazonaws.<region>.ssm`/`ssmmessages`/`ec2messages` 三个 Interface Endpoint，说明该 VPC 内的私有子网具备通过 SSM Session Manager 免密登录实例的**网络前提条件**。**但这只是网络路径存在，不代表实例一定可被 SSM 管理**——还需要实例本身安装了 SSM Agent、挂了正确的 IAM 角色、且处于 running 状态（`aws ssm describe-instance-information` 才是判断"当前是否被 SSM 管理"的直接证据，两者不可互相替代）。

**组件识别逻辑**（`nametag-groups.json`）：
- `clusterKey` = Name tag 去掉结尾 `-<数字>`（`tikv-source-1` → `tikv-source`）。
- `component` = 按 Name tag 关键字归类（tikv/pd/tidb/tiflash/mysql/redis/zookeeper/kafka/replication-cdc/monitoring/ops）。
- `azSpread` = 每 AZ 的成员数（AZ 分布分析的直接输入）。

> **裸 EC2 的采集盲区**：主机内配置（PD 拓扑、TiKV `location-labels`、副本因子、复制模式）、以及应用层的逻辑备份（如 TiDB BR、mysqldump，区别于本节新增的 EBS 快照——快照只能恢复卷，不保证数据库事务一致性）**无法通过 AWS 只读 API 获取**。这些项在分析时标 `UNKNOWN`/`UNABLE_TO_ASSESS`，并建议在 ops/bastion 主机上**只读**补采：`tiup cluster display`、`pd-ctl config show`/`member`/`store`、`redis-cli info`、`kafka-topics --describe` 等，落盘后再重跑分析。
>
> **`manifest.json.apiErrors`**：任一 `describe-*` 调用失败（权限/参数/限流）都会记录在这里，而不是静默写一个"看起来像确认为空"的占位符。分析前必须先检查这个字段——凡列在其中的资源类型，其对应的 `.json` 文件内容是空占位符而非真实的"该资源不存在"，必须标 `UNABLE_TO_ASSESS`。

---

## 手动 / MCP 采集清单

若无法运行 `collect.sh`，按类别逐项执行并落盘到上面对应路径。

### A. 平台层（cluster/）

```bash
kubectl version -o json                         > cluster/version.json
kubectl get nodes -o json                        > cluster/nodes.json
kubectl get namespaces -o json                   > cluster/namespaces.json
kubectl get storageclasses -o json               > cluster/storageclasses.json
kubectl get pv -o json                           > cluster/persistentvolumes.json
kubectl get crds -o json                         > cluster/crds.json
kubectl get priorityclasses -o json              > cluster/priorityclasses.json
```

> 节点的 AZ 来自标签 `topology.kubernetes.io/zone`（旧版 `failure-domain.beta.kubernetes.io/zone`）；实例类型来自 `node.kubernetes.io/instance-type`。这是所有 AZ 分布分析的基础，务必确认 nodes.json 里这些标签存在。

### B. AWS 层（aws/）— 只读 Describe

```bash
aws sts get-caller-identity --output json                                          > aws/caller-identity.json
aws eks describe-cluster --name $C --region $R --output json                        > aws/eks-cluster.json
aws eks list-nodegroups --cluster-name $C --region $R --output json                > aws/eks-nodegroups.json
aws eks list-addons --cluster-name $C --region $R --output json                    > aws/eks-addons.json
aws ec2 describe-volumes --region $R \
  --filters "Name=tag:kubernetes.io/cluster/$C,Values=owned,shared" --output json  > aws/ebs-volumes.json
aws ec2 describe-instances --region $R \
  --filters "Name=tag-key,Values=kubernetes.io/cluster/$C" --output json           > aws/ec2-instances.json
```

MCP 等价：`awslabs.aws-api-mcp-server`（EC2/EKS Describe）、`awslabs.eks-mcp-server`（集群与工作负载）。

> **★★ EC2 Name tag 是组件识别的关键键（本客户强制要求）**
> 本客户的自建组件**依靠 EC2 主机的 `Name` 标签来区分**（例如节点 Name tag 形如 `tikv-node-az1`、`kafka-broker-az2`、`redis-master-node`）。
> 因此 **必须完整采集每台节点 EC2 的 `Name` 标签**，`collect.sh` 会自动从 `ec2-instances.json` 派生出 `aws/node-nametag-map.json`：
>
> ```bash
> aws ec2 describe-instances --region $R \
>   --filters "Name=tag-key,Values=kubernetes.io/cluster/$C" --output json \
> | jq '{instances: [.Reservations[]?.Instances[]? | {
>     instanceId: .InstanceId,
>     nameTag: ((.Tags // []) | map(select(.Key=="Name")) | (.[0].Value // null)),
>     privateDnsName: .PrivateDnsName, privateIp: .PrivateIpAddress,
>     az: .Placement.AvailabilityZone, instanceType: .InstanceType,
>     allTags: ((.Tags // []) | map({(.Key): .Value}) | add) }]}' \
> > aws/node-nametag-map.json
> ```
>
> 若 `describe-instances` 权限受限拿不到全部实例，**务必**单独补采所有相关实例的 Name 标签——这是后续按 Name tag 识别"哪台机器跑哪个组件"的唯一依据，不可缺失。

### C. 工作负载层（k8s/）— 目标 namespace

对每个目标 namespace（或 `--all-namespaces` 后过滤系统 ns）导出：
`pods, statefulsets, deployments, daemonsets, replicasets, services, endpoints, persistentvolumeclaims, poddisruptionbudgets, horizontalpodautoscalers, serviceaccounts, networkpolicies`（均 `-o json`）。

**脱敏处理（强制）**：

```bash
# ConfigMap：只留 keys
kubectl get configmaps -n $NS -o json | jq '{items: [.items[] |
  {metadata: {name:.metadata.name, namespace:.metadata.namespace, labels:.metadata.labels},
   dataKeys: (.data // {} | keys)}]}' > k8s/configmaps.json

# Secret：只留 name/type/keys，绝不含 data
kubectl get secrets -n $NS -o json | jq '{items: [.items[] |
  {name:.metadata.name, namespace:.metadata.namespace, type:.type, keys:(.data // {} | keys)}]}' \
  > k8s/secrets-index.json
```

### D. 组件专属 CR（components/）

先看 `cluster/crds.json` 里有哪些 CRD，命中才导出：

| 中间件 | CRD | 导出为 |
|--------|-----|--------|
| TiDB | `tidbclusters.pingcap.com` | `components/tidb-tidbclusters.json` |
| TiDB 备份 | `backups.pingcap.com` / `backupschedules.pingcap.com` | `components/tidb-backups.json` 等 |
| Kafka(Strimzi) | `kafkas.kafka.strimzi.io` | `components/kafka-kafkas.json` |
| Kafka topic | `kafkatopics.kafka.strimzi.io` | `components/kafka-topics.json` |
| Redis | `redisfailovers.databases.spotahome.com` / opstree 系列 | `components/redis-*.json` |
| MySQL | `innodbclusters.mysql.oracle.com` / `mysqlclusters.moco.cybozu.com` / `perconaxtradbclusters.pxc.percona.com` | `components/mysql-*.json` |
| 监控 | `servicemonitors.monitoring.coreos.com` / `prometheusrules.monitoring.coreos.com` | `components/mon-*.json` |

> **无 Operator 的裸 StatefulSet 部署**：许多客户直接用 Helm chart / 原生 StatefulSet 跑 MySQL/Redis/Kafka，没有 CR。此时组件信息全在 `k8s/statefulsets.json` + `k8s/configmaps.json`（配置）+ `k8s/services.json` 里。分析阶段靠命名约定和 label 识别（见 topology-modeling）。

### E. 关键配置文件（强烈建议补采，需人工脱敏确认）

中间件的真实韧性参数往往在配置里，仅靠 K8s 对象看不全。请向客户额外索取（确认已脱敏）：

- **MySQL**：`my.cnf` 关键项 —— `server_id`、`log_bin`、`sync_binlog`、`rpl_semi_sync_*`、`gtid_mode`、复制拓扑（谁是主）。
- **TiDB**：`TidbCluster` CR 里 `pd.replicas`、`tikv.replicas`、`tikv.config` 的 `raftstore`、`config.replication.max-replicas`、`location-labels`。
- **Redis**：`redis.conf` —— `appendonly`、`save`、`maxmemory`、`maxmemory-policy`；哨兵 `quorum`；Cluster 分片数。
- **Kafka**：`server.properties` 或 Strimzi `.spec.kafka.config` —— `default.replication.factor`、`min.insync.replicas`、`offsets.topic.replication.factor`、`transaction.state.log.replication.factor`、`broker.rack`；以及**每个业务 topic** 的 RF/ISR。

---

## 采集自检（manifest.json）

脚本会生成 `manifest.json`，分析开始前先读它：

- `counts` —— nodes/pods/statefulsets/pvcs 数量，快速判断是否抓到东西。
- `detectionHints` —— 各中间件是否检测到（CRD 或 StatefulSet 命名命中）。用于确认覆盖面。
- `failed[]` —— 采集失败的项（权限不足 / 超时 / 资源不存在）。**关键项（★）失败必须补采后重跑**，不要用残缺 bundle 硬分析。

自检结论三选一：
1. **完整** → 进入阶段二。
2. **部分缺失但不影响目标组件** → 记录在报告"评估限制"章节，继续。
3. **关键项缺失** → 停止，向用户要权限或让其手动补采对应清单项。
