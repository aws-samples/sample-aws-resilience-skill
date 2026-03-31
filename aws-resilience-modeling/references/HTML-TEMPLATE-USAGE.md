# HTML Report Template Usage Guide

## Overview

The AWS Resilience Assessment Skill now supports generating **interactive HTML reports** with the following features:

**Visual Design**
- AWS brand style (orange #ff9900 theme)
- Gradient headers and modern UI
- Responsive design supporting mobile and desktop
- Print-friendly styles

**Interactive Visualizations**
- Chart.js library (v4.4.0)
  - Radar chart: 9 resilience dimension scores
  - Doughnut chart: Risk distribution statistics
  - Bar chart: Risk priority ranking
  - Scatter chart: Cost vs. benefit analysis
- Mermaid architecture diagrams (v10)
  - System architecture overview
  - Dependency diagrams
  - Improved architecture comparison

**Risk Visualization**
- Color-coded risk cards
  - Red: Critical
  - Orange: High
  - Yellow: Medium
  - Green: Low
- Implementation roadmap timeline
- Statistics dashboard

---

## File Description

### Core Files

```
aws-resilience-modeling/
├── SKILL.md                                    # Skill main configuration (Chinese)
├── SKILL_EN.md                                 # Skill main configuration (English)
├── README.md                                   # Skill documentation (Chinese)
├── README_EN.md                                # Skill documentation (English)
├── references/
│   ├── resilience-framework.md                 # Assessment framework (Chinese)
│   ├── resilience-framework_en.md              # Assessment framework (English)
│   ├── report-generation.md                    # Report generation workflow (Chinese)
│   ├── report-generation_en.md                 # Report generation workflow (English)
│   └── ...                                     # Other reference files
├── scripts/
│   └── generate-html-report.py                 # Python report generator
└── assets/
    ├── html-report-template.html               # HTML interactive report template
    ├── example-report-template.md              # Markdown report example (Chinese)
    └── example-report-template_en.md           # Markdown report example (English)
```

### Template File Structure

**assets/html-report-template.html** contains:

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <!-- Chart.js 4.4.0 -->
    <!-- Mermaid 10 -->
    <!-- Custom CSS styles -->
</head>
<body>
    <!-- Placeholder markers -->
    {{PROJECT_NAME}}           # Project name
    {{ASSESSMENT_DATE}}        # Assessment date
    {{OVERALL_SCORE}}          # Overall score
    {{TOTAL_RISKS}}            # Total risk count
    {{CRITICAL_RISKS}}         # Critical risk count
    {{CURRENT_RTO}}            # Current RTO
    {{ESTIMATED_COST}}         # Estimated cost
    {{RESILIENCE_DATA}}        # Resilience dimension data (JSON array)
    {{RISK_DISTRIBUTION_DATA}} # Risk distribution data (JSON array)
    {{RISK_CARDS}}             # Risk card HTML
    {{ARCHITECTURE_DIAGRAM}}   # Mermaid architecture diagram code
    {{DEPENDENCY_DIAGRAM}}     # Mermaid dependency diagram code
</body>
</html>
```

---

## Usage Methods

### Method 1: Using Python Script (Recommended)

**Step 1: Prepare Assessment Data**

```python
assessment_data = {
    "projectName": "E-Commerce System",
    "assessmentDate": "2026-03-03",
    "overallScore": 4.2,  # 1-5 score

    "stats": {
        "totalRisks": 15,
        "criticalRisks": 3,
        "currentRTO": "15 minutes",
        "estimatedCost": 2500  # Monthly cost (USD)
    },

    "resilienceDimensions": {
        "redundancy": 4,           # Redundancy Design: 1-5
        "azFaultTolerance": 3,     # AZ Fault Tolerance: 1-5
        "timeoutRetry": 4,         # Timeout & Retry: 1-5
        "circuitBreaker": 3,       # Circuit Breaker: 1-5
        "autoScaling": 4,          # Auto Scaling: 1-5
        "configProtection": 5,     # Configuration Safeguards: 1-5
        "faultIsolation": 3,       # Fault Isolation: 1-5
        "backupRecovery": 4,       # Backup & Recovery: 1-5
        "bestPractices": 4         # Best Practices: 1-5
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
            "title": "RDS Single-Region Deployment",
            "category": "Single Point of Failure",
            "severity": "critical",  # critical/high/medium/low
            "probability": 3,        # 1-5
            "impact": 5,            # 1-5
            "riskScore": 15.0,
            "currentState": "Primary database deployed only in us-east-1",
            "recommendation": "Implement Aurora Global Database",
            "estimatedCost": "$800/month",
            "implementation": "3-4 weeks"
        }
        # ... more risks
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

**Step 2: Generate HTML Report**

```bash
# Method A: Using Python module
cd ~/.claude/skills/aws-resilience-modeling
python3 -c "
import sys; sys.path.insert(0, 'scripts')
from generate_html_report import generate_html_report
import json

# Load data from analysis results
with open('assessment-data.json', 'r') as f:
    data = json.load(f)

output = generate_html_report(data)
print(f'Report generated: {output}')
"

# Method B: Run script directly (using sample data)
python3 scripts/generate-html-report.py
```

**Step 3: View Report**

```bash
# Open in default browser
open project-resilience-assessment-2026-03-03.html

# Or use a specific browser
google-chrome project-resilience-assessment-2026-03-03.html
firefox project-resilience-assessment-2026-03-03.html
```

---

### Method 2: Manual Template Population

If not using the Python script, you can manually edit the HTML template:

```bash
# 1. Copy template
cp assets/html-report-template.html my-project-report.html

# 2. Use sed to replace placeholders
sed -i '' 's/{{PROJECT_NAME}}/My Project/g' my-project-report.html
sed -i '' 's/{{ASSESSMENT_DATE}}/2026-03-03/g' my-project-report.html
sed -i '' 's/{{OVERALL_SCORE}}/4.2/g' my-project-report.html

# 3. Replace Chart.js data (requires JSON format)
# resilienceData = [4, 3, 4, 3, 4, 5, 3, 4, 4]
sed -i '' 's/{{RESILIENCE_DATA}}/[4, 3, 4, 3, 4, 5, 3, 4, 4]/g' my-project-report.html

# 4. Open in text editor, manually add risk cards and Mermaid diagrams
```

---

## Integration into Skill Workflow

Using the new HTML template in SKILL.md:

### Auto-Generate Report After Assessment Completion

```python
# After analysis tasks complete, call report generation function
from pathlib import Path
import sys

# Add scripts directory to Python path
skill_dir = Path.home() / '.claude' / 'skills' / 'aws-resilience-modeling'
sys.path.insert(0, str(skill_dir / 'scripts'))

from generate_html_report import generate_html_report

# Build data from analysis results
assessment_data = {
    "projectName": project_name,
    "assessmentDate": current_date,
    # ... populate all analysis results
}

# Generate HTML report
html_file = generate_html_report(assessment_data)
print(f"Interactive HTML report: {html_file}")
```

### Report File Naming Convention

```
{project-name}-resilience-assessment-{date}.html

Examples:
- ecommerce-resilience-assessment-2026-03-03.html
- payment-system-resilience-assessment-2026-03-03.html
- order-service-resilience-assessment-2026-03-03.html
```

---

## Customization and Extension

### Modify Color Scheme

In `assets/html-report-template.html`, modify CSS variables:

```css
:root {
    --primary-color: #ff9900;      /* AWS orange */
    --secondary-color: #232f3e;    /* AWS dark blue */
    --success-color: #28a745;
    --warning-color: #ffc107;
    --danger-color: #dc3545;
}
```

### Add Custom Charts

Add new Chart.js charts in the template:

```javascript
// Example: Add cost trend line chart
const costTrendChart = new Chart(ctx, {
    type: 'line',
    data: {
        labels: ['Q1', 'Q2', 'Q3', 'Q4'],
        datasets: [{
            label: 'Estimated Cost Trend',
            data: [1000, 1500, 2000, 2500],
            borderColor: '#ff9900',
            tension: 0.4
        }]
    }
});
```

### Add Custom Risk Fields

Extend the risk data structure in `scripts/generate-html-report.py`:

```python
risk_cards_html += f"""
    <div class="risk-card {severity_class}">
        <!-- Existing fields -->
        <div class="custom-field">
            <strong>Owner Team:</strong> {risk.get('owner', 'N/A')}
        </div>
        <div class="custom-field">
            <strong>Due Date:</strong> {risk.get('deadline', 'N/A')}
        </div>
    </div>
"""
```

---

## Troubleshooting

### Issue 1: HTML File Cannot Display Charts

**Cause**: Chart.js or Mermaid CDN loading failure

**Solution**:
```bash
# Download Chart.js locally
curl -o chart.min.js https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js

# Modify HTML template to reference local file
<script src="./chart.min.js"></script>
```

### Issue 2: Character Encoding Issues

**Cause**: File encoding is not UTF-8

**Solution**:
```python
# Ensure saving with UTF-8 encoding
with open(output_file, 'w', encoding='utf-8') as f:
    f.write(html_output)
```

### Issue 3: Mermaid Diagrams Not Rendering

**Cause**: Mermaid syntax errors

**Solution**:
```bash
# Validate syntax in Mermaid Live Editor
# https://mermaid.live/

# Check common errors:
# - Missing line breaks
# - Unescaped quotes
# - Unhandled special characters
```

---

## Performance Optimization

### Reduce Report File Size

```python
# Only include Top 10 risks (not all)
for risk in risks[:10]:
    # Generate risk cards

# Compress Mermaid diagrams (remove extra spaces and comments)
diagram = re.sub(r'\s+', ' ', diagram).strip()
```

### Speed Up Loading

```html
<!-- Use CDN caching -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>

<!-- Or use local files -->
<script src="./assets/chart.min.js"></script>
```

---

## Comparison: Old vs. New Report Methods

| Feature | Old Method (Basic HTML) | New Method (Interactive Template) |
|---------|------------------------|----------------------------------|
| Generation | Pandoc/Python markdown | Custom template + Python |
| Visualization | Static text | Chart.js interactive charts |
| Risk Display | Tables | Color-coded cards + scores |
| Architecture Diagrams | Mermaid text | Renderable Mermaid diagrams |
| Design Style | GitHub Markdown CSS | AWS brand style |
| Responsive | Basic | Fully responsive |
| Print Support | Limited | Optimized print styles |
| File Size | ~50KB | ~80KB |
| Browser Compatibility | All modern browsers | All modern browsers |

---

## Best Practices

### 1. Data Accuracy

- Validate all data fields before generating the report
- Use clear scoring criteria (1-5 stars)
- Ensure risk priority ranking is correct

### 2. Report Readability

- Limit the number of displayed risks (Top 10-15)
- Use concise risk descriptions
- Provide clear improvement recommendations

### 3. Version Management

- Include date in filename
- Save historical assessment reports to track improvements
- Note version information at the end of reports

### 4. Sharing and Presentation

- Share HTML files with the team (no additional dependencies needed)
- Print or export to PDF from browser
- Use interactive charts in review meetings

---

## Example Output

The generated HTML report will contain:

### 1. Header Information
```
Project Name: E-Commerce System
Assessment Date: 2026-03-03
Overall Score: 4.2/5.0
```

### 2. Statistics Dashboard
```
[15]        [3]         [15 min]    [$2,500]
Total Risks Critical    Current RTO  Est. Cost/mo
```

### 3. Interactive Charts
- Radar chart: 9-dimension resilience assessment
- Doughnut chart: Risk category distribution
- Bar chart: Top 10 risk priorities
- Scatter chart: Cost vs. benefit analysis

### 4. Risk Inventory
- Color-coded cards (red/orange/yellow/green)
- Risk scores and priorities
- Current state and improvement recommendations
- Estimated cost and implementation timeline

### 5. Architecture Visualization
- Current architecture Mermaid diagram
- Dependency diagram
- Improved architecture comparison

---

## Changelog

### v1.0.0 (2026-03-03)
- Created interactive HTML report template
- Integrated Chart.js 4.4.0 interactive charts
- Added Mermaid 10 architecture diagram support
- Implemented color-coded risk cards
- Created Python report generator
- Updated SKILL.md report generation workflow
- Added responsive design and print styles

---

## Support and Feedback

For questions or suggestions:

1. See `SKILL.md` / `SKILL_EN.md` for the complete workflow
2. See `README.md` / `README_EN.md` for Skill basic information
3. See `resilience-framework.md` / `resilience-framework_en.md` for the assessment framework
4. Run `python3 scripts/generate-html-report.py` to see an example report

---

**Created**: 2026-03-03
**Version**: 1.0.0
**Maintainer**: AWS Resilience Assessment Skill
