#!/usr/bin/env bash
# validate-skill.sh — 静态验证 chaos-engineering-on-aws skill 的完整性
set -uo pipefail

SKILL_DIR="/home/ubuntu/tech/sample-aws-resilience-skill/chaos-engineering-on-aws"
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

# ─── 1. JSON 模板语法 ──────────────────────────────────────────────
echo "【1】JSON 模板语法验证"
for f in "$SKILL_DIR"/references/templates/*.json; do
    if jq empty "$f" 2>/dev/null; then
        pass "$(basename "$f") — JSON 语法正确"
    else
        fail "$(basename "$f") — JSON 语法错误"
    fi
done

# ─── 2. FIS 模板结构验证 ───────────────────────────────────────────
echo ""
echo "【2】FIS 模板结构验证（必需字段）"
for f in "$SKILL_DIR"/references/templates/*.json; do
    fname=$(basename "$f")
    # 必须有 actions, targets, stopConditions, roleArn
    for field in actions targets stopConditions roleArn; do
        if jq -e ".$field" "$f" >/dev/null 2>&1; then
            pass "$fname — 包含 .$field"
        else
            fail "$fname — 缺失 .$field"
        fi
    done
    
    # 每个 action 必须有 actionId 和 targets
    action_count=$(jq '.actions | length' "$f")
    for key in $(jq -r '.actions | keys[]' "$f"); do
        if jq -e ".actions[\"$key\"].actionId" "$f" >/dev/null 2>&1; then
            pass "$fname → action '$key' 有 actionId"
        else
            # aws:fis:wait 也有 actionId
            fail "$fname → action '$key' 缺失 actionId"
        fi
    done
    echo "  📊 $fname: $action_count 个 action"
done

# ─── 3. startAfter 引用完整性 ─────────────────────────────────────
echo ""
echo "【3】startAfter 引用完整性（action 名称必须存在）"
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

# ─── 4. 占位符一致性 ──────────────────────────────────────────────
echo ""
echo "【4】占位符格式验证（必须是 {{name}} 格式）"
for f in "$SKILL_DIR"/references/templates/*.json; do
    fname=$(basename "$f")
    placeholders=$(grep -oP '\{\{[a-zA-Z_]+\}\}' "$f" | sort -u)
    count=$(echo "$placeholders" | grep -c . || true)
    echo "  📋 $fname: $count 个占位符"
    for p in $placeholders; do
        pass "$fname — 占位符 $p 格式正确"
    done
    # 检查有没有不规范的占位符（如 {name} 单大括号）
    bad=$(grep -oP '(?<!\{)\{[a-zA-Z_]+\}(?!\})' "$f" 2>/dev/null || true)
    if [[ -n "$bad" ]]; then
        fail "$fname — 不规范占位符: $bad"
    fi
done

# ─── 5. YAML 语法 ────────────────────────────────────────────────
echo ""
echo "【5】fault-catalog.yaml 语法验证"
if python3 -c "import yaml; yaml.safe_load(open('$SKILL_DIR/references/fault-catalog.yaml'))" 2>/dev/null; then
    pass "fault-catalog.yaml — YAML 语法正确"
    # 统计条目
    total=$(grep "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | wc -l)
    fis=$(grep -A1 "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | grep "backend: fis$" | wc -l)
    cm=$(grep -A1 "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | grep "backend: chaosmesh" | wc -l)
    scenario=$(grep -A1 "^  - type:" "$SKILL_DIR/references/fault-catalog.yaml" | grep "backend: fis-scenario" | wc -l)
    echo "  📊 总计 $total 个 fault（FIS: $fis, CM: $cm, Scenario: $scenario）"
    if [[ $total -eq 41 ]]; then
        pass "fault 总数 = 41（与 README 一致）"
    else
        fail "fault 总数 = $total（README 声称 41）"
    fi
else
    fail "fault-catalog.yaml — YAML 语法错误"
fi

# ─── 6. Shell 脚本语法 ───────────────────────────────────────────
echo ""
echo "【6】Shell 脚本语法验证"
for f in "$SKILL_DIR"/scripts/*.sh; do
    if bash -n "$f" 2>/dev/null; then
        pass "$(basename "$f") — bash 语法正确"
    else
        fail "$(basename "$f") — bash 语法错误"
    fi
done

# ─── 7. Markdown 链接验证 ────────────────────────────────────────
echo ""
echo "【7】Markdown 内部链接验证（README → 文件是否存在）"
for readme in README.md README_zh.md; do
    echo "  --- $readme ---"
    # 提取 Markdown 链接中的相对路径
    links=$(grep -oP '\]\((?!http)([^)]+)\)' "$SKILL_DIR/$readme" | sed 's/\](//' | sed 's/)//' | sort -u)
    for link in $links; do
        target="$SKILL_DIR/$link"
        if [[ -e "$target" ]]; then
            pass "$readme → $link 存在"
        else
            fail "$readme → $link 不存在！"
        fi
    done
done

# ─── 8. 中英文章节编号对齐 ────────────────────────────────────────
echo ""
echo "【8】SKILL 中英文章节对齐"
# After refactoring, SKILL files are ~120 lines directory-style. Check section headers match.
zh_sections=$(grep "^## " "$SKILL_DIR/SKILL_ZH.md" | wc -l)
en_sections=$(grep "^## " "$SKILL_DIR/SKILL_EN.md" | wc -l)
if [[ "$zh_sections" -eq "$en_sections" ]]; then
    pass "SKILL_ZH.md 与 SKILL_EN.md 顶级章节数一致（各 $zh_sections 个）"
else
    fail "顶级章节数不一致！ZH=$zh_sections EN=$en_sections"
fi

# ─── 9. 示例文件中英文配对 ────────────────────────────────────────
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

# ─── 10. experiment-runner.sh CM CR 检查逻辑 ─────────────────────
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

# ─── 11. FIS 模板 target 引用验证 ────────────────────────────────
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

# ─── 12. SKILL 文件行数（context management） ────────────────────
echo ""
echo "【12】SKILL 文件行数检查（目录模式 ≤ 150 行）"
for f in SKILL_EN.md SKILL_ZH.md; do
    lines=$(wc -l < "$SKILL_DIR/$f")
    if [[ $lines -le 150 ]]; then
        pass "$f — $lines 行（≤ 150，目录模式 ✓）"
    else
        fail "$f — $lines 行（> 150，应精简为目录+指针）"
    fi
done

# ─── 13. 新增必要文件存在性 ──────────────────────────────────────
echo ""
echo "【13】新增文件存在性检查"
for f in "references/workflow-guide.md" "references/workflow-guide_zh.md" "scripts/README.md"; do
    if [[ -f "$SKILL_DIR/$f" ]]; then
        pass "$f 存在"
    else
        fail "$f 不存在"
    fi
done

# ─── 14. fault-catalog 快速索引 ──────────────────────────────────
echo ""
echo "【14】fault-catalog.yaml 快速索引"
if grep -q "Quick Index" "$SKILL_DIR/references/fault-catalog.yaml"; then
    pass "fault-catalog.yaml 包含 Quick Index"
else
    fail "fault-catalog.yaml 缺少 Quick Index"
fi

# ─── 15. doc/ 目录声明 ──────────────────────────────────────────
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

# ─── Summary ─────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  验证结果：✅ $PASS passed | ❌ $FAIL failed | ⚠️  $WARN warnings"
echo "═══════════════════════════════════════════════════════════════"

exit $FAIL
