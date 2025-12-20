cat <<'EOF' > loop_mattermost_channel.sh

#!/usr/bin/env bash
set -euo pipefail

# 強制要求起始日期環境變數
if [[ -z "${START_DATE:-}" ]]; then
  echo "ERROR: START_DATE is not set"
  exit 1
fi

# 今天的日期
TODAY=$(date -I)

current="$START_DATE"

while true; do
  # 如果 current 已經是未來日期，退出迴圈
  if [[ "$current" > "$TODAY" ]]; then
    echo "Reached future date ($current), exiting loop."
    break
  fi

  echo "Processing date: $current"

  # 呼叫單日 export script
  START_DATE="$current" ./export_mattermost_channel.sh

  # 日期 +1 天
  current=$(date -I -d "$current +1 day")
done

echo "All done."
EOF
