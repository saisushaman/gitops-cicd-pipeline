#!/usr/bin/env bash
# Delete the local kind cluster created by setup.sh.
set -euo pipefail
CLUSTER=gitops-demo
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "Deleting kind cluster '$CLUSTER'…"
  kind delete cluster --name "$CLUSTER"
else
  echo "No kind cluster named '$CLUSTER'."
fi
