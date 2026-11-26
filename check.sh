#!/usr/bin/env bash
# Corenna repo check, as a GitHub Action step.
#
# Sends one thing to Corenna: the repo's GitHub link and the platform. Corenna
# reads the public repo from GitHub (its default branch), the same way the free
# check at https://corenna.dev/check does, and answers with what is ready and
# what is missing. Nothing from the runner is sent: no token, no files.
set -uo pipefail

ENDPOINT="https://dqwnwgkjhbiluockgnji.supabase.co/functions/v1/repo-check"
SITE="https://corenna.dev"
UTM="utm_source=github&utm_medium=action&utm_campaign=repo_check"
VERSION="1.0.0"

out() { [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >>"$GITHUB_OUTPUT"; return 0; }
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"; return 0; }
# Text in a workflow command has to escape %, CR and LF, or it ends the command early.
cmd_escape() { local s="${1//'%'/%25}"; s="${s//$'\r'/%0D}"; printf '%s' "${s//$'\n'/%0A}"; }

# Every output is written once, at the end, whichever way the step ends.
checked=false; ready=false; blocking=0; warnings=0; report_url=""
body=""
finish() {
  out checked "$checked"; out ready "$ready"; out blocking "$blocking"; out warnings "$warnings"
  [ -n "$report_url" ] && out report-url "$report_url"
  [ -n "$body" ] && rm -f "$body"
  return 0
}
trap finish EXIT

for tool in curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "::error title=Corenna repo check::$tool is not installed on this runner. GitHub's hosted runners have it."
    exit 1
  fi
done

# ── Inputs ──────────────────────────────────────────────────────────────────
repo="${INPUT_REPOSITORY:-${GITHUB_REPOSITORY:-}}"
repo="${repo#"${repo%%[![:space:]]*}"}"   # trim leading space
repo="${repo%"${repo##*[![:space:]]}"}"   # trim trailing space
repo="${repo%/}"
repo="${repo%.git}"
repo="${repo#https://github.com/}"
repo="${repo#http://github.com/}"
repo="${repo#github.com/}"
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "::error title=Corenna repo check::repository should be owner/name or a github.com link. Got: $(cmd_escape "${INPUT_REPOSITORY:-}")"
  exit 1
fi
repo_url="https://github.com/$repo"

platform="$(printf '%s' "${INPUT_PLATFORM:-android}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$platform" in
  android) platform_name="Android" ;;
  ios | iphone) platform="ios"; platform_name="iPhone (beta)" ;;
  *)
    echo "::error title=Corenna repo check::platform should be android or ios. Got: $(cmd_escape "${INPUT_PLATFORM:-}")"
    exit 1
    ;;
esac

fail_on_blocking="$(printf '%s' "${INPUT_FAIL_ON_BLOCKING:-false}" | tr '[:upper:]' '[:lower:]')"

report_url="$SITE/check?repo=$(jq -rn --arg r "$repo_url" '$r|@uri')&platform=$platform&$UTM"
signup_url="$SITE/auth?mode=signup&$UTM"

# ── Ask Corenna ─────────────────────────────────────────────────────────────
body="$(mktemp)"
payload="$(jq -cn --arg u "$repo_url" --arg p "$platform" '{repo_url: $u, platform: $p}')"

echo "Checking $repo for an $platform_name build with Corenna..."
code=000
for attempt in 1 2 3 4; do
  code="$(curl -sS -m 90 -o "$body" -w '%{http_code}' -X POST "$ENDPOINT" \
    -H 'Content-Type: application/json' \
    -H "User-Agent: corenna-repo-check-action/$VERSION" \
    --data "$payload" 2>/dev/null)" || code=000
  # Busy (429), GitHub's rate limit on Corenna's side (503), or no answer: wait and try again.
  case "$code" in
    429 | 502 | 503 | 504 | 000) [ "$attempt" -lt 4 ] && sleep $((attempt * 5)) && continue ;;
  esac
  break
done

field() { jq -r "$1" "$body" 2>/dev/null; }

if [ "$code" = 404 ] && [ "$(field '.private_or_missing // false')" = true ]; then
  echo "::warning title=Corenna repo check::$repo is private or doesn't exist, so the public check can't read it. Connect it on corenna.dev to check it there: $signup_url"
  summary "### Corenna repo check: $repo"
  summary ""
  summary "**Not checked.** This repo is private or doesn't exist, so the public check can't read it."
  summary ""
  summary "Private repos are checked inside Corenna: [sign up free]($signup_url), connect the repo through Corenna's GitHub App, and the check runs there."
  exit 0
fi

if [ "$code" = 400 ]; then
  echo "::error title=Corenna repo check::$(cmd_escape "$(field '.error // "Corenna could not use this repository link."')")"
  exit 1
fi

if [ "$code" != 200 ] || ! jq -e '.checks | type == "array"' "$body" >/dev/null 2>&1; then
  # Corenna being down is not a problem in your repo, so it never fails your workflow.
  echo "::warning title=Corenna repo check::Corenna's check didn't answer (HTTP $code). Your workflow carries on. You can run the check at $report_url"
  summary "### Corenna repo check: $repo"
  summary ""
  summary "Corenna's check didn't answer this time (HTTP $code). [Run it on corenna.dev]($report_url)."
  exit 0
fi

# ── Report ──────────────────────────────────────────────────────────────────
blocking="$(field '.blocking // 0')"
warnings="$(field '.warnings // 0')"
branch="$(field '.branch // "main"')"
checked=true
if [ "$blocking" = 0 ]; then ready=true; fi

# Annotations: each problem shows on the run page, and on the pull request when one triggered the run.
jq -r '
  def esc: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
  def prop: esc | gsub(":"; "%3A") | gsub(","; "%2C");
  .checks[]
  | select(.status == "fail" or .status == "warn")
  | "::\(if .status == "fail" then "error" else "warning" end) title=Corenna: \(.label | prop)::\(.message | esc)"
' "$body"

# The log: one line per check.
jq -r '
  .checks[]
  | "\(if .status == "pass" then "  ok  " elif .status == "warn" then "  look" else "  FAIL" end)  \(.label): \(.message | gsub("[\r\n]+"; " "))"
' "$body"

# The job summary: a table of checks, then what the stores will ask for.
cell='gsub("[\r\n]+"; " ") | gsub("\\|"; "\\|") | gsub("<"; "&lt;") | gsub(">"; "&gt;")'
plural() { [ "$1" = 1 ] && printf '%s' "$2" || printf '%s' "$3"; }

summary "### Corenna repo check: $repo, $platform_name"
summary ""
if [ "$blocking" != 0 ]; then
  summary "**$blocking $(plural "$blocking" problem problems) would stop an $platform_name build** of the \`$branch\` branch."
elif [ "$warnings" != 0 ]; then
  summary "**Ready to build**, with $warnings $(plural "$warnings" thing things) to look at first."
else
  summary "**Ready to build.** Nothing in the \`$branch\` branch stops an $platform_name build."
fi
stack="$(field 'if .stack.confident then .stack.stack else "" end')"
case "$stack" in
  flutter) summary ""; summary "Found a Flutter app." ;;
  react-native | reactnative | expo) summary ""; summary "Found a React Native app." ;;
esac
if [ "$platform" = ios ]; then
  summary ""
  summary "An iPhone build also needs your Apple certificate and provisioning profile, which you add on corenna.dev."
fi
summary ""
summary "| | Check | What Corenna found |"
summary "|---|---|---|"
summary "$(jq -r ".checks[] | \"| \(if .status == \"pass\" then \"✅\" elif .status == \"warn\" then \"⚠️\" else \"❌\" end) | \(.label | $cell) | \(.message | $cell) |\"" "$body")"

store="$(jq -r "
  [(.store.findings // [])[] | select(.level == \"todo\" or .level == \"risk\")]
  | .[] | \"- \(if .level == \"risk\" then \"⚠️\" else \"📝\" end) **\(.title | $cell).** \(.detail // \"\" | $cell)\(if .fix then \" Fix: \" + (.fix | $cell) else \"\" end)\"
" "$body")"
if [ -n "$store" ]; then
  summary ""
  summary "#### Before you publish to the stores"
  summary ""
  summary "$store"
fi

summary ""
summary "[See the full report on corenna.dev]($report_url) · [Build this app on Corenna]($signup_url)"
summary ""
summary "Building your Android app is free. Downloading it needs a plan: \$1 for your first month. iPhone builds are in beta and need a plan."

if [ "$blocking" != 0 ]; then
  echo "$blocking $(plural "$blocking" problem problems) would stop the build. Full report: $report_url"
  if [ "$fail_on_blocking" = true ]; then
    echo "::error title=Corenna repo check::$blocking $(plural "$blocking" problem problems) would stop an $platform_name build. See the job summary."
    exit 1
  fi
else
  echo "Ready to build. Full report: $report_url"
fi
exit 0
