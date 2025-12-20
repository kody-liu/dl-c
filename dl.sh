cat <<'EOF' > export_mattermost_channel.sh
#!/usr/bin/env bash
set -euo pipefail

set -a
source /etc/mattermost/mmomni.mattermost.env
set +a

DB_DSN="${MM_SQLSETTINGS_DATASOURCE}"

CHANNEL_ID="81379rbpyiyrmxojfb56rrxywo"
START_DATE="2025-12-10"
END_DATE="2025-12-20"

DATA_DIR="/var/opt/mattermost/data"
EXPORT_DIR="/tmp/mattermost_export"

# ===== 改成你的 S3 資訊 =====
S3_BUCKET="lie-cheater"
S3_REGION="ap-northeast-1"
S3_BASE_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/mattermost"
# ===========================

mkdir -p "$EXPORT_DIR"

current="$START_DATE"

while [[ "$current" < "$END_DATE" ]]; do
  next=$(date -u -d "$current +1 day" +"%Y-%m-%d")
  csv="$EXPORT_DIR/$current.csv"

  echo "Exporting $current..."

  psql "$DB_DSN" <<SQL > "$csv"
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
    AND to_timestamp(p.createat / 1000) >= TIMESTAMPTZ '$current 00:00:00+00'
    AND to_timestamp(p.createat / 1000) <  TIMESTAMPTZ '$next 00:00:00+00'
  ORDER BY p.createat
) TO STDOUT WITH CSV HEADER;
SQL

  echo "Uploading CSV $current.csv"
  curl -sSf -X PUT --upload-file "$csv" \
    "$S3_BASE_URL/csv/$current.csv"

  # 處理附件
  tail -n +2 "$csv" | cut -d',' -f4 | sort -u | grep -v '^$' | while read -r fid; do
    find "$DATA_DIR" -type d -name "$fid" | while read -r dir; do
      for file in "$dir"/*; do
        fname=$(basename "$file")
        echo "Uploading file $fid/$fname"
        curl -sSf -X PUT --upload-file "$file" \
          "$S3_BASE_URL/files/$fid/$fname"
      done
    done
  done

  current="$next"
done
EOF