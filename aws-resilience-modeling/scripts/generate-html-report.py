#!/usr/bin/env python3
"""
AWS Resilience Assessment - HTML Report Generator
使用美观的HTML模板生成交互式评估报告
"""

import json
import sys
from pathlib import Path
from datetime import datetime


def generate_html_report(assessment_data, output_file=None):
    """
    从评估数据生成美观的HTML报告

    Args:
        assessment_data: 评估数据字典
        output_file: 输出文件路径（可选）

    Returns:
        生成的HTML文件路径
    """

    # 1. 读取HTML模板
    script_dir = Path(__file__).parent
    template_path = script_dir.parent / 'assets' / 'html-report-template.html'

    if not template_path.exists():
        raise FileNotFoundError(f"HTML模板文件不存在: {template_path}")

    with open(template_path, 'r', encoding='utf-8') as f:
        html_template = f.read()

    # 2. 准备输出文件名
    if output_file is None:
        project_name = assessment_data.get('projectName', 'project')
        date_str = datetime.now().strftime('%Y-%m-%d')
        output_file = f"{project_name}-resilience-assessment-{date_str}.html"

    # 3. 替换基本信息占位符
    html_output = html_template
    html_output = html_output.replace('{{PROJECT_NAME}}', assessment_data.get('projectName', '项目'))
    html_output = html_output.replace('{{ASSESSMENT_DATE}}', assessment_data.get('assessmentDate', datetime.now().strftime('%Y-%m-%d')))
    html_output = html_output.replace('{{OVERALL_SCORE}}', str(assessment_data.get('overallScore', 3.5)))

    # 4. 替换统计数据
    stats = assessment_data.get('stats', {})
    html_output = html_output.replace('{{TOTAL_RISKS}}', str(stats.get('totalRisks', 0)))
    html_output = html_output.replace('{{CRITICAL_RISKS}}', str(stats.get('criticalRisks', 0)))
    html_output = html_output.replace('{{CURRENT_RTO}}', stats.get('currentRTO', 'N/A'))
    html_output = html_output.replace('{{ESTIMATED_COST}}', str(stats.get('estimatedCost', 0)))

    # 5. 替换Chart.js数据
    dimensions = assessment_data.get('resilienceDimensions', {})
    resilience_data = [
        dimensions.get('redundancy', 3),
        dimensions.get('azFaultTolerance', 3),
        dimensions.get('timeoutRetry', 3),
        dimensions.get('circuitBreaker', 3),
        dimensions.get('autoScaling', 3),
        dimensions.get('configProtection', 3),
        dimensions.get('faultIsolation', 3),
        dimensions.get('backupRecovery', 3),
        dimensions.get('bestPractices', 3)
    ]
    html_output = html_output.replace('{{RESILIENCE_DATA}}', json.dumps(resilience_data))

    risk_dist = assessment_data.get('riskDistribution', {})
    risk_distribution_data = [
        risk_dist.get('critical', 0),
        risk_dist.get('high', 0),
        risk_dist.get('medium', 0),
        risk_dist.get('low', 0)
    ]
    html_output = html_output.replace('{{RISK_DISTRIBUTION_DATA}}', json.dumps(risk_distribution_data))

    # 6. 生成风险卡片HTML
    risks = assessment_data.get('risks', [])
    risk_cards_html = ""

    for risk in risks[:10]:  # 只显示前10个高优先级风险
        severity = risk.get('severity', 'medium')
        severity_class = f"risk-{severity}"

        risk_cards_html += f"""
        <div class="risk-card {severity_class}">
            <div class="risk-header">
                <span class="risk-id">{risk.get('id', 'R-???')}</span>
                <span class="badge badge-{severity}">{severity.upper()}</span>
            </div>
            <h3>{risk.get('title', '未命名风险')}</h3>
            <p class="risk-category">{risk.get('category', '未分类')}</p>
            <div class="risk-metrics">
                <div>概率: {risk.get('probability', 0)}/5</div>
                <div>影响: {risk.get('impact', 0)}/5</div>
                <div>风险得分: {risk.get('riskScore', 0):.1f}</div>
            </div>
            <div class="risk-details">
                <p><strong>当前状态:</strong> {risk.get('currentState', 'N/A')}</p>
                <p><strong>改进建议:</strong> {risk.get('recommendation', 'N/A')}</p>
                <div class="risk-footer">
                    <span class="badge">成本: {risk.get('estimatedCost', 'N/A')}</span>
                    <span class="badge">时间: {risk.get('implementation', 'N/A')}</span>
                </div>
            </div>
        </div>
        """

    html_output = html_output.replace('{{RISK_CARDS}}', risk_cards_html)

    # 7. 替换Mermaid架构图
    architecture_diagram = assessment_data.get('architectureDiagram', 'graph TD\n    A[暂无架构图]')
    html_output = html_output.replace('{{ARCHITECTURE_DIAGRAM}}', architecture_diagram)

    dependency_diagram = assessment_data.get('dependencyDiagram', 'graph TD\n    A[暂无依赖图]')
    html_output = html_output.replace('{{DEPENDENCY_DIAGRAM}}', dependency_diagram)

    # 8. 保存HTML文件
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html_output)

    return output_file


def main():
    """命令行入口"""

    # 示例评估数据（实际使用时从分析结果中提取）
    example_data = {
        "projectName": "示例电商系统",
        "assessmentDate": "2026-03-03",
        "overallScore": 4.2,

        "stats": {
            "totalRisks": 15,
            "criticalRisks": 3,
            "currentRTO": "15分钟",
            "estimatedCost": 2500
        },

        "resilienceDimensions": {
            "redundancy": 4,
            "azFaultTolerance": 3,
            "timeoutRetry": 4,
            "circuitBreaker": 3,
            "autoScaling": 4,
            "configProtection": 5,
            "faultIsolation": 3,
            "backupRecovery": 4,
            "bestPractices": 4
        },

        "riskDistribution": {
            "critical": 3,
            "high": 5,
            "medium": 5,
            "low": 2
        },

        "risks": [
            {
                "id": "R-001",
                "title": "RDS单区域部署",
                "category": "单点故障",
                "severity": "critical",
                "probability": 3,
                "impact": 5,
                "detectionDifficulty": 2,
                "remediationComplexity": 2,
                "riskScore": 15,
                "currentState": "主数据库仅部署在us-east-1，无跨区域复制",
                "recommendation": "实施Aurora Global Database，启用跨区域自动故障转移",
                "estimatedCost": "$800/月",
                "implementation": "3-4周"
            },
            {
                "id": "R-002",
                "title": "缺少Auto Scaling策略",
                "category": "过度负载",
                "severity": "high",
                "probability": 4,
                "impact": 4,
                "detectionDifficulty": 1,
                "remediationComplexity": 3,
                "riskScore": 5.3,
                "currentState": "EC2实例固定容量，无自动扩展",
                "recommendation": "配置Target Tracking Auto Scaling，基于CPU和请求数动态调整",
                "estimatedCost": "$300/月",
                "implementation": "1-2周"
            },
            {
                "id": "R-003",
                "title": "未配置Circuit Breaker",
                "category": "过度延迟",
                "severity": "high",
                "probability": 3,
                "impact": 4,
                "detectionDifficulty": 3,
                "remediationComplexity": 4,
                "riskScore": 9.0,
                "currentState": "微服务之间无断路器保护，级联故障风险高",
                "recommendation": "集成AWS App Mesh或Istio，实施断路器模式",
                "estimatedCost": "$200/月",
                "implementation": "4-6周"
            }
        ],

        "architectureDiagram": """graph TB
    subgraph "AWS Region: us-east-1"
        subgraph "AZ-1a"
            EC2_1[EC2 Instances]
            RDS_1[RDS Primary]
        end
        subgraph "AZ-1b"
            EC2_2[EC2 Instances]
            RDS_2[RDS Standby]
        end
        ALB[Application Load Balancer]
        ALB --> EC2_1
        ALB --> EC2_2
        EC2_1 --> RDS_1
        EC2_2 --> RDS_1
        RDS_1 -.->|Sync Replication| RDS_2
    end
    Users[用户] --> ALB""",

        "dependencyDiagram": """graph LR
    Frontend[前端应用] --> API[API Gateway]
    API --> Auth[认证服务]
    API --> Order[订单服务]
    API --> Payment[支付服务]
    Order --> DB[(数据库)]
    Payment --> DB
    Payment --> External[外部支付网关]"""
    }

    try:
        output_file = generate_html_report(example_data)
        print(f"✅ HTML报告已生成: {output_file}")
        print(f"💡 在浏览器中打开查看: open {output_file}")

    except Exception as e:
        print(f"❌ 生成报告失败: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
