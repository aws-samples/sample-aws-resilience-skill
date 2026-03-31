# AWS Common Service Risk Reference Manual

This document compiles resilience risk points for commonly used AWS services, serving as a reference during resilience assessments. When assessing, combine these with the customer's actual environment to identify whether these risks exist and provide targeted improvement recommendations.

---

## 1. Storage Risks

### 1.1 EBS (Elastic Block Store)

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Storage-Risk-1 | EBS gp3 I/O latency spikes | gp3 I/O latency sometimes rises above 10ms, potentially lasting minutes to tens of minutes, affecting application performance | Upgrade to io2 for I/O latency-sensitive applications (2 orders of magnitude more consistent than gp3); migrate self-managed MySQL to Aurora (distributed storage, not EBS); build application-layer HA to switch to standby node when latency reaches threshold |
| Storage-Risk-2 | EBS Volume corruption/loss | Volume corruption leads to unrecoverable data loss | For RPO=0 workloads, configure multi-replica at application layer distributed across AZs with multi-replica write confirmation; use DLM for periodic volume backups; use AWS Backup for periodic EBS backups |
| Storage-Risk-3 | Snapshot-created EBS Volume initialization performance | Volumes created from snapshots have high read/write latency (tens of ms) before full initialization | Enable FSR (Fast Snapshot Restore); use FIO sequential reads to trigger proactive initialization |
| Storage-Risk-4 | Lack of EBS I/O fault simulation tools | No methods/tools to simulate EBS Volume I/O latency spikes/stops | Use AWS FIS to inject I/O pause on EBS Volumes (seconds to hours), verify if upper-layer applications can correctly failover |
| Storage-Risk-5 | EBS Volume performance not meeting preset targets | Volume performance (IOPS/throughput) doesn't meet targets when application workload increases | EC2 instances have I/O performance limits; when cumulative multi-volume performance reaches the limit, upgrade EC2 instance type; monitor ec2_instance_ebs_performance_exceeded_iops metric |

### 1.2 S3

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Storage-Risk-6 | S3 objects deleted or overwritten without recovery | Users cannot recover original data when objects are deleted or overwritten | Enable S3 Versioning; consider enabling Object Lock to prevent old version deletion |
| Storage-Risk-9 | S3 high-concurrency 503 errors | 503 errors during high-concurrency reads/writes | S3 has 3500 PUT/5500 GET limits per prefix; distribute requests across different prefixes; add hash strings or attributes to prefixes; add retry logic in code |

### 1.3 EFS

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Storage-Risk-7 | EFS billing spikes | Elastic Throughput mode charges by traffic, generating high costs during extended peak periods | Switch to Provisioned Throughput mode when peak periods exceed 5% of the time |

### 1.4 FSx

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Storage-Risk-8 | FSx periodic performance degradation | I/O affected during maintenance windows (software upgrades, security patches) | Choose Multi-region mode to reduce impact (<1 min vs Single-region minutes to 30 min); schedule maintenance windows during business off-peak hours |

### 1.5 DataSync

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Storage-Risk-10 | DataSync generates high S3 request costs | Full scan of source and destination buckets on every job start | Reduce DataSync job frequency; use S3 Replication for bucket synchronization instead |

---

## 2. Database Risks

### 2.1 Architecture and High Availability

| Risk ID | Applicable Service | Risk Point | Root Cause | Improvement Recommendation |
|---------|-------------------|-----------|-----------|---------------------------|
| DB-Risk-1 | RDS/Aurora/ElastiCache/DocumentDB | Not using Multi-AZ HA architecture | Cannot handle primary node/single AZ failures | RDS production should use Multi-AZ Instance/Cluster (SLA increases from 99.5% to 99.95%); Multi-AZ Cluster: most failovers <35s; Aurora/ElastiCache/DocumentDB: create at least one cross-AZ replica |
| DB-Risk-2 | RDS/Aurora/ElastiCache/MemoryDB/DocumentDB/DynamoDB | No cross-region architecture | Has cross-region DR requirements but not configured | RDS: create cross-region read replicas; Aurora: use Global Database (replication lag <1s); ElastiCache: use Global Datastore; MemoryDB: use Multi-Region (SLA 99.999%); DynamoDB: use Global Table (supports multi-write) |

### 2.2 Performance and Configuration

| Risk ID | Applicable Service | Risk Point | Root Cause | Improvement Recommendation |
|---------|-------------------|-----------|-----------|---------------------------|
| DB-Risk-3 | RDS | Using T-series instances in production | T-series use a credit system; performance degrades when credits are exhausted | Use M/R series for production; R series recommended for high-concurrency (CPU:memory=1:8); use r8g/r7g/r6g Graviton for cost efficiency |
| DB-Risk-4 | RDS | Inappropriate storage type causing latency issues | Latency-sensitive workloads using io1/gp3 | Use io2 storage (supports online storage type conversion); or choose Aurora for lower latency; for replication lag sensitivity, use Aurora (redo-based physical replication) |
| DB-Risk-5 | Aurora/RDS | Version selection issues | Stability-first but chose non-LTS version requiring annual upgrades | LTS versions have at least 3-year lifecycle; Aurora LTS version is 3.04 (as of 2025/02); RDS users can migrate to Aurora LTS |

### 2.3 Application and Operations

| Risk ID | Applicable Service | Risk Point | Root Cause | Improvement Recommendation |
|---------|-------------------|-----------|-----------|---------------------------|
| DB-Risk-6 | RDS/Aurora | Application not tested for failure recovery | Cannot recover quickly during production issues | Conduct failover recovery testing in test environments; Aurora has more granular fault injection test scenarios |
| DB-Risk-7 | Database Client | Local DNS cache configured on application side | Client cannot detect new nodes promptly during failover | Disable local DNS cache (note Java JVM default DNS cache); use AWS Driver/RDS Proxy for faster detection; configure client topology refresh for ElastiCache cluster mode |
| DB-Risk-8 | Database Application | Application not using connection pooling | Excessive connections or large bursts of new connections impact performance | Enable driver-side connection pooling with proper timeout/reconnect strategy; use RDS Proxy if driver doesn't support connection pooling |
| DB-Risk-9 | Database | Slow query logging not enabled or not regularly optimized | Database performance degradation or avalanche | Enable slow query logging for regular analysis and optimization; enable Performance Insight to monitor Top SQL; control single table data volume; simulate data volume for load testing before go-live |
| DB-Risk-10 | Database | Not subscribed to resource alerts | Cannot scale or optimize promptly as business grows | Subscribe to core monitoring metrics (CPU/memory/latency); enable Performance Insight to monitor Database Load and AAS; use Serverless auto-scaling for insufficient ops capacity |
| DB-Risk-11 | Database | No proper storage space planning | Disk/memory data fills up | Subscribe to storage metrics; enable RDS auto-expansion for disk; configure data eviction policies and TTL for ElastiCache; use cluster mode + AutoScaling/Serverless for large capacity; Aurora >128TB can use Limitless Database/DSQL |
| DB-Risk-12 | Database | Maintenance operations during peak hours | Forced version upgrades cause unexpected interruptions | Proactively monitor version lifecycle notifications; follow upgrade best practices (preparation/testing/plan design/rollback); disable minor version auto-upgrade; schedule during off-peak hours; use blue-green deployment to minimize downtime |
| DB-Risk-13 | Database | No proper data recovery plan | Data accidentally deleted/lost without recovery | RDS/Aurora/DocumentDB: use PITR to restore to any point in time; Aurora: enable Backtrack for in-cluster recovery; AWS Backup for cross-region backup; MemoryDB provides RPO=0 protection for AZ failures |
| DB-Risk-14 | Database | No cost optimization | Costs exceed expectations | Use Graviton series; use RI; consider Serverless for peak/valley workloads; Aurora/DocumentDB: consider IO Optimized when IO costs exceed 25%; ElastiCache: migrate to Valkey to save 20%-33%; consider data tiering when hot data is <20% |

---

## 3. Container Risks (EKS)

### 3.1 Cluster and Infrastructure

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EKS-Risk-1 | EKS cluster region failure | Region failure causes service outage | Deploy disaster recovery cluster in another region, shift traffic via Route 53 |
| EKS-Risk-2 | Worker nodes not deployed across multiple AZs | Single AZ failure causes service outage | Use multi-node groups or cross-AZ node groups; apply Pod Topology Spread Constraints; enable EKS Zonal Shift; regular chaos engineering testing |
| EKS-Risk-3 | AZ-specific instance type capacity insufficient | Insufficient capacity for special instance types like GPU prevents scaling | Set up cross-AZ node groups; leverage Karpenter multi-instance type selection; reserve some compute resources |
| EKS-Risk-4 | Subnet IP address exhaustion | Cannot expand nodes or Pods | Create larger subnets or create new node groups in larger subnets; use Custom Networking to separate Pod and node subnets |
| EKS-Risk-5 | Control plane upgrade causes unavailability | API Server or cluster components become unavailable | Check compatibility and audit logs before updates; regularly update cluster component versions; use blue-green upgrade strategy |
| EKS-Risk-6 | Control plane overloaded | Too many nodes or API requests cause response delays | Monitor API Server metrics and optimize request patterns (pagination/reduce Watch); open support case for control plane scaling before peaks; regularly update cluster version |

### 3.2 Cluster Components

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EKS-Risk-7 | CoreDNS service failure | CoreDNS issues or exceeding DNS PPS limits cause DNS resolution failures | Deploy CoreDNS with at least 2 replicas across AZs; use EKS Managed Addon for auto-scaling; use Node-Local DNS; monitor CoreDNS metrics |
| EKS-Risk-8 | Other cluster component failures (CSI, etc.) | Dependency component failures prevent Pod scheduling | Configure Liveness Probes for auto-restart; monitor component logs and cluster events |

### 3.3 Nodes and Instances

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EKS-Risk-9 | EC2 instance failures without auto-recovery | Instance stop/restart/network maintenance causes unavailability | Use managed node groups or Karpenter for auto-detection and repair; use Descheduler for rapid Pod eviction; use Node Monitoring Agent or EKS Auto Mode |
| EKS-Risk-10 | Insufficient node resource reservation | System components become unresponsive | Continuously monitor node resources; use right-sizing tools to configure Pod Request/Limit; configure kubelet with increased resource reservations |
| EKS-Risk-11 | Incorrect sysctl parameter configuration | Node performance degradation or instability | Avoid modifying OS kernel parameters whenever possible |
| EKS-Risk-12 | High Spot instance interruption rate | Improper instance type configuration | Use Karpenter to expand instance selection range and multi-AZ; use On-Demand instances or Capacity Block for baseline workloads |

### 3.4 Pod and Workloads

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EKS-Risk-13 | Pod single point of failure | All Pod replicas on same node | Configure multiple replicas; configure Pod Anti-Affinity or Topology Spread Constraints |
| EKS-Risk-14 | Persistent storage single point of failure | EBS single point of failure causes data unavailability | Use EFS shared storage whenever possible; configure volumeClaimTemplates for StatefulSet and sync data at application layer; regular snapshot backups |
| EKS-Risk-15 | Pod cannot handle rescheduling | Resource or Spot interruptions cause Pod rescheduling failures | Evaluate if application is suitable for Kubernetes; enable PreStop Lifecycle Hook for graceful termination |
| EKS-Risk-16 | Pod lacks health check mechanisms | Cannot auto-recover during failures or rolling updates | Configure Liveness/Readiness probes; set PDB to ensure minimum available replicas; enable PreStop Hook for graceful termination |
| EKS-Risk-17 | Unstable inter-Pod networking | Request failures or high latency | Configure retry mechanisms in applications (ensure idempotency); use service mesh for unified routing and retry |
| EKS-Risk-18 | Improper Pod resource configuration | Scheduler cannot work properly, causing resource waste/contention | Use right-sizing tools like krr+Prometheus to configure Requests; use HPA+Karpenter for dynamic resource adjustment |

---

## 4. Compute Risks (EC2)

### 4.1 Observability and Failure Detection

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EC2-Risk-1 | Lack of EC2 underlying maintenance awareness | Cannot detect stop/restart/network maintenance events | Use EC2 Health Dashboard; build automation scripts with EC2 Health API; AWS Health Event + EventBridge for event-driven observability; deploy AWS Health Aware solution |
| EC2-Risk-2 | Lack of EC2 underlying failure detection | Cannot detect underlying failures | Use CloudWatch to monitor Status Check Failed (system) metrics and specify triggered actions |

### 4.2 High Availability and Capacity

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EC2-Risk-3 | Lack of EC2 single point of failure handling | Single point failures cannot auto-recover | Prefer EC2 Auto Scaling management (built-in health checks and auto-replacement); enable EC2 Auto Recovery for non-ASG instances; enable application-layer HA (e.g., Redis/Kafka multi-replica) |
| EC2-Risk-4 | Lack of EC2 operational testing methods | Cannot verify HA/DR plans | Use AWS FIS for fault injection and simulation testing |
| EC2-Risk-5 | Lack of effective capacity planning | Stable critical workloads lack capacity reservations | Use ODCR (On-Demand Capacity Reservation); use Future-dated Capacity Reservation; FOOB process as supplement |
| EC2-Risk-6 | ICE errors during sudden capacity demand | Insufficient Capacity Error | Increase flexibility (Instance -> Geography -> Time); set up retry and exponential backoff; scale early, small steps, high frequency |

### 4.3 Spot Instances

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EC2-Risk-7 | Excessive Spot interruption rate | Insufficient flexibility in instance type/AZ selection | Increase flexibility (instance family/generation/size/AZ); use capacity-optimized/price-capacity-optimized allocation strategy; use Spot Placement Score/Spot Instance Advisor/Attribute-based Instance Selection |
| EC2-Risk-8 | Application unable to handle Spot interruptions efficiently | Application not designed for interruptions | Evaluate if application suits Spot (async/fault-tolerant/time-shiftable); set up Checkpoint/State Management; use CloudWatch Events to listen for interruption notices; use FIS to simulate Spot interruptions |

### 4.4 Cost Optimization

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| EC2-Risk-9 | Inappropriate instance selection increasing costs | Oversized or undersized instances | Use Compute Optimizer/Cost Explorer for recommendations; use T-series for burstable workloads; migrate to latest generation instances; adopt Graviton for better price-performance; x86 can migrate from Intel to AMD |
| EC2-Risk-10 | Improper operations increasing costs | Stopped instances not terminated, etc. | Use console or Trusted Advisor to check stopped instances; CloudWatch to monitor Status Check Failed to terminate damaged instances; Instance Scheduler for auto start/stop |
| EC2-Risk-11 | Not using optimal purchasing options | Not using SP/RI/Spot | Purchase Savings Plans for stable workloads; use Spot for flexible stateless workloads |
| EC2-Risk-12 | Capacity configured beyond business needs | Resource waste | Use EC2 Auto Scaling with scaling policies to match business demand |

---

## 5. Network Risks

### 5.1 Direct Connect

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Network-Risk-1 | Direct Connect single point of failure | Single connection without backup/insufficient backup bandwidth/same AWS router/same PoP | Backup bandwidth matches primary; choose different DX locations; use VPN as backup |
| Network-Risk-2 | Direct Connect gray failure prevents timely failover | Lack of end-to-end visibility, cannot identify connection quality issues | Use Network Synthetic Monitor for latency and packet loss monitoring; use NHI for rapid root cause identification; configure CloudWatch alarms for auto/manual failover; regular failover drills |

### 5.2 VPN & SDWAN

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Network-Risk-3 | Site-to-site VPN single point of failure | No redundant tunnels configured | Use BGP with both tunnels simultaneously (load-balanced mode); create 2 VPN connections (avoid simultaneous maintenance); use multiple on-premises VPN routers |
| Network-Risk-4 | SDWAN brief disconnections | TGW underlying maintenance causes BGP session interruption | Establish 2 BGP peering sessions per connect peer (4 total) |

### 5.3 NAT Gateway

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Network-Risk-5 | NAT Gateway outbound connection failures | Maximum 55,000 concurrent connections per destination; new connections fail when exceeded | Use NAT Gateway Multiple IP (up to 8 IPs, increasing concurrency to 440,000) |

### 5.4 Load Balancing

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Network-Risk-6 | ALB cannot handle traffic spikes | Traffic spikes exceed ALB scaling capacity | Use Load Balancer Capacity Unit Reservation (pre-warming) to reserve minimum capacity in advance |
| Network-Risk-7 | ALB IP addresses cannot be fixed | Underlying EC2 scaling causes IP changes | Clients must use DNS to connect to ALB (follow TTL=1 minute); if fixed IP is required, use ALB-type Target Group for NLB |
| Network-Risk-8 | NLB long connection timeouts | NLB TCP timeout defaults to 350 seconds | Configure NLB TCP idle timeout to an appropriate value between 60-6000 seconds |
| Network-Risk-9 | 50% packet loss with GWLB + third-party firewall | Single-AZ firewall deployment or firewall failure | Enable GWLB cross-zone load balancing; enable appliance mode when using TGW for east-west inspection |

### 5.5 Network Monitoring

| Risk ID | Risk Point | Root Cause | Improvement Recommendation |
|---------|-----------|-----------|---------------------------|
| Network-Risk-10 | Application performance degradation and TCP connection timeouts | Cannot quickly determine if issue is network or application | Use Network Flow Monitor NHI for rapid differentiation; monitor Retransmissions and Timeouts metrics; set up CloudWatch alarms |

---

## 6. Assessment Checklist

During resilience assessments, verify the following checklist items for each service type:

### Storage Checklist
- [ ] Is EBS storage type matched to business I/O requirements (gp3 vs io2)?
- [ ] Do EBS Volumes have periodic backup policies (DLM/AWS Backup)?
- [ ] Is FSR enabled for Volumes restored from snapshots?
- [ ] Have EBS I/O fault simulation tests been conducted (FIS)?
- [ ] Does EC2 instance I/O performance ceiling meet multi-volume requirements?
- [ ] Is S3 Versioning enabled?
- [ ] Is S3 prefix distribution configured for high-concurrency scenarios?
- [ ] Does EFS throughput mode match usage patterns?
- [ ] Is FSx maintenance window set during business off-peak hours?

### Database Checklist
- [ ] Is production using Multi-AZ architecture?
- [ ] Is there a cross-region DR plan (if needed)?
- [ ] Does production avoid T-series instances?
- [ ] Does storage type meet latency requirements?
- [ ] Is the appropriate database version selected (LTS vs non-LTS)?
- [ ] Have failover recovery tests been conducted?
- [ ] Is local DNS cache disabled on clients?
- [ ] Is the application using connection pooling?
- [ ] Is slow query logging and Performance Insight enabled?
- [ ] Are core monitoring alerts subscribed?
- [ ] Is there auto-expansion or alerting for storage space?
- [ ] Are maintenance operations scheduled during off-peak hours?
- [ ] Is there a data recovery plan (PITR/Backtrack/cross-region backup)?
- [ ] Have costs been evaluated for optimization?

### EKS Checklist
- [ ] Is there a cross-region disaster recovery cluster?
- [ ] Are worker nodes deployed across multiple AZs?
- [ ] Are multiple instance types configured for capacity insufficiency?
- [ ] Are subnet IP addresses sufficient?
- [ ] Is there a compatibility verification process for control plane upgrades?
- [ ] Is there load monitoring for the control plane?
- [ ] Is CoreDNS deployed with multiple replicas across AZs?
- [ ] Are cluster components configured with health checks?
- [ ] Can node failures auto-recover (managed node groups/Karpenter)?
- [ ] Are node resource reservations sufficient?
- [ ] Are Spot instances configured with multiple instance types and AZs?
- [ ] Are Pods configured with multiple replicas and anti-affinity?
- [ ] Is there a backup strategy for persistent storage?
- [ ] Are Pods configured with Liveness/Readiness probes?
- [ ] Are Pods configured with PDB and graceful termination?
- [ ] Are Pod resource Request/Limit properly set?

### EC2 Checklist
- [ ] Is there awareness of EC2 underlying maintenance events?
- [ ] Is there awareness of EC2 underlying failures?
- [ ] Is Auto Scaling or Auto Recovery used for single point of failure handling?
- [ ] Have FIS operational tests been conducted?
- [ ] Do stable workloads have capacity reservations (ODCR)?
- [ ] Is there a strategy for handling ICE errors?
- [ ] Are Spot instances configured with flexible instance selection?
- [ ] Can the application efficiently handle Spot interruptions?
- [ ] Has instance selection been optimized?
- [ ] Is there an auto start/stop strategy to avoid waste?
- [ ] Are optimal purchasing options selected (SP/RI/Spot)?

### Network Checklist
- [ ] Does Direct Connect have redundancy (different DX locations)?
- [ ] Is there gray failure detection for Direct Connect?
- [ ] Are VPN redundant tunnels configured?
- [ ] Are NAT Gateways deployed across AZs?
- [ ] Do NAT Gateway concurrent connections meet requirements?
- [ ] Is there a pre-warming strategy for ALB traffic spikes?
- [ ] Is NLB TCP timeout properly configured?
- [ ] Is GWLB cross-zone load balancing enabled?
- [ ] Is there network performance monitoring (Network Flow Monitor)?
