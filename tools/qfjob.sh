#!/usr/bin/env bash
# Client-side helper for the QF job runner.
#   qfjob.sh pack  <job_dir> <job_id> [repo_checkout_dir]   -> <dir>/jobs/<job_id>.tar.gpg.b64 (commit + dispatch run-job.yml)
#   qfjob.sh fetch <job_id> [owner/repo] [dest_dir]          -> downloads results/<job_id>/* via the public API and decrypts to dest_dir/<job_id>/hopN/out/
# Key: env QF_ACTION_KEY, or the file in QF_KEY_FILE (default /data/qf_infra/QF_ACTION_KEY).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
if [ -z "${QF_ACTION_KEY:-}" ]; then QF_ACTION_KEY=$(cat "${QF_KEY_FILE:-/data/qf_infra/QF_ACTION_KEY}"); fi
export QF_ACTION_KEY
cmd=${1:-}; shift || true
case "$cmd" in
  pack)
    dir=${1:?job_dir}; id=${2:?job_id}; out=${3:-.}
    test -f "$dir/run.sh" || { echo "run.sh missing in $dir" >&2; exit 1; }
    mkdir -p "$out/jobs"
    tar -czf - -C "$dir" . | bash "$here/qfcrypt.sh" enc - "$out/jobs/$id.tar.gpg.b64"
    echo "packed -> $out/jobs/$id.tar.gpg.b64 ($(du -k "$out/jobs/$id.tar.gpg.b64" | cut -f1) KB)" ;;
  fetch)
    id=${1:?job_id}; repo=${2:-Nicholas022400701/QF}; dest=${3:-results_plain}
    mkdir -p "$dest/$id"
    curl -fsSL "https://api.github.com/repos/$repo/contents/results/$id" \
      | python3 -c 'import json,sys; [print(f["name"], f["download_url"]) for f in json.load(sys.stdin)]' \
      | while read -r name url; do
          case "$name" in
            *.out.tar.gpg.b64) hop=${name%%.out.tar.gpg.b64}; mkdir -p "$dest/$id/$hop"
                               curl -fsSL "$url" | bash "$here/qfcrypt.sh" dec - - | tar -xzf - -C "$dest/$id/$hop"
                               echo "decrypted $name -> $dest/$id/$hop/out" ;;
            *.status.txt)      curl -fsSL "$url" -o "$dest/$id/$name"; echo "== $name"; cat "$dest/$id/$name" ;;
          esac
        done ;;
  *) echo "usage: qfjob.sh pack <job_dir> <job_id> [repo_dir] | fetch <job_id> [owner/repo] [dest]" >&2; exit 2 ;;
esac
