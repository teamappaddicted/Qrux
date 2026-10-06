"""
QRUX ESP32 Device Registration & Management Backend
"""

import os
import json
import secrets

from datetime import datetime
from functools import wraps

from flask import Flask, request, jsonify
from flask_cors import CORS

import firebase_admin
from firebase_admin import credentials, db, auth, firestore

from dotenv import load_dotenv


# ============================================================
# LOAD ENVIRONMENT
# ============================================================

load_dotenv()


# ============================================================
# FLASK APP
# ============================================================

app = Flask(__name__)

CORS(app)


# ============================================================
# FIREBASE INITIALIZATION
# ============================================================

try:

    service_account_json = os.getenv(
        "FIREBASE_SERVICE_ACCOUNT_JSON"
    )

    if service_account_json:

        firebase_cred = credentials.Certificate(
            json.loads(service_account_json)
        )

    else:

        firebase_cred = credentials.Certificate(
            "serviceAccountKey.json"
        )

    firebase_admin.initialize_app(
        firebase_cred,
        {
            "databaseURL": os.getenv(
                "FIREBASE_DATABASE_URL",
                "https://qrux-11a39-default-rtdb.firebaseio.com"
            )
        }
    )

    rtdb = db
    fs_db = firestore.client()

    print("[Firebase] Initialized successfully")

except Exception as e:

    print(f"[Firebase] Initialization error: {e}")

    exit(1)


# ============================================================
# AUTHENTICATION MIDDLEWARE
# ============================================================

def require_admin_token(f):

    @wraps(f)

    def decorated_function(*args, **kwargs):

        token = request.headers.get("Authorization")

        if not token:

            return jsonify({
                "success": False,
                "error": "Missing authorization token"
            }), 401

        try:

            token = token.replace(
                "Bearer ",
                ""
            )

            decoded = auth.verify_id_token(
                token
            )

            request.admin_id = decoded["uid"]

            request.admin_email = decoded.get(
                "email",
                ""
            )

            return f(
                *args,
                **kwargs
            )

        except Exception as e:

            return jsonify({
                "success": False,
                "error": f"Invalid token: {str(e)}"
            }), 401

    return decorated_function


# ============================================================
# CHECK DEVICE REGISTRATION STATUS
# ============================================================

@app.route(
    "/api/devices/<device_id>/registration-status",
    methods=["GET"]
)
def get_device_registration_status(device_id):

    try:

        device = rtdb.reference(
            f"devices/{device_id}"
        ).get()

        if not device:

            return jsonify({

                "success": True,

                "registered": False,

                "deviceId": device_id

            }), 200


        return jsonify({

            "success": True,

            "registered": True,

            "deviceId": device_id,

            "containerId":
                device.get("containerId"),

            "deviceName":
                device.get("deviceName"),

            "online":
                device.get("online", False),

            "status":
                device.get("status", "registered")

        }), 200


    except Exception as e:

        print(
            f"[Device Status Error] {e}"
        )

        return jsonify({

            "success": False,

            "message":
                "Could not check device status",

            "error":
                str(e)

        }), 500


# ============================================================
# DEVICE REGISTRATION
# ============================================================

@app.route(
    "/api/devices/register",
    methods=["POST"]
)
def register_device():

    try:

        data = request.get_json(
            force=True,
            silent=True
        )

        if not data:

            return jsonify({
                "success": False,
                "message": "Invalid JSON payload"
            }), 400


        # ----------------------------------------------------
        # DEVICE DATA
        # ----------------------------------------------------

        device_id = data.get(
            "deviceId"
        )

        device_name = data.get(
            "deviceName",
            "QRUX Device"
        )

        mac_address = data.get(
            "macAddress"
        )

        firmware_version = data.get(
            "firmwareVersion",
            "1.0.0"
        )

        qr_code_id = data.get(
            "qrCodeId"
        )

        admin_id = data.get(
            "adminId"
        )

        requested_container_id = data.get(
            "containerId"
        )


        # ----------------------------------------------------
        # VALIDATION
        # ----------------------------------------------------

        if not device_id:

            return jsonify({
                "success": False,
                "message": "Missing deviceId"
            }), 400


        print(
            f"[Registration] Request from device: {device_id}"
        )


        # ----------------------------------------------------
        # CHECK EXISTING DEVICE
        # ----------------------------------------------------

        existing_device = rtdb.reference(
            f"devices/{device_id}"
        ).get()


        # ====================================================
        # DEVICE ALREADY EXISTS
        # ====================================================

        if existing_device:

            print(
                f"[Registration] Existing device found: {device_id}"
            )


            existing_container_id = existing_device.get(
                "containerId"
            )

            existing_email = existing_device.get(
                "email"
            )

            existing_uid = existing_device.get(
                "uid"
            )


            new_password = secrets.token_hex(16)


            try:

                auth.update_user(

                    existing_uid,

                    password=new_password

                )

            except Exception as auth_error:

                print(
                    "[Registration] Could not update password:"
                )

                print(
                    auth_error
                )

                return jsonify({

                    "success": False,

                    "message":
                        "Could not refresh device credentials"

                }), 500


            rtdb.reference(
                f"devices/{device_id}"
            ).update({

                "lastSeen":
                    datetime.now().isoformat(),

                "online":
                    True,

                "status":
                    "registered"

            })


            return jsonify({

                "success": True,

                "alreadyRegistered": True,

                "credentials": {

                    "email":
                        existing_email,

                    "password":
                        new_password

                },

                "containerId":
                    existing_container_id,

                "message":
                    "Device already registered. Credentials refreshed."

            }), 200


        # ====================================================
        # NEW DEVICE REGISTRATION
        # ====================================================

        password = secrets.token_hex(
            16
        )


        email = (
            f"device_{device_id.lower()}@qrux.com"
        )


        # ----------------------------------------------------
        # CONTAINER ID
        # ----------------------------------------------------

        if requested_container_id:

            container_id = requested_container_id

        else:

            container_id = (
                f"device_{device_id.lower()}"
            )


        # ----------------------------------------------------
        # CREATE FIREBASE AUTH USER
        # ----------------------------------------------------

        user = auth.create_user(

            email=email,

            password=password,

            display_name=device_name

        )


        # ----------------------------------------------------
        # DETERMINE ADMIN
        # ----------------------------------------------------

        admin_email = None


        if not admin_id and qr_code_id:

            qr_doc = (
                fs_db
                .collection("qr_codes")
                .document(qr_code_id)
                .get()
            )


            if qr_doc.exists:

                admin_id = qr_doc.get(
                    "adminId"
                )

                admin_email = qr_doc.get(
                    "adminEmail"
                )


        elif admin_id:

            admin_doc = (
                fs_db
                .collection("admins")
                .document(admin_id)
                .get()
            )


            if admin_doc.exists:

                admin_email = admin_doc.get(
                    "email"
                )


        # ----------------------------------------------------
        # DEVICE RECORD
        # ----------------------------------------------------

        device_record = {

            "uid":
                user.uid,

            "email":
                email,

            "deviceName":
                device_name,

            "macAddress":
                mac_address,

            "containerId":
                container_id,

            "firmwareVersion":
                firmware_version,

            "registeredAt":
                datetime.now().isoformat(),

            "lastSeen":
                datetime.now().isoformat(),

            "online":
                True,

            "status":
                "registered",

            "adminId":
                admin_id,

            "adminEmail":
                admin_email,

            "qrCodeId":
                qr_code_id

        }


        # ----------------------------------------------------
        # SAVE DEVICE TO RTDB
        # ----------------------------------------------------

        rtdb.reference(
            f"devices/{device_id}"
        ).set(
            device_record
        )


        # ----------------------------------------------------
        # CREATE RTDB CONTAINER
        # ----------------------------------------------------

        rtdb.reference(
            f"containers/{container_id}"
        ).set({

            "deviceId":
                device_id,

            "deviceName":
                device_name,

            "command":
                "STOP",

            "online":
                True,

            "createdAt":
                datetime.now().isoformat(),

            "adminId":
                admin_id,

            "adminEmail":
                admin_email

        })


        # ----------------------------------------------------
        # SAVE DEVICE TO FIRESTORE
        # ----------------------------------------------------

        fs_db.collection(
            "devices"
        ).document(
            device_id
        ).set({

            "deviceId":
                device_id,

            "deviceName":
                device_name,

            "email":
                email,

            "macAddress":
                mac_address,

            "containerId":
                container_id,

            "status":
                "active",

            "firmwareVersion":
                firmware_version,

            "registeredAt":
                datetime.now(),

            "lastSeen":
                datetime.now(),

            "adminId":
                admin_id,

            "adminEmail":
                admin_email,

            "qrCodeId":
                qr_code_id

        })


        # ----------------------------------------------------
        # LINK DEVICE TO ADMIN
        # ----------------------------------------------------

        if admin_id:

            rtdb.reference(
                f"admins/{admin_id}/devices/{device_id}"
            ).set({

                "containerId":
                    container_id,

                "linkedAt":
                    datetime.now().isoformat()

            })


            rtdb.reference(
                f"admins/{admin_id}/containers/{container_id}"
            ).set({

                "deviceId":
                    device_id,

                "deviceName":
                    device_name,

                "linkedAt":
                    datetime.now().isoformat()

            })


            try:

                fs_db.collection(
                    "admins"
                ).document(
                    admin_id
                ).update({

                    "totalDevices":
                        firestore.Increment(1),

                    "lastUpdated":
                        datetime.now()

                })

            except Exception as e:

                print(
                    "[Admin] Could not update statistics:"
                )

                print(e)


        print(
            f"[Registration] New device registered: {device_id}"
        )


        return jsonify({

            "success":
                True,

            "alreadyRegistered":
                False,

            "credentials": {

                "email":
                    email,

                "password":
                    password

            },

            "containerId":
                container_id,

            "message":
                "Device registered successfully"

        }), 201


    except Exception as e:

        print(
            f"[Registration Error] {e}"
        )


        return jsonify({

            "success":
                False,

            "message":
                "Internal server error",

            "error":
                str(e)

        }), 500


# ============================================================
# DEVICE STATUS
# ============================================================

@app.route(
    "/api/devices/<device_id>/status",
    methods=["GET"]
)
def get_device_status(device_id):

    try:

        device = rtdb.reference(
            f"devices/{device_id}"
        ).get()


        if not device:

            return jsonify({

                "success":
                    False,

                "message":
                    "Device not found"

            }), 404


        return jsonify({

            "success":
                True,

            "device":
                device

        }), 200


    except Exception as e:

        return jsonify({

            "success":
                False,

            "error":
                str(e)

        }), 500


# ============================================================
# LIST DEVICES
# ============================================================

@app.route(
    "/api/devices",
    methods=["GET"]
)
def list_all_devices():

    try:

        devices = (
            fs_db
            .collection("devices")
            .stream()
        )


        device_list = [

            doc.to_dict()

            for doc in devices

        ]


        return jsonify({

            "success":
                True,

            "devices":
                device_list,

            "totalDevices":
                len(device_list)

        }), 200


    except Exception as e:

        return jsonify({

            "success":
                False,

            "error":
                str(e)

        }), 500


# ============================================================
# HEALTH CHECK
# ============================================================

@app.route(
    "/health",
    methods=["GET"]
)
def health_check():

    return jsonify({

        "status":
            "healthy",

        "timestamp":
            datetime.now().isoformat()

    }), 200


# ============================================================
# START SERVER
# ============================================================

if __name__ == "__main__":

    print("\n" + "=" * 60)

    print(
        "QRUX ESP32 Device Registration Backend"
    )

    print("=" * 60)


    port = int(

        os.getenv(

            "PORT",

            os.getenv(
                "SERVER_PORT",
                5000
            )

        )

    )


    print(
        f"Server starting on port {port}"
    )

    print("=" * 60 + "\n")


    app.run(

        debug=os.getenv(
            "DEBUG",
            "False"
        ).lower() == "true",

        host=os.getenv(
            "SERVER_HOST",
            "0.0.0.0"
        ),

        port=port

    )