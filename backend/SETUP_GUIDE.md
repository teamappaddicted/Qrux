# QRUX Backend Setup Guide (Python/Flask)

## ✅ Works on All Platforms: Windows, Mac, Linux

---

## 📋 Prerequisites

- **Python 3.8+** installed
- **Firebase Project** with Realtime Database and Firestore
- **serviceAccountKey.json** from Firebase Console

---

## 🚀 Setup Instructions

### Step 1: Download & Install Python

**Windows:**
```powershell
# Download from https://www.python.org/downloads/
# Or use Windows Package Manager:
winget install Python.Python.3.11
```

**Mac:**
```bash
# Using Homebrew
brew install python3
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install python3 python3-pip
```

Verify installation:
```bash
python --version
```

---

### Step 2: Get Firebase Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project → **Settings** (⚙️)
3. Go to **Service Accounts** tab
4. Click **Generate New Private Key**
5. Save as `serviceAccountKey.json` in the `backend/` folder

⚠️ **Keep this file secure! Don't commit to GitHub!**

---

### Step 3: Install Backend

```bash
# Navigate to backend folder
cd backend

# Create virtual environment (recommended)
python -m venv venv

# Activate virtual environment
# Windows:
venv\Scripts\activate
# Mac/Linux:
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

---

### Step 4: Run the Backend

```bash
python app.py
```

You should see:
```
============================================================
QRUX ESP32 Device Registration Backend
Platform: Python/Flask (Windows, Mac, Linux)
============================================================
Server starting at http://localhost:5000
============================================================
```

---

## 🔌 API Endpoints

### 1. **Device Registration** (Called by ESP32)
```
POST /api/devices/register
Content-Type: application/json

{
  "deviceId": "A1B2C3D4E5F6",
  "deviceName": "QRUX_ESP32_Controller",
  "macAddress": "A1:B2:C3:D4:E5:F6",
  "firmwareVersion": "1.0.0",
  "qrCodeId": "generated_qr_code_id"  // Optional, links to admin
}

Response:
{
  "success": true,
  "credentials": {
    "email": "device_a1b2c3d4e5f6@qrux.com",
    "password": "secure_password"
  },
  "containerId": "device_a1b2c3d4e5f6",
  "linkedToAdmin": true
}
```

---

### 2. **Generate QR Code** (Admin Action)
```
POST /api/qr-codes/generate
Authorization: Bearer <admin_id_token>
Content-Type: application/json

{
  "deviceName": "Device A"
}

Response: PNG image file
```

---

### 3. **Get QR Code Info**
```
GET /api/qr-codes/<qr_code_id>

Response:
{
  "success": true,
  "qrCode": {
    "qrCodeId": "...",
    "adminId": "...",
    "adminEmail": "admin@example.com",
    "deviceName": "Device A",
    "createdAt": "2024-01-15T10:30:00",
    "scanned": false
  }
}
```

---

### 4. **Admin Registration**
```
POST /api/admin/register
Content-Type: application/json

{
  "email": "admin@example.com",
  "password": "secure_password_123",
  "name": "John Doe",
  "organization": "My Company"
}

Response:
{
  "success": true,
  "adminId": "firebase_uid",
  "message": "Admin registered successfully"
}
```

---

### 5. **Get Admin's Devices**
```
GET /api/admin/devices
Authorization: Bearer <admin_id_token>

Response:
{
  "success": true,
  "devices": [
    {
      "deviceId": "A1B2C3D4E5F6",
      "deviceName": "QRUX_ESP32_Controller",
      "status": "active",
      "lastSeen": "2024-01-15T10:30:00",
      "adminId": "admin_uid"
    }
  ],
  "totalDevices": 1
}
```

---

### 6. **Get Admin's QR Codes**
```
GET /api/admin/qr-codes
Authorization: Bearer <admin_id_token>

Response:
{
  "success": true,
  "qrCodes": [
    {
      "qrCodeId": "...",
      "deviceName": "Device A",
      "createdAt": "2024-01-15T10:30:00",
      "scanned": false
    }
  ],
  "totalQRCodes": 5
}
```

---

### 7. **Get Admin Statistics**
```
GET /api/admin/stats
Authorization: Bearer <admin_id_token>

Response:
{
  "success": true,
  "stats": {
    "totalDevices": 5,
    "onlineDevices": 3,
    "offlineDevices": 2,
    "totalQRCodesGenerated": 10
  }
}
```

---

### 8. **Get Device Status**
```
GET /api/devices/<device_id>/status

Response:
{
  "success": true,
  "device": {
    "deviceId": "A1B2C3D4E5F6",
    "deviceName": "Device A",
    "online": true,
    "lastSeen": "2024-01-15T10:30:00",
    "adminId": "admin_uid",
    "adminEmail": "admin@example.com"
  }
}
```

---

### 9. **List All Devices**
```
GET /api/devices

Response:
{
  "success": true,
  "devices": [
    {
      "deviceId": "A1B2C3D4E5F6",
      "deviceName": "Device A",
      "status": "active"
    }
  ],
  "totalDevices": 1
}
```

---

### 10. **Health Check**
```
GET /health

Response:
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00"
}
```

---

## 📊 Database Structure Created

### Realtime Database (`/`)
```
/admins
  /{adminId}
    /email: "admin@example.com"
    /name: "Admin Name"
    /devices
      /{deviceId}: true
      
/devices
  /{deviceId}
    /uid: "firebase_uid"
    /email: "device_xxx@qrux.com"
    /deviceName: "Device A"
    /status: "registered"
    /online: false
    /adminId: "admin_uid"
    
/containers
  /{containerId}
    /deviceId: "A1B2C3D4E5F6"
    /deviceName: "Device A"
    /command: "STOP"
    /online: false
    /adminId: "admin_uid"
```

### Firestore (`db.firestore()`)
```
/admins/{adminId}
  - adminId: string
  - email: string
  - name: string
  - totalDevices: number
  - totalQRCodesGenerated: number
  - createdAt: timestamp

/devices/{deviceId}
  - deviceId: string
  - deviceName: string
  - status: string
  - adminId: string (links to admin)
  - adminEmail: string
  - registeredAt: timestamp
  
/qr_codes/{qrCodeId}
  - qrCodeId: string
  - adminId: string (links to admin)
  - deviceName: string
  - createdAt: timestamp
  - scanned: boolean
  - linkedDeviceId: string (once scanned)
```

---

## 🔄 Complete Flow

```
1. ADMIN:
   - Registers account via mobile/web app
   - Calls POST /api/admin/register
   - Creates admin document in Firestore

2. ADMIN CREATES QR CODE:
   - Calls POST /api/qr-codes/generate (with auth token)
   - Backend generates QR code with admin ID
   - Returns PNG image
   - Metadata saved to Firestore

3. ESP32 BOOTS:
   - Scans QR code or gets QR code ID manually
   - Calls POST /api/devices/register (with qrCodeId)
   - Backend creates Firebase user
   - Backend links device to admin
   - Returns credentials to ESP32
   - ESP32 saves credentials locally

4. DEVICE NOW LINKED:
   - Device appears in admin's device list
   - Admin can see device status in dashboard
   - Admin can send commands via Firebase
   - Device auto-updates as "online"
```

---

## 🚀 Deployment Options

### Option 1: Local Network (For Testing)
```bash
# Run on your machine
python app.py
# Access from ESP32: http://<your_computer_ip>:5000
```

### Option 2: Cloud Deployment

#### **Heroku** (Easy, Free tier available)
```bash
# Install Heroku CLI
pip install heroku

# Login and create app
heroku login
heroku create your-app-name

# Deploy
git push heroku main

# Your backend URL: https://your-app-name.herokuapp.com
```

#### **Google Cloud Run** (Recommended)
```bash
# Install Google Cloud SDK
# Deploy:
gcloud run deploy qrux-backend --source .

# Your backend URL: https://qrux-backend-xxxxx.run.app
```

#### **AWS EC2** (Full control)
```bash
# Launch EC2 instance
# Install Python and dependencies
# Run: python app.py
# Access via Elastic IP
```

---

## 🔐 Environment Setup

Create `.env` file in `backend/` folder (optional, for future configs):
```
FIREBASE_PROJECT_ID=qrux-11a39
FLASK_ENV=production
DEBUG=False
```

---

## ✅ Testing the Backend

### Test 1: Health Check
```bash
curl http://localhost:5000/health
```

### Test 2: Register Admin
```bash
curl -X POST http://localhost:5000/api/admin/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@test.com",
    "password": "password123",
    "name": "Test Admin",
    "organization": "Test Org"
  }'
```

### Test 3: Register Device (Simulating ESP32)
```bash
curl -X POST http://localhost:5000/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "A1B2C3D4E5F6",
    "deviceName": "Test Device",
    "macAddress": "A1:B2:C3:D4:E5:F6",
    "firmwareVersion": "1.0.0",
    "qrCodeId": "test_qr_123"
  }'
```

---

## 🐛 Troubleshooting

| Error | Solution |
|-------|----------|
| `ModuleNotFoundError: No module named 'firebase_admin'` | Run `pip install -r requirements.txt` |
| `KeyError: 'serviceAccountKey.json'` | Make sure file is in `backend/` folder |
| `ConnectionRefusedError` | Check Firebase credentials and internet connection |
| `QR code generation fails` | Install Pillow: `pip install Pillow` |
| `CORS error from mobile app` | Backend already has CORS enabled |

---

## 📝 ESP32 Configuration

Update your ESP32 code with backend URL:

```cpp
#define REGISTRATION_SERVER "localhost"     // Or your deployed URL
#define REGISTRATION_ENDPOINT "/api/devices/register"
#define REGISTRATION_PORT 5000              // Or 443 for HTTPS
```

For deployed backend:
```cpp
#define REGISTRATION_SERVER "qrux-backend-xxxxx.run.app"  // Google Cloud Run
#define REGISTRATION_PORT 443
```

---

## 🎯 Next Steps

1. ✅ Set up Python backend
2. ✅ Get Firebase service account key
3. ✅ Install dependencies: `pip install -r requirements.txt`
4. ✅ Run backend: `python app.py`
5. ✅ Update ESP32 with backend URL
6. ✅ Upload ESP32 code
7. ✅ Test device registration
8. ✅ Deploy to cloud for production

---

## 📞 Support

For Firebase issues: https://firebase.google.com/support
For Flask issues: https://flask.palletsprojects.com/
For Python issues: https://www.python.org/help/

