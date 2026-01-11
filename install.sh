#!/bin/bash
# Elgato Key Light Camera Automation - Installer
# Run: curl -fsSL <url> | bash  OR  bash install.sh

set -e

INSTALL_DIR="$HOME/elgato-camera-light"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.elgato-camera-light.plist"

echo "Installing Elgato Light Automation..."

# Create directory
mkdir -p "$INSTALL_DIR"

# Write Python script
cat > "$INSTALL_DIR/camera_light.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Elgato Key Light Camera Automation - turns light on/off with camera usage.
Uses log stream for fast ON detection, polling for OFF detection.
"""

import json
import subprocess
import sys
import threading
import time
import urllib.request
import urllib.error
from pathlib import Path


def load_config():
    """Load configuration from config.json with defaults."""
    defaults = {
        "light_ip": "YOUR_LIGHT_IP",
        "light_port": 9123,
        "poll_interval_seconds": 2,
        "off_delay_seconds": 3,
        "on_settings": {"brightness": 50, "temperature": 213},
        "off_settings": {"brightness": 40, "temperature": 162}
    }
    config_path = Path(__file__).parent / "config.json"
    if config_path.exists():
        try:
            with open(config_path) as f:
                defaults.update(json.load(f))
        except Exception as e:
            print(f"Config error: {e}", file=sys.stderr, flush=True)
    return defaults


def set_light(config, on):
    """Control the Elgato Key Light."""
    url = f"http://{config['light_ip']}:{config['light_port']}/elgato/lights"
    settings = config['on_settings'] if on else config['off_settings']

    payload = {
        "numberOfLights": 1,
        "lights": [{
            "on": 1 if on else 0,
            "brightness": settings['brightness'],
            "temperature": settings['temperature']
        }]
    }

    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode('utf-8'),
            method='PUT',
            headers={'Content-Type': 'application/json'}
        )
        urllib.request.urlopen(req, timeout=5)
        print(f"Light {'ON' if on else 'OFF'} (brightness: {settings['brightness']}%, temp: {settings['temperature']})", flush=True)
        return True
    except Exception as e:
        print(f"Light error: {e}", file=sys.stderr, flush=True)
        return False


def is_camera_active():
    """Check if any camera is streaming via CoreMediaIO."""
    # Primary: Swift helper using kCMIODevicePropertyDeviceIsRunningSomewhere
    try:
        helper = Path(__file__).parent / "camera_check"
        if helper.exists():
            result = subprocess.run([str(helper)], capture_output=True, timeout=5)
            if result.returncode == 0:
                return True
    except Exception:
        pass

    # Fallback: IORegistry for built-in camera
    try:
        result = subprocess.run(
            ['ioreg', '-l', '-w0', '-r', '-c', 'AppleH13CamIn'],
            capture_output=True, text=True, timeout=5
        )
        if '"FrontCameraStreaming" = Yes' in result.stdout:
            return True
    except Exception:
        pass

    return False


class CameraMonitor:
    """Hybrid camera monitor using log stream + polling."""

    def __init__(self, config, callback):
        self.config = config
        self.callback = callback
        self.light_is_on = False
        self.lock = threading.Lock()
        self.log_process = None
        self.should_stop = False
        self.last_camera_active_time = 0
        self.off_delay = config.get('off_delay_seconds', 3)

    def start_log_stream(self):
        """Monitor log stream for camera START events."""
        cmd = [
            'log', 'stream',
            '--predicate',
            'subsystem == "com.apple.cmio" AND eventMessage CONTAINS "Start"',
            '--style', 'compact'
        ]

        try:
            self.log_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1
            )

            for line in self.log_process.stdout:
                if self.should_stop:
                    break
                self._process_log_line(line)

        except Exception as e:
            print(f"Error in log stream: {e}", file=sys.stderr, flush=True)

    def _process_log_line(self, line):
        """Process log line for camera START events."""
        # Skip log stream header lines
        if 'Filtering' in line or 'Timestamp' in line:
            return

        # Verify camera is actually active (filters startup noise)
        if not is_camera_active():
            return

        with self.lock:
            if not self.light_is_on:
                self.light_is_on = True
                self.last_camera_active_time = time.time()
                print("Camera START (log stream)", flush=True)
                self.callback(True)

    def poll_camera_state(self):
        """Poll for camera state to detect when it turns OFF."""
        while not self.should_stop:
            time.sleep(self.config.get('poll_interval_seconds', 2))
            active = is_camera_active()

            with self.lock:
                if active:
                    self.last_camera_active_time = time.time()
                    if not self.light_is_on:
                        self.light_is_on = True
                        print("Camera ON (polling)", flush=True)
                        self.callback(True)
                elif self.light_is_on and time.time() - self.last_camera_active_time >= self.off_delay:
                    self.light_is_on = False
                    print("Camera OFF (polling)", flush=True)
                    self.callback(False)

    def start(self):
        """Start both log stream and polling monitors."""
        threading.Thread(target=self.start_log_stream, daemon=True).start()
        threading.Thread(target=self.poll_camera_state, daemon=True).start()
        print(f"Monitoring (poll: {self.config.get('poll_interval_seconds', 2)}s, off delay: {self.off_delay}s)", flush=True)

    def stop(self):
        """Stop monitoring."""
        self.should_stop = True
        if self.log_process:
            self.log_process.terminate()
            self.log_process.wait()


LOG_FILE = Path("/tmp/elgato-camera-light.log")
MAX_LOG_SIZE = 1024 * 1024  # 1MB
LOG_CHECK_INTERVAL = 86400  # 24 hours


def check_log_size():
    """Truncate log file if it exceeds MAX_LOG_SIZE."""
    try:
        if LOG_FILE.exists() and LOG_FILE.stat().st_size > MAX_LOG_SIZE:
            LOG_FILE.write_text("")
            print("Log rotated", flush=True)
    except Exception:
        pass


def main():
    config = load_config()
    print(f"Elgato Light Automation - {config['light_ip']}:{config['light_port']}", flush=True)

    monitor = CameraMonitor(config, lambda on: set_light(config, on))
    monitor.start()

    last_log_check = 0
    try:
        while True:
            time.sleep(60)
            if time.time() - last_log_check >= LOG_CHECK_INTERVAL:
                check_log_size()
                last_log_check = time.time()
    except KeyboardInterrupt:
        print("\nStopping...", flush=True)
        monitor.stop()


if __name__ == "__main__":
    main()
PYTHON_EOF

# Write Swift helper
cat > "$INSTALL_DIR/camera_check.swift" << 'SWIFT_EOF'
import CoreMediaIO
import Foundation

func isCameraStreaming() -> Bool {
    var propertyAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )

    var dataSize: UInt32 = 0
    var result = CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize
    )

    guard result == kCMIOHardwareNoError else { return false }

    let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
    guard deviceCount > 0 else { return false }

    var devices = [CMIODeviceID](repeating: 0, count: deviceCount)
    result = CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &propertyAddress,
        0, nil,
        dataSize,
        &dataSize,
        &devices
    )

    guard result == kCMIOHardwareNoError else { return false }

    for device in devices {
        var isRunningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)

        let runningResult = CMIOObjectGetPropertyData(
            device,
            &isRunningAddress,
            0, nil,
            isRunningSize,
            &isRunningSize,
            &isRunning
        )

        if runningResult == kCMIOHardwareNoError && isRunning != 0 {
            return true
        }
    }

    return false
}

if isCameraStreaming() {
    print("1")
    exit(0)
} else {
    print("0")
    exit(1)
}
SWIFT_EOF

# Compile Swift helper
echo "Compiling camera helper..."
swiftc -O "$INSTALL_DIR/camera_check.swift" -o "$INSTALL_DIR/camera_check"

# Create default config if not exists
if [ ! -f "$INSTALL_DIR/config.json" ]; then
    cat > "$INSTALL_DIR/config.json" << 'CONFIG_EOF'
{
    "light_ip": "YOUR_LIGHT_IP",
    "light_port": 9123,
    "poll_interval_seconds": 2,
    "off_delay_seconds": 3,
    "on_settings": {
        "brightness": 40,
        "temperature": 162
    },
    "off_settings": {
        "brightness": 40,
        "temperature": 162
    }
}
CONFIG_EOF
    echo "Created config.json - edit light_ip to match your Elgato Key Light"
fi

# Create launchd plist
mkdir -p "$PLIST_DIR"
cat > "$PLIST_DIR/$PLIST_NAME" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.elgato-camera-light</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$INSTALL_DIR/camera_light.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/elgato-camera-light.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/elgato-camera-light.err</string>
</dict>
</plist>
PLIST_EOF

# Load the service
launchctl unload "$PLIST_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$PLIST_DIR/$PLIST_NAME"

echo ""
echo "Installation complete!"
echo ""
echo "Config: $INSTALL_DIR/config.json"
echo "Logs:   /tmp/elgato-camera-light.log"
echo ""
echo "Commands:"
echo "  Restart: launchctl unload ~/Library/LaunchAgents/$PLIST_NAME && launchctl load ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Stop:    launchctl unload ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Logs:    tail -f /tmp/elgato-camera-light.log"
