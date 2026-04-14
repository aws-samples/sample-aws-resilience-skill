#!/bin/bash
# validate-all-skills.sh — 全量静态验证脚本
# 用法: cd /home/ubuntu/tech/sample-aws-resilience-skill && bash validate-all-skills.sh

set -uo pipefail
PASS=0; FAIL=0; WARN=0
SKILLS=("aws-resilience-modeling" "aws-rma-assessment" "chaos-engineering-on-aws" "eks-resilience-checker")

pass() { echo "  ✅ $1"; ((PASS++)); }
fail() { echo "  ❌ $1"; ((FAIL++)); }
warn() { echo "  ⚠️  $1"; ((WARN++)); }

echo "═══════════════════════════════════════════════════════════════"
echo "  AWS Resilience Skill Suite — 全量静态验证"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ──────────────────────────────────────────
echo "【1】SKILL.md Frontmatter 检查"
# ──────────────────────────────────────────
for skill in "${SKILLS[@]}"; do
  echo "  --- $skill ---"
  f="$skill/SKILL.md"
  if [[ ! -f "$f" ]]; then
    fail "$f 不存在"
    continue
  fi
  
  # frontmatter 存在
  if head -1 "$f" | grep -q '^---'; then
    pass "$f — frontmatter 存在"
  else
    fail "$f — 缺少 frontmatter"
  fi
  
  # name 字段
  if grep -q '^name:' "$f"; then
    pass "$f — 有 name 字段"
  else
    fail "$f — 缺少 name 字段"
  fi
  
  # description 字段
  if grep -q '^description:' "$f" || grep -q '^description:' "$f"; then
    pass "$f — 有 description 字段"
  else
    fail "$f — 缺少 description 字段"
  fi
  
  # allowed-tools 字段
  if grep -q '^allowed-tools:' "$f"; then
    pass "$f — 有 allowed-tools 字段"
  else
    fail "$f — 缺少 allowed-tools 字段"
  fi
  
  # model 字段
  if grep -q '^model:' "$f"; then
    pass "$f — 有 model 字段"
  else
    fail "$f — 缺少 model 字段"
  fi
done

echo ""
# ──────────────────────────────────────────
echo "【2】SKILL.md ↔ .kiro/skill.md 一致性"
# ──────────────────────────────────────────
for skill in "${SKILLS[@]}"; do
  kiro=".kiro/skills/$skill/skill.md"
  src="$skill/SKILL.md"
  if [[ ! -f "$kiro" ]]; then
    fail ".kiro/skills/$skill/skill.md 不存在"
    continue
  fi
  
  skill_name=$(grep '^name:' "$src" | head -1 | sed 's/name: *//')
  kiro_name=$(grep '^name:' "$kiro" | head -1 | sed 's/name: *//')
  if [[ "$skill_name" == "$kiro_name" ]]; then
    pass "$skill — name 一致: $skill_name"
  else
    fail "$skill — name 不一致: SKILL='$skill_name' vs kiro='$kiro_name'"
  fi
done

echo ""
# ──────────────────────────────────────────
echo "【3】SKILL_EN/ZH.md 行数检查（≤250 行）"
# ──────────────────────────────────────────
MAX_LINES=250
for skill in "${SKILLS[@]}"; do
  for lang in EN ZH; do
    f="$skill/SKILL_${lang}.md"
    if [[ ! -f "$f" ]]; then
      fail "$f 不存在"
      continue
    fi
    lines=$(wc -l < "$f")
    if (( lines <= MAX_LINES )); then
      pass "$f — $lines 行 (≤$MAX_LINES)"
    else
      fail "$f — $lines 行 (>$MAX_LINES)"
    fi
  done
done

echo ""
# ──────────────────────────────────────────
echo "【4】内部链接检查（文件存在性）"
# ──────────────────────────────────────────
for skill in "${SKILLS[@]}"; do
  for f in "$skill"/SKILL_EN.md "$skill"/SKILL_ZH.md "$skill"/README.md "$skill"/README_zh.md; do
    [[ ! -f "$f" ]] && continue
    grep -oP '\[.*?\]\(((?!http|#)[^)#]+)\)' "$f" 2>/dev/null | grep -oP '\(([^)]+)\)' | tr -d '()' | while read link; do
      target="$skill/$link"
      if [[ ! -f "$target" && ! -d "$target" ]]; then
        echo "  ❌ 断链: $f → $link" && ((FAIL++)) || true
      fi
    done
  done
done
echo "  (无❌输出 = 全部通过)"

echo ""
# ──────────────────────────────────────────
echo "【5】JSON 语法检查"
# ──────────────────────────────────────────
json_errors=0
find . -name '*.json' ! -path './.git/*' ! -path '*/output/*' | sort | while read f; do
  if ! python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
    echo "  ❌ JSON 错误: $f"
    ((json_errors++)) || true
  fi
done
if (( json_errors == 0 )); then
  pass "所有 JSON 文件语法正确"
fi

echo ""
# ──────────────────────────────────────────
echo "【6】YAML 语法检查"
# ──────────────────────────────────────────
yaml_errors=0
find . -name '*.yaml' -o -name '*.yml' | sort | while read f; do
  if ! python3 -c "import yaml; list(yaml.safe_load_all(open('$f')))" 2>/dev/null; then
    echo "  ❌ YAML 错误: $f"
    ((yaml_errors++)) || true
  fi
done
if (( yaml_errors == 0 )); then
  pass "所有 YAML 文件语法正确"
fi

echo ""
# ──────────────────────────────────────────
echo "【7】EN/ZH 对称性检查"
# ──────────────────────────────────────────
for skill in "${SKILLS[@]}"; do
  # SKILL 文件对称
  if [[ -f "$skill/SKILL_EN.md" && -f "$skill/SKILL_ZH.md" ]]; then
    pass "$skill — SKILL_EN/ZH 都存在"
  else
    fail "$skill — SKILL_EN 或 SKILL_ZH 缺失"
  fi
  
  # README 对称
  if [[ -f "$skill/README.md" && -f "$skill/README_zh.md" ]]; then
    pass "$skill — README/README_zh 都存在"
  else
    fail "$skill — README 或 README_zh 缺失"
  fi
done

echo ""
# ──────────────────────────────────────────
echo "【8】.gitignore 排除检查"
# ──────────────────────────────────────────
if grep -q 'chaos-engineering-on-aws/doc/' .gitignore; then
  pass ".gitignore 排除 chaos doc/"
else
  fail ".gitignore 未排除 chaos doc/"
fi

if grep -q 'eks-resilience-checker/doc/' .gitignore; then
  pass ".gitignore 排除 eks doc/"
else
  warn ".gitignore 未排除 eks-resilience-checker/doc/"
fi

if grep -q 'eks-resilience-checker/output/' .gitignore; then
  pass ".gitignore 排除 eks output/"
else
  fail ".gitignore 未排除 eks output/"
fi

if grep -q 'chaos-engineering-on-aws/output/' .gitignore; then
  pass ".gitignore 排除 chaos output/"
else
  fail ".gitignore 未排除 chaos output/"
fi

echo ""
# ──────────────────────────────────────────
echo "【9】Token 估算（Context Window 模拟）"
# ──────────────────────────────────────────
TOKEN_LIMIT=5000
for skill in "${SKILLS[@]}"; do
  total_chars=0
  for f in "$skill/SKILL.md" "$skill/SKILL_EN.md"; do
    [[ -f "$f" ]] && total_chars=$(( total_chars + $(wc -c < "$f") ))
  done
  tokens=$(( total_chars / 3 ))
  if (( tokens <= TOKEN_LIMIT )); then
    pass "$skill 初始加载 — ~${tokens} tokens (≤${TOKEN_LIMIT})"
  else
    fail "$skill 初始加载 — ~${tokens} tokens (>${TOKEN_LIMIT})"
  fi
done

echo ""
# ──────────────────────────────────────────
echo "【10】references 孤立文件检查"
# ──────────────────────────────────────────
for skill in "${SKILLS[@]}"; do
  [[ ! -d "$skill/references" ]] && continue
  for ref in "$skill"/references/*.md "$skill"/references/*.yaml "$skill"/references/*.json; do
    [[ ! -f "$ref" ]] && continue
    basename_ref=$(basename "$ref")
    # 在 SKILL_EN, SKILL_ZH, README, README_zh 及同目录其他 md 中搜索引用
    found=0
    for src in "$skill"/SKILL_EN.md "$skill"/SKILL_ZH.md "$skill"/README.md "$skill"/README_zh.md "$skill"/references/*.md; do
      [[ ! -f "$src" ]] && continue
      [[ "$src" == "$ref" ]] && continue
      if grep -q "$basename_ref" "$src" 2>/dev/null; then
        found=1
        break
      fi
    done
    if (( found == 0 )); then
      warn "$ref — 未被任何文件引用（可能孤立）"
    fi
  done
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  结果: ✅ $PASS passed | ❌ $FAIL failed | ⚠️  $WARN warnings"
echo "═══════════════════════════════════════════════════════════════"

exit $FAIL
