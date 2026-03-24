# MCP Server 配置指南

本 Skill 依赖 AWS 官方 MCP Server 与 AWS 服务交互。以下是各 MCP Server 的配置方法。

> ⚠️ `awslabs.core-mcp-server` 已废弃（DEPRECATED）。请直接配置独立 MCP Server。
> 迁移指南：https://github.com/awslabs/mcp/blob/main/docs/migration-core.md

---

## 必需的 MCP Server

### 1. aws-api-mcp-server

**用途**：FIS 实验创建/执行/停止、EC2/RDS/EKS 资源验证、IAM 权限检查

**安装**：需要 Python 3.10+ 和 [uv](https://docs.astral.sh/uv/getting-started/installation/)

#### Claude Code

```bash
claude mcp add awslabs-aws-api-mcp-server \
  -e AWS_REGION=ap-northeast-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.aws-api-mcp-server@latest
```

#### Kiro

编辑 `.kiro/settings/mcp.json`：

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_REGION": "ap-northeast-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

#### Cursor / VS Code

编辑 `.cursor/mcp.json` 或 `.vscode/mcp.json`：

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_REGION": "ap-northeast-1",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    }
  }
}
```

---

### 2. cloudwatch-mcp-server

**用途**：CloudWatch 指标读取、告警创建/查询（Stop Condition）、日志查询

#### Claude Code

```bash
claude mcp add awslabs-cloudwatch-mcp-server \
  -e AWS_REGION=ap-northeast-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.cloudwatch-mcp-server@latest
```

#### Kiro / Cursor / VS Code

同上格式，替换包名为 `awslabs.cloudwatch-mcp-server@latest`。

---

## 推荐的 MCP Server（按需配置）

### 3. eks-mcp-server

**条件**：目标系统为 EKS 架构时配置
**用途**：EKS 集群管理、K8s 资源操作、Pod 日志查看

#### Claude Code

```bash
claude mcp add awslabs-eks-mcp-server \
  -e AWS_REGION=ap-northeast-1 \
  -e AWS_PROFILE=default \
  -e FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.eks-mcp-server@latest
```

---

### 4. chaosmesh-mcp

**条件**：EKS 集群已安装 Chaos Mesh 时配置
**用途**：K8s 应用层故障注入（30 个 tool，覆盖全部 CRD 类型）
**仓库**：https://github.com/RadiumGu/Chaosmesh-MCP

#### Claude Code

```bash
# 克隆仓库
git clone https://github.com/RadiumGu/Chaosmesh-MCP.git
cd Chaosmesh-MCP

# 添加 MCP Server
claude mcp add chaosmesh-mcp \
  -e KUBECONFIG=~/.kube/config \
  -- python3 server.py
```

#### Kiro

```json
{
  "mcpServers": {
    "chaosmesh-mcp": {
      "command": "python3",
      "args": ["/path/to/Chaosmesh-MCP/server.py"],
      "env": {
        "KUBECONFIG": "~/.kube/config"
      },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

---

## 完整配置示例

以下是本 Skill 推荐的完整 MCP 配置（覆盖所有场景）：

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_REGION": "ap-northeast-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.cloudwatch-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.cloudwatch-mcp-server@latest"],
      "env": {
        "AWS_REGION": "ap-northeast-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "awslabs.eks-mcp-server": {
      "command": "uvx",
      "args": ["awslabs.eks-mcp-server@latest"],
      "env": {
        "AWS_REGION": "ap-northeast-1",
        "AWS_PROFILE": "default",
        "FASTMCP_LOG_LEVEL": "ERROR"
      }
    },
    "chaosmesh-mcp": {
      "command": "python3",
      "args": ["/path/to/Chaosmesh-MCP/server.py"],
      "env": {
        "KUBECONFIG": "~/.kube/config"
      }
    }
  }
}
```

---

## AWS 凭证配置

MCP Server 使用标准 AWS 凭证链。推荐配置方式：

```bash
# 方式 1：AWS Profile（推荐）
aws configure --profile default
# 在 MCP 配置中设置 AWS_PROFILE=default

# 方式 2：环境变量
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_SESSION_TOKEN=xxx  # 如使用临时凭证

# 方式 3：IAM Role（EC2/EKS 环境）
# 无需额外配置，自动使用实例角色
```

---

## FIS IAM Role

FIS 实验执行需要专用 IAM Role。如果还没有，Skill 的 Step 4 会自动生成创建命令。手动创建参考：

```bash
# 创建 FIS 执行角色
aws iam create-role \
  --role-name FISExperimentRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "fis.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# 附加权限（按实验类型选择）
# EC2 实验
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

# RDS 实验
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

# EKS 实验
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# 网络实验
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess

# CloudWatch（Stop Condition 读取告警状态）
aws iam attach-role-policy --role-name FISExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess
```

> ⚠️ 生产环境建议使用最小权限策略，而非 FullAccess。上述仅为快速开始参考。

---

## 验证配置

配置完成后验证：

```bash
# 验证 aws-api-mcp-server
# Claude Code 中运行
> /mcp
# 应看到 awslabs-aws-api-mcp-server 状态为 connected

# 验证 AWS 凭证
aws sts get-caller-identity

# 验证 FIS 权限
aws fis list-experiment-templates

# 验证 CloudWatch 权限
aws cloudwatch describe-alarms --max-items 1

# 验证 EKS（如配置）
aws eks list-clusters

# 验证 Chaos Mesh（如配置）
kubectl get crd | grep chaos-mesh
```

---

## 无 MCP 降级

如果 MCP Server 未配置或不可用，Skill 自动降级为 AWS CLI 直接调用：

| 操作 | MCP 方式 | CLI 降级 |
|------|---------|---------|
| FIS 实验 | aws-api-mcp-server | `aws fis create-experiment-template` / `start-experiment` |
| 指标读取 | cloudwatch-mcp-server | `aws cloudwatch get-metric-data` |
| 告警管理 | cloudwatch-mcp-server | `aws cloudwatch put-metric-alarm` |
| K8s 操作 | eks-mcp-server | `kubectl` |
| Chaos Mesh | chaosmesh-mcp | `kubectl apply -f` |

降级后功能完整，但准确性略低（LLM 需自行拼 JSON/YAML）。
