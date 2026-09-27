#!/bin/bash
# Cloud sessions only: install the asset-pipeline tools and generate assets.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi
exec "$CLAUDE_PROJECT_DIR/tools/cloud_setup.sh"
