
# 給執行權限
chmod +x export_mattermost_channel.sh
chmod +x loop_mattermost_channel.sh




START_DATE="2025-02-13" sudo -E bash ./loop_mattermost_channel.sh


START_DATE="2025-02-11" END_DATE="2025-12-17" sudo  -E bash ./export_mattermost_channel.sh
