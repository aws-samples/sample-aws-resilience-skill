# 报告生成详细指南

> 本文件包含 AWS 韧性评估报告的完整生成流程、模板代码和质量检查清单。
> 主流程概述见 [SKILL.md](../SKILL.md) 的"报告生成要求"章节。

---

## 自动生成报告流程

### 1. 生成 Markdown 格式报告

使用 Write 工具创建完整的 markdown 报告文件：

```markdown
文件名格式：{项目名称}-resilience-assessment-{日期}.md
例如：ecommerce-resilience-assessment-2026-02-28.md

报告应包含：
- 完整的目录结构（TOC）
- 所有 8 个分析任务的结果
- 所有 Mermaid 图表
- 表格、代码块、告警配置
- 执行摘要和关键发现
- 实施路线图
- 附录和参考资料
```

### 2. 生成 HTML 格式报告（使用美观模板）

**推荐方法：使用交互式HTML模板**

使用预制的美观HTML模板（`assets/html-report-template.html`），该模板包含：
- AWS品牌设计风格（橙色主题）
- Chart.js交互式图表（雷达图、甜甜圈图、柱状图、散点图）
- Mermaid架构图支持
- 响应式设计，支持移动端和打印
- 时间轴可视化
- 风险卡片颜色编码

**生成步骤**：

```python
# 使用Python脚本填充模板数据并生成HTML报告
python3 << 'EOF'
import json
from pathlib import Path

# 1. 读取HTML模板
template_path = Path(__file__).parent / 'assets/html-report-template.html'
with open(template_path, 'r', encoding='utf-8') as f:
    html_template = f.read()

# 2. 准备评估数据（从分析结果中提取）
assessment_data = {
    "projectName": "{项目名称}",
    "assessmentDate": "{评估日期}",
    "overallScore": {总体评分},  # 1-5的评分

    # 统计数据
    "stats": {
        "totalRisks": {风险总数},
        "criticalRisks": {严重风险数},
        "currentRTO": "{当前RTO}",
        "estimatedCost": {预估月度成本}
    },

    # 韧性维度评分（9个维度）
    "resilienceDimensions": {
        "redundancy": {冗余设计评分},      # 1-5
        "azFaultTolerance": {AZ容错评分},
        "timeoutRetry": {超时重试评分},
        "circuitBreaker": {断路器评分},
        "autoScaling": {自动扩展评分},
        "configProtection": {配置防护评分},
        "faultIsolation": {故障隔离评分},
        "backupRecovery": {备份恢复评分},
        "bestPractices": {最佳实践评分}
    },

    # 风险分布
    "riskDistribution": {
        "critical": {严重风险数},
        "high": {高风险数},
        "medium": {中风险数},
        "low": {低风险数}
    },

    # 风险清单（按优先级排序）
    "risks": [
        {
            "id": "R-001",
            "title": "{风险标题}",
            "category": "{故障类别}",  # SPOF/过度延迟/过度负载/错误配置/共享命运
            "severity": "critical",     # critical/high/medium/low
            "probability": {概率评分},   # 1-5
            "impact": {影响评分},       # 1-5
            "detectionDifficulty": {检测难度}, # 1-5
            "remediationComplexity": {修复复杂度}, # 1-5
            "riskScore": {风险得分},
            "currentState": "{当前状态描述}",
            "recommendation": "{改进建议}",
            "estimatedCost": "{预估成本}",
            "implementation": "{实施时间}"
        }
        // ... 更多风险
    ],

    # 实施路线图（时间轴数据）
    "roadmap": [
        {
            "phase": "第一阶段：基础韧性",
            "startDate": "2026-03-01",
            "duration": "2个月",
            "tasks": [
                "Multi-AZ部署",
                "配置自动备份",
                "实施基础监控"
            ],
            "milestone": "M1: 基础冗余完成"
        }
        // ... 更多阶段
    ],

    # Mermaid架构图代码
    "architectureDiagram": "{mermaid图表代码}",
    "dependencyDiagram": "{依赖关系图代码}"
}

# 3. 将数据注入到HTML模板中（替换占位符）
html_output = html_template

# 替换基本信息
html_output = html_output.replace('{{PROJECT_NAME}}', assessment_data['projectName'])
html_output = html_output.replace('{{ASSESSMENT_DATE}}', assessment_data['assessmentDate'])
html_output = html_output.replace('{{OVERALL_SCORE}}', str(assessment_data['overallScore']))

# 替换统计数据
html_output = html_output.replace('{{TOTAL_RISKS}}', str(assessment_data['stats']['totalRisks']))
html_output = html_output.replace('{{CRITICAL_RISKS}}', str(assessment_data['stats']['criticalRisks']))
html_output = html_output.replace('{{CURRENT_RTO}}', assessment_data['stats']['currentRTO'])
html_output = html_output.replace('{{ESTIMATED_COST}}', str(assessment_data['stats']['estimatedCost']))

# 替换Chart.js数据
html_output = html_output.replace('{{RESILIENCE_DATA}}', json.dumps(list(assessment_data['resilienceDimensions'].values())))
html_output = html_output.replace('{{RISK_DISTRIBUTION_DATA}}', json.dumps(list(assessment_data['riskDistribution'].values())))

# 生成风险卡片HTML
risk_cards_html = ""
for risk in assessment_data['risks'][:10]:  # 只显示前10个风险
    severity_class = f"risk-{risk['severity']}"
    risk_cards_html += f"""
    <div class="risk-card {severity_class}">
        <div class="risk-header">
            <span class="risk-id">{risk['id']}</span>
            <span class="badge badge-{risk['severity']}">{risk['severity'].upper()}</span>
        </div>
        <h3>{risk['title']}</h3>
        <p class="risk-category">{risk['category']}</p>
        <div class="risk-metrics">
            <div>概率: {risk['probability']}/5</div>
            <div>影响: {risk['impact']}/5</div>
            <div>风险得分: {risk['riskScore']:.1f}</div>
        </div>
        <div class="risk-details">
            <p><strong>当前状态:</strong> {risk['currentState']}</p>
            <p><strong>改进建议:</strong> {risk['recommendation']}</p>
            <div class="risk-footer">
                <span class="badge">成本: {risk['estimatedCost']}</span>
                <span class="badge">时间: {risk['implementation']}</span>
            </div>
        </div>
    </div>
    """

html_output = html_output.replace('{{RISK_CARDS}}', risk_cards_html)

# 替换Mermaid图表
html_output = html_output.replace('{{ARCHITECTURE_DIAGRAM}}', assessment_data['architectureDiagram'])

# 4. 保存HTML文件
output_file = '{项目名称}-resilience-assessment-{日期}.html'
with open(output_file, 'w', encoding='utf-8') as f:
    f.write(html_output)

print(f'✅ 美观的HTML报告已生成: {output_file}')
print(f'💡 在浏览器中打开即可查看交互式报告')
EOF
```

**备选方法：使用Pandoc进行基础转换**

如果需要快速生成基础HTML版本：

```bash
pandoc {报告文件}.md \
  -f gfm \
  -t html5 \
  --standalone \
  --toc \
  --toc-depth=3 \
  --css=https://cdn.jsdelivr.net/npm/github-markdown-css@5/github-markdown.min.css \
  --metadata title="AWS 系统韧性评估报告" \
  -o {报告文件}-basic.html
```

### 3. 生成混沌工程数据（当用户选择需要时）

如果用户选择需要混沌工程测试计划，按照 `references/assessment-output-spec.md` 规范生成结构化数据：

**方式 1：嵌入模式（推荐）**
在评估报告（Markdown 和 HTML）末尾添加 `## Chaos Engineering Ready Data` 附录章节，一份报告人机共读。

**方式 2：独立文件模式**
```markdown
文件名：{项目名称}-chaos-input-{日期}.md
例如：ecommerce-chaos-input-2026-02-28.md

内容：按照"混沌工程测试计划"部分的规范结构生成，
包含：项目元数据、AWS 资源清单（含 ARN）、业务功能依赖链、
风险清单（含可实验性标记和建议注入方式）、风险详情、
监控就绪度、韧性评分（9 维度）、约束和偏好、开放发现
```

**HTML 报告中的混沌工程数据**：
当用户选择混沌工程测试计划时，HTML 报告中也应包含对应的可视化章节：
- **可实验风险卡片**：风险卡片增加 `可实验` 标记和 `建议注入方式` 标签
- **监控就绪度仪表盘**：用甜甜圈图显示就绪状态
- **注入方式分布图**：用柱状图显示 FIS / Chaos Mesh / 手动 / 不可实验的分布
- **资源 ARN 清单表**：可折叠的完整资源清单，含复制按钮
- **实验优先级矩阵**：散点图显示可实验风险的概率 vs 影响

### 4. 报告文件位置

所有生成的报告文件应保存在当前工作目录：

```
{当前工作目录}/
├── {项目名称}-resilience-assessment-{日期}.md    (主报告 Markdown)
├── {项目名称}-resilience-assessment-{日期}.html   (主报告 HTML，含交互式图表)
└── {项目名称}-chaos-input-{日期}.md              (混沌工程数据，独立文件模式时生成，可选)
```

---

## 报告质量检查清单

在生成报告后，确保：

- ✅ 所有 Mermaid 图表语法正确（在 HTML 中可渲染）
- ✅ 所有表格格式正确对齐
- ✅ 代码块有正确的语法高亮标记（```bash, ```yaml, ```json 等）
- ✅ 中文和英文之间有适当的空格（提高可读性）
- ✅ 所有链接有效（内部锚点和外部 URL）
- ✅ 风险 ID、任务 ID 等引用一致
- ✅ HTML 文件在浏览器中显示正常

---

## 完成提示

生成报告后，向用户提供：

```markdown
✅ **AWS 韧性评估报告已生成**

📄 **Markdown 格式**：`{文件名}.md`
🌐 **交互式HTML格式**：`{文件名}.html`
🧪 **混沌工程数据**：`{文件名}-chaos-input.md`（如用户选择了混沌工程测试计划）

**HTML报告特性**：
✨ AWS品牌风格设计（橙色主题）
📊 交互式Chart.js图表（雷达图、甜甜圈图、柱状图、散点图）
🎨 风险卡片颜色编码（红色=严重、橙色=高、黄色=中、绿色=低）
📱 响应式设计，支持手机/平板/电脑查看
🖨️ 打印友好样式
⏱️ 时间轴可视化实施路线图
🏗️ Mermaid架构图支持
🧪 混沌工程数据可视化（可实验风险标记、监控就绪度、注入方式分布图，如适用）

**关键发现**：
1. {关键风险 1}
2. {关键风险 2}
3. {关键风险 3}

**优先建议**：
1. {建议 1}
2. {建议 2}
3. {建议 3}

**预计投资**：${总成本}/月
**预期效果**：年度停机时间从 {当前} 降至 {目标}

您可以：
- 在浏览器中打开交互式HTML报告，体验动态图表
- 使用Markdown编辑器编辑和自定义报告
- 从浏览器打印或导出为PDF用于分享
- 与团队成员共享HTML文件（无需额外依赖）
- 将混沌工程数据文件直接传递给 chaos-engineering-on-aws skill 使用（如适用）
```

---

## 工具安装检查

在尝试生成 HTML 之前，检查必要的工具和模板文件：

```bash
# 检查HTML模板文件是否存在
TEMPLATE_PATH="$HOME/.claude/skills/aws-resilience-modeling/assets/html-report-template.html"

if [ -f "$TEMPLATE_PATH" ]; then
    echo "✅ 找到美观的HTML模板"
    echo "💡 推荐：使用交互式HTML模板生成报告（包含Chart.js可视化）"
    # 使用推荐的模板方法
elif command -v pandoc &> /dev/null; then
    echo "✅ 使用 pandoc 生成基础 HTML"
    echo "⚠️  提示：安装html-report-template.html可获得更美观的报告"
    # 使用pandoc备选方法
elif python3 -c "import markdown" 2>/dev/null; then
    echo "✅ 使用 Python markdown 库生成基础 HTML"
    echo "⚠️  提示：安装html-report-template.html可获得更美观的报告"
    # 使用Python markdown备选方法
else
    echo "⚠️  未找到 HTML 生成工具"
    echo "💡 推荐选项："
    echo "   1. 下载 html-report-template.html 到 skill 目录（最美观）"
    echo "   2. 安装 pandoc：brew install pandoc"
    echo "   3. 安装 Python markdown：pip3 install markdown"
    echo "📝 已生成 Markdown 报告，HTML 生成跳过"
fi
```

---

## 报告格式注意事项

**报告结尾格式要求**：
- 在报告末尾只包含"报告生成日期"和"版本"信息
- **不要**添加联系方式（如 email 地址）
- **不要**添加署名或团队信息
- 保持报告结尾简洁专业

示例正确格式：
```markdown
---

**报告生成日期**: YYYY-MM-DD
**版本**: 1.0
```

---

## 重要提醒

每次分析结束后，应自动执行报告生成流程，这样用户可以：
- 在浏览器中轻松查看美观的报告
- 将报告分享给团队成员和管理层
- 保存报告作为历史记录
- 导出为 PDF 用于演示

不要只在对话中输出分析结果，应同时生成文件。
