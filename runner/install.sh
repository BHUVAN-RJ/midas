#!/bin/zsh
# Installs the repair runner as a launchd agent on this Mac (the founder's Mac mini only).
# Keeps it alive across crashes and logins. Remove with: runner/install.sh --uninstall
set -eu

runner_dir="${0:A:h}"
launch_agents_dir="$HOME/Library/LaunchAgents"
label="com.midas.repair-runner"
plist_path="$launch_agents_dir/$label.plist"
log_dir="$HOME/Library/Logs/midas-runner"
user_id="$(id -u)"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$user_id/$label" 2>/dev/null || true
  rm -f "$plist_path"
  echo "Repair runner removed."
  exit 0
fi

if [ ! -f "$HOME/.midas-runner/env" ]; then
  echo "Missing $HOME/.midas-runner/env. See runner/README.md." >&2
  exit 1
fi

mkdir -p "$launch_agents_dir" "$log_dir"
chmod 600 "$HOME/.midas-runner/env"

cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$runner_dir/bin/start.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>StandardOutPath</key>
  <string>$log_dir/runner.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/runner.log</string>
</dict>
</plist>
PLIST

plutil -lint "$plist_path" >/dev/null
launchctl bootout "gui/$user_id/$label" 2>/dev/null || true
launchctl bootstrap "gui/$user_id" "$plist_path"
echo "Repair runner installed: $label. Log: $log_dir/runner.log"
