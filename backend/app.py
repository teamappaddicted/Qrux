"""
QRUX ESP32 Device Registration & Management Backend
Platform: Python/Flask (Works on Windows, Mac, Linux)
"""

import os
import json
import secrets
import qrcode
from io import BytesIO
from datetime import datetime
from functools import wraps
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import firebase_admin
from firebase_admin import credentials, db, auth, firestore
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize Flask App
app = Flask(__name__)
CORS(app)

# Initialize Firebase Admin SDK
try:
    service_account_json = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON')
    if service_account_json:
        firebase_cred = credentials.Certificate(json.loads(service_account_json))
    else:
        firebase_cred = credentials.Certificate('serviceAccountKey.json')
    firebase_admin.initialize_app(firebase_cred, {
        'databaseURL': os.getenv(
            'FIREBASE_DATABASE_URL',
            'https://qrux-11a39-default-rtdb.firebaseio.com',
        )
    })
    rtdb = db
    fs_db = firestore.client()
    print("[Firebase] ✓ Initialized successfully")
except Exception as e:
    print(f"[Firebase] ✗ Initialization error: {e}")
    exit(1)

# ============ AUTHENTICATION MIDDLEWARE ============

def require_admin_token(f):
    """Verify admin authentication token"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({'success': False, 'error': 'Missing authorization token'}), 401
        
        try:
            # Remove 'Bearer ' prefix if present
            token = token.replace('Bearer ', '')
            decoded = auth.verify_id_token(token)
            request.admin_id = decoded['uid']
            request.admin_email = decoded['email']
            return f(*args, **kwargs)
        except Exception as e:
            return jsonify({'success': False, 'error': f'Invalid token: {str(e)}'}), 401
    
    return decorated_function

# ============ DEVICE REGISTRATION ENDPOINTS ============

@app.route('/api/devices/register', methods=['POST'])
def register_device():
    """
    Device Registration Endpoint
    Called by ESP32 on first boot
    
    Can be called in 2 ways:
    1. Auto-discovery via QR code (qrCodeId provided)
    2. Admin provisioning via mobile app (adminId provided)
    """
    try:
        data = request.get_json()
        
        device_id = data.get('deviceId')
        device_name = data.get('deviceName', 'QRUX Device')
        mac_address = data.get('macAddress')
        firmware_version = data.get('firmwareVersion', '1.0.0')
        qr_code_id = data.get('qrCodeId')
        admin_id = data.get('adminId')  # NEW: Direct admin provisioning

        if not device_id or not device_name:
            return jsonify({
                'success': False,
                'message': 'Missing required fields: deviceId, deviceName'
            }), 400

        # Check if device already exists
        existing = rtdb.reference(f'devices/{device_id}').get()
        if existing:
            return jsonify({
                'success': False,
                'message': 'Device already registered',
                'error': 'DEVICE_EXISTS'
            }), 409

        # Generate unique credentials
        password = secrets.token_hex(16)
        email = f"device_{device_id.lower()}@qrux.com"
        container_id = f"device_{device_id.lower()}"

        # Create Firebase Auth user for device
        user = auth.create_user(
            email=email,
            password=password,
            display_name=device_name
        )

        # Get admin info - either from QR code OR direct admin ID
        admin_email = None
        if not admin_id and qr_code_id:
            # QR code based registration
            qr_data = fs_db.collection('qr_codes').document(qr_code_id).get()
            if qr_data.exists:
                admin_id = qr_data.get('adminId')
                admin_email = qr_data.get('adminEmail')
        elif admin_id:
            # Direct admin provisioning - get admin email
            admin_doc = fs_db.collection('admins').document(admin_id).get()
            if admin_doc.exists:
                admin_email = admin_doc.get('email')

        # Save device record in Realtime Database
        device_record = {
            'uid': user.uid,
            'email': email,
            'deviceName': device_name,
            'macAddress': mac_address,
            'containerId': container_id,
            'firmwareVersion': firmware_version,
            'registeredAt': datetime.now().isoformat(),
            'lastSeen': datetime.now().isoformat(),
            'online': False,
            'status': 'registered',
            'adminId': admin_id,
            'adminEmail': admin_email,
            'qrCodeId': qr_code_id
        }
        rtdb.reference(f'devices/{device_id}').set(device_record)

        # Create container in Realtime Database - linked to admin
        rtdb.reference(f'containers/{container_id}').set({
            'deviceId': device_id,
            'deviceName': device_name,
            'command': 'STOP',
            'online': False,
            'createdAt': datetime.now().isoformat(),
            'adminId': admin_id,
            'adminEmail': admin_email
        })

        # Save to Firestore for admin dashboard
        fs_db.collection('devices').document(device_id).set({
            'deviceId': device_id,
            'deviceName': device_name,
            'email': email,
            'macAddress': mac_address,
            'containerId': container_id,
            'status': 'active',
            'firmwareVersion': firmware_version,
            'registeredAt': datetime.now(),
            'lastSeen': datetime.now(),
            'adminId': admin_id,
            'adminEmail': admin_email,
            'qrCodeId': qr_code_id
        })

        # Link device to admin if admin exists
        if admin_id:
            # Add device to admin's device list in RTDB
            rtdb.reference(f'admins/{admin_id}/devices/{device_id}').set({
                'containerid': container_id,
                'linkedAt': datetime.now().isoformat()
            })
            
            # Add container to admin's containers in RTDB (NEW)
            rtdb.reference(f'admins/{admin_id}/containers/{container_id}').set({
                'deviceId': device_id,
                'deviceName': device_name,
                'linkedAt': datetime.now().isoformat()
            })
            
            # Update Firestore admin document
            fs_db.collection('admins').document(admin_id).update({
                'totalDevices': firestore.Increment(1),
                'lastUpdated': datetime.now()
            })

        return jsonify({
            'success': True,
            'credentials': {
                'email': email,
                'password': password
            },
            'containerId': container_id,
            'message': 'Device registered successfully',
            'linkedToAdmin': admin_id is not None,
            'adminId': admin_id
        }), 201

    except Exception as e:
        print(f"[Registration Error] {e}")
        return jsonify({
            'success': False,
            'message': 'Internal server error',
            'error': str(e)
        }), 500


@app.route('/api/containers/<container_id>/move', methods=['POST'])
@require_admin_token
def move_container(container_id):
    """
    Move Container to New Admin
    
    Called when admin clicks "Move Container" option:
    1. Receives container ID
    2. Receives new admin ID (if transferring)
    3. Updates database to link container to new admin
    4. Returns provisioning details for ESP32 hotspot
    """
    try:
        data = request.get_json()
        new_admin_id = data.get('newAdminId', request.admin_id)  # Default: current admin
        
        # Get container details
        container_doc = fs_db.collection('devices').document(container_id).get()
        if not container_doc.exists:
            return jsonify({
                'success': False,
                'message': 'Container not found'
            }), 404
        
        container_data = container_doc.to_dict()
        old_admin_id = container_data.get('adminId')
        
        # Verify current admin owns this container
        if old_admin_id != request.admin_id:
            return jsonify({
                'success': False,
                'message': 'You do not have permission to move this container'
            }), 403
        
        # Update container to new admin
        fs_db.collection('devices').document(container_id).update({
            'adminId': new_admin_id,
            'movedAt': datetime.now(),
            'movedFrom': old_admin_id
        })
        
        # Update RTDB
        rtdb.reference(f'containers/{container_id}').update({
            'adminId': new_admin_id,
            'movedAt': datetime.now().isoformat()
        })
        
        # Update admin's container lists
        if old_admin_id != new_admin_id:
            # Remove from old admin
            rtdb.reference(f'admins/{old_admin_id}/containers/{container_id}').delete()
            
            # Add to new admin
            rtdb.reference(f'admins/{new_admin_id}/containers/{container_id}').set({
                'deviceId': container_data.get('deviceId'),
                'deviceName': container_data.get('deviceName'),
                'linkedAt': datetime.now().isoformat()
            })
        
        return jsonify({
            'success': True,
            'message': 'Container moved successfully',
            'container': {
                'containerId': container_id,
                'deviceId': container_data.get('deviceId'),
                'newAdminId': new_admin_id
            }
        }), 200

    except Exception as e:
        print(f"[Move Container Error] {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============ QR CODE GENERATION ENDPOINTS ============

@app.route('/api/qr-codes/generate', methods=['POST'])
@require_admin_token
def generate_qr_code():
    """
    Generate QR Code for device registration
    Called by admin from mobile/web app
    """
    try:
        data = request.get_json()
        device_name = data.get('deviceName', 'QRUX Device')
        
        # Generate unique QR code ID
        qr_code_id = secrets.token_urlsafe(16)
        
        # QR code data containing admin info and QR ID
        qr_data = {
            'qrCodeId': qr_code_id,
            'adminId': request.admin_id,
            'adminEmail': request.admin_email,
            'createdAt': datetime.now().isoformat(),
            'expiresAt': None,  # Optional: add expiration
            'deviceName': device_name,
            'scanned': False
        }
        
        # Generate QR code image
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=2,
        )
        qr.add_data(json.dumps(qr_data))
        qr.make(fit=True)
        
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to bytes
        img_io = BytesIO()
        img.save(img_io, 'PNG')
        img_io.seek(0)
        
        # Save QR code metadata to Firestore
        fs_db.collection('qr_codes').document(qr_code_id).set({
            'qrCodeId': qr_code_id,
            'adminId': request.admin_id,
            'adminEmail': request.admin_email,
            'deviceName': device_name,
            'createdAt': datetime.now(),
            'scanned': False,
            'linkedDeviceId': None,
            'scannedAt': None
        })
        
        # Save QR code link in admin's document
        fs_db.collection('admins').document(request.admin_id).update({
            'totalQRCodesGenerated': firestore.Increment(1),
            'lastQRCodeGenerated': datetime.now()
        })
        
        return send_file(
            img_io,
            mimetype='image/png',
            as_attachment=True,
            download_name=f'qrcode_{qr_code_id}.png'
        )

    except Exception as e:
        print(f"[QR Generation Error] {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/qr-codes/<qr_code_id>', methods=['GET'])
def get_qr_code_info(qr_code_id):
    """Get QR code information"""
    try:
        qr_doc = fs_db.collection('qr_codes').document(qr_code_id).get()
        
        if not qr_doc.exists:
            return jsonify({
                'success': False,
                'message': 'QR code not found'
            }), 404
        
        return jsonify({
            'success': True,
            'qrCode': qr_doc.to_dict()
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============ ADMIN ENDPOINTS ============

@app.route('/api/admin/register', methods=['POST'])
def admin_register():
    """
    Admin Registration Endpoint
    Create admin account and Firestore document
    """
    try:
        data = request.get_json()
        email = data.get('email')
        password = data.get('password')
        name = data.get('name')
        organization = data.get('organization')

        if not email or not password or not name:
            return jsonify({
                'success': False,
                'message': 'Missing required fields'
            }), 400

        # Create Firebase Auth user for admin
        user = auth.create_user(
            email=email,
            password=password,
            display_name=name
        )

        # Create admin document in Firestore
        fs_db.collection('admins').document(user.uid).set({
            'adminId': user.uid,
            'email': email,
            'name': name,
            'organization': organization,
            'createdAt': datetime.now(),
            'totalDevices': 0,
            'totalQRCodesGenerated': 0,
            'lastQRCodeGenerated': None,
            'status': 'active'
        })

        # Create admin entry in RTDB
        rtdb.reference(f'admins/{user.uid}').set({
            'email': email,
            'name': name,
            'organization': organization,
            'createdAt': datetime.now().isoformat()
        })

        return jsonify({
            'success': True,
            'adminId': user.uid,
            'message': 'Admin registered successfully'
        }), 201

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/admin/login', methods=['POST'])
def admin_login():
    """
    Admin Login Endpoint
    Returns Firebase ID token for authenticated requests
    """
    try:
        data = request.get_json()
        email = data.get('email')
        password = data.get('password')

        if not email or not password:
            return jsonify({
                'success': False,
                'message': 'Missing email or password'
            }), 400

        # Note: Firebase Admin SDK doesn't have built-in password authentication
        # Use Firebase REST API for authentication (client-side in real app)
        # This is a simplified version - in production, use Firebase Client SDK
        
        return jsonify({
            'success': False,
            'message': 'Use Firebase Auth SDK for login',
            'note': 'Call this from your mobile/web app using Firebase SDK'
        }), 400

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/admin/provisioning-data', methods=['GET'])
@require_admin_token
def get_provisioning_data():
    """
    Get provisioning data for mobile app to send to ESP32
    
    Mobile app uses this to configure ESP32 hotspot provisioning
    """
    try:
        admin_doc = fs_db.collection('admins').document(request.admin_id).get()
        if not admin_doc.exists:
            return jsonify({
                'success': False,
                'message': 'Admin not found'
            }), 404
        
        # Return provisioning info for ESP32
        provisioning_info = {
            'adminId': request.admin_id,
            'adminEmail': request.admin_email,
            'backendUrl': os.getenv('BACKEND_URL', 'localhost'),
            'backendPort': int(os.getenv('BACKEND_PORT', 5000))
        }
        
        return jsonify({
            'success': True,
            'provisioningData': provisioning_info
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/containers/<container_id>/provisioning', methods=['GET'])
@require_admin_token
def get_container_provisioning(container_id):
    """
    Get provisioning data for a specific container
    Used when admin wants to "Move Container" to this ESP32
    """
    try:
        # Verify admin owns this container
        container_doc = fs_db.collection('devices').document(container_id).get()
        if not container_doc.exists:
            return jsonify({
                'success': False,
                'message': 'Container not found'
            }), 404
        
        container_data = container_doc.to_dict()
        if container_data.get('adminId') != request.admin_id:
            return jsonify({
                'success': False,
                'message': 'You do not have permission to access this container'
            }), 403
        
        provisioning_info = {
            'adminId': request.admin_id,
            'adminEmail': request.admin_email,
            'containerId': container_id,
            'deviceId': container_data.get('deviceId'),
            'deviceName': container_data.get('deviceName'),
            'backendUrl': os.getenv('BACKEND_URL', 'localhost'),
            'backendPort': int(os.getenv('BACKEND_PORT', 5000))
        }
        
        return jsonify({
            'success': True,
            'provisioningData': provisioning_info
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
    """Get all devices for logged-in admin"""
    try:
        # Get admin's devices from Firestore
        devices_query = fs_db.collection('devices').where('adminId', '==', request.admin_id)
        devices = [doc.to_dict() for doc in devices_query.stream()]
        
        return jsonify({
            'success': True,
            'devices': devices,
            'totalDevices': len(devices)
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/admin/qr-codes', methods=['GET'])
@require_admin_token
def admin_get_qr_codes():
    """Get all QR codes generated by admin"""
    try:
        qr_query = fs_db.collection('qr_codes').where('adminId', '==', request.admin_id)
        qr_codes = [doc.to_dict() for doc in qr_query.stream()]
        
        return jsonify({
            'success': True,
            'qrCodes': qr_codes,
            'totalQRCodes': len(qr_codes)
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/admin/stats', methods=['GET'])
@require_admin_token
def admin_get_stats():
    """Get admin dashboard statistics"""
    try:
        admin_doc = fs_db.collection('admins').document(request.admin_id).get()
        devices_query = fs_db.collection('devices').where('adminId', '==', request.admin_id)
        devices = list(devices_query.stream())
        
        online_count = sum(1 for d in devices if d.get('status') == 'active')
        
        return jsonify({
            'success': True,
            'stats': {
                'totalDevices': len(devices),
                'onlineDevices': online_count,
                'offlineDevices': len(devices) - online_count,
                'totalQRCodesGenerated': admin_doc.get('totalQRCodesGenerated', 0)
            }
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============ DEVICE STATUS ENDPOINTS ============

@app.route('/api/devices/<device_id>/status', methods=['GET'])
def get_device_status(device_id):
    """Get device status"""
    try:
        device = rtdb.reference(f'devices/{device_id}').get()
        
        if not device:
            return jsonify({
                'success': False,
                'message': 'Device not found'
            }), 404

        return jsonify({
            'success': True,
            'device': device
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/devices', methods=['GET'])
def list_all_devices():
    """List all registered devices"""
    try:
        devices = fs_db.collection('devices').stream()
        device_list = [doc.to_dict() for doc in devices]
        
        return jsonify({
            'success': True,
            'devices': device_list,
            'totalDevices': len(device_list)
        }), 200

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# ============ HEALTH CHECK ============

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat()
    }), 200


if __name__ == '__main__':
    print("\n" + "="*60)
    print("QRUX ESP32 Device Registration Backend")
    print("Platform: Python/Flask (Windows, Mac, Linux)")
    print("="*60)
    port = int(os.getenv('PORT', os.getenv('SERVER_PORT', 5000)))
    print(f"Server starting on port {port}")
    print("="*60 + "\n")
    
    # Run on all interfaces (0.0.0.0) to allow access from other machines
    app.run(
        debug=os.getenv('DEBUG', 'False').lower() == 'true',
        host=os.getenv('SERVER_HOST', '0.0.0.0'),
        port=port,
    )
