# Report Generation Detailed Guide

> This document contains the complete generation workflow, template code, and quality checklist for AWS resilience assessment reports.
> For the main workflow overview, see the "Report Generation Requirements" section in [SKILL_EN.md](../SKILL_EN.md).

---

## Automated Report Generation Workflow

### 1. Generate Markdown Report

Use the Write tool to create a complete markdown report file:

```markdown
Filename Format: {project-name}-resilience-assessment-{date}.md
Example: ecommerce-resilience-assessment-2026-02-28.md

The report should include:
- Complete table of contents (TOC)
- Results from all 8 analysis tasks
- All Mermaid diagrams
- Tables, code blocks, alarm configurations
- Executive summary and key findings
- Implementation roadmap
- Appendices and references
```

### 2. Generate HTML Report (Using Template)

**Recommended Method: Using the Interactive HTML Template**

Use the pre-built HTML template (`assets/html-report-template.html`), which includes:
- AWS brand design style (orange theme)
- Chart.js interactive charts (radar, doughnut, bar, scatter)
- Mermaid architecture diagram support
- Responsive design supporting mobile and print
- Timeline visualization
- Color-coded risk cards

**Generation Steps**:

```python
# Use Python script to populate template data and generate HTML report
python3 << 'EOF'
import json
from pathlib import Path

# 1. Read HTML template
template_path = Path(__file__).parent / 'assets/html-report-template.html'
with open(template_path, 'r', encoding='utf-8') as f:
    html_template = f.read()

# 2. Prepare assessment data (extracted from analysis results)
assessment_data = {
    "projectName": "{project name}",
    "assessmentDate": "{assessment date}",
    "overallScore": {overall score},  # 1-5 score

    # Statistics
    "stats": {
        "totalRisks": {total risk count},
        "criticalRisks": {critical risk count},
        "currentRTO": "{current RTO}",
        "estimatedCost": {estimated monthly cost}
    },

    # Resilience dimension scores (9 dimensions)
    "resilienceDimensions": {
        "redundancy": {redundancy design score},      # 1-5
        "azFaultTolerance": {AZ fault tolerance score},
        "timeoutRetry": {timeout retry score},
        "circuitBreaker": {circuit breaker score},
        "autoScaling": {auto scaling score},
        "configProtection": {config protection score},
        "faultIsolation": {fault isolation score},
        "backupRecovery": {backup recovery score},
        "bestPractices": {best practices score}
    },

    # Risk distribution
    "riskDistribution": {
        "critical": {critical risk count},
        "high": {high risk count},
        "medium": {medium risk count},
        "low": {low risk count}
    },

    # Risk inventory (sorted by priority)
    "risks": [
        {
            "id": "R-001",
            "title": "{risk title}",
            "category": "{failure category}",  # SPOF/Excessive Latency/Excessive Load/Misconfiguration/Shared Fate
            "severity": "critical",     # critical/high/medium/low
            "probability": {probability score},   # 1-5
            "impact": {impact score},       # 1-5
            "detectionDifficulty": {detection difficulty}, # 1-5
            "remediationComplexity": {remediation complexity}, # 1-5
            "riskScore": {risk score},
            "currentState": "{current state description}",
            "recommendation": "{improvement recommendation}",
            "estimatedCost": "{estimated cost}",
            "implementation": "{implementation timeline}"
        }
        // ... more risks
    ],

    # Implementation roadmap (timeline data)
    "roadmap": [
        {
            "phase": "Phase 1: Foundation Resilience",
            "startDate": "2026-03-01",
            "duration": "2 months",
            "tasks": [
                "Multi-AZ deployment",
                "Configure automated backup",
                "Implement baseline monitoring"
            ],
            "milestone": "M1: Baseline redundancy complete"
        }
        // ... more phases
    ],

    # Mermaid architecture diagram code
    "architectureDiagram": "{mermaid diagram code}",
    "dependencyDiagram": "{dependency diagram code}"
}

# 3. Inject data into HTML template (replace placeholders)
html_output = html_template

# Replace basic info
html_output = html_output.replace('{{PROJECT_NAME}}', assessment_data['projectName'])
html_output = html_output.replace('{{ASSESSMENT_DATE}}', assessment_data['assessmentDate'])
html_output = html_output.replace('{{OVERALL_SCORE}}', str(assessment_data['overallScore']))

# Replace statistics
html_output = html_output.replace('{{TOTAL_RISKS}}', str(assessment_data['stats']['totalRisks']))
html_output = html_output.replace('{{CRITICAL_RISKS}}', str(assessment_data['stats']['criticalRisks']))
html_output = html_output.replace('{{CURRENT_RTO}}', assessment_data['stats']['currentRTO'])
html_output = html_output.replace('{{ESTIMATED_COST}}', str(assessment_data['stats']['estimatedCost']))

# Replace Chart.js data
html_output = html_output.replace('{{RESILIENCE_DATA}}', json.dumps(list(assessment_data['resilienceDimensions'].values())))
html_output = html_output.replace('{{RISK_DISTRIBUTION_DATA}}', json.dumps(list(assessment_data['riskDistribution'].values())))

# Generate risk card HTML
risk_cards_html = ""
for risk in assessment_data['risks'][:10]:  # Show only top 10 risks
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
            <div>Probability: {risk['probability']}/5</div>
            <div>Impact: {risk['impact']}/5</div>
            <div>Risk Score: {risk['riskScore']:.1f}</div>
        </div>
        <div class="risk-details">
            <p><strong>Current State:</strong> {risk['currentState']}</p>
            <p><strong>Recommendation:</strong> {risk['recommendation']}</p>
            <div class="risk-footer">
                <span class="badge">Cost: {risk['estimatedCost']}</span>
                <span class="badge">Timeline: {risk['implementation']}</span>
            </div>
        </div>
    </div>
    """

html_output = html_output.replace('{{RISK_CARDS}}', risk_cards_html)

# Replace Mermaid diagrams
html_output = html_output.replace('{{ARCHITECTURE_DIAGRAM}}', assessment_data['architectureDiagram'])

# 4. Save HTML file
output_file = '{project-name}-resilience-assessment-{date}.html'
with open(output_file, 'w', encoding='utf-8') as f:
    f.write(html_output)

print(f'HTML report generated: {output_file}')
print(f'Open in browser to view the interactive report')
EOF
```

**Alternative Method: Basic Conversion with Pandoc**

For a quick basic HTML version:

```bash
pandoc {report-file}.md \
  -f gfm \
  -t html5 \
  --standalone \
  --toc \
  --toc-depth=3 \
  --css=https://cdn.jsdelivr.net/npm/github-markdown-css@5/github-markdown.min.css \
  --metadata title="AWS System Resilience Assessment Report" \
  -o {report-file}-basic.html
```

### 3. Generate Chaos Engineering Data (When User Selects)

If the user selects a chaos engineering test plan, generate structured data according to the `references/assessment-output-spec_en.md` specification:

**Method 1: Standalone File Mode (Recommended)**
```markdown
Filename: {project-name}-chaos-input-{date}.md
Example: ecommerce-chaos-input-2026-02-28.md

Content: Generated according to the assessment-output-spec.md specification structure,
including all 8 structured sections: project metadata, AWS resource inventory (with ARNs),
business function dependency chains, risk inventory (with experiment-readiness flags and
suggested injection methods), risk details, monitoring readiness, resilience scores
(9 dimensions), constraints and preferences
```

The main report (Markdown and HTML) should **NOT duplicate the full chaos engineering data**. Instead, add a brief reference at the appropriate location:
```markdown
> Chaos engineering test plan details: see standalone file [{project-name}-chaos-input-{date}.md]({project-name}-chaos-input-{date}.md)
```

**Method 2: Embedded Mode** (only when user explicitly requests embedding)
Add a `## Chaos Engineering Ready Data` appendix section at the end of the assessment report (Markdown and HTML), one report readable by both humans and machines.

**Chaos Engineering Data in HTML Reports**:
When the user selects a chaos engineering test plan, the HTML report should also include corresponding visualization sections:
- **Testable risk cards**: Risk cards with `Testable` markers and `Suggested Injection Method` labels
- **Monitoring readiness dashboard**: Doughnut chart showing readiness status
- **Injection method distribution chart**: Bar chart showing FIS / Chaos Mesh / Manual / Not Testable distribution
- **Resource ARN inventory table**: Collapsible complete resource inventory with copy buttons
- **Experiment priority matrix**: Scatter chart showing testable risk probability vs. impact

### 4. Report File Location

All generated report files should be saved in the current working directory:

```
{current-working-directory}/
├── {project-name}-resilience-assessment-{date}.md    (Main report Markdown)
├── {project-name}-resilience-assessment-{date}.html   (Main report HTML with interactive charts)
└── {project-name}-chaos-input-{date}.md              (Chaos engineering data, standalone file, generated by default when user selects chaos engineering)
```

---

## Report Quality Checklist

After generating the report, ensure:

- All Mermaid diagrams have correct syntax (renderable in HTML)
- All table formatting is properly aligned
- Code blocks have correct syntax highlighting markers (```bash, ```yaml, ```json, etc.)
- Proper spacing between Chinese and English characters (improves readability)
- All links are valid (internal anchors and external URLs)
- Risk IDs, task IDs, and other references are consistent
- HTML file displays correctly in browser

---

## Completion Prompt

After generating the report, provide the user with:

```markdown
**AWS Resilience Assessment Report Generated**

**Markdown Format**: `{filename}.md`
**Interactive HTML Format**: `{filename}.html`
**Chaos Engineering Data**: `{filename}-chaos-input.md` (if user selected chaos engineering test plan)

**HTML Report Features**:
- AWS brand style design (orange theme)
- Interactive Chart.js charts (radar, doughnut, bar, scatter)
- Color-coded risk cards (red=critical, orange=high, yellow=medium, green=low)
- Responsive design supporting phone/tablet/desktop viewing
- Print-friendly styles
- Timeline visualization for implementation roadmap
- Mermaid architecture diagram support
- Chaos engineering data visualization (testable risk markers, monitoring readiness, injection method distribution, if applicable)

**Key Findings**:
1. {Key risk 1}
2. {Key risk 2}
3. {Key risk 3}

**Priority Recommendations**:
1. {Recommendation 1}
2. {Recommendation 2}
3. {Recommendation 3}

**Estimated Investment**: ${total cost}/month
**Expected Outcome**: Annual downtime reduced from {current} to {target}

You can:
- Open the interactive HTML report in browser for dynamic charts
- Edit and customize the report using a Markdown editor
- Print or export to PDF from browser for sharing
- Share the HTML file with team members (no additional dependencies needed)
- Pass the chaos engineering data file directly to the chaos-engineering-on-aws skill (if applicable)
```

---

## Tool Installation Check

Before attempting HTML generation, check for necessary tools and template files:

```bash
# Check if HTML template file exists
TEMPLATE_PATH="$HOME/.claude/skills/aws-resilience-modeling/assets/html-report-template.html"

if [ -f "$TEMPLATE_PATH" ]; then
    echo "Found interactive HTML template"
    echo "Recommended: Use interactive HTML template for report generation (includes Chart.js visualizations)"
    # Use recommended template method
elif command -v pandoc &> /dev/null; then
    echo "Using pandoc for basic HTML generation"
    echo "Tip: Install html-report-template.html for better-looking reports"
    # Use pandoc alternative method
elif python3 -c "import markdown" 2>/dev/null; then
    echo "Using Python markdown library for basic HTML generation"
    echo "Tip: Install html-report-template.html for better-looking reports"
    # Use Python markdown alternative method
else
    echo "No HTML generation tools found"
    echo "Recommended options:"
    echo "   1. Download html-report-template.html to skill directory (best looking)"
    echo "   2. Install pandoc: brew install pandoc"
    echo "   3. Install Python markdown: pip3 install markdown"
    echo "Markdown report generated, HTML generation skipped"
fi
```

---

## Report Format Notes

**Report Ending Format Requirements**:
- Only include "Report generation date" and "Version" information at the end of the report
- **Do not** add contact information (e.g., email addresses)
- **Do not** add signatures or team information
- Keep the report ending clean and professional

Example correct format:
```markdown
---

**Report Generation Date**: YYYY-MM-DD
**Version**: 1.0
```

---

## Important Reminder

After each analysis, the report generation workflow should be executed automatically so users can:
- Easily view attractive reports in the browser
- Share reports with team members and management
- Save reports as historical records
- Export to PDF for presentations

Do not only output analysis results in conversation -- generate files simultaneously.
