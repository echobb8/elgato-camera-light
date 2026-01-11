# Elgato Key Light Camera Automation

Automatically turns your Elgato Key Light on when the camera is in use, and off when released. Works with built-in and USB cameras on macOS.

## Requirements

- macOS (tested on Tahoe)
- Elgato Key Light on the same network
- Xcode Command Line Tools (`xcode-select --install`)

## Installation

```bash
git clone https://github.com/echobb8/elgato-camera-light.git
cd elgato-camera-light
./install.sh
```

Then edit `~/elgato-camera-light/config.json` and set your light's IP address.

## Configuration

Edit `~/elgato-camera-light/config.json`:

```json
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
```

Find your light's IP in the Elgato Control Center app.

## Commands

```bash
# View logs
tail -f /tmp/elgato-camera-light.log

# Restart service
launchctl unload ~/Library/LaunchAgents/com.user.elgato-camera-light.plist
launchctl load ~/Library/LaunchAgents/com.user.elgato-camera-light.plist

# Stop service
launchctl unload ~/Library/LaunchAgents/com.user.elgato-camera-light.plist

# Uninstall
launchctl unload ~/Library/LaunchAgents/com.user.elgato-camera-light.plist
rm ~/Library/LaunchAgents/com.user.elgato-camera-light.plist
rm -rf ~/elgato-camera-light
```
