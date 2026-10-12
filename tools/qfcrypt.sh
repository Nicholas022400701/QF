#!/usr/bin/env bash
# Symmetric, authenticated encryption (gpg AES-256, base64 armoured so files can live in git / artifacts).
# usage: qfcrypt.sh enc <in|-> <out|->     qfcrypt.sh dec <in|-> <out|->
# key: environment variable QF_ACTION_KEY (GitHub Actions secret of the same name).
set -euo pipefail
mode=${1:?enc|dec}; in=${2:?in}; out=${3:?out}
: "${QF_ACTION_KEY:?QF_ACTION_KEY not set}"
[ "$in" = "-" ] && in=/dev/stdin
[ "$out" = "-" ] && out=/dev/stdout
export GNUPGHOME="${GNUPGHOME:-$(mktemp -d)}"
gpgopts=(--batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3)
case "$mode" in
  enc) gpg "${gpgopts[@]}" --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 --s2k-count 65011712 -o - "$in" 3< <(printf '%s' "$QF_ACTION_KEY") | base64 -w0 > "$out" ;;
  dec) base64 -d "$in" | gpg "${gpgopts[@]}" --decrypt -o "$out" 3< <(printf '%s' "$QF_ACTION_KEY") ;;
  *) echo "usage: qfcrypt.sh enc|dec <in|-> <out|->" >&2; exit 2 ;;
esac
