# QRUX "Move Container" Feature - Complete Guide

## 🎯 Overview

The "Move Container" feature allows admins to dynamically provision ESP32 devices directly from their mobile app:

1. **Admin scans QR code** containing device info
2. **Admin clicks "Move Container"** 
3. **App asks "Connect to ESP32 WiFi?"**
4. **Admin connects to ESP32's WiFi hotspot**
5. **App sends provisioning data directly to ESP32**
6. **ESP32 automatically connects to backend**
7. **Device linked to admin's account**
8. **Admin can now control device from anywhere**

---

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│   Admin Mobile App (Flutter)         │
│                                      │
│  1. Scan QR Code (get device ID)    │
│  2. Click "Move Container"          │
│  3. Get provisioning data from      │
│     backend (auth required)         │
│  4. Connect to ESP32 WiFi hotspot   │
│  5. Send provisioning data to       │
│     ESP32 via local WiFi            │
└──────────────┬──────────────────────┘
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
   Internet         WiFi Hotspot
       │                │
   Backend          ESP32 Access Point
   (Python)         (QRUX-A1B2C3D4E5F6)
       │                │
       └────────┬───────┘
              (Reconnect)
              
ESP32 connects to internet via backend WiFi
and receives provisioning from mobile app
```

---

## 📱 Mobile App Flow (Flutter)

### Step 1: Scan QR Code

```dart
// In your Flutter app
void scanQRCode() {
  var result = await SimpleBarcodeScanner.scanBarcode(
    lineColor: "#ff6600",
    scanMode: ScanMode.SINGLE,
    isShowFlashIcon: true,
    isShowClosingIcon: true,
  );
  
  // Parse QR code data
  Map<String, dynamic> qrData = jsonDecode(result);
  deviceId = qrData['deviceId'];
  qrCodeId = qrData['qrCodeId'];
}
```

### Step 2: Show "Move Container" Dialog

```dart
void showMoveContainerDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Move Container'),
      content: Text('Do you want to move this container to this ESP32?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            startContainerProvisioning();
          },
          child: Text('Yes, Move It'),
        ),
      ],
    ),
  );
}
```

### Step 3: Get Provisioning Data from Backend

```dart
Future<void> startContainerProvisioning() async {
  // Get provisioning data from backend
  final response = await http.get(
    Uri.parse('https://your-backend.com/api/containers/$containerId/provisioning'),
    headers: {
      'Authorization': 'Bearer $adminIdToken',
    },
  );
  
  if (response.statusCode == 200) {
    Map<String, dynamic> provisioningData = jsonDecode(response.body);
    
    // Show WiFi connection instructions
    showWiFiConnectionDialog(provisioningData);
  }
}
```

### Step 4: Prompt to Connect to ESP32 WiFi

```dart
void showWiFiConnectionDialog(Map<String, dynamic> data) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Connect to ESP32 WiFi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('1. Go to WiFi Settings'),
          Text('2. Find: QRUX-A1B2C3D4E5F6'),
          Text('3. Connect with password: 12345678'),
          SizedBox(height: 16),
          Text('App will auto-detect when connected'),
          SizedBox(height: 16),
          LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Open WiFi settings
            openWiFiSettings();
          },
          child: Text('Open WiFi Settings'),
        ),
      ],
    ),
  );
  
  // Start checking for WiFi connection
  checkWiFiConnection(data);
}
```

### Step 5: Send Provisioning Data to ESP32

```dart
Future<void> checkWiFiConnection(Map<String, dynamic> data) async {
  // Wait for app to connect to ESP32's WiFi
  await Future.delayed(Duration(seconds: 2));
  
  try {
    // Send provisioning data to ESP32 hotspot
    final response = await http.post(
      Uri.parse('http://192.168.4.1/api/provision'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'adminId': adminId,
        'backendUrl': data['backendUrl'],
        'backendPort': data['backendPort'],
        'qrCodeId': qrCodeId,
      }),
    ).timeout(Duration(seconds: 5));
    
    if (response.statusCode == 200) {
      showSuccessDialog('Device provisioned! Reconnecting to WiFi...');
      
      // Wait for ESP32 to reconnect to main WiFi
      await Future.delayed(Duration(seconds: 5));
      
      // Re-connect app to normal WiFi
      reconnectToNormalWiFi();
    }
  } catch (e) {
    showErrorDialog('Failed to provision device: $e');
  }
}
```

---

## 💾 Database Schema (Admin-Container Linking)

### Firestore (`/devices/{deviceId}`)
```json
{
  "deviceId": "A1B2C3D4E5F6",
  "deviceName": "Device A",
  "containerName": "device_a1b2c3d4e5f6",
  "status": "active",
  "adminId": "user_123",           // ← Linked to admin
  "adminEmail": "admin@company.com",
  "registeredAt": "2024-01-15T10:00:00Z",
  "lastSeen": "2024-01-15T12:30:00Z",
  "movedAt": "2024-01-15T11:00:00Z",  // ← Timestamp of move
  "movedFrom": "user_456"             // ← Previous admin
}
```

### Firestore (`/admins/{adminId}`)
```json
{
  "adminId": "user_123",
  "email": "admin@company.com",
  "name": "John Doe",
  "organization": "Company Name",
  "totalDevices": 5,
  "totalContainers": 5,
  "lastUpdated": "2024-01-15T12:30:00Z",
  "devices": {
    "A1B2C3D4E5F6": {
      "linkedAt": "2024-01-15T10:00:00Z"
    },
    "B2C3D4E5F6A1": {
      "linkedAt": "2024-01-14T09:00:00Z"
    }
  },
  "containers": {
    "device_a1b2c3d4e5f6": {
      "deviceId": "A1B2C3D4E5F6",
      "deviceName": "Device A",
      "linkedAt": "2024-01-15T10:00:00Z"
    },
    "device_b2c3d4e5f6a1": {
      "deviceId": "B2C3D4E5F6A1",
      "deviceName": "Device B",
      "linkedAt": "2024-01-14T09:00:00Z"
    }
  }
}
```

### Realtime Database (`/admins/{adminId}`)
```json
{
  "email": "admin@company.com",
  "name": "John Doe",
  "devices": {
    "A1B2C3D4E5F6": {
      "containerid": "device_a1b2c3d4e5f6",
      "linkedAt": "2024-01-15T10:00:00Z"
    }
  },
  "containers": {
    "device_a1b2c3d4e5f6": {
      "deviceId": "A1B2C3D4E5F6",
      "deviceName": "Device A",
      "linkedAt": "2024-01-15T10:00:00Z"
    }
  }
}
```

### Realtime Database (`/containers/{containerId}`)
```json
{
  "deviceId": "A1B2C3D4E5F6",
  "deviceName": "Device A",
  "command": "STOP",
  "online": true,
  "adminId": "user_123",              // ← Linked to admin
  "adminEmail": "admin@company.com",
  "createdAt": "2024-01-15T10:00:00Z",
  "movedAt": "2024-01-15T11:00:00Z"
}
```

---

## 🔌 Backend API Endpoints

### 1. Get Provisioning Data for New Container

```
GET /api/admin/provisioning-data
Authorization: Bearer <admin_id_token>

Response:
{
  "success": true,
  "provisioningData": {
    "adminId": "user_123",
    "adminEmail": "admin@company.com",
    "backendUrl": "your-backend.com",
    "backendPort": 5000
  }
}
```

### 2. Get Provisioning Data for Existing Container

```
GET /api/containers/{containerId}/provisioning
Authorization: Bearer <admin_id_token>

Response:
{
  "success": true,
  "provisioningData": {
    "adminId": "user_123",
    "adminEmail": "admin@company.com",
    "containerId": "device_a1b2c3d4e5f6",
    "deviceId": "A1B2C3D4E5F6",
    "deviceName": "Device A",
    "backendUrl": "your-backend.com",
    "backendPort": 5000
  }
}
```

### 3. Move Container to New Admin

```
POST /api/containers/{containerId}/move
Authorization: Bearer <admin_id_token>
Content-Type: application/json

{
  "newAdminId": "user_789"  // Optional: transfer to another admin
}

Response:
{
  "success": true,
  "message": "Container moved successfully",
  "container": {
    "containerId": "device_a1b2c3d4e5f6",
    "deviceId": "A1B2C3D4E5F6",
    "newAdminId": "user_123"
  }
}
```

### 4. Register Device (Called by ESP32 after provisioning)

```
POST /api/devices/register
Content-Type: application/json

{
  "deviceId": "A1B2C3D4E5F6",
  "deviceName": "Device A",
  "macAddress": "A1:B2:C3:D4:E5:F6",
  "firmwareVersion": "1.0.0",
  "adminId": "user_123",              // ← From mobile app provisioning
  "qrCodeId": "qr_code_123"           // ← From QR scan
}

Response:
{
  "success": true,
  "credentials": {
    "email": "device_a1b2c3d4e5f6@qrux.com",
    "password": "auto_generated_secure_password"
  },
  "containerId": "device_a1b2c3d4e5f6",
  "linkedToAdmin": true,
  "adminId": "user_123"
}
```

---

## 🔧 ESP32 Hotspot Mode

### How It Works

```cpp
// ESP32 boots - no credentials found
→ Starts WiFi hotspot: QRUX-A1B2C3D4E5F6
→ Starts web server on 192.168.4.1:80
→ Waits for admin provisioning

// Admin connects phone to QRUX-A1B2C3D4E5F6
→ Phone connects to 192.168.4.1
→ App sends: POST /api/provision
→ ESP32 receives admin ID + backend details
→ Saves to SPIFFS
→ Restarts

// ESP32 reboots
→ Loads provisioning data
→ Connects to normal WiFi
→ Registers with backend
→ Backend links to admin
→ Ready for commands!
```

### ESP32 Endpoints

```
POST /api/provision
Body: {
  "adminId": "user_123",
  "backendUrl": "your-backend.com",
  "backendPort": 5000,
  "qrCodeId": "qr_code_123"
}

GET /api/device-info
Response: {
  "deviceId": "A1B2C3D4E5F6",
  "deviceName": "QRUX_ESP32_Controller",
  "registered": false,
  "adminId": null
}

GET /health
Response: { "status": "online" }
```

---

## 📊 Complete "Move Container" Flow

```
STEP 1: ADMIN SCANS QR CODE
  Admin opens app
  → Scans QR code on device
  → Gets: deviceId, qrCodeId
  
STEP 2: ADMIN CLICKS "MOVE CONTAINER"
  Admin taps "Move This Device"
  → App calls: GET /api/containers/{containerId}/provisioning
  → Backend returns: adminId, backendUrl, backendPort
  → App shows: "Connect to ESP32 WiFi instructions"
  
STEP 3: ADMIN CONNECTS TO ESP32 HOTSPOT
  Admin phone WiFi settings
  → Finds: QRUX-A1B2C3D4E5F6
  → Connects with password: 12345678
  → Phone now connected to ESP32
  
STEP 4: APP SENDS PROVISIONING DATA
  App detects phone is connected to ESP32
  → Sends: POST /api/provision to 192.168.4.1
  → Data: adminId, backendUrl, qrCodeId
  → ESP32 saves to SPIFFS
  
STEP 5: ESP32 RECONNECTS TO MAIN WIFI
  ESP32 receives provisioning data
  → Exits hotspot mode
  → Restarts
  → Loads provisioning data from SPIFFS
  → Connects to internet WiFi
  
STEP 6: ESP32 REGISTERS WITH BACKEND
  ESP32 calls: POST /api/devices/register
  → Sends: deviceId, adminId, qrCodeId
  → Backend creates Firebase user
  → Backend creates device entry
  → Backend LINKS to admin (adminId field)
  → Returns: credentials, containerId
  
STEP 7: DEVICE NOW LINKED TO ADMIN
  Firestore /devices/{deviceId}.adminId = "user_123"
  Firestore /admins/{adminId}.containers.{containerId} exists
  RTDB /admins/{adminId}/containers/{containerId} exists
  
STEP 8: ADMIN CAN NOW CONTROL DEVICE
  Admin app reconnects to normal WiFi
  → Opens device dashboard
  → Sees device status: "Online"
  → Can send commands:
      - FORWARD
      - BACKWARD
      - LEFT
      - RIGHT
      - STOP
```

---

## 🔐 Security Features

| Feature | How It Works |
|---------|-------------|
| **Admin Authentication** | Only authenticated admins can get provisioning data |
| **Device Ownership** | Only device owner can move container |
| **Hotspot Timeout** | ESP32 hotspot expires after 30 seconds (configurable) |
| **One-time Provisioning** | Credentials saved on device, not shared again |
| **Firebase Auth** | Device login requires credentials returned from backend |
| **SPIFFS Encryption** | Consider encrypting stored credentials (optional) |

---

## ⚙️ Configuration

### ESP32 Code (`qrux_esp32_controller_with_hotspot.ino`)

```cpp
// WiFi hotspot settings
#define HOTSPOT_SSID_PREFIX "QRUX-"
#define HOTSPOT_PASSWORD "12345678"

// Backend settings
#define REGISTRATION_SERVER "your-backend.com"
#define REGISTRATION_PORT 5000
```

### Python Backend (`.env`)

```
BACKEND_URL=your-backend.com
BACKEND_PORT=5000
```

### Mobile App (constants.dart)

```dart
const String BACKEND_URL = 'https://your-backend.com';
const String HOTSPOT_IP = '192.168.4.1';
const String HOTSPOT_PASSWORD = '12345678';
```

---

## 🧪 Testing

### Test 1: Manual QR Code + Provisioning

1. Print QR code containing:
   ```json
   {
     "deviceId": "TEST123456",
     "qrCodeId": "test_qr_001"
   }
   ```

2. Scan with mobile app

3. Click "Move Container"

4. Connect to `QRUX-TEST123456` WiFi

5. App sends provisioning data

6. Check Serial Monitor for:
   ```
   [Hotspot] Received provisioning request from admin...
   [Registration] Device registered successfully!
   [Firebase] Stream started successfully!
   ```

### Test 2: Verify Database Links

Firestore:
```
/devices/TEST123456
  → adminId should equal your admin ID
  
/admins/{adminId}
  → containers/device_test123456 should exist
```

RTDB:
```
/containers/device_test123456
  → adminId should equal your admin ID
  
/admins/{adminId}/containers
  → device_test123456 should exist
```

---

## 📱 Flutter UI Example

```dart
class MoveContainerScreen extends StatefulWidget {
  final String containerId;
  final String deviceId;
  
  @override
  State<MoveContainerScreen> createState() => _MoveContainerScreenState();
}

class _MoveContainerScreenState extends State<MoveContainerScreen> {
  bool isConnecting = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Move Container')),
      body: Column(
        children: [
          Card(
            child: ListTile(
              title: Text('Device ID'),
              subtitle: Text(widget.deviceId),
            ),
          ),
          SizedBox(height: 24),
          if (!isConnecting)
            ElevatedButton(
              onPressed: () => moveContainer(),
              child: Text('Move Container'),
            )
          else
            Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('1. Go to WiFi Settings'),
                Text('2. Connect to QRUX-...'),
                Text('3. Wait for auto-provisioning'),
              ],
            ),
        ],
      ),
    );
  }
  
  Future<void> moveContainer() async {
    setState(() => isConnecting = true);
    
    try {
      // Get provisioning data
      final response = await http.get(
        Uri.parse('$BACKEND_URL/api/containers/${widget.containerId}/provisioning'),
        headers: {'Authorization': 'Bearer $authToken'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['provisioningData'];
        
        // Send to ESP32 hotspot
        await sendProvisioningDataToESP32(data);
        
        // Success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device provisioned successfully!')),
        );
        
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isConnecting = false);
    }
  }
  
  Future<void> sendProvisioningDataToESP32(dynamic data) async {
    await http.post(
      Uri.parse('http://192.168.4.1/api/provision'),
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    ).timeout(Duration(seconds: 5));
  }
}
```

---

## 🚀 Deployment

1. Update backend URL in ESP32 code and mobile app
2. Deploy Python backend to cloud
3. Get Firebase service account key
4. Run: `python app.py`
5. Build and deploy Flutter app
6. Test with multiple ESP32 devices

---

## 📞 Troubleshooting

| Issue | Solution |
|-------|----------|
| ESP32 won't start hotspot | Check SPIFFS initialization, increase delay |
| Mobile app can't find hotspot | Ensure ESP32 hotspot is broadcasting (check WiFi settings) |
| Provisioning data not received | Check network, verify JSON format, increase timeout |
| Device registers but no admin link | Verify adminId is being sent in registration request |
| Container not in admin's list | Check Firestore and RTDB for `adminId` field |

