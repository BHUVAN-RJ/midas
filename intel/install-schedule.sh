#!/bin/zsh
# Install the macOS launchd schedule for Midas intel on this machine:
#   daily  at 07:00 and 19:00
#   weekly on Sunday at 09:00
# Re-run after moving the repo. Remove with: intel/install-schedule.sh --uninstall

set -eu

intel_dir="${0:A:h}"
launch_agents_dir="$HOME/Library/LaunchAgents"
user_id="$(id -u)"
mkdir -p "$launch_agents_dir" "$HOME/Library/Logs/midas-intel"

daily_label="com.midas.intel-daily"
weekly_label="com.midas.intel-weekly"

unload_job() {
  local job_label="$1"
  launchctl bootout "gui/$user_id/$job_label" 2>/dev/null || true
  rm -f "$launch_agents_dir/$job_label.plist"
}

if [ "${1:-}" = "--uninstall" ]; then
  unload_job "$daily_label"
  unload_job "$weekly_label"
  echo "Midas intel schedule removed."
  exit 0
fi

write_plist() {
  local job_label="$1" run_mode="$2" calendar_xml="$3"
  cat > "$launch_agents_dir/$job_label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$job_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$intel_dir/run.sh</string>
    <string>$run_mode</string>
  </array>
  <key>StartCalendarInterval</key>
  $calendar_xml
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/midas-intel/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/midas-intel/launchd.log</string>
</dict>
</plist>
PLIST
  plutil -lint "$launch_agents_dir/$job_label.plist" >/dev/null
  launchctl bootout "gui/$user_id/$job_label" 2>/dev/null || true
  launchctl bootstrap "gui/$user_id" "$launch_agents_dir/$job_label.plist"
}

daily_calendar='<array>
    <dict><key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer></dict>
    <dict><key>Hour</key><integer>19</integer><key>Minute</key><integer>0</integer></dict>
  </array>'
weekly_calendar='<dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>'

chmod +x "$intel_dir/run.sh"
write_plist "$daily_label" daily "$daily_calendar"
write_plist "$weekly_label" weekly "$weekly_calendar"
echo "Installed: $daily_label (07:00, 19:00) and $weekly_label (Sun 09:00). Logs: ~/Library/Logs/midas-intel/"
