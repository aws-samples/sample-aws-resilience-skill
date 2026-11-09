#!/usr/bin/env bash
# validate-skill.sh — Static integrity validation for the chaos-engineering-on-aws skill
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
WARN=0

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1"; }
warn() { ((WARN++)); echo "  ⚠️  $1"; }

echo "═══════════════════════════════════════════════════════════════"
echo "  Chaos Engineering Skill — 静态验证"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ─── 1. JSON template syntax ──────────────────────────────────────
echo "【1】JSON 模板语法验证"
for f in "$SKILL_DIR"/references/templates/*.json; do
    if jq empty "$f" 2>/dev/null; then
        pass "$(basename "$f") — JSON 语法正确"
    else
        fail "$(basename "$f") — JSON 语法错误"
    fi
done
# Also syntax-check fis-templates (upstream fis-template-library integration)
fis_tpl_bad=0
fis_tpl_total=0
while IFS= read -r f; do
    ((fis_tpl_total++))
    if ! jq empty "$f" 2>/dev/null; then
        fail "fis-templates/${f#*fis-templates/} — JSON 语法错误"
        ((fis_tpl_bad++))
    fi
done < <(find "$SKILL_DIR/references/fis-templates" -name "*.json" 2>/dev/null)
if [[ $fis_tpl_total -gt 0 && $fis_tpl_bad -eq 0 ]]; then
    pass "references/fis-templates/ 全部 $fis_tpl_total 个 JSON 语法正确"
fi

# ─── 2. FIS template structure (required fields) ──────────────────
echo ""
echo "【2】FIS 模板结构验证(必需字段)"
for f in "$SKILL_DIR"/references/templates/*.json; do
    fname=$(basename "$f")
    # Must contain actions, targets, stopConditions, roleArn
    for field in actions targets stopConditions roleArn; do
        if jq -e ".$field" "$f" >/dev/null 2>&1; then
            pass "$fname — 包含 .$field"
        else
            fail "$fname — 缺失 .$field"
        fi
    done
    
    # Every action must have an actionId and targets
    action_count=$(jq '.actions | length' "$f")
    for key in $(jq -r '.actions | keys[]' "$f"); do
        if jq -e ".actions[\"$key\"].actionId" "$f" >/dev/null 2>&1; then
            pass "$fname → action '$key' 有 actionId"
        else
            # aws:fis:wait also carries an actionId
            fail "$fname → action '$key' 缺失 actionId"
        fi
    done
    echo "  📊 $fname: $action_count 个 action"
done

# ─── 3. startAfter reference integrity ────────────────────────────
echo ""
echo "【3】startAfter 引用完整性(action 名称必须存在)"
for f in "$SKILL_DIR"/references/templates/*.json; do
    fname=$(basename "$f")
    all_actions=$(jq -r '.actions | keys[]' "$f")
    broken=0
    for key in $(jq -r '.actions | keys[]' "$f"); do
        starts=$(jq -r ".actions[\"$key\"].startAfter // [] | .[]" "$f" 2>/dev/null)
        for dep in $starts; do
            if echo "$all_actions" | grep -qx "$dep"; then
                pass "$fname → '$key' startAfter '$dep' 存在"
            else
                fail "$fname → '$key' startAfter '$dep' 不存在！悬空引用"
                ((broken++))
            fi
        done
    done
    if [[ $broken -eq 0 ]]; then
        pass "$fname — 所有 startAfter 引用完整"
    fi
done

# ─── 4. Placeholder consistency ───────────────────────────────────
echo ""
echo "【4】占位符格式验证(必须是 {{name}} 格式)"
for f in "$SKILL_DIR"/references/templates/*.json; do
    fname=$(basename "$f")
    placeholders=$(grep -oE '\{\{[a-zA-Z_]+\}\}' "$f" | sort -u)
    count=$(echo "$placeholders" | grep -c . || true)
    echo "  📋 $fname: $count 个占位符"
    for p in $placeholders; do
        pass "$fname — 占位符 $p 格式正确"
    done
    # Detect malformed placeholders (e.g. single-brace {name})
    bad=$(grep -oE '\{+[a-zA-Z_]+\}+' "$f" | sort -u | grep -vE '^\{\{[a-zA-Z_]+\}\}$' || true)
    if [[ -n "$bad" ]]; then
        fail "$fname — 不规范占位符: $bad"
    fi
done

# ─── 5. YAML syntax ───────────────────────────────────────────────
echo ""
echo "【5】fault-catalog.yaml 语法验证"
if ! python3 -c "import yaml" 2>/dev/null; then
    warn "python3/pyyaml 不可用 — 跳过 YAML 语法验证(pip install pyyaml)"
elif python3 -c "import yaml; yaml.safe_load(open('$SKILL_DIR/references/fault-catalog.yaml'))" 2>/dev/null; then
    pass "fault-catalog.yaml — YAML 语法正确"
else
    fail "fault-catalog.yaml — YAML 语法错误"
fi
# Count entries (no pyyaml dependency)
total=$(grep -c "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" || true)
fis=$(grep -A1 "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | grep -c "backend: fis$" || true)
cm=$(grep -A1 "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | grep -c "backend: chaosmesh" || true)
scenario=$(grep -A1 "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | grep -c "backend: fis-scenario" || true)
echo "  📊 总计 $total 个 fault (FIS: $fis, CM: $cm, Scenario: $scenario)"
# Compare against the count claimed in README (no hardcoded 42)
readme_claim=$(grep -oE 'Fault Catalog Summary: [0-9]+' "$SKILL_DIR/README.md" | grep -oE '[0-9]+' | head -1)
if [[ -z "$readme_claim" ]]; then
    warn "README.md 未找到 'Fault Catalog Summary: N' 声明 — 跳过数量比对"
elif [[ $total -eq $readme_claim ]]; then
    pass "fault 总数 = $total(与 README 声明一致)"
else
    fail "fault 总数 = $total(README 声称 $readme_claim)"
fi

# ─── 6. Shell script syntax ───────────────────────────────────────
echo ""
echo "【6】Shell 脚本语法验证"
for f in "$SKILL_DIR"/scripts/*.sh; do
    if bash -n "$f" 2>/dev/null; then
        pass "$(basename "$f") — bash 语法正确"
    else
        fail "$(basename "$f") — bash 语法错误"
    fi
done

# ─── 7. Markdown internal links ───────────────────────────────────
echo ""
echo "【7】Markdown 内部链接验证(README → 文件是否存在)"
for readme in README.md README_zh.md; do
    echo "  --- $readme ---"
    # Extract relative paths from Markdown links
    links=$(grep -oE '\]\([^)]+\)' "$SKILL_DIR/$readme" | sed 's/^](//; s/)$//' | grep -v '^http' | sort -u)
    for link in $links; do
        target="$SKILL_DIR/$link"
        if [[ -e "$target" ]]; then
            pass "$readme → $link 存在"
        else
            fail "$readme → $link 不存在！"
        fi
    done
done

# ─── 8. EN/ZH section alignment ───────────────────────────────────
echo ""
echo "【8】SKILL 中英文章节对齐"
# After refactoring, SKILL files are ~120 lines directory-style. Check section headers match.
zh_sections=$(grep "^## " "$SKILL_DIR/SKILL_ZH.md" | wc -l)
en_sections=$(grep "^## " "$SKILL_DIR/SKILL_EN.md" | wc -l)
if [[ "$zh_sections" -eq "$en_sections" ]]; then
    pass "SKILL_ZH.md 与 SKILL_EN.md 顶级章节数一致(各 $zh_sections 个)"
else
    fail "顶级章节数不一致！ZH=$zh_sections EN=$en_sections"
fi

# ─── 9. EN/ZH example file pairing ────────────────────────────────
echo ""
echo "【9】示例文件中英文配对"
for en in "$SKILL_DIR"/examples/*[!_zh].md; do
    base=$(basename "$en" .md)
    zh="$SKILL_DIR/examples/${base}_zh.md"
    if [[ -f "$zh" ]]; then
        pass "$base — 中英文都存在"
    else
        warn "$base — 缺少中文版 ${base}_zh.md"
    fi
done

# ─── 10. experiment-runner.sh CM CR existence check ───────────────
echo ""
echo "【10】experiment-runner.sh — CM CR 存在性检查"
if grep -q "CR not found" "$SKILL_DIR/scripts/experiment-runner.sh"; then
    pass "包含 CR 存在性检查逻辑"
else
    fail "缺少 CR 存在性检查"
fi
if grep -q "ABORTED" "$SKILL_DIR/scripts/experiment-runner.sh"; then
    pass "包含 ABORTED 状态输出"
else
    fail "缺少 ABORTED 状态"
fi

# ─── 11. FIS template action→target references ────────────────────
echo ""
echo "【11】FIS 模板 action→target 引用验证"
for f in "$SKILL_DIR"/references/templates/*.json; do
    fname=$(basename "$f")
    all_targets=$(jq -r '.targets | keys[]' "$f")
    for key in $(jq -r '.actions | keys[]' "$f"); do
        action_targets=$(jq -r ".actions[\"$key\"].targets // {} | values[]" "$f" 2>/dev/null)
        for t in $action_targets; do
            if echo "$all_targets" | grep -qx "$t"; then
                pass "$fname → action '$key' target '$t' 已定义"
            else
                fail "$fname → action '$key' 引用了未定义的 target '$t'"
            fi
        done
    done
done

# ─── 12. SKILL file line count (context management) ───────────────
echo ""
echo "【12】SKILL 文件行数检查(目录模式 ≤ 150 行)"
for f in SKILL_EN.md SKILL_ZH.md; do
    lines=$(wc -l < "$SKILL_DIR/$f")
    if [[ $lines -le 150 ]]; then
        pass "$f — $lines 行(≤ 150，目录模式 ✓)"
    else
        fail "$f — $lines 行(> 150，应精简为目录+指针)"
    fi
done

# ─── 13. Required new files existence ─────────────────────────────
echo ""
echo "【13】新增文件存在性检查"
for f in "references/workflow-guide.md" "references/workflow-guide_zh.md" "scripts/README.md"; do
    if [[ -f "$SKILL_DIR/$f" ]]; then
        pass "$f 存在"
    else
        fail "$f 不存在"
    fi
done

# ─── 14. fault-catalog quick index ────────────────────────────────
echo ""
echo "【14】fault-catalog.yaml 快速索引"
if grep -q "Quick Index" "$SKILL_DIR/references/fault-catalog.yaml"; then
    pass "fault-catalog.yaml 包含 Quick Index"
else
    fail "fault-catalog.yaml 缺少 Quick Index"
fi

# ─── 15. doc/ exclusion statement ─────────────────────────────────
echo ""
echo "【15】doc/ 排除声明"
if grep -qi "internal\|NOT needed\|不需要" "$SKILL_DIR/SKILL_EN.md"; then
    pass "SKILL_EN.md 包含 doc/ 排除声明"
else
    fail "SKILL_EN.md 缺少 doc/ 排除声明"
fi
if grep -qi "internal\|不需要\|内部" "$SKILL_DIR/SKILL_ZH.md"; then
    pass "SKILL_ZH.md 包含 doc/ 排除声明"
else
    fail "SKILL_ZH.md 缺少 doc/ 排除声明"
fi

# ─── 16. v1.4.0 new scripts existence ─────────────────────────────
echo ""
echo "【16】v1.4.0 新脚本存在性"
for script in update-dashboard.sh render-dashboard.sh; do
    if [[ -f "$SKILL_DIR/scripts/$script" ]]; then
        pass "scripts/$script 存在"
        if bash -n "$SKILL_DIR/scripts/$script" 2>/dev/null; then
            pass "scripts/$script 语法正确"
        else
            fail "scripts/$script 语法错误"
        fi
    else
        fail "scripts/$script 缺失"
    fi
done

# ─── 17. New script flags ─────────────────────────────────────────
echo ""
echo "【17】脚本新参数验证"
if grep -q -- "--one-shot" "$SKILL_DIR/scripts/experiment-runner.sh"; then
    pass "experiment-runner.sh 支持 --one-shot"
else
    fail "experiment-runner.sh 缺少 --one-shot"
fi
if grep -q -- "--deployment" "$SKILL_DIR/scripts/experiment-runner.sh"; then
    pass "experiment-runner.sh 支持 --deployment"
else
    fail "experiment-runner.sh 缺少 --deployment"
fi
if grep -q -- "--pod-label" "$SKILL_DIR/scripts/experiment-runner.sh"; then
    pass "experiment-runner.sh 支持 --pod-label"
else
    fail "experiment-runner.sh 缺少 --pod-label"
fi

# ─── 18. monitor.sh Chaos Mesh mode ───────────────────────────────
echo ""
echo "【18】monitor.sh Chaos Mesh 模式"
if grep -q "EXPERIMENT_ID.*not set\|metrics-only\|FIS status checks disabled" "$SKILL_DIR/scripts/monitor.sh"; then
    pass "monitor.sh 支持无 EXPERIMENT_ID 模式"
else
    fail "monitor.sh 不支持无 EXPERIMENT_ID 模式"
fi
if grep -q 'INTERVAL=.*15' "$SKILL_DIR/scripts/monitor.sh"; then
    pass "monitor.sh 默认 INTERVAL=15"
else
    warn "monitor.sh 默认 INTERVAL 可能不是 15s"
fi

# ─── 19. log-collector SIGTERM handling ───────────────────────────
echo ""
echo "【19】log-collector SIGTERM 处理"
if grep -q "sleep.*&" "$SKILL_DIR/scripts/log-collector.sh"; then
    pass "log-collector.sh 使用可中断 sleep 模式"
else
    fail "log-collector.sh 未使用可中断 sleep 模式"
fi
if grep -q "exit 0" "$SKILL_DIR/scripts/log-collector.sh"; then
    pass "log-collector.sh cleanup 包含 exit 0"
else
    fail "log-collector.sh cleanup 缺少 exit 0"
fi

# ─── 20. EN/ZH doc sync ───────────────────────────────────────────
echo ""
echo "【20】中英文文档同步检查"
latest_ver=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$SKILL_DIR/README.md" | sort -V | tail -1)
if [[ -z "$latest_ver" ]]; then
    warn "README.md 未找到版本号 — 跳过 changelog 同步检查"
elif grep -q "$latest_ver" "$SKILL_DIR/README_zh.md"; then
    pass "README 中英文均包含 $latest_ver changelog"
else
    fail "README_zh.md 缺少最新版本 $latest_ver 的 changelog"
fi
en_sync=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$SKILL_DIR/SKILL_EN.md" | head -1)
zh_sync=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$SKILL_DIR/SKILL_ZH.md" | head -1)
if [[ -n "$en_sync" && "$en_sync" == "$zh_sync" ]]; then
    pass "SKILL 中英文 Last sync 均为 $en_sync"
else
    fail "SKILL 中英文 Last sync 不同步(EN=$en_sync ZH=$zh_sync)"
fi
if grep -q "MANDATORY" "$SKILL_DIR/references/workflow-guide_zh.md"; then
    pass "workflow-guide_zh.md 包含 MANDATORY log-collector"
else
    fail "workflow-guide_zh.md 缺少 MANDATORY log-collector"
fi
if grep -q "6.0.5" "$SKILL_DIR/references/report-templates_zh.md"; then
    pass "report-templates_zh.md 包含 §6.0.5 数据完整性检查"
else
    fail "report-templates_zh.md 缺少 §6.0.5"
fi
if grep -qi "常见错误\|静默失败" "$SKILL_DIR/references/fis-actions_zh.md"; then
    pass "fis-actions_zh.md 包含 Lambda env var 警告"
else
    fail "fis-actions_zh.md 缺少 Lambda env var 警告"
fi

# ─── 21. Code→docs: script flags covered in README ────────────────
echo ""
echo "【21】代码→文档：脚本 CLI 参数在文档中有描述"

# Extract all --flags from experiment-runner.sh argument parser (case block only)
# Filter out jq flags, kubectl flags, and other non-CLI parameters
runner_flags=$(sed -n '/while.*\$#.*gt.*0/,/esac/p' "$SKILL_DIR/scripts/experiment-runner.sh" \
    | grep -oE -- '--[a-z][-a-z]*\)' | sed 's/^--//; s/)$//' | grep -v '^help$' | sort -u)
for flag in $runner_flags; do
    # Check scripts/README.md
    if grep -qi -- "--$flag" "$SKILL_DIR/scripts/README.md"; then
        pass "experiment-runner --$flag → scripts/README.md ✓"
    else
        fail "experiment-runner --$flag → scripts/README.md 未描述"
    fi
done

# Extract env vars from monitor.sh (user-configurable ones at the top of the file, before first function)
# Only check the first 30 lines where defaults are declared
# Exclude internal vars (OUTPUT_FILE, CUSTOM_METRICS_FILE) that aren't user-configurable
monitor_vars=$(head -40 "$SKILL_DIR/scripts/monitor.sh" | grep -oE '^[A-Z_]+="\$\{' | sed 's/="\${$//' \
    | grep -vE '^(OUTPUT_FILE|CUSTOM_METRICS_FILE)$' | sort -u)
for var in $monitor_vars; do
    if grep -q "$var" "$SKILL_DIR/scripts/README.md"; then
        pass "monitor.sh \$$var → scripts/README.md ✓"
    else
        fail "monitor.sh \$$var → scripts/README.md 未描述"
    fi
done

# Extract --flags from log-collector.sh argument parser (case block only)
lc_flags=$(sed -n '/while.*\$#.*gt.*0/,/esac/p' "$SKILL_DIR/scripts/log-collector.sh" \
    | grep -oE -- '--[a-z][-a-z]*\)' | sed 's/^--//; s/)$//' | sort -u | grep -v '^help$')
for flag in $lc_flags; do
    if grep -qi -e "--$flag" -e "$flag" "$SKILL_DIR/scripts/README.md"; then
        pass "log-collector --$flag → scripts/README.md ✓"
    else
        fail "log-collector --$flag → scripts/README.md 未描述"
    fi
done

# Extract --flags from discover-dependencies.sh argument parser (case block only)
dd_flags=$(sed -n '/while.*\$#.*gt.*0/,/esac/p' "$SKILL_DIR/scripts/discover-dependencies.sh" \
    | grep -oE -- '--[a-z][-a-z]*\)' | sed 's/^--//; s/)$//' | sort -u | grep -v '^help$')
for flag in $dd_flags; do
    if grep -q -- "--$flag" "$SKILL_DIR/scripts/README.md"; then
        pass "discover-dependencies --$flag → scripts/README.md ✓"
    else
        fail "discover-dependencies --$flag → scripts/README.md 未描述"
    fi
done

# ─── 22. Docs→code: README-claimed flags exist in code ────────────
echo ""
echo "【22】文档→代码：scripts/README.md 声称的参数在代码中存在"

# Extract --flags from scripts/README.md tables (| `--xxx` | pattern)
readme_runner_flags=$(grep -oE '\| `--[a-z][-a-z]*' "$SKILL_DIR/scripts/README.md" | sed 's/^| `--//' | sort -u)
for flag in $readme_runner_flags; do
    found=0
    for script in experiment-runner.sh log-collector.sh monitor.sh discover-dependencies.sh; do
        if grep -q -- "--$flag" "$SKILL_DIR/scripts/$script" 2>/dev/null; then
            found=1
            break
        fi
    done
    # Also check env var style (for monitor.sh vars documented as flags)
    if [[ $found -eq 0 ]]; then
        upper_flag=$(echo "$flag" | tr '[:lower:]-' '[:upper:]_')
        for script in monitor.sh experiment-runner.sh log-collector.sh; do
            if grep -q "$upper_flag" "$SKILL_DIR/scripts/$script" 2>/dev/null; then
                found=1
                break
            fi
        done
    fi
    if [[ $found -eq 1 ]]; then
        pass "README --$flag → 代码中存在"
    else
        fail "README --$flag → 代码中不存在(幽灵参数)"
    fi
done

# ─── 23. EN/ZH technical term alignment ───────────────────────────
echo ""
echo "【23】中英文关键术语对齐"

# Key technical terms that must appear in both EN and ZH versions
declare -A doc_pairs=(
    ["README.md"]="README_zh.md"
    ["SKILL_EN.md"]="SKILL_ZH.md"
    ["references/workflow-guide.md"]="references/workflow-guide_zh.md"
    ["references/fis-actions.md"]="references/fis-actions_zh.md"
    ["references/report-templates.md"]="references/report-templates_zh.md"
    ["examples/03-eks-pod-kill.md"]="examples/03-eks-pod-kill_zh.md"
)

# Technical terms that should be language-neutral (same in both EN and ZH)
tech_terms=("state.json" "dashboard.md" "one-shot" "EXPERIMENT_ID" "metric-queries.json" "flock" "SIGTERM" "experiment-runner.sh" "monitor.sh" "log-collector.sh" "render-dashboard.sh" "update-dashboard.sh")

for en_file in "${!doc_pairs[@]}"; do
    zh_file="${doc_pairs[$en_file]}"
    [[ ! -f "$SKILL_DIR/$en_file" || ! -f "$SKILL_DIR/$zh_file" ]] && continue
    for term in "${tech_terms[@]}"; do
        en_has=$(grep -cF "$term" "$SKILL_DIR/$en_file" 2>/dev/null)
        zh_has=$(grep -cF "$term" "$SKILL_DIR/$zh_file" 2>/dev/null)
        en_has=${en_has:-0}
        zh_has=${zh_has:-0}
        if [[ "$en_has" -gt 0 && "$zh_has" -eq 0 ]]; then
            fail "$(basename "$en_file") 有 '$term' (${en_has}次) 但 $(basename "$zh_file") 没有"
        elif [[ "$en_has" -gt 0 && "$zh_has" -gt 0 ]]; then
            pass "$(basename "$en_file") ↔ $(basename "$zh_file"): '$term' ✓"
        fi
        # Don't flag if EN doesn't have it either (not relevant for this file pair)
    done
done

# ─── 24. Numeric consistency: extract from code → compare docs ────
echo ""
echo "【24】数字一致性"

# Count scripts in scripts/ (excluding README.md)
actual_scripts=$(find "$SKILL_DIR/scripts" -name "*.sh" -o -name "*.conf" | wc -l)
echo "  📊 实际脚本数: $actual_scripts"

# Count fault types from YAML (grep-based; no pyyaml dependency)
total_faults=$(grep -c "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" || true)
fis_count=$(grep -A1 "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | grep -c "backend: fis$" || true)
echo "  📊 实际 fault 数: $total_faults (FIS=$fis_count)"

# Check all files that mention fault counts
if [[ "$total_faults" -eq 0 ]]; then
    warn "fault-catalog.yaml 统计为 0 — 跳过文档数量比对(结构可能已变化)"
else
for doc in README.md README_zh.md SKILL_EN.md SKILL_ZH.md references/fault-catalog.yaml; do
    if grep -q "$total_faults" "$SKILL_DIR/$doc" 2>/dev/null; then
        pass "$(basename "$doc") fault 数量 = $total_faults ✓"
    else
        if grep -qE "[0-9]+ [Ff]ault|[0-9]+ 个故障|[0-9]+ 种故障|[0-9]+ faults" "$SKILL_DIR/$doc" 2>/dev/null; then
            wrong_num=$(grep -oE "[0-9]+ ([Ff]aults?|个故障|种故障)" "$SKILL_DIR/$doc" | grep -oE '^[0-9]+' | head -1)
            fail "$(basename "$doc") fault 数量 = $wrong_num(实际 $total_faults)"
        fi
        # No mention = OK (not all files need to state the count)
    fi
done
fi

# Count example files
en_examples=$(ls "$SKILL_DIR/examples/"*.md 2>/dev/null | grep -v "_zh" | wc -l)
zh_examples=$(ls "$SKILL_DIR/examples/"*_zh.md 2>/dev/null | wc -l)
if [[ $en_examples -eq $zh_examples ]]; then
    pass "示例文件中英文数量一致 ($en_examples 对)"
else
    fail "示例文件中英文不一致 (EN=$en_examples, ZH=$zh_examples)"
fi

# Count reference docs
en_refs=$(ls "$SKILL_DIR/references/"*.md 2>/dev/null | grep -v "_zh" | wc -l)
zh_refs=$(ls "$SKILL_DIR/references/"*_zh.md 2>/dev/null | wc -l)
if [[ $en_refs -eq $zh_refs ]]; then
    pass "参考文档中英文数量一致 ($en_refs 对)"
else
    fail "参考文档中英文不一致 (EN=$en_refs, ZH=$zh_refs)"
fi

# ─── 25. Offline script tests ─────────────────────────────────────
echo ""
echo "【25】脚本离线测试(scripts/tests/,bash + jq,aws/kubectl 为桩)"
for t in "$SKILL_DIR"/scripts/tests/test-*.sh; do
    [[ -f "$t" ]] || continue
    if out=$(bash "$t" 2>&1); then
        pass "$(basename "$t") — $(echo "$out" | grep -E '结果' | tail -1 | sed 's/^ *//')"
    else
        fail "$(basename "$t") — $(echo "$out" | grep -E '❌' | head -3 | tr '\n' ' ')"
    fi
done

# ─── 26. EN/ZH structure parity ───────────────────────────────────
# Counting files in pairs (【9】【24】) did not catch a ZH guide that had silently
# lost whole sections; compare the structure itself: headings, fenced blocks and
# table rows outside fences must match between each EN file and its _zh twin.
echo ""
echo "【26】中英文结构对齐(标题 / 代码块 / 表格行)"
if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 不可用 — 跳过结构对齐检查"
else
    while IFS=$'\t' read -r status name detail; do
        if [[ "$status" == "OK" ]]; then pass "$name ↔ _zh 结构一致 ($detail)"; else fail "$name ↔ _zh 结构不一致: $detail"; fi
    done < <(python3 - "$SKILL_DIR" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
def stats(p):
    h = f = t = 0; fence = False
    for line in open(p, encoding="utf-8"):
        if line.lstrip().startswith("```"):
            f += 1; fence = not fence; continue
        if fence: continue
        if re.match(r"#{1,6} ", line): h += 1
        if line.lstrip().startswith("|"): t += 1
    return h, f, t
ens = sorted(glob.glob(root + "/references/*.md") + glob.glob(root + "/examples/*.md")) + \
      [root + "/README.md", root + "/SKILL_EN.md", root + "/MCP_SETUP_GUIDE.md"]
for en in ens:
    if en.endswith("_zh.md"): continue
    zh = root + "/SKILL_ZH.md" if en.endswith("SKILL_EN.md") else en[:-3] + "_zh.md"
    if not os.path.exists(zh): continue
    a, b = stats(en), stats(zh)
    name = os.path.relpath(en, root)
    if a == b: print(f"OK\t{name}\theadings={a[0]} fences={a[1]} table-rows={a[2]}")
    else: print(f"DIFF\t{name}\tEN headings/fences/table-rows={a} ZH={b}")
PY
)
fi

# ─── 27. FIS action IDs against the official list ─────────────────
echo ""
echo "【27】FIS action ID 对照官方清单(references/fis-official-ids.txt)"
OFFICIAL="$SKILL_DIR/references/fis-official-ids.txt"
if [[ ! -f "$OFFICIAL" ]]; then
    fail "references/fis-official-ids.txt 不存在"
else
    bad_ids=$( {
        grep -rhoE '"actionId"[[:space:]]*:[[:space:]]*"aws:[a-z0-9-]+:[a-z0-9-]+"' \
            "$SKILL_DIR/references/templates" "$SKILL_DIR/references/fis-templates" 2>/dev/null | grep -oE 'aws:[a-z0-9-]+:[a-z0-9-]+'
        grep -hoE 'fis_action_id:[[:space:]]*"?aws:[a-z0-9-]+:[a-z0-9-]+' "$SKILL_DIR/references/fault-catalog.yaml" | grep -oE 'aws:[a-z0-9-]+:[a-z0-9-]+'
        grep -hE '^[[:space:]]+- aws:[a-z0-9-]+:[a-z0-9-]+' "$SKILL_DIR/references/fault-catalog.yaml" | grep -oE 'aws:[a-z0-9-]+:[a-z0-9-]+'
      } | sort -u | grep -vxF -f <(grep -v '^#' "$OFFICIAL") || true)
    checked=$( {
        grep -rhoE '"actionId"[[:space:]]*:[[:space:]]*"aws:[a-z0-9-]+:[a-z0-9-]+"' "$SKILL_DIR/references/templates" "$SKILL_DIR/references/fis-templates" 2>/dev/null
        grep -hoE 'fis_action_id:[[:space:]]*"?aws:[a-z0-9-]+:[a-z0-9-]+' "$SKILL_DIR/references/fault-catalog.yaml"
        grep -hE '^[[:space:]]+- aws:[a-z0-9-]+:[a-z0-9-]+' "$SKILL_DIR/references/fault-catalog.yaml"
      } | wc -l | tr -d ' ')
    if [[ -z "$bad_ids" ]]; then
        pass "模板与 fault-catalog 中 $checked 处 action ID 全部在官方清单内"
    else
        for id in $bad_ids; do fail "不在官方清单内的 action ID: $id"; done
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  验证结果：✅ $PASS passed | ❌ $FAIL failed | ⚠️  $WARN warnings"
echo "═══════════════════════════════════════════════════════════════"

exit $FAIL
