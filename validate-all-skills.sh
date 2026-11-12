#!/bin/bash
# validate-all-skills.sh — 全量静态验证脚本
# 用法: bash validate-all-skills.sh   (可在任意目录运行)

set -uo pipefail
# All paths below are relative to the repo root; resolve it from the script location.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
PASS=0; FAIL=0; WARN=0
# Auto-discover every skill folder (any top-level dir with a SKILL.md) so newly
# added skills are validated too. Bash 3.2 compatible (no mapfile).
SKILLS=()
for f in */SKILL.md; do
  [[ -f "$f" ]] && SKILLS+=("${f%/SKILL.md}")
done
# Bilingual router-pattern skills (SKILL.md + SKILL_EN.md + SKILL_ZH.md)
is_bilingual() { [[ -f "$1/SKILL_EN.md" || -f "$1/SKILL_ZH.md" ]]; }

# Repo files with the given extensions: git-tracked only (skips local reports and
# experiment output), falling back to find outside a git checkout.
list_files() {
  local ext pats=() names=()
  for ext in "$@"; do pats+=("*.$ext"); names+=(-o -name "*.$ext"); done
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -- "${pats[@]}" | sort
  else
    find . \( "${names[@]:1}" \) ! -path './.git/*' ! -path './.kiro/*' ! -path '*/output/*' | sort
  fi
}

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
  
  # description 字段 + 长度（Agent Skills 规范上限 1024 字符）
  if grep -q '^description:' "$f"; then
    pass "$f — 有 description 字段"
    desc_len=$(python3 - "$f" <<'PY' 2>/dev/null
import sys, yaml
text = open(sys.argv[1], encoding="utf-8").read()
fm = text.split("---", 2)[1] if text.startswith("---") else ""
print(len(str((yaml.safe_load(fm) or {}).get("description", ""))))
PY
)
    if [[ -z "$desc_len" ]]; then
      warn "$f — 无法解析 frontmatter（需要 python3 + PyYAML）"
    elif (( desc_len <= 1024 )); then
      pass "$f — description ${desc_len} 字符 (≤1024)"
    else
      fail "$f — description ${desc_len} 字符 (>1024)"
    fi
  else
    fail "$f — 缺少 description 字段"
  fi
  
  # allowed-tools / model：本仓库约定（非规范必需），缺失只告警
  for field in allowed-tools model; do
    if grep -q "^${field}:" "$f"; then
      pass "$f — 有 $field 字段"
    else
      warn "$f — 缺少 $field 字段"
    fi
  done
done

echo ""
# ──────────────────────────────────────────
echo "【2】SKILL.md ↔ .kiro/skills 本地安装一致性"
# ──────────────────────────────────────────
# .kiro/ is gitignored: it is a LOCAL Kiro install (users copy skill folders into
# .kiro/skills/, see README "Installation"), never part of a clone. Only compare
# when such an install exists; a fresh checkout has nothing to compare.
if [[ ! -d ".kiro/skills" ]]; then
  echo "  ⏭  未发现 .kiro/skills/（本地 Kiro 安装目录，已被 .gitignore 排除）— 跳过"
else
for skill in "${SKILLS[@]}"; do
  src="$skill/SKILL.md"
  # Kiro reads SKILL.md; older local copies used skill.md
  kiro=""
  for cand in ".kiro/skills/$skill/SKILL.md" ".kiro/skills/$skill/skill.md"; do
    [[ -f "$cand" ]] && { kiro="$cand"; break; }
  done
  if [[ -z "$kiro" ]]; then
    # Users may install only the skills they need — only a half-copied folder is an error
    if [[ -d ".kiro/skills/$skill" ]]; then
      fail ".kiro/skills/$skill/SKILL.md 不存在（本地安装不完整，重新复制 $skill/）"
    else
      echo "  ⏭  $skill — 未安装到 .kiro/skills/，跳过"
    fi
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
fi

echo ""
# ──────────────────────────────────────────
echo "【3】SKILL_EN/ZH.md 行数检查（≤250 行）"
# ──────────────────────────────────────────
MAX_LINES=250
for skill in "${SKILLS[@]}"; do
  is_bilingual "$skill" || { echo "  ⏭  $skill — 单语言 skill，跳过"; continue; }
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
link_errors=0
for skill in "${SKILLS[@]}"; do
  for f in "$skill"/SKILL_EN.md "$skill"/SKILL_ZH.md "$skill"/README.md "$skill"/README_zh.md; do
    [[ ! -f "$f" ]] && continue
    # Parse real Markdown links only ([text](target)), skip URLs and pure anchors,
    # and strip "#anchor" before checking the file. Portable ERE (BSD grep has
    # no -P); process substitution (not a pipe) so FAIL is counted in this shell.
    while read -r link; do
      path="${link%%#*}"
      [[ -z "$path" ]] && continue
      target="$skill/$path"
      if [[ ! -f "$target" && ! -d "$target" ]]; then
        fail "断链: $f → $link"; link_errors=$((link_errors + 1))
      fi
    done < <(grep -oE '\]\([^)[:space:]]+\)' "$f" 2>/dev/null \
               | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^(https?:|mailto:|#)')
  done
done
(( link_errors == 0 )) && pass "所有内部链接有效"

echo ""
# ──────────────────────────────────────────
echo "【5】JSON 语法检查"
# ──────────────────────────────────────────
json_errors=0
# Process substitution (not a pipe): a `| while` subshell would drop the counter
while IFS= read -r f; do
  if ! python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" 2>/dev/null; then
    fail "JSON 错误: $f"
    json_errors=$((json_errors + 1))
  fi
done < <(list_files json)
if (( json_errors == 0 )); then
  pass "所有 JSON 文件语法正确"
fi

echo ""
# ──────────────────────────────────────────
echo "【6】YAML 语法检查"
# ──────────────────────────────────────────
yaml_errors=0
if ! python3 -c 'import yaml' 2>/dev/null; then
  warn "未安装 PyYAML（pip install pyyaml）— 跳过 YAML 检查"
  yaml_errors=-1
else
  while IFS= read -r f; do
    # CloudFormation short-form intrinsics (!Ref, !Sub, ...) are valid YAML tags
    if ! python3 -c '
import sys, yaml
class L(yaml.SafeLoader): pass
L.add_multi_constructor("!", lambda loader, suffix, node: None)
list(yaml.load_all(open(sys.argv[1], encoding="utf-8"), Loader=L))' "$f" 2>/dev/null; then
      fail "YAML 错误: $f"
      yaml_errors=$((yaml_errors + 1))
    fi
  done < <(list_files yaml yml)
fi
if (( yaml_errors == 0 )); then
  pass "所有 YAML 文件语法正确"
fi

echo ""
# ──────────────────────────────────────────
echo "【7】EN/ZH 对称性检查"
# ──────────────────────────────────────────
for skill in "${SKILLS[@]}"; do
  is_bilingual "$skill" || { echo "  ⏭  $skill — 单语言 skill，跳过"; continue; }
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
  elif is_bilingual "$skill"; then
    fail "$skill 初始加载 — ~${tokens} tokens (>${TOKEN_LIMIT})"
  else
    # Single-language skills keep the full workflow in SKILL.md (no router split)
    warn "$skill 初始加载 — ~${tokens} tokens (>${TOKEN_LIMIT}，单语言 skill)"
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
# ──────────────────────────────────────────
echo "【11】eks-resilience-checker EXP_MAP ↔ chaos fault-catalog 一致性"
# ──────────────────────────────────────────
# assess.sh recommends fault types that chaos-engineering-on-aws consumes; every
# type|backend pair must exist in fault-catalog.yaml or the hand-off breaks.
ASSESS="eks-resilience-checker/scripts/assess.sh"
CATALOG="chaos-engineering-on-aws/references/fault-catalog.yaml"
if [[ -f "$ASSESS" && -f "$CATALOG" ]] && python3 -c 'import yaml' 2>/dev/null; then
  map_errors=0
  while IFS='|' read -r check_id ftype backend; do
    if python3 - "$CATALOG" "$ftype" "$backend" <<'PY'
import sys, yaml
cat = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
ok = any(e.get("type") == sys.argv[2] and e.get("backend") == sys.argv[3]
         for entries in cat.values() if isinstance(entries, list) for e in entries)
sys.exit(0 if ok else 1)
PY
    then :; else
      fail "$ASSESS EXP_MAP[$check_id]: $ftype|$backend 不在 $CATALOG 中"
      map_errors=$((map_errors + 1))
    fi
  done < <(sed -nE 's/^ *EXP_MAP\["([A-Z0-9]+)"\]="([a-z0-9_]+)\|P[0-9]\|([a-z-]+)\|.*/\1|\2|\3/p' "$ASSESS")
  (( map_errors == 0 )) && pass "EXP_MAP 故障类型全部存在于 fault-catalog.yaml"
else
  echo "  ⏭  缺少 $ASSESS / $CATALOG 或 PyYAML — 跳过"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  结果: ✅ $PASS passed | ❌ $FAIL failed | ⚠️  $WARN warnings"
echo "═══════════════════════════════════════════════════════════════"

# Exit status is 0/1: a raw count would wrap modulo 256 (256 failures → exit 0)
(( FAIL == 0 ))
