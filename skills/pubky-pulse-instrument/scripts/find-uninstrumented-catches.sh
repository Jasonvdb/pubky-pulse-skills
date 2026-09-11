#!/bin/sh
# find-uninstrumented-catches.sh — list error-handling sites that report nothing.
#
# Neither the Swift nor the Android SDK captures crashes, and the web and Node
# SDKs only capture what nobody caught. Find handling sites without a local
# Pulse.error or browser Pulse.captureException report. This is a heuristic:
# shared reporting helpers and intentional skips need manual review.
#
# POSIX sh, grep/awk only. Read-only. JSON on stdout, diagnostics on stderr.

set -eu

usage() {
  cat <<'USAGE'
Usage: find-uninstrumented-catches.sh <root> [--window N] [--lang ts,swift,kt]
       find-uninstrumented-catches.sh --self-test
       find-uninstrumented-catches.sh --help

Finds error-handling sites (catch, .catch(, onFailure, runCatching,
Result.failure, case .failure) that have no Pulse.error or Pulse.captureException
call on the same line or
within the next N lines. The forward search stops at the next error-handling
site, so a report belonging to a later handler never covers an earlier one.

Only a Pulse receiver counts as a report: `Pulse.error(`, `pulse.error(`, and a
scoped receiver whose token is `pulse` or ends in `Pulse` (`req.pulse.error(`,
`scopedPulse.error(`), or `.captureException(` on those receivers. Calls through
other reporting helpers need manual review. `console.error`, `logger.error`,
`logger.captureException`, `log.error`, `Log.error`
and `Timber.e` are not captured by any SDK, so a catch that only logs is still
reported as uninstrumented.

Options:
  --window N     Lines after the site to search for a report, or until the
                 next handling site, whichever comes first. Default 8.
  --lang LIST    Comma-separated subset of ts,swift,kt. Default all three.
                 ts = .ts .tsx .js .jsx .mjs .cjs, swift = .swift, kt = .kt .kts
  --self-test    Run the built-in fixture check; exits 1 on a regression.
  --help         Print this and exit 0.

Skips node_modules, dist, build, .next, .git, Pods and DerivedData, and lines
that are entirely a comment.

Prints one JSON object on stdout:

  {"total":N,"uninstrumented":[{"file":"...","line":12,"snippet":"..."}]}

"total" counts every error-handling site found; "uninstrumented" lists only the
ones with no report. A clean tree is {"total":N,"uninstrumented":[]}.
Exit status is 0 whether or not anything was found; 2 means bad arguments.
USAGE
}

scan() {
  # scan <root> <window> <extension-predicate-args...>
  scan_root=$1
  scan_window=$2
  shift 2

  scan_list=$(mktemp)
  find "$scan_root" \
    \( -name node_modules -o -name dist -o -name build -o -name .next \
       -o -name .git -o -name Pods -o -name DerivedData \) -prune \
    -o -type f \( "$@" \) -print 2>/dev/null | LC_ALL=C sort >"$scan_list"

  awk -v list="$scan_list" -v window="$scan_window" '
    function esc(s) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\t/, " ", s)
      gsub(/\r/, "", s)
      return s
    }
    function trim(s) {
      sub(/^[ \t]+/, "", s)
      sub(/[ \t]+$/, "", s)
      return s
    }
    function is_site(s) {
      if (s ~ /^[ \t]*(\/\/|\*|\/\*|#)/) return 0
      return (s ~ /(^|[^A-Za-z0-9_.])catch([^A-Za-z0-9_]|$)|\.catch\(|onFailure|runCatching|Result\.failure|case[ \t]+\.failure/)
    }
    function is_report(s) {
      if (s ~ /^[ \t]*(\/\/|\*|\/\*|#)/) return 0
      return (s ~ /(^|[^A-Za-z0-9_])(pulse|[A-Za-z0-9_]*Pulse)\.(error|captureException)\(/)
    }
    BEGIN {
      total = 0
      out = ""
      while ((getline path < list) > 0) {
        n = 0
        while ((getline line < path) > 0) { n++; L[n] = line }
        close(path)
        for (i = 1; i <= n; i++) {
          if (!is_site(L[i])) continue
          total++
          reported = is_report(L[i])
          # Stop at the next handling site: its report covers itself, not this one.
          for (j = i + 1; !reported && j <= n && j <= i + window; j++) {
            if (is_site(L[j])) break
            if (is_report(L[j])) { reported = 1; break }
          }
          if (reported) continue
          snippet = trim(L[i])
          if (length(snippet) > 160) snippet = substr(snippet, 1, 160)
          out = out (out == "" ? "" : ",") \
            "{\"file\":\"" esc(path) "\",\"line\":" i ",\"snippet\":\"" esc(snippet) "\"}"
        }
        for (i = 1; i <= n; i++) delete L[i]
      }
      close(list)
      print "{\"total\":" total ",\"uninstrumented\":[" out "]}"
    }
  '

  rm -f "$scan_list"
}

self_test() {
  st_dir=$(mktemp -d)
  mkdir -p "$st_dir/src" "$st_dir/node_modules"

  cat >"$st_dir/src/bad.ts" <<'FIXTURE'
export async function pay() {
  try {
    await charge();
  } catch (err) {
    showToast("failed");
  }
}
FIXTURE

  cat >"$st_dir/src/good.ts" <<'FIXTURE'
export async function upload() {
  try {
    await send();
  } catch (err) {
    Pulse.error(err, "upload_failed");
  }
  await send().catch((err) => Pulse.error(err, "upload_failed"));
}
FIXTURE

  cat >"$st_dir/src/Repo.kt" <<'FIXTURE'
fun load() {
    runCatching { api.get() }
        .onFailure { showError(it) }
}
FIXTURE

  cat >"$st_dir/src/View.swift" <<'FIXTURE'
func save() {
    // catch is only mentioned in this comment
    switch result {
    case .failure(let error):
        Pulse.error(error, "save_failed")
    case .success:
        break
    }
}
FIXTURE

  cat >"$st_dir/src/logged.ts" <<'FIXTURE'
export async function sync() {
  try {
    await pull();
  } catch (err) {
    console.error(err);
    logger.error(err);
  }
}
FIXTURE

  cat >"$st_dir/src/scoped.ts" <<'FIXTURE'
export function handle(req) {
  try {
    work();
  } catch (err) {
    req.pulse.error(err, "work_failed");
  }
}
FIXTURE

  cat >"$st_dir/src/adjacent.ts" <<'FIXTURE'
export async function refresh() {
  try {
    await pull();
  } catch (err) {
    showToast("failed");
  }
  try {
    await push();
  } catch (err) {
    Pulse.error(err, "push_failed");
  }
}
FIXTURE

  cat >"$st_dir/src/captured.ts" <<'FIXTURE'
try { throw "failed"; } catch (err) {
  Pulse.captureException(err, { message: "load_failed" });
}
await send().catch((err) => pulse.captureException(err));
try { work(); } catch (err) {
  scopedPulse.captureException(err);
}
try { work(); } catch (err) {
  req.pulse.captureException(err);
}
FIXTURE

  cat >"$st_dir/src/other-capture.ts" <<'FIXTURE'
try { work(); } catch (err) {
  logger.captureException(err);
}
try { work(); } catch (err) {
  // Pulse.captureException(err);
}
FIXTURE

  cat >"$st_dir/src/adjacent-inline.ts" <<'FIXTURE'
try { work(); } catch (err) {
  showToast("failed");
}
await send().catch((err) => Pulse.captureException(err));
FIXTURE

  cat >"$st_dir/node_modules/vendor.ts" <<'FIXTURE'
try { a(); } catch (e) { ignore(e); }
FIXTURE

  st_out=$(scan "$st_dir" 8 -name '*.ts' -o -name '*.kt' -o -name '*.swift')
  rm -rf "$st_dir"

  st_status=0
  # Eighteen sites: the original ten error-reporting cases, four captureException
  # calls on Pulse receivers, two rejected reports (logger/comment), and two
  # adjacent sites where the later report is inline. Eight are unreported.
  echo "$st_out" | grep -q '"total":18' || {
    echo "self-test: expected 18 sites, got: $st_out" >&2
    st_status=1
  }
  echo "$st_out" | grep -q '"file":"[^"]*bad\.ts","line":4' || {
    echo "self-test: missed the uninstrumented catch in bad.ts" >&2
    st_status=1
  }
  echo "$st_out" | grep -q 'Repo\.kt' || {
    echo "self-test: missed the uninstrumented Kotlin failure branch" >&2
    st_status=1
  }
  case $st_out in
    *good.ts*) echo "self-test: flagged an instrumented site in good.ts" >&2; st_status=1 ;;
  esac
  case $st_out in
    *View.swift*) echo "self-test: flagged a comment or a reported .failure" >&2; st_status=1 ;;
  esac
  echo "$st_out" | grep -q '"file":"[^"]*logged\.ts","line":4' || {
    echo "self-test: a catch whose only report is console.error must count as uninstrumented" >&2
    st_status=1
  }
  case $st_out in
    *scoped.ts*) echo "self-test: flagged a catch reported through req.pulse.error" >&2; st_status=1 ;;
  esac
  case $st_out in
    *node_modules*) echo "self-test: did not skip node_modules" >&2; st_status=1 ;;
  esac
  echo "$st_out" | grep -q '"file":"[^"]*adjacent\.ts","line":4' || {
    echo "self-test: a later handler's Pulse.error must not cover the catch before it" >&2
    st_status=1
  }
  case $st_out in
    *'adjacent.ts","line":9'*)
      echo "self-test: flagged the adjacent catch that reports on its own next line" >&2
      st_status=1 ;;
  esac

  case $st_out in
    *captured.ts*) echo "self-test: flagged a Pulse.captureException report" >&2; st_status=1 ;;
  esac
  for st_line in 1 4; do
    echo "$st_out" | grep -q '"file":"[^"]*other-capture\.ts","line":'"$st_line"',' || {
      echo "self-test: unrelated or commented capture must not cover line $st_line" >&2
      st_status=1
    }
  done
  echo "$st_out" | grep -q '"file":"[^"]*adjacent-inline\.ts","line":1,' || {
    echo "self-test: a later inline handler must not cover the preceding catch" >&2
    st_status=1
  }
  case $st_out in
    *'adjacent-inline.ts","line":4,'*)
      echo "self-test: flagged the inline handler that reports its own error" >&2
      st_status=1 ;;
  esac

  if [ "$st_status" -eq 0 ]; then echo "self-test: ok"; fi
  return $st_status
}

root=""
window=8
langs="ts,swift,kt"

while [ $# -gt 0 ]; do
  case $1 in
    --help|-h) usage; exit 0 ;;
    --self-test) if self_test; then exit 0; else exit 1; fi ;;
    --window)
      [ $# -ge 2 ] || { echo "--window needs a number" >&2; exit 2; }
      window=$2; shift 2 ;;
    --lang)
      [ $# -ge 2 ] || { echo "--lang needs a list" >&2; exit 2; }
      langs=$2; shift 2 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$root" ] || { echo "only one root is accepted" >&2; exit 2; }
      root=$1; shift ;;
  esac
done

[ -n "$root" ] || { echo "a root directory is required" >&2; usage >&2; exit 2; }
[ -d "$root" ] || { echo "not a directory: $root" >&2; exit 2; }
case $window in
  ''|*[!0-9]*) echo "--window must be a non-negative integer" >&2; exit 2 ;;
esac

exts=""
old_ifs=$IFS
IFS=,
for lang in $langs; do
  IFS=$old_ifs
  case $lang in
    ts) exts="$exts ts tsx js jsx mjs cjs" ;;
    swift) exts="$exts swift" ;;
    kt) exts="$exts kt kts" ;;
    *) echo "unknown language: $lang (expected ts, swift or kt)" >&2; exit 2 ;;
  esac
  IFS=,
done
IFS=$old_ifs

set --
for ext in $exts; do
  if [ $# -eq 0 ]; then set -- -name "*.$ext"; else set -- "$@" -o -name "*.$ext"; fi
done
[ $# -gt 0 ] || { echo "--lang selected no languages" >&2; exit 2; }

scan "$root" "$window" "$@"
