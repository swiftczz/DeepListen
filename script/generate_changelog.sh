#!/usr/bin/env bash
# 生成两个 tag 之间的 changelog（按 Conventional Commits 前缀分组）
# 兼容 macOS 自带 bash 3.2（不用关联数组、不用 mapfile）
# 用法: ./script/generate_changelog.sh <prev_tag> <current_tag> [repo]
# 输出到 stdout
# 例: ./script/generate_changelog.sh v0.1.0 v0.2.0 swiftczz/DeepListen
set -euo pipefail

prev_tag="${1:?用法: generate_changelog.sh <prev_tag> <current_tag> [repo]}"
current_tag="${2:?缺少 current_tag}"
repo="${3:-}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "$prev_tag" ]]; then
  range="${prev_tag}..${current_tag}"
else
  # 首次发版，没有上一个 tag：列出从仓库开始的全部提交
  range="$current_tag"
fi
commits_raw=$(git -C "$root" log --pretty=format:"%s__DELIM__%h" "$range" 2>/dev/null || true)

if [[ -z "$commits_raw" ]]; then
  echo "No changes up to ${current_tag}."
  echo ""
  echo "**Full Changelog**: https://github.com/${repo}/commits/${current_tag}"
  exit 0
fi

# 各组的临时文件
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
feat_f="$tmp_dir/feat.txt"; fix_f="$tmp_dir/fix.txt"; style_f="$tmp_dir/style.txt"
ref_f="$tmp_dir/ref.txt"; docs_f="$tmp_dir/docs.txt"; ci_f="$tmp_dir/ci.txt"
test_f="$tmp_dir/test.txt"; perf_f="$tmp_dir/perf.txt"; chore_f="$tmp_dir/chore.txt"
other_f="$tmp_dir/other.txt"
: > "$feat_f"; : > "$fix_f"; : > "$style_f"; : > "$ref_f"; : > "$docs_f"
: > "$ci_f"; : > "$test_f"; : > "$perf_f"; : > "$chore_f"; : > "$other_f"

# 去掉前缀、scope、!、: 后保留描述
strip_prefix() {
  local s="$1"
  # 去 type(scope)!:
  s="${s#"$2"}"
  s="${s#*):}"      # 去 (scope):
  s="${s#!:}"       # 去 !:
  s="${s#:}"        # 去 :
  s="${s#" "}"      # 去前导空格
  echo "$s"
}

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  subject="${line%%__DELIM__*}"
  hash="${line##*__DELIM__}"

  prefix=""
  if [[ "$subject" =~ ^([a-z]+)(\([^\)]+\))?(!)?: ]]; then
    prefix="${BASH_REMATCH[1]}"
  fi

  desc=$(strip_prefix "$subject" "$prefix")

  case "$prefix" in
    feat)     echo "- $desc (\`$hash\`)" >> "$feat_f" ;;
    fix)      echo "- $desc (\`$hash\`)" >> "$fix_f" ;;
    style)    echo "- $desc (\`$hash\`)" >> "$style_f" ;;
    refactor) echo "- $desc (\`$hash\`)" >> "$ref_f" ;;
    docs)     echo "- $desc (\`$hash\`)" >> "$docs_f" ;;
    ci)       echo "- $desc (\`$hash\`)" >> "$ci_f" ;;
    test)     echo "- $desc (\`$hash\`)" >> "$test_f" ;;
    perf)     echo "- $desc (\`$hash\`)" >> "$perf_f" ;;
    chore)    echo "- $desc (\`$hash\`)" >> "$chore_f" ;;
    *)        echo "- $subject (\`$hash\`)" >> "$other_f" ;;
  esac
done <<< "$commits_raw"

emit_group() {
  local title="$1" emoji="$2" file="$3"
  if [[ -s "$file" ]]; then
    echo "### $emoji $title"
    cat "$file"
    echo ""
  fi
}

echo "## Changes"
echo ""
emit_group "Features"    "✨" "$feat_f"
emit_group "Fixes"       "🐛" "$fix_f"
emit_group "Styles"      "🎨" "$style_f"
emit_group "Refactors"   "♻️" "$ref_f"
emit_group "Docs"        "📚" "$docs_f"
emit_group "CI"          "👷" "$ci_f"
emit_group "Tests"       "✅" "$test_f"
emit_group "Performance" "⚡️" "$perf_f"
emit_group "Chores"      "🔧" "$chore_f"
emit_group "Others"      "📦" "$other_f"

if [[ -n "$repo" ]]; then
  if [[ -n "$prev_tag" ]]; then
    echo "**Full Changelog**: https://github.com/${repo}/compare/${prev_tag}...${current_tag}"
  else
    echo "**Full Changelog**: https://github.com/${repo}/commits/${current_tag}"
  fi
fi
