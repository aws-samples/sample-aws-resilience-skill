# HTML报告模板使用指南

## 概述

AWS Resilience Assessment Skill现在支持生成**美观的交互式HTML报告**，包含以下特性：

✨ **视觉设计**
- AWS品牌风格（橙色#ff9900主题）
- 渐变色标题和现代化UI
- 响应式设计，支持移动端和桌面端
- 打印友好样式

📊 **交互式可视化**
- Chart.js图表库（v4.4.0）
  - 雷达图：9个韧性维度评分
  - 甜甜圈图：风险分布统计
  - 柱状图：风险优先级排序
  - 散点图：成本vs收益分析
- Mermaid架构图（v10）
  - 系统架构总览
  - 依赖关系图
  - 改进后架构对比

🎨 **风险可视化**
- 颜色编码风险卡片
  - 🔴 严重 (Critical)
  - 🟠 高 (High)
  - 🟡 中 (Medium)
  - 🟢 低 (Low)
- 实施路线图时间轴
- 统计仪表板

---

## 文件说明

### 核心文件

```
aws-resilience-modeling/
├── SKILL.md                                    # Skill 主配置
├── README.md                                   # Skill 说明文档
├── references/
│   ├── resilience-framework.md                 # 评估框架
│   ├── report-generation.md                    # 报告生成流程
│   └── ...                                     # 其他参考文件
├── scripts/
│   └── generate-html-report.py                 # Python 报告生成器
└── assets/
    ├── html-report-template.html               # HTML 交互式报告模板
    └── example-report-template.md              # Markdown 报告示例
```

### 模板文件结构

**assets/html-report-template.html** 包含：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <!-- Chart.js 4.4.0 -->
    <!-- Mermaid 10 -->
    <!-- 自定义CSS样式 -->
</head>
<body>
    <!-- 占位符标记 -->
    {{PROJECT_NAME}}           # 项目名称
    {{ASSESSMENT_DATE}}        # 评估日期
    {{OVERALL_SCORE}}          # 总体评分
    {{TOTAL_RISKS}}            # 风险总数
    {{CRITICAL_RISKS}}         # 严重风险数
    {{CURRENT_RTO}}            # 当前RTO
    {{ESTIMATED_COST}}         # 预估成本
    {{RESILIENCE_DATA}}        # 韧性维度数据（JSON数组）
    {{RISK_DISTRIBUTION_DATA}} # 风险分布数据（JSON数组）
    {{RISK_CARDS}}             # 风险卡片HTML
    {{ARCHITECTURE_DIAGRAM}}   # Mermaid架构图代码
    {{DEPENDENCY_DIAGRAM}}     # Mermaid依赖图代码
</body>
</html>
```

---

## 使用方法

### 方法1：使用Python脚本（推荐）

**步骤1：准备评估数据**

```python
assessment_data = {
    "projectName": "电商系统",
    "assessmentDate": "2026-03-03",
    "overallScore": 4.2,  # 1-5评分

    "stats": {
        "totalRisks": 15,
        "criticalRisks": 3,
        "currentRTO": "15分钟",
        "estimatedCost": 2500  # 月度成本（美元）
    },

    "resilienceDimensions": {
        "redundancy": 4,           # 冗余设计: 1-5
        "azFaultTolerance": 3,     # AZ容错: 1-5
        "timeoutRetry": 4,         # 超时重试: 1-5
        "circuitBreaker": 3,       # 断路器: 1-5
        "autoScaling": 4,          # 自动扩展: 1-5
        "configProtection": 5,     # 配置防护: 1-5
        "faultIsolation": 3,       # 故障隔离: 1-5
        "backupRecovery": 4,       # 备份恢复: 1-5
        "bestPractices": 4         # 最佳实践: 1-5
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
            "severity": "critical",  # critical/high/medium/low
            "probability": 3,        # 1-5
            "impact": 5,            # 1-5
            "riskScore": 15.0,
            "currentState": "主数据库仅部署在us-east-1",
            "recommendation": "实施Aurora Global Database",
            "estimatedCost": "$800/月",
            "implementation": "3-4周"
        }
        # ... 更多风险
    ],

    "architectureDiagram": """
    graph TB
        subgraph "AWS Region"
            ALB[Load Balancer] --> EC2[EC2 Instances]
            EC2 --> RDS[(Database)]
        end
    """,

    "dependencyDiagram": "graph LR\n    A[App] --> B[API]"
}
```

**步骤2：生成HTML报告**

```bash
# 方式A：使用Python模块
cd ~/.claude/skills/aws-resilience-modeling
python3 -c "
import sys; sys.path.insert(0, 'scripts')
from generate_html_report import generate_html_report
import json

# 从分析结果加载数据
with open('assessment-data.json', 'r') as f:
    data = json.load(f)

output = generate_html_report(data)
print(f'✅ 报告已生成: {output}')
"

# 方式B：直接运行脚本（使用示例数据）
python3 scripts/generate-html-report.py
```

**步骤3：查看报告**

```bash
# 在默认浏览器中打开
open project-resilience-assessment-2026-03-03.html

# 或使用特定浏览器
google-chrome project-resilience-assessment-2026-03-03.html
firefox project-resilience-assessment-2026-03-03.html
```

---

### 方法2：手动填充模板

如果不使用Python脚本，可以手动编辑HTML模板：

```bash
# 1. 复制模板
cp assets/html-report-template.html my-project-report.html

# 2. 使用sed替换占位符
sed -i '' 's/{{PROJECT_NAME}}/我的项目/g' my-project-report.html
sed -i '' 's/{{ASSESSMENT_DATE}}/2026-03-03/g' my-project-report.html
sed -i '' 's/{{OVERALL_SCORE}}/4.2/g' my-project-report.html

# 3. 替换Chart.js数据（需要JSON格式）
# resilienceData = [4, 3, 4, 3, 4, 5, 3, 4, 4]
sed -i '' 's/{{RESILIENCE_DATA}}/[4, 3, 4, 3, 4, 5, 3, 4, 4]/g' my-project-report.html

# 4. 在文本编辑器中打开，手动添加风险卡片和Mermaid图表
```

---

## 集成到Skill工作流

在SKILL.md中使用新的HTML模板：

### 评估完成后自动生成报告

```python
# 在分析任务完成后，调用报告生成函数
from pathlib import Path
import sys

# 添加scripts目录到Python路径
skill_dir = Path.home() / '.claude' / 'skills' / 'aws-resilience-modeling'
sys.path.insert(0, str(skill_dir / 'scripts'))

from generate_html_report import generate_html_report

# 从分析结果构建数据
assessment_data = {
    "projectName": project_name,
    "assessmentDate": current_date,
    # ... 填充所有分析结果
}

# 生成HTML报告
html_file = generate_html_report(assessment_data)
print(f"✅ 交互式HTML报告: {html_file}")
```

### 报告文件命名约定

```
{项目名称}-resilience-assessment-{日期}.html

示例：
- ecommerce-resilience-assessment-2026-03-03.html
- payment-system-resilience-assessment-2026-03-03.html
- order-service-resilience-assessment-2026-03-03.html
```

---

## 自定义和扩展

### 修改配色方案

在 `assets/html-report-template.html` 中修改CSS变量：

```css
:root {
    --primary-color: #ff9900;      /* AWS橙色 */
    --secondary-color: #232f3e;    /* AWS深蓝 */
    --success-color: #28a745;
    --warning-color: #ffc107;
    --danger-color: #dc3545;
}
```

### 添加自定义图表

在模板中添加新的Chart.js图表：

```javascript
// 示例：添加成本趋势折线图
const costTrendChart = new Chart(ctx, {
    type: 'line',
    data: {
        labels: ['Q1', 'Q2', 'Q3', 'Q4'],
        datasets: [{
            label: '预估成本趋势',
            data: [1000, 1500, 2000, 2500],
            borderColor: '#ff9900',
            tension: 0.4
        }]
    }
});
```

### 添加自定义风险字段

在 `scripts/generate-html-report.py` 中扩展风险数据结构：

```python
risk_cards_html += f"""
    <div class="risk-card {severity_class}">
        <!-- 现有字段 -->
        <div class="custom-field">
            <strong>负责团队:</strong> {risk.get('owner', 'N/A')}
        </div>
        <div class="custom-field">
            <strong>截止日期:</strong> {risk.get('deadline', 'N/A')}
        </div>
    </div>
"""
```

---

## 故障排查

### 问题1：HTML文件无法显示图表

**原因**：Chart.js或Mermaid CDN加载失败

**解决方案**：
```bash
# 下载Chart.js到本地
curl -o chart.min.js https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js

# 修改HTML模板引用本地文件
<script src="./chart.min.js"></script>
```

### 问题2：中文显示乱码

**原因**：文件编码不是UTF-8

**解决方案**：
```python
# 确保以UTF-8编码保存
with open(output_file, 'w', encoding='utf-8') as f:
    f.write(html_output)
```

### 问题3：Mermaid图表不渲染

**原因**：Mermaid语法错误

**解决方案**：
```bash
# 在Mermaid Live Editor中验证语法
# https://mermaid.live/

# 检查常见错误：
# - 缺少换行符
# - 引号未转义
# - 特殊字符未处理
```

---

## 性能优化

### 减少报告文件大小

```python
# 只包含Top 10风险（而非全部）
for risk in risks[:10]:
    # 生成风险卡片

# 压缩Mermaid图表（移除多余空格和注释）
diagram = re.sub(r'\s+', ' ', diagram).strip()
```

### 加快加载速度

```html
<!-- 使用CDN缓存 -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>

<!-- 或使用本地文件 -->
<script src="./assets/chart.min.js"></script>
```

---

## 对比：新旧报告方式

| 特性 | 旧方式（基础HTML） | 新方式（交互式模板） |
|------|------------------|---------------------|
| 生成方式 | Pandoc/Python markdown | 自定义模板 + Python |
| 可视化 | 静态文本 | Chart.js交互图表 |
| 风险展示 | 表格 | 彩色卡片 + 评分 |
| 架构图 | Mermaid文本 | 可渲染Mermaid图 |
| 设计风格 | GitHub Markdown CSS | AWS品牌风格 |
| 响应式 | 基础 | 完全响应式 |
| 打印支持 | 有限 | 优化的打印样式 |
| 文件大小 | ~50KB | ~80KB |
| 浏览器兼容 | 所有现代浏览器 | 所有现代浏览器 |

---

## 最佳实践

### 1. 数据准确性

- 在生成报告前验证所有数据字段
- 使用明确的评分标准（1-5星）
- 确保风险优先级排序正确

### 2. 报告可读性

- 限制显示的风险数量（Top 10-15）
- 使用简洁的风险描述
- 提供清晰的改进建议

### 3. 版本管理

- 在文件名中包含日期
- 保存历史评估报告以跟踪改进
- 在报告末尾标注版本信息

### 4. 分享和展示

- 将HTML文件与团队共享（无需额外依赖）
- 从浏览器打印或导出为PDF
- 在评审会议中使用交互式图表

---

## 示例输出

生成的HTML报告将包含：

### 1. 头部信息
```
项目名称：电商系统
评估日期：2026-03-03
总体评分：4.2/5.0 ⭐⭐⭐⭐
```

### 2. 统计仪表板
```
[15]        [3]         [15分钟]    [$2,500]
风险总数    严重风险    当前RTO     预估成本/月
```

### 3. 交互式图表
- 雷达图：9维度韧性评估
- 甜甜圈图：风险分类分布
- 柱状图：Top 10风险优先级
- 散点图：成本vs收益分析

### 4. 风险清单
- 颜色编码卡片（红/橙/黄/绿）
- 风险评分和优先级
- 当前状态和改进建议
- 预估成本和实施时间

### 5. 架构可视化
- 当前架构Mermaid图
- 依赖关系图
- 改进后架构对比

---

## 更新日志

### v1.0.0 (2026-03-03)
- ✅ 创建美观的HTML报告模板
- ✅ 集成Chart.js 4.4.0交互式图表
- ✅ 添加Mermaid 10架构图支持
- ✅ 实现风险卡片颜色编码
- ✅ 创建Python报告生成器
- ✅ 更新SKILL.md报告生成流程
- ✅ 添加响应式设计和打印样式

---

## 支持和反馈

如有问题或建议：

1. 查看 `SKILL.md` 了解完整工作流程
2. 查看 `README.md` 了解Skill基础信息
3. 查看 `resilience-framework.md` 了解评估框架
4. 运行 `python3 scripts/generate-html-report.py` 查看示例报告

---

**创建日期**: 2026-03-03
**版本**: 1.0.0
**维护者**: AWS Resilience Assessment Skill
