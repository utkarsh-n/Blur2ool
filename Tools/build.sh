#!/bin/zsh
# Tools/build.sh — Blur2ool build, check and phone driver (ARCHITECTURE.md §11.1). OWNER: SKEL (frozen after the gate;
# change only through Documentation/build/requests/<AREA>.md). Modelled on AI Stuff/Toothpaste Toy/Tools/build.sh.
#
# xcodebuild hangs on this iCloud folder (NSFileCoordinator), so every command first mirrors the tree to a scratch
# directory, $B2_BUILD_DIR/src, and works there. Mirroring is "against stable neighbours" (§11.1 rule 2): paths owned by
# $B2_AREA, SKEL's frozen files and the read-only documents come from the live repo; every other area's paths come from
# that area's last green snapshot ($B2_GREEN_DIR/<TAG>/), or, while it has none, from the skeleton baseline
# ($B2_GREEN_DIR/SKEL/), or, if even that is missing, from the live tree (with a warning). B2_AREA=INTEGRATE mirrors the
# live tree unchanged. Ownership comes from Tools/ownership.tsv (most specific row wins).
#
# SIMULATOR HOLD (Documentation/HOLD-SIMULATOR.md, ARCHITECTURE §12): while that file contains `Status: **ACTIVE**`,
# this script refuses, with exit status 3 and BEFORE mirroring anything, every command that would use a simulator:
# `sim`, `screenshot`, any argument or destination naming the iphonesimulator SDK, `platform=iOS Simulator` or the
# simulator control tool, and test / build-for-testing / test-without-building without a device destination. It calls
# the simulator control tool only inside the post-release functions (section 6), which run only after release.
#
# Environment
#   B2_AREA        required (except hold-status/help): your area id or tag (FAM-F1 or FAMF1); INTEGRATE = the live tree
#   B2_BUILD_DIR   scratch directory (default $TMPDIR/Blur2oolBuild; every agent sets its own, e.g. $TMPDIR/b2-FAM-F1)
#   B2_GREEN_DIR   green snapshots (default $TMPDIR/b2-green); B2_DEVICE_ID (required for physical device commands)
#   B2_CONFIG      Debug | Release (device: Release by default; phone builds: Debug)        B2_SIM_UDID: post-release only
#
# Commands
#   hold-status                      ACTIVE or RELEASED (no B2_AREA needed)
#   mirror | owner <path…> | check-ownership | lint-names [--area X] | publish-green [--note "text"]
#   core-test [--area TAG] [--filter X]          swift test of BlurCore + BlurGPU (Mac, Mac GPU) in the mirror
#   gpucheck [args]                              build and run the Mac GPU↔CPU parity CLI (--metallib $B2_BUILD_DIR/metal/macos.metallib)
#   typecheck-ios · metal-check                  device-SDK Swift typecheck · Metal -Wall -Wextra, iphoneos + macOS per-file metallib
#   device · verify-shaders                      generic/platform=iOS unsigned build-only · bundle ShaderSources vs repo + combined SHA
#   device-status · device-build · device-build-for-testing
#   device-session "install; check-stamp; launch [--validate] [args…]; wait 3; shot <png>; test --area TAG [--kind app|ui|all]"
#   device-install · device-launch [--validate] [args] · device-shot <png> · device-test [--area TAG]
#   test | build-for-testing | test-without-building [xcodebuild args]   (device destination only while the hold is ACTIVE)
#   sim · screenshot <png> [launch args]          (refused while the hold is ACTIVE)
set -e
setopt pipefail extendedglob

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$REPO/Tools/build.sh"
HOLD_FILE="$REPO/Documentation/HOLD-SIMULATOR.md"
WORK="${B2_BUILD_DIR:-${TMPDIR:-/tmp}/Blur2oolBuild}"; WORK="${WORK%/}"
GREEN="${B2_GREEN_DIR:-${TMPDIR:-/tmp}/b2-green}"; GREEN="${GREEN%/}"
DEVICE_ID="${B2_DEVICE_ID:-}"
BUNDLE_ID="com.utkarsh.blur2ool"
DEVICE_LOCK="${TMPDIR:-/tmp}/b2-device.lock"
SRC="$WORK/src"
CMD="${1:-help}"
[[ $# -gt 0 ]] && shift
case "$CMD" in
  device-status|device-build|device-build-for-testing|device-session|device-install|device-launch|device-shot|device-test)
    [[ -n "$DEVICE_ID" ]] || { print -u2 "Set B2_DEVICE_ID to your own physical device identifier."; exit 2; } ;;
esac

# ------------------------------------------------------------------------------------------------------------------
# 1. Hold guard: first, before mirroring. Keys only on simulator destinations and SDKs (review fix E-2).
# ------------------------------------------------------------------------------------------------------------------
hold_active() { [[ -f "$HOLD_FILE" ]] && grep -qF 'Status: **ACTIVE**' "$HOLD_FILE" }
refuse_hold() {
  print "REFUSED: simulator work is on hold — see Documentation/HOLD-SIMULATOR.md"
  print -u2 "(Tools/build.sh $CMD: the simulator hold is ACTIVE; use typecheck-ios, metal-check, device and device-* instead.)"
  exit 3
}
names_simulator() {   # a simulator SDK, a simulator destination or the simulator control tool
  local s="${(L)1}" tool="sim""ctl"
  [[ "$s" == *iphonesimulator* || "$s" == *"ios simulator"* || "$s" == *"$tool"* ]]
}
has_device_destination() {
  local a
  for a in "$@" "${B2_DESTINATION:-}"; do
    [[ "$a" == *"platform=iOS,id="* || "$a" == *"generic/platform=iOS"* || "$a" == "--device" ]] && return 0
  done
  return 1
}
if hold_active; then
  for a in "$CMD" "$@" "$*" "${B2_DESTINATION:-}" "${B2_SDK:-}"; do names_simulator "$a" && refuse_hold; done
  case "$CMD" in
    sim|screenshot) refuse_hold ;;
    test|build-for-testing|test-without-building) has_device_destination "$@" || refuse_hold ;;
  esac
fi

case "$CMD" in
  hold-status) if hold_active; then print ACTIVE; else print RELEASED; fi; exit 0 ;;
  help|-h|--help) sed -n '2,35p' "$SELF" | sed -E 's/^# ?//'; exit 0 ;;
esac

# ------------------------------------------------------------------------------------------------------------------
# 2. Area and the embedded helper
# ------------------------------------------------------------------------------------------------------------------
if [[ -z "${B2_AREA:-}" ]]; then
  print -u2 "Tools/build.sh: set B2_AREA to your area id or tag (FAM-F1 or FAMF1; INTEGRATE for the live tree)."
  exit 2
fi
AREA_TAG="${${(U)B2_AREA}//-/}"
mkdir -p "$WORK/logs" "$WORK/.b2" "$WORK/checks"
PY="$WORK/.b2/b2.py"
cat > "$PY" <<'PYEOF'
# Blur2ool build helper, embedded in Tools/build.sh (OWNER: SKEL). Ownership resolution, the stable-neighbour mirror
# plan, the ownership check, the symbol-prefix lint, diagnostics classification and test-class discovery.
import os, re, sys, hashlib

def tag(owner): return (owner or "").replace("-", "").upper()

def load_rows(repo):
    rows = []
    with open(os.path.join(repo, "Tools", "ownership.tsv"), encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"): continue
            parts = line.split("\t")
            if len(parts) < 2: continue
            g, owner = parts[0].strip(), parts[1].strip()
            rx = "^" + "".join(".*" if t == "**" else "[^/]*" if t == "*" else re.escape(t)
                               for t in re.split(r"(\*\*|\*)", g) if t) + "$"
            rows.append((re.compile(rx), owner, (0 if "*" in g else 1, len(g.replace("*", ""))), g))
    return rows

def owners_of(rows, path):
    best, found = None, {}
    for rx, owner, spec, g in rows:
        if rx.match(path):
            if best is None or spec > best: best, found = spec, {owner: g}
            elif spec == best: found[owner] = g
    return found

def owner_of(rows, path):
    found = owners_of(rows, path)
    return next(iter(found)) if len(found) == 1 else None

def ignored(rel):
    parts = rel.split("/")
    name = parts[-1]
    if name == ".DS_Store" or name.endswith(" 2") or " 2." in name: return True   # iCloud duplicates ("x 2.swift")
    return any(p in (".build", ".swiftpm", "DerivedData", ".git") or p.endswith(".xcodeproj") for p in parts)

def mirrored_doc(rel):
    return (rel.startswith("Documentation/interfaces/") or rel == "Documentation/metro-station-design-tokens.json"
            or rel == "Documentation/HOLD-SIMULATOR.md")

def walk(root, mirror_filter=False):
    out = []
    for dp, dns, fns in os.walk(root):
        rel_dir = os.path.relpath(dp, root)
        rel_dir = "" if rel_dir == "." else rel_dir
        dns[:] = [d for d in dns if not ignored((rel_dir + "/" + d if rel_dir else d) + "/x")]
        for fn in fns:
            rel = rel_dir + "/" + fn if rel_dir else fn
            if ignored(rel) or rel == "GREEN.txt": continue
            if mirror_filter and rel.startswith("Documentation/") and not mirrored_doc(rel): continue
            out.append(rel)
    return out

def cmd_plan(repo, green, area, src, planfile):
    rows = load_rows(repo)
    live = walk(repo, mirror_filter=True)
    warn, result = [], {}
    live_owned = {area, "SKEL", "INTEGRATE", "READONLY", "NOBODY"}
    if area == "INTEGRATE":
        for p in live: result[p] = repo
    else:
        base = os.path.join(green, "SKEL")
        if area != "SKEL" and os.path.isdir(base):
            for p in walk(base, mirror_filter=True): result[p] = base
        else:
            if area != "SKEL":
                warn.append("WARNING: no skeleton baseline at %s: other areas' paths come from the LIVE tree" % base)
            for p in live: result[p] = repo
        if os.path.isdir(green):
            for snap in sorted(os.listdir(green)):
                sdir = os.path.join(green, snap)
                if snap in ("SKEL", area) or snap.startswith(".") or not os.path.isdir(sdir): continue
                for p in [p for p in result if tag(owner_of(rows, p)) == snap]: del result[p]
                for p in walk(sdir, mirror_filter=True):
                    if tag(owner_of(rows, p)) == snap: result[p] = sdir
        for p in [p for p in result if tag(owner_of(rows, p) or "?") in live_owned]: del result[p]
        for p in live:
            o = owner_of(rows, p)
            if o is None:
                warn.append("WARNING: unowned or doubly owned path, mirrored from the live tree: " + p)
                result[p] = repo
            elif tag(o) in live_owned:
                result[p] = repo
    groups = {}
    for p, root in result.items(): groups.setdefault(root, []).append(p)
    with open(planfile, "w") as plan:
        for i, (root, paths) in enumerate(sorted(groups.items())):
            lf = "%s.%d" % (planfile, i)
            with open(lf, "w") as f: f.write("\n".join(sorted(paths)) + "\n")
            plan.write("%s\t%s\t%d\n" % (root, lf, len(paths)))
    stale = []
    if os.path.isdir(src):
        planned = set(result)
        stale = [p for p in walk(src) if p not in planned and p != "App/Info.plist"]
    with open(planfile + ".stale", "w") as f: f.write("".join(p + "\n" for p in stale))
    for w in warn[:12]: print(w, file=sys.stderr)
    if len(warn) > 12: print("… and %d more warnings" % (len(warn) - 12), file=sys.stderr)

def cmd_mirror_id(src):
    h = hashlib.sha256()
    for p in sorted(walk(src)):
        st = os.stat(os.path.join(src, p))
        h.update(("%s\0%d\0%d\n" % (p, st.st_size, int(st.st_mtime))).encode())
    print(h.hexdigest()[:16])

def cmd_check_ownership(repo, verbose):
    rows = load_rows(repo)
    files = walk(repo)
    unowned, double, counts = [], [], {}
    for p in sorted(files):
        found = owners_of(rows, p)
        if not found: unowned.append(p)
        elif len(found) > 1: double.append((p, found))
        else:
            o = next(iter(found)); counts[o] = counts.get(o, 0) + 1
            if verbose: print("%-17s %s" % (o, p))
    print("check-ownership: %d files · %d owners · unowned %d · doubly owned %d" % (len(files), len(counts), len(unowned), len(double)))
    for o in sorted(counts): print("  %-17s %4d files" % (o, counts[o]))
    for p in unowned: print("UNOWNED " + p)
    for p, f in double: print("DOUBLY-OWNED %s %s" % (p, f))
    sys.exit(1 if unowned or double else 0)

def cmd_owner(repo, paths):
    rows = load_rows(repo)
    for p in paths:
        if os.path.isabs(p): p = os.path.relpath(p, repo)
        found = owners_of(rows, p)
        print("%s\t%s" % (p, ",".join(found) if found else "UNOWNED"))

def cmd_owned(repo, root, area):
    rows = load_rows(repo)
    for p in sorted(walk(root, mirror_filter=True)):
        if tag(owner_of(rows, p) or "?") == area: print(p)

# ---- lint-names (ARCHITECTURE §0 rule 4a) ----
SEEDS = {"GaussianOperator", "GaussianLinearPipeline", "GaussianSeparablePipeline", "GaussianComputeTilePipeline"}
FROZEN_TEST_HELPERS = {"Tests/BlurGPUTests/SKEL/GPUContractTests.swift": {"shaderDirectory"}}
DECL = re.compile(r"^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*((?:(?:public|internal|open|package|final|nonisolated|static|indirect|"
                  r"fileprivate|private|@MainActor|@preconcurrency)\s+)*)(struct|class|enum|protocol|actor|func|let|var|typealias)\s+"
                  r"([A-Za-z_][A-Za-z0-9_]*)")

def top_level_decls(text):
    depth, out, in_block = 0, [], False
    for n, raw in enumerate(text.split("\n"), 1):
        line = raw
        if in_block:
            if "*/" not in line: continue
            line, in_block = line.split("*/", 1)[1], False
        if "/*" in line and "*/" not in line.split("/*", 1)[1]: line, in_block = line.split("/*", 1)[0], True
        code = re.sub(r'"(?:\\.|[^"\\])*"', '""', line.split("//")[0])
        if depth == 0:
            m = DECL.match(code)
            if m and not re.search(r"\b(private|fileprivate)\b", m.group(1) or ""): out.append((n, m.group(2), m.group(3)))
        depth += code.count("{") - code.count("}")
    return out

def cmd_lint(repo, root, only):
    rows = load_rows(repo)
    problems, checked = [], 0
    for p in sorted(walk(root)):
        if not p.endswith(".swift"): continue
        owner = owner_of(rows, p) or "?"
        if only and tag(owner) != only: continue
        prefixes, exempt = None, set()
        m = re.match(r"^Sources/(?:BlurCore/Operators|BlurGPU/Pipelines)/([^/]+)/", p)
        if m:
            g = m.group(1)
            prefixes, exempt = [g, tag(owner)], {g + "Catalog", g + "Pipelines"} | SEEDS
        elif re.match(r"^(Tests/[^/]+|UITests)/[^/]+/", p):
            prefixes, exempt = [tag(owner) + "_"], FROZEN_TEST_HELPERS.get(p, set())
        if prefixes is None: continue
        checked += 1
        with open(os.path.join(root, p), encoding="utf-8") as f: text = f.read()
        for n, kind, name in top_level_decls(text):
            if name in exempt or any(name.startswith(x) for x in prefixes): continue
            problems.append("%s:%d: %s %s must start with %s (ARCHITECTURE §0 rule 4a)" % (p, n, kind, name, " or ".join(prefixes)))
    for x in problems: print(x)
    print("lint-names: %d Swift files checked%s, %d problems" % (checked, (" for " + only) if only else "", len(problems)))
    sys.exit(1 if problems else 0)

# ---- diagnostics classification: who owns each warning/error ----
def cmd_classify(repo, src, log, area):
    rows = load_rows(repo)
    seen, counts, mine = set(), {"warning": [0, 0], "error": [0, 0]}, []
    pat = re.compile(r"^(/[^:]+):(\d+)(?::(\d+))?: (warning|error): (.*)$")
    with open(log, errors="replace") as f:
        for line in f:
            m = pat.match(line.strip())
            if not m: continue
            key = m.groups()
            if key in seen: continue
            seen.add(key)
            path, kind = m.group(1), m.group(4)
            rel = os.path.relpath(path, src) if path.startswith(src + "/") else None
            o = owner_of(rows, rel) if rel else None
            counts[kind][0] += 1
            text = "%s:%s: %s: %s" % (rel or path, m.group(2), kind, m.group(5))
            if o and tag(o) == area:
                counts[kind][1] += 1; mine.append(text)
            else:
                print("  [%s] %s" % (o or "outside the repo", text))
    for x in mine: print("  [YOURS] " + x)
    print("diagnostics: %d warning(s), %d under %s's paths · %d error(s), %d under %s's paths" % (
        counts["warning"][0], counts["warning"][1], area, counts["error"][0], counts["error"][1], area))

def cmd_test_classes(src, area):
    out = []
    for target, folder in (("Blur2oolTests", "Tests/AppTests"), ("Blur2oolUITests", "UITests")):
        d = os.path.join(src, folder, area)
        if not os.path.isdir(d): continue
        for p in sorted(walk(d)):
            if p.endswith(".swift"):
                with open(os.path.join(d, p), encoding="utf-8") as f:
                    out += ["%s/%s" % (target, c) for c in re.findall(r"\bclass\s+(" + re.escape(area) + r"_\w+)\s*:", f.read())]
    print("\n".join(out))

if __name__ == "__main__":
    c, a = sys.argv[1], sys.argv[2:]
    if c == "plan": cmd_plan(*a[:5])
    elif c == "mirror-id": cmd_mirror_id(a[0])
    elif c == "check-ownership": cmd_check_ownership(a[0], len(a) > 1 and a[1] == "-v")
    elif c == "owner": cmd_owner(a[0], a[1:])
    elif c == "owned": cmd_owned(a[0], a[1], a[2])
    elif c == "lint": cmd_lint(a[0], a[1], a[2] if len(a) > 2 else "")
    elif c == "classify": cmd_classify(*a[:4])
    elif c == "test-classes": cmd_test_classes(a[0], a[1])
    else: sys.exit("unknown helper command " + c)
PYEOF
py() { python3 -I "$PY" "$@" }

# ------------------------------------------------------------------------------------------------------------------
# 3. Mirror (§11.1 rule 2; PLAN S13) and small helpers
# ------------------------------------------------------------------------------------------------------------------
mirror() {
  mkdir -p "$SRC"
  local plan="$WORK/.b2/plan" root list n stale
  py plan "$REPO" "$GREEN" "$AREA_TAG" "$SRC" "$plan"
  while IFS=$'\t' read -r root list n; do rsync -a --files-from="$list" "$root/" "$SRC/"; done < "$plan"
  while IFS= read -r stale; do [[ -n "$stale" ]] && rm -f "$SRC/$stale"; done < "$plan.stale"
  find "$SRC" -mindepth 1 -type d -empty -not -path '*.xcodeproj*' -delete 2>/dev/null || true
  MIRROR_ID="$(py mirror-id "$SRC")"
  print -r -- "$MIRROR_ID" > "$WORK/mirror.id"
}
xcodegen_project() { (cd "$SRC" && xcodegen generate --quiet) }
mark_ok() { print -r -- "${MIRROR_ID:-unknown} $(date '+%Y-%m-%d %H:%M:%S')" > "$WORK/checks/$1.ok" }
classify() { py classify "$REPO" "$SRC" "$1" "$AREA_TAG" }
now_label() { date '+%Y-%m-%d %H:%M %Z' }

# ------------------------------------------------------------------------------------------------------------------
# 4. Phone helpers: devicectl only, every call under a timeout; installs only com.utkarsh.blur2ool and its test runners
# ------------------------------------------------------------------------------------------------------------------
dctl() { perl -e 'alarm 300; exec @ARGV' xcrun devicectl "$@" }
phone_state() {   # CONNECTED, LOCKED or UNAVAILABLE
  local listing lock
  listing="$(perl -e 'alarm 120; exec @ARGV' xcrun devicectl list devices --search "$DEVICE_ID" 2>/dev/null || true)"
  if ! print -r -- "$listing" | grep -F "$DEVICE_ID" | grep -qiE 'connected|available'; then print UNAVAILABLE; return 0; fi
  lock="$(perl -e 'alarm 120; exec @ARGV' xcrun devicectl device info lockState --device "$DEVICE_ID" --json-output - 2>/dev/null \
          | python3 -I -c 'import json,sys
try:
    r = json.load(sys.stdin).get("result", {}); print("LOCKED" if r.get("passcodeRequired") else "UNLOCKED")
except Exception: print("UNKNOWN")' || print UNKNOWN)"
  if [[ "$lock" == LOCKED ]]; then print LOCKED; else print CONNECTED; fi
}
stamp_get() { [[ -f "$WORK/stamp" ]] && sed -n "s/^$1=//p" "$WORK/stamp" | head -1 }
phone_fail() {   # a devicectl failure that means "locked" or "absent" is not a build failure (exit 4)
  if print -r -- "$1" | grep -qiE 'locked|passcode'; then print "PHONE-LOCKED $(now_label)"; exit 4; fi
  if print -r -- "$1" | grep -qiE 'unavailable|not connected|could not be found|no device|timed out|disconnected|not paired'; then
    print "PHONE-UNAVAILABLE $(now_label)"; exit 4
  fi
  return 0
}
check_stamp() {   # the installed app must be this area's stamped build (bundle version = the stamp's build number)
  local want_version="$(stamp_get VERSION)" want_stamp="$(stamp_get STAMP)" out have rc=0
  [[ -n "$want_version" ]] || { print "STAMP MISMATCH: no stamp in $WORK/stamp (run device-build first)"; exit 5; }
  local apps_json="$WORK/.b2/apps.json"; rm -f "$apps_json"
  out="$(dctl device info apps --device "$DEVICE_ID" --bundle-id "$BUNDLE_ID" --json-output "$apps_json" 2>&1)" || rc=$?
  [[ $rc -eq 0 ]] || { phone_fail "$out"; print -r -- "$out" | tail -5; exit 1; }
  have="$(python3 -I -c 'import json,sys
try:
    apps = json.load(open(sys.argv[1])).get("result", {}).get("apps", [])
    print(apps[0].get("bundleVersion", "") if apps else "")
except Exception: print("")' "$apps_json")"
  if [[ "$have" != "$want_version" ]]; then
    print "STAMP MISMATCH: installed bundle version '${have:-none}' is not this build's $want_version ($want_stamp)."
    print "Another area's build is installed: rebuild (device-build) and retry; never judge that screenshot."
    exit 5
  fi
  # The app writes its B2BuildStamp into Library/Caches at launch (AppEnvironment); compare it when it is there.
  local copied="$WORK/.b2/installed-stamp.txt"; rm -f "$copied"
  if dctl device copy from --device "$DEVICE_ID" --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
       --source Library/Caches/B2BuildStamp.txt --destination "$copied" >/dev/null 2>&1 && [[ -s "$copied" ]]; then
    local launched="$(head -1 "$copied")"
    if [[ "$launched" == "$want_stamp" ]]; then print "STAMP OK $want_stamp (bundle version $want_version; the launched app reports the same B2BuildStamp)"
    else print "STAMP OK $want_stamp (bundle version $want_version; last launched B2BuildStamp in the container: $launched)"; fi
  else
    print "STAMP OK $want_stamp (bundle version $want_version)"
  fi
}
session_step() {   # one device-session step, inside the lock (never builds)
  local step="$1" verb out rc=0
  local -a words; words=(${(z)step}); words=(${(Q)words})
  verb="${words[1]}"; shift words
  case "$verb" in
    install)
      local app="$(stamp_get APP)"
      [[ -d "$app" ]] || { print "device-session: no stamped app (run device-build first)"; exit 1; }
      print "• install ${app:t} ($(stamp_get STAMP))"
      out="$(dctl device install app --device "$DEVICE_ID" "$app" 2>&1)" || rc=$?
      [[ $rc -eq 0 ]] || { phone_fail "$out"; print -r -- "$out" | tail -8; exit 1; }
      print -r -- "$out" | grep -iE 'installed|bundleID' | head -2 ;;
    check-stamp)
      print "• check-stamp"; check_stamp ;;
    launch)
      local -a env_args; env_args=()
      if [[ "${words[1]:-}" == "--validate" ]]; then env_args=(--environment-variables '{"MTL_DEBUG_LAYER":"1"}'); shift words; fi
      print "• launch ${words[*]}"
      out="$(dctl device process launch --device "$DEVICE_ID" --terminate-existing "${env_args[@]}" "$BUNDLE_ID" -- "${words[@]}" 2>&1)" || rc=$?
      [[ $rc -eq 0 ]] || { phone_fail "$out"; print -r -- "$out" | tail -8; exit 1; } ;;
    wait)
      sleep "${words[1]:-3}" ;;
    shot)
      local png="${words[1]:?shot needs a .png path}"
      [[ "$png" == /* ]] || png="$REPO/$png"
      mkdir -p "${png:h}"
      print "• shot $png"
      check_stamp
      out="$(dctl device capture screenshot --device "$DEVICE_ID" --destination "$png" 2>&1)" || rc=$?
      [[ $rc -eq 0 ]] || { phone_fail "$out"; print -r -- "$out" | tail -8; exit 1; }
      [[ -s "$png" ]] && print "  saved ($(sips -g pixelWidth -g pixelHeight "$png" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')px)" ;;
    test)
      local t="$AREA_TAG" kind=all
      while (( ${#words} )); do
        case "${words[1]}" in
          --area) t="${${(U)words[2]}//-/}"; shift 2 words ;;
          --kind) kind="${words[2]}"; shift 2 words ;;
          *) shift words ;;
        esac
      done
      device_test_inner "$t" "$kind" ;;
    *)
      print "device-session: unknown step '$verb' (install, check-stamp, launch [--validate] [args…], wait <s>, shot <png>, test --area TAG [--kind app|ui|all])"
      exit 2 ;;
  esac
}
device_test_inner() {   # xcodebuild test-without-building on the products of device-build-for-testing
  local t="$1" kind="${2:-all}" xctestrun log rc=0 executed c
  local -a classes only
  classes=(${(f)"$(py test-classes "$SRC" "$t")"})
  # --kind app runs only Tests/AppTests/<TAG> (UI automation on the phone needs the user's Face ID approval each time).
  [[ "$kind" == app ]] && classes=(${(M)classes:#Blur2oolTests/*})
  [[ "$kind" == ui ]] && classes=(${(M)classes:#Blur2oolUITests/*})
  (( ${#classes} )) || { print "device-test: no ${t}_ test classes in Tests/AppTests/$t or UITests/$t"; exit 1; }
  for c in "${classes[@]}"; do only+=("-only-testing:$c"); done
  xctestrun="$(ls -t "$WORK"/dd-device/Build/Products/*.xctestrun(N) 2>/dev/null | head -1)"
  [[ -f "$xctestrun" ]] || { print "device-test: no .xctestrun (run device-build-for-testing first)"; exit 1; }
  print "• test --area $t: ${classes[*]}"
  log="$WORK/logs/device-test-$t.log"
  perl -e 'alarm 1800; exec @ARGV' xcodebuild test-without-building -xctestrun "$xctestrun" \
    -destination "platform=iOS,id=$DEVICE_ID" -resultBundlePath "$WORK/results-$t-$(date +%s).xcresult" "${only[@]}" > "$log" 2>&1 || rc=$?
  grep -E "Test Case .*(passed|failed)|Test case .*(passed|failed)|Executed [0-9]+ test|error:|\*\* TEST" "$log" | tail -40
  executed="$(grep -oE 'Executed [0-9]+ test' "$log" | tail -1 | grep -oE '[0-9]+' || true)"
  if [[ $rc -ne 0 ]] && grep -qiE 'device is locked|passcode' "$log"; then print "PHONE-LOCKED $(now_label)"; exit 4; fi
  (( ${executed:-0} > 0 )) || { print "device-test: zero tests executed (log: $log)"; exit 1; }
  [[ $rc -eq 0 ]] || { print "device-test: FAILED (log: $log)"; exit 1; }
  print "device-test: $executed tests executed, 0 failures (log: $log)"
}

# ------------------------------------------------------------------------------------------------------------------
# 5. Commands
# ------------------------------------------------------------------------------------------------------------------
# Xcode 27's Metal flags for MTL_FAST_MATH YES + MTL_MATH_MODE FAST, copied from a `device` build log (the CompileMetalFile
# invocation of every App/GPU/Shaders file, 14 Oct 2026: `metal -c -target air64-apple-ios27.0 … -fmetal-math-mode=fast
# -fmetal-math-fp32-functions=fast`). metal-check uses them for the macOS per-file library of `gpucheck --metallib`.
METAL_XCODE_FLAGS=(-fmetal-math-mode=fast -fmetal-math-fp32-functions=fast)

do_core_test() {
  mirror
  local -a filter; filter=()
  while (( $# )); do
    case "$1" in
      --area) filter=(--filter "\\.${${(U)2}//-/}_"); shift 2 ;;
      --filter) filter=(--filter "$2"); shift 2 ;;
      *) filter+=("$1"); shift ;;
    esac
  done
  local log="$WORK/logs/core-test.log" rc=0
  (cd "$SRC" && swift test --scratch-path "$WORK/spm" "${filter[@]}") > "$log" 2>&1 || rc=$?
  grep -E "error:|✘|Test run with|Executed [0-9]+ test|recorded an issue" "$log" | tail -60 || true
  if (( rc == 0 )); then mark_ok core-test; print "core-test: PASS (log: $log)"; else print "core-test: FAIL (exit $rc, log: $log)"; exit $rc; fi
}

do_gpucheck() {
  mirror
  local log="$WORK/logs/gpucheck-build.log" rc=0
  (cd "$SRC" && swift build -c release --product blur-gpucheck --scratch-path "$WORK/spm-release") > "$log" 2>&1 || rc=$?
  (( rc == 0 )) || { tail -30 "$log"; print "gpucheck: build FAILED (log: $log)"; exit 2; }
  local -a args; args=("$@")
  if [[ " ${args[*]} " != *" --shaders "* ]]; then args=(--shaders App/GPU/Shaders "${args[@]}"); fi
  (cd "$SRC" && "$WORK/spm-release/release/blur-gpucheck" "${args[@]}") || rc=$?
  (( rc == 0 )) && mark_ok gpucheck
  exit $rc
}

do_typecheck_ios() {
  mirror
  local out="$WORK/ios-modules" log="$WORK/logs/typecheck-ios.log" rc=0 sdk
  sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
  local -a flags; flags=(-swift-version 6 -strict-concurrency=complete -target arm64-apple-ios27.0 -sdk "$sdk" -parse-as-library)
  rm -rf "$out"; mkdir -p "$out"
  {
    print "== BlurCore"
    (cd "$SRC" && xcrun -sdk iphoneos swiftc "${flags[@]}" -emit-module -module-name BlurCore -emit-module-path "$out/BlurCore.swiftmodule" \
       Sources/BlurCore/**/*.swift(N))
    print "== BlurGPU"
    (cd "$SRC" && xcrun -sdk iphoneos swiftc "${flags[@]}" -emit-module -module-name BlurGPU -I "$out" -emit-module-path "$out/BlurGPU.swiftmodule" \
       Sources/BlurGPU/**/*.swift(N))
    print "== App"
    (cd "$SRC" && xcrun -sdk iphoneos swiftc "${flags[@]}" -typecheck -module-name Blur2ool -I "$out" App/**/*.swift(N))
  } > "$log" 2>&1 || rc=$?
  sed -E "s#^(Sources|App)/#$SRC/\\1/#" "$log" > "$log.abs"
  classify "$log.abs"
  if (( rc == 0 )); then mark_ok typecheck-ios; print "typecheck-ios: OK (BlurCore, BlurGPU modules; App typechecked for arm64-apple-ios27.0, Swift 6, strict concurrency; log: $log)"
  else grep -E "error:" "$log" | head -25; print "typecheck-ios: FAILED (log: $log)"; exit 1; fi
}

do_metal_check() {
  mirror
  local out="$WORK/metal" diag="$WORK/logs/metal-check.log" n=0 f b
  rm -rf "$out"; mkdir -p "$out/ios" "$out/macos"; : > "$diag"
  local -a ios_air mac_air
  for f in "$SRC"/App/GPU/Shaders/*.metal(N) "$SRC"/App/DesignSystem/*.metal(N); do
    b="${f:t:r}"
    xcrun -sdk iphoneos metal -Wall -Wextra -target air64-apple-ios27.0 -c "$f" -o "$out/ios/$b.air" >> "$diag" 2>&1 || print "FAILED $f" >> "$diag"
    ios_air+=("$out/ios/$b.air"); n=$((n + 1))
  done
  xcrun -sdk iphoneos metallib "${ios_air[@]}" -o "$out/ios.metallib" >> "$diag" 2>&1 || print "FAILED iphoneos metallib" >> "$diag"
  # macOS per-file library for `gpucheck --metallib` (the app's offline per-file compile, with Xcode's fast-math flags).
  # The SwiftUI lens shader (App/DesignSystem) is not part of it: blur-gpucheck never loads SwiftUI shaders.
  for f in "$SRC"/App/GPU/Shaders/*.metal(N); do
    b="${f:t:r}"
    xcrun -sdk macosx metal -Wall -Wextra -target air64-apple-macos27.0 "${METAL_XCODE_FLAGS[@]}" -c "$f" -o "$out/macos/$b.air" >> "$diag" 2>&1 \
      || print "FAILED macOS $f" >> "$diag"
    mac_air+=("$out/macos/$b.air")
  done
  xcrun -sdk macosx metallib "${mac_air[@]}" -o "$out/macos.metallib" >> "$diag" 2>&1 || print "FAILED macOS metallib" >> "$diag"
  if [[ -s "$diag" ]]; then cat "$diag"; print "metal-check: FAIL ($(grep -c . "$diag") diagnostic lines; log: $diag)"; exit 1; fi
  mark_ok metal-check
  print "metal-check: 0 diagnostics · iphoneos -Wall -Wextra: $n files compiled and linked into $out/ios.metallib"
  print "metal-check: macOS per-file library $out/macos.metallib (${#mac_air} files; flags ${METAL_XCODE_FLAGS[*]})"
}

do_device() {
  mirror; xcodegen_project
  local cfg="${B2_CONFIG:-Release}" log="$WORK/logs/device.log" rc=0
  (cd "$SRC" && xcodebuild -project Blur2ool.xcodeproj -scheme Blur2ool -configuration "$cfg" -destination 'generic/platform=iOS' \
     -derivedDataPath "$WORK/dd" CODE_SIGNING_ALLOWED=NO build "$@") > "$log" 2>&1 || rc=$?
  classify "$log"
  grep -E '^\*\* BUILD' "$log" || true
  if (( rc == 0 )); then mark_ok device; print "device: generic/platform=iOS, $cfg, build only, unsigned (log: $log)"
  else grep -E "error:" "$log" | head -25; print "device: FAILED (log: $log)"; exit 1; fi
}

do_verify_shaders() {
  mirror
  local cfg="${B2_CONFIG:-Release}" bad=0 count=0 f repo_sha bundle_sha
  local app="$WORK/dd/Build/Products/$cfg-iphoneos/Blur2ool.app"
  [[ -d "$app/ShaderSources" ]] || { print "verify-shaders: $app/ShaderSources is missing (run device first)"; exit 1; }
  for f in "$SRC"/App/GPU/Shaders/*(.N); do
    count=$((count + 1))
    if cmp -s "$f" "$app/ShaderSources/${f:t}"; then print "identical  ${f:t}"; else print "DIFFERS    ${f:t}"; bad=1; fi
  done
  for f in "$app"/ShaderSources/*(.N); do
    [[ "${f:t}" == ShaderManifest.json ]] && continue
    [[ -f "$SRC/App/GPU/Shaders/${f:t}" ]] || { print "EXTRA      ${f:t} (bundle only)"; bad=1; }
  done
  (cd "$SRC" && swift build -c release --product blur-gpucheck --scratch-path "$WORK/spm-release") > "$WORK/logs/gpucheck-build.log" 2>&1 \
    || { print "verify-shaders: blur-gpucheck build failed"; exit 2; }
  repo_sha="$(cd "$SRC" && "$WORK/spm-release/release/blur-gpucheck" --print-sha --shaders App/GPU/Shaders | sed -n 's/^SHA //p')"
  (cd "$SRC" && "$WORK/spm-release/release/blur-gpucheck" --print-sha --shaders "$app/ShaderSources" \
     --manifest "$app/ShaderSources/ShaderManifest.json") > "$WORK/logs/verify-bundle.log" 2>&1 || bad=1
  bundle_sha="$(sed -n 's/^SHA //p' "$WORK/logs/verify-bundle.log")"
  grep -E '^manifest' "$WORK/logs/verify-bundle.log" || true
  print "combined SHA-256, repo App/GPU/Shaders (blur-gpucheck --print-sha): $repo_sha"
  print "combined SHA-256, bundle ShaderSources:                           $bundle_sha"
  if (( bad == 0 )) && [[ -n "$repo_sha" && "$repo_sha" == "$bundle_sha" ]]; then
    print "verify-shaders: PASS ($count files byte-identical; combined SHA-256 equal)"
  else print "verify-shaders: FAIL"; exit 1; fi
}

do_device_build() {   # outside the lock: a signed build for the phone, stamped <TAG>-<uuid>
  mirror; xcodegen_project
  local cfg="${B2_CONFIG:-Debug}" action=build stamp version log rc=0 dest
  [[ "$CMD" == device-build-for-testing ]] && action=build-for-testing
  stamp="$AREA_TAG-${(L)$(uuidgen)}"; version="$(date +%s)"
  log="$WORK/logs/$CMD.log"
  dest="platform=iOS,id=$DEVICE_ID"
  [[ "$(phone_state)" == UNAVAILABLE ]] && dest='generic/platform=iOS'
  (cd "$SRC" && xcodebuild -project Blur2ool.xcodeproj -scheme Blur2ool -configuration "$cfg" -destination "$dest" \
     -derivedDataPath "$WORK/dd-device" -allowProvisioningUpdates B2_BUILD_STAMP="$stamp" CURRENT_PROJECT_VERSION="$version" \
     "$action" "$@") > "$log" 2>&1 || rc=$?
  classify "$log"
  grep -E '^\*\* (BUILD|TEST BUILD)' "$log" || true
  (( rc == 0 )) || { grep -E "error:" "$log" | head -25; print "$CMD: FAILED (log: $log)"; exit 1; }
  local app="$WORK/dd-device/Build/Products/$cfg-iphoneos/Blur2ool.app"
  { print "STAMP=$stamp"; print "VERSION=$version"; print "APP=$app"; print "CONFIG=$cfg"; print "ACTION=$action"; print "DATE=$(date)"; } > "$WORK/stamp"
  print "$CMD: OK · B2BuildStamp $stamp · bundle version $version · destination $dest · $app"
}

do_device_session() {
  mirror > /dev/null
  local script="${1:?usage: device-session \"install; check-stamp; launch -B2Scenario bench; wait 3; shot Documentation/screenshots/X.png\"}" s
  [[ -f "$script" ]] && script="$(cat "$script")"
  s="$(phone_state)"
  [[ "$s" == UNAVAILABLE ]] && { print "PHONE-UNAVAILABLE $(now_label)"; exit 4; }
  [[ "$s" == LOCKED ]] && { print "PHONE-LOCKED $(now_label)"; exit 4; }
  print "device-session: waiting for $DEVICE_LOCK (lockf -t 900)"
  B2_SESSION_SCRIPT="$script" lockf -t 900 "$DEVICE_LOCK" "$SELF" __session-inner
}

do_session_inner() {   # runs only inside lockf: install → launch → capture → test, nothing compiled
  local st
  local -a steps
  print "device-session: lock held from $(date '+%H:%M:%S')"
  steps=("${(@s:;:)${B2_SESSION_SCRIPT//$'\n'/;}}")
  for st in "${steps[@]}"; do
    st="${st##[[:space:]]#}"; st="${st%%[[:space:]]#}"
    [[ -n "$st" ]] && session_step "$st"
  done
  print "device-session: lock released at $(date '+%H:%M:%S')"
}

do_xcode_test_action() {   # test / build-for-testing / test-without-building (device destination while the hold is ACTIVE)
  mirror; xcodegen_project
  local -a dargs; dargs=("$@")
  if (( ${dargs[(Ie)--device]} )); then dargs=("${(@)dargs:#--device}"); dargs+=(-destination "platform=iOS,id=$DEVICE_ID"); fi
  if [[ " ${dargs[*]} " != *" -destination "* && -n "${B2_DESTINATION:-}" ]]; then dargs+=(-destination "$B2_DESTINATION"); fi
  if [[ " ${dargs[*]} " != *" -destination "* ]]; then post_release_destination dargs; fi
  local log="$WORK/logs/$CMD.log" rc=0
  (cd "$SRC" && xcodebuild -project Blur2ool.xcodeproj -scheme Blur2ool -configuration "${B2_CONFIG:-Debug}" \
     -derivedDataPath "$WORK/dd-device" -allowProvisioningUpdates "$CMD" "${dargs[@]}") > "$log" 2>&1 || rc=$?
  classify "$log"
  grep -E '^\*\* |Executed [0-9]+ test|error:' "$log" | tail -12 || true
  return $rc
}

# ------------------------------------------------------------------------------------------------------------------
# 6. Post-release branches (ARCHITECTURE §12.5). Called only when HOLD-SIMULATOR.md no longer says ACTIVE: the guard in
#    section 1 exits 3 before any of these can run. Every simulator call is wrapped in a 180-s alarm; only the
#    simulator named by B2_SIM_UDID is touched (one per agent, named "Blur2ool <AREA>").
# ------------------------------------------------------------------------------------------------------------------
post_release_destination() {   # post_release_destination <array name>: append the agent's simulator destination
  hold_active && refuse_hold
  [[ -n "${B2_SIM_UDID:-}" ]] || { print "set B2_SIM_UDID to your own simulator (\"Blur2ool $AREA_TAG\")"; exit 2; }
  eval "$1+=(-destination 'platform=iOS Simulator,id=$B2_SIM_UDID')"
}
post_release_simctl() {   # post-release only
  hold_active && refuse_hold
  perl -e 'alarm 180; exec @ARGV' xcrun simctl "$@"
}
post_release() {
  hold_active && refuse_hold
  [[ -n "${B2_SIM_UDID:-}" ]] || { print "set B2_SIM_UDID to your own simulator (\"Blur2ool $AREA_TAG\")"; exit 2; }
  mirror; xcodegen_project
  local log="$WORK/logs/$1.log" rc=0 app png
  (cd "$SRC" && xcodebuild -project Blur2ool.xcodeproj -scheme Blur2ool -configuration Debug \
     -destination "platform=iOS Simulator,id=$B2_SIM_UDID" -derivedDataPath "$WORK/dd-sim" build) > "$log" 2>&1 || rc=$?
  classify "$log"; grep -E '^\*\* BUILD' "$log" || true
  (( rc == 0 )) || exit 1
  [[ "$1" == sim ]] && return 0
  png="${2:?usage: screenshot <png> [launch args]}"; shift 2
  [[ "$png" == /* ]] || png="$REPO/$png"
  app="$WORK/dd-sim/Build/Products/Debug-iphonesimulator/Blur2ool.app"
  post_release_simctl boot "$B2_SIM_UDID" 2>/dev/null || true
  post_release_simctl install "$B2_SIM_UDID" "$app"
  post_release_simctl launch --terminate-running-process "$B2_SIM_UDID" "$BUNDLE_ID" "$@"
  sleep 4
  post_release_simctl io "$B2_SIM_UDID" screenshot "$png"
  print "screenshot: $png"
}

# ------------------------------------------------------------------------------------------------------------------
# 7. Dispatch
# ------------------------------------------------------------------------------------------------------------------
case "$CMD" in
  mirror)            mirror; print "$SRC (mirror $MIRROR_ID, B2_AREA $AREA_TAG)" ;;
  owner)             py owner "$REPO" "$@" ;;
  check-ownership)   py check-ownership "$REPO" "$@" ;;
  lint-names)        mirror; py lint "$REPO" "$SRC" "${${${(U)2:-}}//-/}" ;;
  publish-green)
    [[ -d "$SRC" && -f "$WORK/mirror.id" ]] || { print "publish-green: no mirror in $WORK (run your checks first)"; exit 1; }
    MIRROR_ID="$(py mirror-id "$SRC")"
    for c in typecheck-ios core-test; do
      if [[ "$c" == core-test && "$AREA_TAG" != SKEL ]] && ! ls -d "$SRC"/Tests/*/"$AREA_TAG" >/dev/null 2>&1; then continue; fi
      if [[ ! -f "$WORK/checks/$c.ok" || "$(cut -d' ' -f1 "$WORK/checks/$c.ok")" != "$MIRROR_ID" ]]; then
        print "publish-green: $c has not passed on the current mirror ($MIRROR_ID); run it first"; exit 1
      fi
    done
    dest="$GREEN/$AREA_TAG"; tmp="$GREEN/.tmp-$AREA_TAG-$$"
    rm -rf "$tmp"; mkdir -p "$tmp"
    if [[ "$AREA_TAG" == SKEL ]]; then
      rsync -a --exclude '*.xcodeproj' --exclude '.build' --exclude '.swiftpm' "$SRC/" "$tmp/"
    else
      py owned "$REPO" "$SRC" "$AREA_TAG" > "$WORK/.b2/owned.list"
      rsync -a --files-from="$WORK/.b2/owned.list" "$SRC/" "$tmp/"
    fi
    {
      print "GREEN $AREA_TAG"
      print "published: $(date '+%Y-%m-%d %H:%M:%S %Z')"
      print "mirror: $MIRROR_ID"
      for c in typecheck-ios core-test metal-check gpucheck device; do [[ -f "$WORK/checks/$c.ok" ]] && print "check $c: $(cat "$WORK/checks/$c.ok")"; done
      [[ "${1:-}" == "--note" ]] && print "note: ${2:-}"
      print "files: $(find "$tmp" -type f | wc -l | tr -d ' ')"
    } > "$tmp/GREEN.txt"
    rm -rf "$dest.old"; [[ -d "$dest" ]] && mv "$dest" "$dest.old"
    mv "$tmp" "$dest"; rm -rf "$dest.old"
    print "publish-green: $dest"; cat "$dest/GREEN.txt" ;;
  core-test)         do_core_test "$@" ;;
  gpucheck)          do_gpucheck "$@" ;;
  typecheck-ios)     do_typecheck_ios ;;
  metal-check)       do_metal_check ;;
  device)            do_device "$@" ;;
  verify-shaders)    do_verify_shaders ;;
  device-status)
    s="$(phone_state)"; print "$s $DEVICE_ID"
    [[ "$s" == UNAVAILABLE ]] && print "PHONE-UNAVAILABLE $(now_label)"
    [[ "$s" == LOCKED ]] && print "PHONE-LOCKED $(now_label)"
    true ;;
  device-build|device-build-for-testing) do_device_build "$@" ;;
  device-session)    do_device_session "$@" ;;
  __session-inner)   mirror > /dev/null; do_session_inner ;;
  device-install)    exec "$SELF" device-session "install; check-stamp" ;;
  device-launch)     exec "$SELF" device-session "check-stamp; launch ${(j: :)${(q)@}}" ;;
  device-shot)       [[ -n "${1:-}" ]] || { print -u2 "usage: device-shot <png>"; exit 2; }; exec "$SELF" device-session "shot ${(q)1}" ;;
  device-test)       exec "$SELF" device-session "test $*" ;;   # [--area TAG] [--kind app|ui|all]; default: your own tag, all
  test|build-for-testing|test-without-building) do_xcode_test_action "$@" ;;
  sim|screenshot)    post_release "$CMD" "$@" ;;
  *)                 print -u2 "Tools/build.sh: unknown command '$CMD' (see Tools/build.sh help)"; exit 2 ;;
esac
