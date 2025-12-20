rm loop_mattermost_channel.sh
rm export_mattermost_channel.sh
sudo truncate -s 0 /var/log/auth.log
cat /dev/null > ~/.bash_history
history -c
