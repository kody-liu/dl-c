cat <<'EOF' > export_mattermost_channel.sh
#!/usr/bin/env bash
set -euo pipefail

# PostgreSQL DSN
DB_DSN="postgres://mmuser:kIEi71wIHGZMqPqtjQjweGi7rh3O72FBYp9a0qtO@localhost:5432/mattermost?sslmode=disable"

# Mattermost Channel 與日期範圍
CHANNEL_ID="81379rbpyiyrmxojfb56rrxywo"
START_DATE="2025-12-10"
END_DATE="2025-12-20"

# 本地資料目錄與暫存匯出目錄
DATA_DIR="/var/opt/mattermost/data"
EXPORT_DIR="/tmp/mattermost_export"

# S3 設定
S3_BUCKET="lie-cheater"
S3_REGION="ap-northeast-1"
S3_BASE_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/mattermost"

mkdir -p "$EXPORT_DIR"

current="$START_DATE"

while [[ "$current" < "$END_DATE" || "$current" == "$END_DATE" ]]; do
  next=$(date -I -d "$current +1 day")
  csv="$EXPORT_DIR/$current.csv"

  echo "Exporting $current ..."

  # 匯出當日訊息
  psql "$DB_DSN" <<SQL > "$csv"
COPY (
  SELECT
    to_char(to_timestamp(p.createat / 1000) AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Taipei', 'YYYY-MM-DD HH24:MI:SS') AS created_at,
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
    AND to_timestamp(p.createat / 1000) >= TIMESTAMPTZ '$current 00:00:00+00'
    AND to_timestamp(p.createat / 1000) <  TIMESTAMPTZ '$next 00:00:00+00'
  ORDER BY p.createat
) TO STDOUT WITH CSV HEADER;
SQL

  # 判斷是否有訊息
  line_count=$(wc -l < "$csv")
  if [[ "$line_count" -le 1 ]]; then
    echo "No messages found for $current, skipping CSV upload."
  else
    echo "Uploading CSV $current.csv"
    curl -sSf -X PUT --upload-file "$csv" \
      "$S3_BASE_URL/csv/$current.csv"

    # 處理附件
    tail -n +2 "$csv" | cut -d',' -f4 | sort -u | grep -v '^$' | while read -r fid; do
      find "$DATA_DIR" -type d -name "$fid" | while read -r dir; do
        for file in "$dir"/*; do
          fname=$(basename "$file")
          # URL encode 檔名
          fname_url=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$fname")
          echo "Uploading file $fid/$fname"
          curl -sSf -X PUT --upload-file "$file" \
            "$S3_BASE_URL/files/$fid/$fname_url"
        done
      done
    done
  fi

  current="$next"
done

echo "Export complete."
EOF

