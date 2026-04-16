# Environment Bootstrap Guide

## Step 1: AWS CLI Detection

```bash
which aws 2>/dev/null && aws --version 2>/dev/null
```

**If found**: Record version, proceed to Step 2.

**If not found**: Guide installation:
```bash
# macOS
brew install awscli

# Linux (pip)
pip3 install awscli --user

# Linux (official)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
```

If user declines: Switch to **questionnaire-only mode** (no programmatic checks).

## Step 2: Credential Verification

```bash
aws sts get-caller-identity --output json
```

Record:
- `Account`: Target AWS account
- `Arn`: Role/User ARN
- `UserId`: Session identifier

**If fails**: Guide credential setup:
1. Option A: `aws configure` with access key
2. Option B: `aws configure --profile wa-review` with named profile
3. Option C: Source environment file (`source ~/.aws-creds.sh`)
4. Option D: Skip → questionnaire-only mode

## Step 3: Permission Boundary Validation (MANDATORY)

See [credential-boundary.md](credential-boundary.md) for the full boundary definition.

**Quick validation**:
```bash
# For IAM Role
ROLE_NAME=$(aws sts get-caller-identity --query 'Arn' --output text | grep -oP '(?<=role/)[\w-]+')
aws iam list-attached-role-policies --role-name "$ROLE_NAME" --output json

# For IAM User
USER_NAME=$(aws sts get-caller-identity --query 'Arn' --output text | grep -oP '(?<=user/)[\w-]+')
aws iam list-attached-user-policies --user-name "$USER_NAME" --output json
```

**Allowed policies** (any of):
- `arn:aws:iam::aws:policy/ReadOnlyAccess`
- `arn:aws:iam::aws:policy/ViewOnlyAccess`
- `arn:aws:iam::aws:policy/SecurityAudit`
- Custom policy with only Describe/Get/List actions

**Blocked policies** (any of):
- `arn:aws:iam::aws:policy/AdministratorAccess`
- `arn:aws:iam::aws:policy/PowerUserAccess`
- Any policy containing write/modify/delete actions

**If boundary violated**: Display warning and HALT. Do NOT proceed.

## Step 4: Region and Scope Detection

```bash
# Current region
aws configure get region

# List available regions
aws ec2 describe-regions --query 'Regions[].RegionName' --output json

# List VPCs in target region
aws ec2 describe-vpcs --query 'Vpcs[].{VpcId:VpcId,Cidr:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' --output table
```

Present to user for confirmation:
```
📋 ASSESSMENT SCOPE

Account:  123456789012
Region:   ap-northeast-1
VPCs:     vpc-abc123 (Production), vpc-def456 (Staging)
Framework: General WA Framework (6 pillars)
Mode:     Autopilot (Security-First)

Proceed? (Y/N)
```

## Step 5: Environment Summary

After all checks pass, log:
```
[BOOTSTRAP] Environment Ready:
• AWS CLI: {version} ✅
• Credentials: {arn} ✅
• Permission Boundary: ReadOnly ✅
• Region: {region}
• VPCs: {count} VPCs in scope
• Framework: General WA (6 pillars, Security-First)
• Mode: Autopilot
```
