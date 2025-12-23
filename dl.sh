cat <<'EOF' > export_mattermost_channel.sh
#!/usr/bin/env bash
set -u  # 只保留未定義變數檢查

# ---- 強制要求環境變數 ----
if [[ -z "${START_DATE:-}" ]]; then
  echo "ERROR: START_DATE is not set"
  echo "Usage: START_DATE=YYYY-MM-DD ./export_mattermost_channel.sh"
  exit 1
fi

# PostgreSQL DSN
DB_DSN="postgres://mmuser:kIEi71wIHGZMqPqtjQjweGi7rh3O72FBYp9a0qtO@localhost:5432/mattermost?sslmode=disable"

# Mattermost Channel ID
CHANNEL_ID="81379rbpyiyrmxojfb56rrxywo"

# 本地資料目錄與暫存匯出目錄
DATA_DIR="/var/opt/mattermost/data"
EXPORT_DIR="/tmp/mattermost_export"

# S3 設定
S3_BUCKET="lie-cheater"
S3_REGION="ap-northeast-1"
S3_BASE_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/mattermost"

mkdir -p "$EXPORT_DIR" || {
  echo "ERROR: Failed to create export directory $EXPORT_DIR" >&2
  exit 1
}

# 設定日期範圍 (以台灣時間為準)
current="$START_DATE"
next=$(date -I -d "$current +1 day")
csv="$EXPORT_DIR/$current.csv"

echo "Exporting $current (Asia/Taipei Time) ..."

# 匯出當日訊息
# 關鍵：進入 psql 後立即 SET TIME ZONE，確保 to_timestamp 與過濾條件一致
psql "$DB_DSN" <<SQL > "$csv" 2> "$EXPORT_DIR/psql_error.log"
SET TIME ZONE 'Asia/Taipei';

COPY (
  SELECT
    to_char(to_timestamp(p.createat / 1000), 'YYYY-MM-DD HH24:MI:SS') AS created_at,
    u.username,
    replace(p.message, E'\n', ' ') AS message,
    f.id   AS file_id,
    f.name AS file_name
  FROM posts p
  JOIN users u ON p.userid = u.id
  LEFT JOIN LATERAL jsonb_array_elements_text(p.fileids::jsonb) AS fid(file_id)
    ON true
  LEFT JOIN fileinfo f
    ON f.id = fid.file_id
  WHERE p.channelid = '$CHANNEL_ID'
    -- 這裡的比較會基於上面設定的 Asia/Taipei 時區
    AND to_timestamp(p.createat / 1000) >= '$current 00:00:00'
    AND to_timestamp(p.createat / 1000) <  '$next 00:00:00'
  ORDER BY p.createat
) TO STDOUT WITH CSV HEADER;
SQL

if [[ $? -ne 0 ]]; then
  echo "ERROR: psql command failed. See $EXPORT_DIR/psql_error.log" >&2
  cat "$EXPORT_DIR/psql_error.log" >&2
  exit 1
fi

# 判斷是否有訊息（只有 header 不上傳）
line_count=$(wc -l < "$csv")
if [[ "$line_count" -le 1 ]]; then
  echo "No messages found for $current, skipping CSV upload."
else
  echo "Uploading CSV $current.csv to S3..."
  curl -sSf -X PUT --upload-file "$csv" \
    "$S3_BASE_URL/csv/$current.csv" || {
    echo "ERROR: Failed to upload CSV $current.csv" >&2
    exit 1
  }

  # 處理附件
  echo "Processing attachments..."
  tail -n +2 "$csv" | cut -d',' -f4 | sort -u | grep -v '^$' | while read -r fid; do
    # Mattermost 檔案通常存放在 DATA_DIR 下以日期命名的路徑中，這裡用 find 找 ID 匹配的目錄
    find "$DATA_DIR" -type d -name "$fid" | while read -r dir; do
      for file in "$dir"/*; do
        if [[ -f "$file" ]]; then
          fname=$(basename "$file")
          # 使用 python3 進行 URL Encode，避免檔名有特殊字元上傳失敗
          fname_url=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$fname")
          echo "Uploading file $fid/$fname"
          curl -sSf -X PUT --upload-file "$file" \
            "$S3_BASE_URL/files/$fid/$fname_url" || {
            echo "ERROR: Failed to upload file $fid/$fname" >&2
          }
        fi
      done
    done
  done
fi

echo "Export complete for $current."
EOF
