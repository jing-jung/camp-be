#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATHFIX="/tmp/stockbrief-pathfix"
mkdir -p "$PATHFIX"
cat >"$PATHFIX/python3" <<'SH'
#!/usr/bin/env bash
exec py -3 "$@"
SH
chmod +x "$PATHFIX/python3"
export PATH="$PATHFIX:$PATH"

cd "$ROOT"
exec bash scripts/bootstrap_github_oidc.sh \
  --environment dev-jung \
  --region ap-northeast-2 \
  --github-owner jing-jung \
  --github-repo camp-be \
  --write-deploy-profile-vars \
  "$@"
