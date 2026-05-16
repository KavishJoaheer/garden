# 📱 External Android Phone Setup Guide

This guide will help you install and run the GardNx app on a physical Android device and connect it to your local backend.

---

## 1. Prerequisites

- **Physical Android Phone** with USB cable.
- **PC** running the GardNx backend.
- Both devices must be on the **same Wi-Fi network**.

---

## 2. Enable Developer Options & USB Debugging

On your Android phone:
1. Go to **Settings > About phone**.
2. Find **Build number** and tap it **7 times** until it says "You are now a developer!".
3. Go back to **Settings > System > Developer options** (or search for it).
4. Enable **USB Debugging**.
5. Connect your phone to your PC via USB.
6. A prompt will appear on your phone: "Allow USB debugging?". Check "Always allow" and tap **Allow**.

---

## 3. Find your PC's IP Address

Your phone needs to know where the backend is running.
1. On your PC, open a terminal (PowerShell or Command Prompt).
2. Type `ipconfig`.
3. Look for **IPv4 Address** under your active Wi-Fi adapter (e.g., `192.168.1.45`).
4. **Note this IP down.**

---

## 4. Configure the Flutter App

1. Open `gardnx_app/lib/config/constants/api_constants.dart`.
2. Find the `_defaultHost` getter:
   ```dart
   static String get _defaultHost {
     if (kIsWeb) return 'localhost';
     if (Platform.isAndroid) return '10.0.2.2'; // Change this!
     return 'localhost';
   }
   ```
3. Change `'10.0.2.2'` to your PC's IP address (e.g., `'192.168.1.45'`).
   ```dart
   if (Platform.isAndroid) return '192.168.1.45'; 
   ```

---

## 5. Prepare the Backend

1. Ensure your backend is running on your PC:
   ```bash
   cd gardnx_backend
   venv\Scripts\activate
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```
   > 💡 The `--host 0.0.0.0` is critical! It allows the server to accept connections from other devices on the network.

2. **Allow Port 8000 through your Firewall:**
   Open PowerShell as Administrator and run:
   ```powershell
   netsh advfirewall firewall add rule name="GardNx Backend" dir=in action=allow protocol=TCP localport=8000
   ```

---

## 6. Install and Run the App

1. Open a new terminal in `gardnx_app`.
2. Check if your device is recognized:
   ```bash
   flutter devices
   ```
3. Run the app:
   ```bash
   flutter run
   ```
   The app will compile and install on your phone.

---

## 7. Troubleshooting

- **App can't connect?** 
  - Double-check the IP address in `api_constants.dart`.
  - Ensure both phone and PC are on the same Wi-Fi.
  - Verify the firewall rule is active.
- **"Connection Refused"?**
  - Ensure the backend is running with `--host 0.0.0.0`.
- **"Device not found"?**
  - Re-plug the USB cable and ensure USB Debugging is still ON.
