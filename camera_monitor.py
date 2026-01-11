import subprocess
import sys
from datetime import datetime

def monitor_camera():
    print("Starting Camera Monitor for macOS (Insta360 Specific)...")
    print("Looking for 'Insta360 Link' session events.")
    print("Press Ctrl+C to stop.")

    # We found that 'com.apple.cameracapture' logs 'addInput:' and 'removeInput:' 
    # with the device name when apps like Zoom/FaceTime use the camera.
    predicate = 'subsystem == "com.apple.cameracapture" and eventMessage contains "Input"'
    
    cmd = ["log", "stream", "--predicate", predicate]
    
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    try:
        while True:
            line = process.stdout.readline()
            if not line:
                break
            
            # Check for Add/Remove Input specifically for Insta360
            if "Insta360" in line:
                if "addInput:" in line:
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    print(f"[{timestamp}] 🟢 Camera STARTED (Active)")
                    # print(f"Raw Log: {line.strip()}")
                elif "removeInput:" in line:
                    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    print(f"[{timestamp}] 🔴 Camera STOPPED (Inactive)")
                    # print(f"Raw Log: {line.strip()}")

    except KeyboardInterrupt:
        print("\nStopping monitor...")
        process.terminate()
    except Exception as e:
        print(f"Error: {e}")
        process.terminate()

if __name__ == "__main__":
    monitor_camera()
