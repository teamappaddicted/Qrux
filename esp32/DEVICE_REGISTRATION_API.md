# Device Registration API Guide

## Overview
The ESP32 code now dynamically registers itself with a backend API. This enables scalability - no more manual Firebase user creation!

## Flow
1. **ESP32 boots** → Checks local storage for credentials
2. **If no credentials found** → Calls backend registration API
3. **Backend receives registration** → Creates Firebase user + Firestore container entry
4. **API returns credentials** → ESP32 stores them locally
5. **Next boot** → ESP32 uses stored credentials (no re-registration needed)

---

## Backend API Implementation

### Required Endpoint
**POST** `/api/devices/register`

### Request Body
```json
{
  "deviceId": "A1B2C3D4E5F6",          // MAC address in hex
  "deviceName": "QRUX_ESP32_Controller",
  "macAddress": "A1:B2:C3:D4:E5:F6",
  "firmwareVersion": "1.0.0"
}
```

### Response (Success)
```json
{
  "success": true,
  "credentials": {
    "email": "device_a1b2c3d4e5f6@qrux.com",
    "password": "auto_generated_secure_password_12345"
  },
  "containerId": "device_a1b2c3d4e5f6",
  "message": "Device registered successfully"
}
```

### Response (Error)
```json
{
  "success": false,
  "message": "Device already registered",
  "error": "DEVICE_EXISTS"
}
```

---

## Node.js/Express Backend Example

```javascript
const express = require('express');
const admin = require('firebase-admin');
const crypto = require('crypto');

const app = express();
app.use(express.json());

// Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccountKey),
  databaseURL: "https://qrux-11a39-default-rtdb.firebaseio.com"
});

const db = admin.database();
const auth = admin.auth();

// Device Registration Endpoint
app.post('/api/devices/register', async (req, res) => {
  try {
    const { deviceId, deviceName, macAddress, firmwareVersion } = req.body;

    if (!deviceId || !deviceName) {
      return res.status(400).json({
        success: false,
        message: "Missing required fields: deviceId, deviceName"
      });
    }

    // Check if device already registered
    const existingDevice = await db
      .ref(`devices/${deviceId}`)
      .once('value');

    if (existingDevice.exists()) {
      return res.status(409).json({
        success: false,
        message: "Device already registered",
        error: "DEVICE_EXISTS"
      });
    }

    // Generate unique credentials
    const password = crypto.randomBytes(16).toString('hex');
    const email = `device_${deviceId.toLowerCase()}@qrux.com`;
    const containerId = `device_${deviceId.toLowerCase()}`;

    // Create Firebase Auth user
    const userRecord = await auth.createUser({
      email: email,
      password: password,
      displayName: deviceName,
      disabled: false
    });

    // Create device entry in Realtime Database
    await db.ref(`devices/${deviceId}`).set({
      uid: userRecord.uid,
      email: email,
      deviceName: deviceName,
      macAddress: macAddress,
      containerId: containerId,
      firmwareVersion: firmwareVersion,
      registeredAt: admin.database.ServerValue.TIMESTAMP,
      lastSeen: admin.database.ServerValue.TIMESTAMP,
      online: false,
      status: "registered"
    });

    // Create container in Realtime Database
    await db.ref(`containers/${containerId}`).set({
      deviceId: deviceId,
      deviceName: deviceName,
      command: "STOP",
      online: false,
      createdAt: admin.database.ServerValue.TIMESTAMP
    });

    // Create container document in Firestore (optional, for admin UI)
    await admin.firestore().collection('containers').doc(containerId).set({
      deviceId: deviceId,
      deviceName: deviceName,
      email: email,
      macAddress: macAddress,
      status: "active",
      registeredAt: new Date(),
      lastSeen: new Date()
    });

    return res.status(201).json({
      success: true,
      credentials: {
        email: email,
        password: password
      },
      containerId: containerId,
      message: "Device registered successfully"
    });

  } catch (error) {
    console.error('Registration error:', error);
    return res.status(500).json({
      success: false,
      message: "Internal server error",
      error: error.message
    });
  }
});

// Get device status endpoint
app.get('/api/devices/:deviceId/status', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const device = await db.ref(`devices/${deviceId}`).once('value');
    
    if (!device.exists()) {
      return res.status(404).json({
        success: false,
        message: "Device not found"
      });
    }

    return res.json({
      success: true,
      device: device.val()
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// List all devices endpoint
app.get('/api/devices', async (req, res) => {
  try {
    const devices = await db.ref('devices').once('value');
    return res.json({
      success: true,
      devices: devices.val() || {}
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.listen(3000, () => {
  console.log('Device Registration API running on port 3000');
});
```

---

## Python/Flask Backend Example

```python
from flask import Flask, request, jsonify
import firebase_admin
from firebase_admin import credentials, db, auth
import secrets
from datetime import datetime

app = Flask(__name__)

# Initialize Firebase
cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://qrux-11a39-default-rtdb.firebaseio.com'
})

@app.route('/api/devices/register', methods=['POST'])
def register_device():
    try:
        data = request.get_json()
        
        device_id = data.get('deviceId')
        device_name = data.get('deviceName')
        mac_address = data.get('macAddress')
        firmware_version = data.get('firmwareVersion', '1.0.0')

        if not device_id or not device_name:
            return jsonify({
                'success': False,
                'message': 'Missing required fields'
            }), 400

        # Check if device already exists
        existing = db.reference(f'devices/{device_id}').get().val()
        if existing:
            return jsonify({
                'success': False,
                'message': 'Device already registered',
                'error': 'DEVICE_EXISTS'
            }), 409

        # Generate credentials
        password = secrets.token_hex(16)
        email = f"device_{device_id.lower()}@qrux.com"
        container_id = f"device_{device_id.lower()}"

        # Create Firebase user
        user = auth.create_user(
            email=email,
            password=password,
            display_name=device_name
        )

        # Save device record
        db.reference(f'devices/{device_id}').set({
            'uid': user.uid,
            'email': email,
            'deviceName': device_name,
            'macAddress': mac_address,
            'containerId': container_id,
            'firmwareVersion': firmware_version,
            'registeredAt': datetime.now().isoformat(),
            'lastSeen': datetime.now().isoformat(),
            'online': False,
            'status': 'registered'
        })

        # Create container record
        db.reference(f'containers/{container_id}').set({
            'deviceId': device_id,
            'deviceName': device_name,
            'command': 'STOP',
            'online': False,
            'createdAt': datetime.now().isoformat()
        })

        return jsonify({
            'success': True,
            'credentials': {
                'email': email,
                'password': password
            },
            'containerId': container_id,
            'message': 'Device registered successfully'
        }), 201

    except Exception as e:
        return jsonify({
            'success': False,
            'message': 'Internal server error',
            'error': str(e)
        }), 500

if __name__ == '__main__':
    app.run(debug=True, port=3000)
```

---

## ESP32 Configuration Changes

Update these defines in your ESP32 code:

```cpp
#define REGISTRATION_SERVER "your-backend-api.com"    // Change to your backend URL
#define REGISTRATION_ENDPOINT "/api/devices/register"
#define REGISTRATION_PORT 80  // or 443 for HTTPS
```

---

## Database Structure Created by Backend

### Realtime Database (`/`)
```
devices/
├── A1B2C3D4E5F6/
│   ├── uid: "firebase_uid"
│   ├── email: "device_a1b2c3d4e5f6@qrux.com"
│   ├── deviceName: "QRUX_ESP32_Controller"
│   ├── containerId: "device_a1b2c3d4e5f6"
│   ├── online: false
│   └── status: "registered"
│
containers/
├── device_a1b2c3d4e5f6/
│   ├── command: "STOP"
│   ├── online: false
│   └── battery: 85
```

### Firestore (optional, for admin dashboard)
```
/containers/{containerId}
  - deviceId: string
  - deviceName: string
  - email: string
  - status: "active" | "inactive"
  - registeredAt: timestamp
  - lastSeen: timestamp
```

---

## Features & Benefits

✅ **Scalability**: Add unlimited ESP32 devices without manual configuration  
✅ **Security**: Unique credentials per device  
✅ **Persistence**: Credentials stored locally on ESP32 (survives reboot)  
✅ **Auto-Recovery**: Auto re-registers if credentials are lost  
✅ **Device Tracking**: Backend can track all registered devices  
✅ **Admin Dashboard**: Easy device management via Firestore  

---

## Testing

### 1. Start your backend
```bash
node server.js  # or python app.py
```

### 2. Upload ESP32 code with your backend URL

### 3. Monitor Serial Output
```
[WiFi] Connecting to your_wifi_network_name
[WiFi] Connected!
[Device] ID: A1B2C3D4E5F6
[Credentials] No stored credentials found
[Registration] Starting device registration process...
[Registration] Device registered successfully!
[Registration] Container ID: device_a1b2c3d4e5f6
[Firebase] Stream started successfully!
```

### 4. Verify in Firebase Console
- Check **Realtime Database** under `/devices`
- Check **Realtime Database** under `/containers`
- Check **Authentication** for new user `device_a1b2c3d4e5f6@qrux.com`

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| `Failed to connect to registration server` | Check backend is running and accessible |
| `DEVICE_EXISTS` | Device already registered. Delete from Firebase or use different ESP32 |
| `Missing required fields` | Ensure ESP32 is sending all fields in registration request |
| `Connection failed` | Check WiFi SSID/password and internet connectivity |

