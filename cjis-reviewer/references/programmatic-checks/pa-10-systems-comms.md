# PA 10 — Systems and Communications Protection — Programmatic Checks

> Execute in order. Read-only AWS CLI. Severity per [`../severity-classification.md`](../severity-classification.md).

CJIS PA 10 (Section 5.10) — encrypt CJI in transit (FIPS 140-2/3, TLS 1.2+), boundary protection, partition CJI from non-CJI systems.

---

## PA10-01: FIPS endpoints in use (GovCloud default, commercial opt-in)

This isn't cleanly queryable from CLI — it's a question of whether the environment *uses* FIPS endpoints. Probe indicators:

```bash
# Partition check — GovCloud defaults to FIPS
aws sts get-caller-identity --query 'Arn' --output text | grep -q 'aws-us-gov' && echo "GovCloud (FIPS default)" || echo "Commercial (FIPS opt-in)"

# Check for VPC endpoints using FIPS-specific service names
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].ServiceName' --output text | tr '\t' '\n' | grep -i fips || echo "No FIPS endpoints in VPC endpoint list"
```

| Result | Severity | Finding |
|---|---|---|
| Commercial partition, no `AWS_USE_FIPS_ENDPOINT` evidence, CJI workload | AUDIT BLOCKER | Commercial AWS without FIPS endpoints — CJIS requires FIPS 140-2 validated TLS |
| GovCloud | INFO | GovCloud partition — FIPS endpoints by default ✅ |
| Commercial with FIPS explicitly configured | INFO | FIPS endpoints in use ✅ |

Questionnaire follow-up: "Is `AWS_USE_FIPS_ENDPOINT=true` set in your application runtime config?" — can't verify from API.

---

## PA10-02: No internet gateway on CJI VPC(s)

Ask the user to identify the CJI VPC(s). For each:

```bash
aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values={vpc_id} --query 'InternetGateways[].InternetGatewayId' --output text
```

| Result | Severity | Finding |
|---|---|---|
| IGW attached to CJI VPC | AUDIT BLOCKER | CJI VPC `{id}` has internet gateway — direct internet exposure for CJI workloads |
| No IGW | INFO | CJI VPC has no direct internet path ✅ |

Note: A NAT Gateway for outbound-only patching is acceptable, but requires the user to confirm it's not also routing inbound. NAT GW check is a follow-up:

```bash
aws ec2 describe-nat-gateways --filter Name=vpc-id,Values={vpc_id} --query 'NatGateways[].NatGatewayId' --output text
```

NAT Gateway present → GAP: "Confirm CJI traffic doesn't egress to internet via NAT."

---

## PA10-03: Security groups with 0.0.0.0/0 ingress on sensitive ports

```bash
aws ec2 describe-security-groups --filters Name=ip-permission.cidr,Values=0.0.0.0/0 --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Rules:IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]].{Proto:IpProtocol,FromPort:FromPort,ToPort:ToPort}}' --output json
```

Port classification:
- **Critical**: 22 (SSH), 3389 (RDP), 3306 (MySQL), 5432 (Postgres), 1433 (MSSQL), 27017 (Mongo), 6379 (Redis), 9200 (ES), all-ports (-1)
- **Web**: 80, 443 — usually intentional but verify for CJI workloads
- **Other**: everything else — flag for review

| Result | Severity | Finding |
|---|---|---|
| 0.0.0.0/0 to any critical port | AUDIT BLOCKER | Security Group `{id}` allows {port} from internet |
| 0.0.0.0/0 to web ports on a CJI app | FINDING RISK | Confirm WAF + authentication in front (manual check) |
| 0.0.0.0/0 to other ports | FINDING RISK | Review unrestricted ingress on SG `{id}` |
| No unrestricted public ingress | INFO | SGs have no unrestricted critical-port ingress ✅ |

---

## PA10-04: Security groups with 0.0.0.0/0 egress (optional tightening)

```bash
aws ec2 describe-security-groups --query 'SecurityGroups[?IpPermissionsEgress[?IpRanges[?CidrIp==`0.0.0.0/0`]]].{Id:GroupId,Name:GroupName}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| SGs with unrestricted egress in CJI VPC | GAP | Egress not restricted — consider tightening to known AWS endpoints or VPC endpoints |
| All egress restricted | INFO | Egress policies tight ✅ |

This is a GAP not a finding because CJIS doesn't explicitly require egress restriction, but it's defense-in-depth.

---

## PA10-05: VPC endpoints used for AWS services (PrivateLink)

```bash
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,Vpc:VpcId,Type:VpcEndpointType}' --output json
```

CJIS-valuable endpoints to check for: `s3`, `kms`, `logs`, `monitoring`, `ec2`, `ssm`, `ssmmessages`, `ec2messages`, `sts`, `secretsmanager`.

| Result | Severity | Finding |
|---|---|---|
| CJI VPC with no endpoints for the CJIS-valuable list | GAP | No VPC endpoints in CJI VPC — AWS API traffic traverses internet |
| Partial coverage | GAP | Consider adding {missing_services} endpoints |
| Full coverage | INFO | VPC endpoints configured for AWS service access ✅ |

---

## PA10-06: Load balancers enforce TLS 1.2+

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text | tr '\t' '\n' | while read lb; do
  aws elbv2 describe-listeners --load-balancer-arn "$lb" --query 'Listeners[?Protocol==`HTTPS` || Protocol==`TLS`].{Port:Port,SslPolicy:SslPolicy}' --output json
done
```

| Result | Severity | Finding |
|---|---|---|
| Listener with SSL policy containing `TLS-1-0` or `TLS-1-1` or `2015-05` / `2016-08` | FINDING RISK | Load balancer allows TLS below 1.2 |
| Listener using `ELBSecurityPolicy-FS-*` or `ELBSecurityPolicy-TLS13-*` | INFO | Modern TLS policy ✅ |
| No HTTPS listeners | NOT_APPLICABLE (or FINDING RISK if plain HTTP on CJI app) | — |

Non-HTTPS listeners on CJI apps is an AUDIT BLOCKER — call that out separately:
```bash
aws elbv2 describe-listeners --load-balancer-arn {arn} --query 'Listeners[?Protocol==`HTTP`]' --output json
```

---

## PA10-07: CloudFront distributions use TLS 1.2+ and HTTPS-only viewer policy

```bash
aws cloudfront list-distributions --query 'DistributionList.Items[].{Id:Id,Domain:DomainName,ViewerCertificate:ViewerCertificate,DefaultBehavior:DefaultCacheBehavior.ViewerProtocolPolicy}' --output json
```

| Result | Severity | Finding |
|---|---|---|
| `ViewerProtocolPolicy: allow-all` on CJI distribution | AUDIT BLOCKER | CloudFront dist `{id}` allows unencrypted HTTP |
| `MinimumProtocolVersion` below `TLSv1.2_2021` | FINDING RISK | Weak TLS minimum on CloudFront `{id}` |
| HTTPS-only, TLS 1.2+ | INFO | CloudFront enforces modern TLS ✅ |
| No distributions | NOT_APPLICABLE | — |

---

## PA10-08: Site-to-Site VPN using FIPS-compliant cipher

```bash
aws ec2 describe-vpn-connections --query 'VpnConnections[].{Id:VpnConnectionId,State:State,Options:Options.TunnelOptions[].{Phase1:Phase1EncryptionAlgorithms[].Value,Phase2:Phase2EncryptionAlgorithms[].Value,IKE:IkeVersions[].Value}}' --output json
```

CJIS-acceptable: AES-256 or AES-256-GCM-16 with SHA-256+, IKEv2.

| Result | Severity | Finding |
|---|---|---|
| Tunnel with `AES128` only or `SHA1` | FINDING RISK | VPN tunnel on `{id}` uses weak cipher; restrict to AES-256/SHA-256 |
| IKEv1 only | FINDING RISK | VPN tunnel on `{id}` allows IKEv1; prefer IKEv2 |
| AES-256 + SHA-256+ + IKEv2 | INFO | VPN cipher CJIS-compliant ✅ |
| No VPN connections | NOT_APPLICABLE | — |

---

## PA10-09: CJI workload not in default VPC

```bash
aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[].VpcId' --output text
# Then check whether the user's CJI instances are in that VPC:
aws ec2 describe-instances --filters Name=vpc-id,Values={default_vpc} --query 'Reservations[].Instances[].InstanceId' --output text
```

| Result | Severity | Finding |
|---|---|---|
| Instances in default VPC in a CJI-workload account | FINDING RISK | {count} instances in default VPC — CJI should be in a dedicated VPC |
| No instances in default VPC | INFO | No CJI workload in default VPC ✅ |

---

## Summary

| Check | ID | Key question |
|---|---|---|
| FIPS endpoints | PA10-01 | Is TLS FIPS-validated? |
| No IGW on CJI VPC | PA10-02 | Is CJI VPC internet-isolated? |
| SG ingress | PA10-03 | Are sensitive ports closed to internet? |
| SG egress | PA10-04 | Is egress restricted? |
| VPC endpoints | PA10-05 | Is AWS API traffic private? |
| ALB/NLB TLS | PA10-06 | Do LBs enforce TLS 1.2+? |
| CloudFront TLS | PA10-07 | Do CDNs enforce HTTPS + TLS 1.2+? |
| VPN cipher | PA10-08 | Is agency VPN CJIS-compliant? |
| Default VPC | PA10-09 | Is CJI out of default VPC? |

**Total: 9 checks.** Expected time: ~3 min.
