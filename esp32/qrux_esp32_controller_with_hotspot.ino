#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Firebase_ESP_Client.h>

#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

#include <SPIFFS.h>
#include <ArduinoJson.h>
#include <WebServer.h>
#include <ESP32Servo.h>


// =====================================================
// FIREBASE CONFIGURATION
// =====================================================

#define DATABASE_URL "https://qrux-11a39-default-rtdb.firebaseio.com/"
#define FIREBASE_API_KEY "AIzaSyC1ZgVWLMVagn4luRdLb4P4UfZVKzwDIRQ"


// =====================================================
// BACKEND CONFIGURATION
// =====================================================

#define REGISTRATION_SERVER \
  "late-habitat-floor-require.trycloudflare.com"

#define REGISTRATION_ENDPOINT "/api/devices/register"

#define REGISTRATION_PORT 443


// =====================================================
// DEVICE CONFIGURATION
// =====================================================

String DEVICE_ID;

String DEVICE_NAME =
    "QRUX_ESP32_Controller";

String CONTAINER_ID;


// =====================================================
// HOTSPOT CONFIGURATION
// =====================================================

#define HOTSPOT_SSID_PREFIX "QRUX-"
#define HOTSPOT_PASSWORD "12345678"

WebServer server(80);

bool hotspotMode = false;
bool hotspotServerStarted = false;


// =====================================================
// FILE STORAGE
// =====================================================

#define CREDENTIALS_FILE "/device_creds_v2.json"


// =====================================================
// MOTOR PINS
// =====================================================

#define MOTOR_LEFT_FORWARD 26
#define MOTOR_LEFT_BACKWARD 27

#define MOTOR_RIGHT_FORWARD 14
#define MOTOR_RIGHT_BACKWARD 25

#define MOTOR_LEFT_ENABLE 13
#define MOTOR_RIGHT_ENABLE 12

#define LID_SERVO_LEFT_PIN 18
#define LID_SERVO_RIGHT_PIN 19

Servo lidServoLeft;
Servo lidServoRight;


// =====================================================
// DEVICE CREDENTIALS
// =====================================================

struct DeviceCredentials {

  String email;
  String password;

  String containerId;
  String adminId;

  String wifiSsid;
  String wifiPassword;

  String backendUrl;
  int backendPort;

  bool isProvisioned;
  bool isRegistered;
};


DeviceCredentials deviceCreds;


// =====================================================
// FIREBASE VARIABLES
// =====================================================

FirebaseData stream;
FirebaseData firebaseData;

FirebaseAuth auth;
FirebaseConfig config;

bool firebaseConnected = false;
bool firebaseInitialized = false;

String lastCommand = "STOP";

unsigned long lastCommandAt = 0;
unsigned long lastCommandCheck = 0;


// =====================================================
// PROVISIONING RESTART
// =====================================================

bool provisioningRestartPending = false;
unsigned long provisioningRestartAt = 0;


// =====================================================
// TIMERS
// =====================================================

unsigned long lastHotspotAttempt = 0;
unsigned long lastWiFiRetry = 0;
unsigned long lastRegistrationAttempt = 0;
unsigned long lastFirebaseAttempt = 0;
unsigned long lastStreamErrorAt = 0;
unsigned long lastReconnectAttempt = 0;


// =====================================================
// NORMALIZE BACKEND HOST
// =====================================================

String normalizeBackendHost(
  String backendUrl
) {

  backendUrl.trim();

  if (
    backendUrl.startsWith("https://")
  ) {

    backendUrl =
        backendUrl.substring(8);
  }

  if (
    backendUrl.startsWith("http://")
  ) {

    backendUrl =
        backendUrl.substring(7);
  }

  while (
    backendUrl.endsWith("/")
  ) {

    backendUrl.remove(
      backendUrl.length() - 1
    );
  }

  int slashIndex =
      backendUrl.indexOf("/");

  if (
    slashIndex != -1
  ) {

    backendUrl =
        backendUrl.substring(
          0,
          slashIndex
        );
  }

  return backendUrl;
}


// =====================================================
// GENERATE DEVICE ID
// =====================================================

String generateDeviceID() {

  const uint64_t factoryMac =
      ESP.getEfuseMac();

  char macStr[13];

  for (
    uint8_t index = 0;
    index < 6;
    index++
  ) {

    const uint8_t macByte =
        (factoryMac >> ((5 - index) * 8)) & 0xFF;

    sprintf(
      macStr + (index * 2),
      "%02X",
      static_cast<unsigned int>(macByte)
    );
  }

  macStr[12] = '\0';

  if (
    (factoryMac & 0xFFFFFFFFFFFFULL) == 0
  ) {

    Serial.println(
      "[Device] Invalid factory MAC address"
    );
  }

  return String(macStr);
}


// =====================================================
// SAVE CREDENTIALS
// =====================================================

bool saveCredentialsToFile(
  const DeviceCredentials& creds
) {

  StaticJsonDocument<1024> doc;

  doc["email"] =
      creds.email;

  doc["password"] =
      creds.password;

  doc["containerId"] =
      creds.containerId;

  doc["adminId"] =
      creds.adminId;

  doc["wifiSsid"] =
      creds.wifiSsid;

  doc["wifiPassword"] =
      creds.wifiPassword;

  doc["backendUrl"] =
      creds.backendUrl;

  doc["backendPort"] =
      creds.backendPort;

  doc["isProvisioned"] =
      creds.isProvisioned;

  doc["isRegistered"] =
      creds.isRegistered;

  doc["deviceId"] =
      DEVICE_ID;


  File file =
      SPIFFS.open(
        CREDENTIALS_FILE,
        "w"
      );


  if (!file) {

    Serial.println(
      "[Storage] Failed to open credentials file"
    );

    return false;
  }


  if (
    serializeJson(
      doc,
      file
    ) == 0
  ) {

    Serial.println(
      "[Storage] Failed to write credentials"
    );

    file.close();

    return false;
  }


  file.close();


  Serial.println(
    "[Storage] Credentials saved successfully"
  );


  return true;
}


// =====================================================
// LOAD CREDENTIALS
// =====================================================

bool loadCredentialsFromFile(
  DeviceCredentials& creds
) {

  if (
    !SPIFFS.exists(
      CREDENTIALS_FILE
    )
  ) {

    Serial.println(
      "[Storage] No credentials file found"
    );

    return false;
  }


  File file =
      SPIFFS.open(
        CREDENTIALS_FILE,
        "r"
      );


  if (!file) {

    Serial.println(
      "[Storage] Failed to open credentials file"
    );

    return false;
  }


  StaticJsonDocument<1024> doc;


  DeserializationError error =
      deserializeJson(
        doc,
        file
      );


  file.close();


  if (error) {

    Serial.println(
      "[Storage] JSON parse error"
    );

    return false;
  }


  creds.email =
      doc["email"]
          .as<String>();


  creds.password =
      doc["password"]
          .as<String>();


  creds.containerId =
      doc["containerId"]
          .as<String>();


  creds.adminId =
      doc["adminId"]
          .as<String>();


  creds.wifiSsid =
      doc["wifiSsid"]
          .as<String>();


  creds.wifiPassword =
      doc["wifiPassword"]
          .as<String>();


  creds.backendUrl =
      doc["backendUrl"]
          .as<String>();


  creds.backendPort =
      doc["backendPort"]
          | REGISTRATION_PORT;


  creds.isProvisioned =
      doc["isProvisioned"]
          | false;


  creds.isRegistered =
      doc["isRegistered"]
          | false;


  const String storedDeviceId =
      doc["deviceId"].as<String>();


  if (
    !storedDeviceId.isEmpty()
    &&
    storedDeviceId != DEVICE_ID
  ) {

    Serial.println(
      "[Storage] Device ID changed; refreshing registration"
    );

    creds.email = "";
    creds.password = "";
    creds.isRegistered = false;
  }


  // Always use current backend configuration.

  creds.backendUrl =
      REGISTRATION_SERVER;

  creds.backendPort =
      REGISTRATION_PORT;


  Serial.println(
    "[Storage] Credentials loaded"
  );


  Serial.print(
    "[Storage] Container ID: "
  );

  Serial.println(
    creds.containerId
  );


  Serial.print(
    "[Storage] Backend Host: "
  );

  Serial.println(
    creds.backendUrl
  );


  return true;
}


// =====================================================
// DEVICE INFO
// =====================================================

void handleDeviceInfoRequest() {

  StaticJsonDocument<512> doc;


  doc["deviceId"] =
      DEVICE_ID;

  doc["deviceName"] =
      DEVICE_NAME;

  doc["macAddress"] =
      WiFi.macAddress();

  doc["containerId"] =
      deviceCreds.containerId;

  doc["registered"] =
      deviceCreds.isRegistered;

    doc["wifiConnected"] =
      WiFi.status() == WL_CONNECTED;

    doc["firebaseReady"] =
      firebaseInitialized && Firebase.ready();

  doc["backendUrl"] =
      deviceCreds.backendUrl;


  String response;


  serializeJson(
    doc,
    response
  );


  server.send(
    200,
    "application/json",
    response
  );
}


// =====================================================
// PROVISIONING REQUEST
// =====================================================

void handleProvisioningRequest() {

  Serial.println(
    "\n[Provisioning] Request received"
  );


  String body =
      server.arg("plain");


  StaticJsonDocument<1024> doc;


  DeserializationError error =
      deserializeJson(
        doc,
        body
      );


  if (error) {

    server.send(
      400,
      "application/json",
      "{\"success\":false,\"error\":\"Invalid JSON\"}"
    );

    return;
  }


  String adminId =
      doc["adminId"]
          .as<String>();


  String wifiSsid =
      doc["wifiSsid"]
          .as<String>();


  String wifiPassword =
      doc["wifiPassword"]
          .as<String>();


  String containerId =
      doc["containerId"]
          .as<String>();


  String backendUrl =
      doc["backendUrl"]
          .as<String>();


  int backendPort =
      doc["backendPort"]
          | REGISTRATION_PORT;


  if (
    adminId.isEmpty()
    ||
    wifiSsid.isEmpty()
    ||
    wifiPassword.isEmpty()
    ||
    containerId.isEmpty()
  ) {

    server.send(
      400,
      "application/json",
      "{\"success\":false,\"error\":\"Missing provisioning data\"}"
    );

    return;
  }


  deviceCreds.adminId =
      adminId;


  deviceCreds.containerId =
      containerId;


  CONTAINER_ID =
      containerId;


  deviceCreds.wifiSsid =
      wifiSsid;


  deviceCreds.wifiPassword =
      wifiPassword;


  if (
    !backendUrl.isEmpty()
  ) {

    deviceCreds.backendUrl =
        normalizeBackendHost(
          backendUrl
        );

    deviceCreds.backendPort =
        backendPort;

  } else {

    deviceCreds.backendUrl =
        REGISTRATION_SERVER;

    deviceCreds.backendPort =
        REGISTRATION_PORT;
  }


  deviceCreds.isProvisioned =
      true;


  deviceCreds.isRegistered =
      false;


  Serial.println(
    "\n================================="
  );

  Serial.println(
    "[Provisioning] SAVED CONFIGURATION"
  );

  Serial.print(
    "[Provisioning] Container ID: "
  );

  Serial.println(
    deviceCreds.containerId
  );

  Serial.print(
    "[Provisioning] Backend: "
  );

  Serial.println(
    deviceCreds.backendUrl
  );

  Serial.println(
    "================================="
  );


  if (
    !saveCredentialsToFile(
      deviceCreds
    )
  ) {

    server.send(
      500,
      "application/json",
      "{\"success\":false,\"error\":\"Could not save credentials\"}"
    );

    return;
  }


  server.send(
    200,
    "application/json",
    "{\"success\":true,\"message\":\"Provisioning successful\"}"
  );


  provisioningRestartPending =
      true;


  provisioningRestartAt =
      millis() + 1500;
}


// =====================================================
// HOTSPOT SERVER
// =====================================================

void setupHotspotServer() {

  if (
    hotspotServerStarted
  ) {

    return;
  }


  server.on(
    "/api/provision",
    HTTP_POST,
    handleProvisioningRequest
  );


  server.on(
    "/api/device-info",
    HTTP_GET,
    handleDeviceInfoRequest
  );


  server.on(
    "/health",
    HTTP_GET,
    []() {

      server.send(
        200,
        "application/json",
        "{\"status\":\"online\"}"
      );

    }
  );


  server.begin();

  hotspotServerStarted =
      true;


  Serial.println(
    "[Hotspot] Web server started"
  );
}


// =====================================================
// START HOTSPOT
// =====================================================

void startHotspotMode() {

  String hotspotSSID =
      String(HOTSPOT_SSID_PREFIX)
      + DEVICE_ID;


  Serial.println(
    "[Hotspot] Starting..."
  );


  // Keep AP + station Wi-Fi together.

  WiFi.mode(
    WIFI_AP_STA
  );


  // Start AP correctly.

  bool apStarted =
      WiFi.softAP(
        hotspotSSID.c_str(),
        HOTSPOT_PASSWORD
      );


  if (
    !apStarted
  ) {

    hotspotMode =
        false;

    Serial.println(
      "[Hotspot] Failed to start"
    );

    return;
  }


  Serial.println(
    "\n================================="
  );

  Serial.println(
    "QRUX ESP32 HOTSPOT ACTIVE"
  );

  Serial.print(
    "SSID: "
  );

  Serial.println(
    hotspotSSID
  );

  Serial.print(
    "Password: "
  );

  Serial.println(
    HOTSPOT_PASSWORD
  );

  Serial.print(
    "IP: "
  );

  Serial.println(
    WiFi.softAPIP()
  );

  Serial.println(
    "================================="
  );


  hotspotMode =
      true;


  setupHotspotServer();
}


// =====================================================
// CONNECT WIFI
// =====================================================

bool connectToWiFi() {

  Serial.println(
    "\n[WiFi] Connecting..."
  );


  WiFi.mode(
    WIFI_AP_STA
  );


  WiFi.begin(
    deviceCreds.wifiSsid.c_str(),
    deviceCreds.wifiPassword.c_str()
  );


  int attempts = 0;


  while (
    WiFi.status() != WL_CONNECTED
    &&
    attempts < 30
  ) {

    delay(500);

    Serial.print(".");

    attempts++;
  }


  if (
    WiFi.status() == WL_CONNECTED
  ) {

    Serial.println(
      "\n[WiFi] Connected successfully!"
    );


    Serial.print(
      "[WiFi] IP: "
    );

    Serial.println(
      WiFi.localIP()
    );


    return true;
  }


  Serial.println(
    "\n[WiFi] Connection failed"
  );


  return false;
}


// =====================================================
// REGISTER DEVICE
// =====================================================

bool registerDeviceWithBackend() {

  if (
    WiFi.status() != WL_CONNECTED
  ) {

    Serial.println(
      "[Registration] WiFi not connected"
    );

    return false;
  }


  Serial.println(
    "[Registration] Connecting to backend..."
  );


  WiFiClientSecure client;

  client.setInsecure();


  String backendHost =
      normalizeBackendHost(
        deviceCreds.backendUrl
      );


  int backendPort =
      deviceCreds.backendPort;


  if (
    backendHost.isEmpty()
  ) {

    backendHost =
        REGISTRATION_SERVER;
  }


  if (
    backendPort == 0
  ) {

    backendPort =
        REGISTRATION_PORT;
  }


  if (
    !client.connect(
      backendHost.c_str(),
      backendPort
    )
  ) {

    Serial.println(
      "[Registration] Could not connect to backend"
    );

    return false;
  }


  StaticJsonDocument<512> payload;


  payload["deviceId"] =
      DEVICE_ID;

  payload["deviceName"] =
      DEVICE_NAME;

  payload["macAddress"] =
      WiFi.macAddress();

  payload["firmwareVersion"] =
      "1.0.0";

  payload["containerId"] =
      deviceCreds.containerId;

  payload["adminId"] =
      deviceCreds.adminId;


  String jsonStr;


  serializeJson(
    payload,
    jsonStr
  );


  String httpRequest =
      "POST "
      + String(REGISTRATION_ENDPOINT)
      + " HTTP/1.1\r\n";


  httpRequest +=
      "Host: "
      + backendHost
      + "\r\n";


  httpRequest +=
      "Content-Type: application/json\r\n";


  httpRequest +=
      "Content-Length: "
      + String(jsonStr.length())
      + "\r\n";


  httpRequest +=
      "Connection: close\r\n\r\n";


  httpRequest +=
      jsonStr;


  client.print(
    httpRequest
  );


  String response;


  unsigned long timeout =
      millis();


  while (
    client.connected()
    ||
    client.available()
  ) {

    if (
      millis() - timeout > 15000
    ) {

      Serial.println(
        "[Registration] Timeout"
      );

      break;
    }


    while (
      client.available()
    ) {

      response +=
          client.readString();

      timeout =
          millis();
    }
  }


  client.stop();


  int statusLineEnd =
      response.indexOf("\r\n");


  if (
    statusLineEnd == -1
  ) {

    Serial.println(
      "[Registration] Invalid HTTP response"
    );

    return false;
  }


  String statusLine =
      response.substring(
        0,
        statusLineEnd
      );


  int statusCodeStart =
      statusLine.indexOf(' ');


  int httpStatus =
      statusCodeStart == -1
          ? 0
          : statusLine.substring(
                statusCodeStart + 1,
                statusCodeStart + 4
            ).toInt();


  if (
    httpStatus < 200
    ||
    httpStatus >= 300
  ) {

    Serial.print(
      "[Registration] Backend HTTP status: "
    );

    Serial.println(
      httpStatus
    );


    int errorBodyStart =
        response.indexOf("\r\n\r\n");


    if (
      errorBodyStart != -1
    ) {

      String errorBody =
          response.substring(
            errorBodyStart + 4
          );


      errorBody.trim();


      if (
        errorBody.indexOf("1033") != -1
      ) {

        Serial.println(
          "[Registration] Cloudflare tunnel unavailable; retrying"
        );
      }
    }


    return false;
  }


  int bodyStart =
      response.indexOf(
        "\r\n\r\n"
      );


  if (
    bodyStart == -1
  ) {

    Serial.println(
      "[Registration] Invalid response"
    );

    return false;
  }


  String jsonResponse =
      response.substring(
        bodyStart + 4
      );


  StaticJsonDocument<1024> responseDoc;


  DeserializationError error =
      deserializeJson(
        responseDoc,
        jsonResponse
      );


  if (error) {

    Serial.println(
      "[Registration] Invalid JSON from backend:"
    );

    Serial.println(
      error.c_str()
    );

    Serial.println(
      jsonResponse
    );

    return false;
  }


  if (
    responseDoc["success"] == true
  ) {

    deviceCreds.email =
        responseDoc["credentials"]["email"]
            .as<String>();


    deviceCreds.password =
        responseDoc["credentials"]["password"]
            .as<String>();


    if (
      deviceCreds.containerId.isEmpty()
    ) {

      String backendContainerId =
          responseDoc["containerId"]
              .as<String>();


      if (
        !backendContainerId.isEmpty()
      ) {

        deviceCreds.containerId =
            backendContainerId;
      }
    }


    CONTAINER_ID =
        deviceCreds.containerId;


    deviceCreds.isRegistered =
        true;


    saveCredentialsToFile(
      deviceCreds
    );


    Serial.println(
      "[Registration] Device registered successfully"
    );


    Serial.print(
      "[Registration] FINAL CONTAINER ID: "
    );

    Serial.println(
      CONTAINER_ID
    );


    return true;
  }


  Serial.println(
    "[Registration] Backend rejected device"
  );


  return false;
}


// =====================================================
// MOTOR CONTROL
// =====================================================

void stopMotors() {

  digitalWrite(
    MOTOR_LEFT_FORWARD,
    LOW
  );

  digitalWrite(
    MOTOR_LEFT_BACKWARD,
    LOW
  );

  digitalWrite(
    MOTOR_RIGHT_FORWARD,
    LOW
  );

  digitalWrite(
    MOTOR_RIGHT_BACKWARD,
    LOW
  );

  digitalWrite(
    MOTOR_LEFT_ENABLE,
    LOW
  );

  digitalWrite(
    MOTOR_RIGHT_ENABLE,
    LOW
  );
}


// =====================================================
// APPLY COMMAND
// =====================================================

void applyCommand(
  const String& command
) {

  Serial.println(
    "---------------------------------"
  );


  Serial.print(
    "[Motor] Applying command: "
  );


  Serial.println(
    command
  );


  stopMotors();

  delay(50);


  lastCommandAt =
      millis();


  if (
    command == "OPEN"
  ) {

    lidServoLeft.write(90);
    lidServoRight.write(90);

  }


  else if (
    command == "CLOSE"
  ) {

    lidServoLeft.write(0);
    lidServoRight.write(0);

  }


  else if (
    command == "FORWARD"
  ) {

    Serial.println(
      "[Motor] Moving FORWARD"
    );


    digitalWrite(
      MOTOR_LEFT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_LEFT_FORWARD,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_FORWARD,
      HIGH
    );

  }


  else if (
    command == "BACKWARD"
  ) {

    Serial.println(
      "[Motor] Moving BACKWARD"
    );


    digitalWrite(
      MOTOR_LEFT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_LEFT_BACKWARD,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_BACKWARD,
      HIGH
    );

  }


  else if (
    command == "LEFT"
  ) {

    Serial.println(
      "[Motor] Moving LEFT"
    );


    digitalWrite(
      MOTOR_LEFT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_LEFT_BACKWARD,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_FORWARD,
      HIGH
    );

  }


  else if (
    command == "RIGHT"
  ) {

    Serial.println(
      "[Motor] Moving RIGHT"
    );


    digitalWrite(
      MOTOR_LEFT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_ENABLE,
      HIGH
    );


    digitalWrite(
      MOTOR_LEFT_FORWARD,
      HIGH
    );


    digitalWrite(
      MOTOR_RIGHT_BACKWARD,
      HIGH
    );

  }


  else {

    Serial.println(
      "[Motor] STOP"
    );


    stopMotors();

    lastCommandAt =
        0;
  }


  Serial.println(
    "---------------------------------"
  );
}


// =====================================================
// PROCESS COMMAND
// =====================================================

void processCommand(
  String command
) {

  command.trim();

  command.toUpperCase();


  if (
    command.isEmpty()
  ) {

    return;
  }


  if (
    command != "FORWARD"
    &&
    command != "BACKWARD"
    &&
    command != "LEFT"
    &&
    command != "RIGHT"
    &&
    command != "STOP"
    &&
    command != "OPEN"
    &&
    command != "CLOSE"
  ) {

    Serial.print(
      "[Command] Invalid command ignored: "
    );

    Serial.println(
      command
    );

    return;
  }


  if (
    command != lastCommand
  ) {

    lastCommand =
        command;


    Serial.print(
      "[Command] Received: "
    );


    Serial.println(
      command
    );


    applyCommand(
      command
    );
  }
}


// =====================================================
// FIREBASE STREAM CALLBACK
// =====================================================

void streamCallback(
  FirebaseStream data
) {

  Serial.print(
    "[Firebase Stream] Type: "
  );


  Serial.println(
    data.dataType()
  );


  if (
    data.dataType() == "string"
  ) {

    String command =
        data.stringData();


    processCommand(
      command
    );
  }
}


// =====================================================
// STREAM TIMEOUT CALLBACK
// =====================================================

void streamTimeoutCallback(
  bool timeout
) {

  if (
    timeout
  ) {

    Serial.println(
      "[Firebase] Stream timeout"
    );
  }
}


// =====================================================
// FALLBACK COMMAND CHECK
// =====================================================

void checkCommandFallback() {

  if (
    millis() - lastCommandCheck < 500
  ) {

    return;
  }


  lastCommandCheck =
      millis();


  if (
    CONTAINER_ID.isEmpty()
  ) {

    return;
  }


  String commandPath =
      "/containers/"
      + CONTAINER_ID
      + "/command";


  if (
    Firebase.RTDB.getString(
      &firebaseData,
      commandPath.c_str()
    )
  ) {

    String command =
        firebaseData.stringData();


    processCommand(
      command
    );

  }


  else {

    Serial.print(
      "[Firebase Read Error] "
    );


    Serial.println(
      firebaseData.errorReason()
    );
  }
}


// =====================================================
// SETUP FIREBASE
// =====================================================

bool setupFirebase() {

  config.api_key =
      FIREBASE_API_KEY;


  config.database_url =
      DATABASE_URL;


  auth.user.email =
      deviceCreds.email;


  auth.user.password =
      deviceCreds.password;


  config.token_status_callback =
      tokenStatusCallback;


  Firebase.begin(
    &config,
    &auth
  );


  Firebase.reconnectWiFi(
    true
  );


  Serial.println(
    "[Firebase] Waiting for authentication..."
  );


  unsigned long startTime =
      millis();


  while (
    !Firebase.ready()
    &&
    millis() - startTime < 30000
  ) {

    delay(100);

    Serial.print(".");
  }


  if (
    !Firebase.ready()
  ) {

    Serial.println(
      "\n[Firebase] Authentication failed"
    );


    return false;
  }


  Serial.println(
    "\n[Firebase] Ready"
  );


  firebaseInitialized =
      true;


  return true;
}


// =====================================================
// START FIREBASE STREAM
// =====================================================

void startFirebaseStream() {

  if (
    CONTAINER_ID.isEmpty()
  ) {

    Serial.println(
      "[Firebase] Container ID empty"
    );

    return;
  }


  String path =
      "/containers/"
      + CONTAINER_ID
      + "/command";


  Serial.println(
    "\n================================="
  );


  Serial.println(
    "[Firebase] LISTENING AT:"
  );


  Serial.println(
    path
  );


  Serial.println(
    "================================="
  );


  if (
    Firebase.RTDB.beginStream(
      &stream,
      path.c_str()
    )
  ) {

    Firebase.RTDB.setStreamCallback(
      &stream,
      streamCallback,
      streamTimeoutCallback
    );


    firebaseConnected =
        true;


    Serial.println(
      "[Firebase] Stream started successfully"
    );

  }


  else {

    firebaseConnected =
        false;


    Serial.print(
      "[Firebase] Stream error: "
    );


    Serial.println(
      stream.errorReason()
    );
  }
}


// =====================================================
// SETUP
// =====================================================

void setup() {

  Serial.begin(
    115200
  );


  delay(1000);


  Serial.println(
    "\n================================="
  );


  Serial.println(
    "QRUX ESP32 CONTROLLER"
  );


  Serial.println(
    "================================="
  );


  // ===================================================
  // SPIFFS
  // ===================================================

  if (
    !SPIFFS.begin(true)
  ) {

    Serial.println(
      "[SPIFFS] Mount failed"
    );

    return;
  }


  // ===================================================
  // DEVICE ID
  // ===================================================

  WiFi.mode(
    WIFI_STA
  );


  DEVICE_ID =
      generateDeviceID();


  Serial.print(
    "[Device] ID: "
  );


  Serial.println(
    DEVICE_ID
  );


  // ===================================================
  // MOTOR PINS
  // ===================================================

  pinMode(
    MOTOR_LEFT_FORWARD,
    OUTPUT
  );


  pinMode(
    MOTOR_LEFT_BACKWARD,
    OUTPUT
  );


  pinMode(
    MOTOR_RIGHT_FORWARD,
    OUTPUT
  );


  pinMode(
    MOTOR_RIGHT_BACKWARD,
    OUTPUT
  );


  pinMode(
    MOTOR_LEFT_ENABLE,
    OUTPUT
  );


  pinMode(
    MOTOR_RIGHT_ENABLE,
    OUTPUT
  );


  // ===================================================
  // SERVOS
  // ===================================================

  lidServoLeft.setPeriodHertz(50);

  lidServoRight.setPeriodHertz(50);


  lidServoLeft.attach(
    LID_SERVO_LEFT_PIN,
    500,
    2400
  );


  lidServoRight.attach(
    LID_SERVO_RIGHT_PIN,
    500,
    2400
  );


  lidServoLeft.write(0);

  lidServoRight.write(0);


  stopMotors();


  // ===================================================
  // LOAD CREDENTIALS
  // ===================================================

  bool credentialsLoaded =
      loadCredentialsFromFile(
        deviceCreds
      );


  // ===================================================
  // ALWAYS START HOTSPOT
  // ===================================================

  startHotspotMode();


  // ===================================================
  // NOT PROVISIONED
  // ===================================================

  if (
    !credentialsLoaded
    ||
    !deviceCreds.isProvisioned
  ) {

    Serial.println(
      "[Setup] Device not provisioned"
    );


    Serial.println(
      "[Setup] Waiting for provisioning through hotspot"
    );


    return;
  }


  // ===================================================
  // PROVISIONED
  // ===================================================

  CONTAINER_ID =
      deviceCreds.containerId;


  Serial.println(
    "[Setup] Device already provisioned"
  );


  Serial.print(
    "[Setup] Container ID: "
  );


  Serial.println(
    CONTAINER_ID
  );


  // ===================================================
  // CONNECT WIFI
  // ===================================================

  if (
    !connectToWiFi()
  ) {

    Serial.println(
      "[Setup] WiFi failed"
    );


    Serial.println(
      "[Setup] Hotspot remains active"
    );


    return;
  }


  // ===================================================
  // REGISTER DEVICE
  // ===================================================

  if (
    !deviceCreds.isRegistered
  ) {

    if (
      !registerDeviceWithBackend()
    ) {

      Serial.println(
        "[Setup] Device registration failed"
      );


      return;
    }
  }


  // ===================================================
  // FIREBASE
  // ===================================================

  if (
    !setupFirebase()
  ) {

    return;
  }


  // ===================================================
  // SET ONLINE
  // ===================================================

  Firebase.RTDB.setBool(
    &firebaseData,

    (
      "/containers/"
      + CONTAINER_ID
      + "/online"
    ).c_str(),

    true
  );


  // ===================================================
  // START STREAM
  // ===================================================

  startFirebaseStream();


  // ===================================================
  // INITIAL COMMAND
  // ===================================================

  checkCommandFallback();


  Serial.println(
    "\n================================="
  );


  Serial.println(
    "QRUX DEVICE READY"
  );


  Serial.print(
    "CONTAINER ID: "
  );


  Serial.println(
    CONTAINER_ID
  );


  Serial.print(
    "COMMAND PATH: /containers/"
  );


  Serial.print(
    CONTAINER_ID
  );


  Serial.println(
    "/command"
  );


  Serial.print(
    "HOTSPOT: QRUX-"
  );


  Serial.println(
    DEVICE_ID
  );


  Serial.println(
    "=================================\n"
  );
}


// =====================================================
// LOOP
// =====================================================

void loop() {

  // ===================================================
  // RESTART AFTER PROVISIONING
  // ===================================================

  if (
    provisioningRestartPending
    &&
    millis() >= provisioningRestartAt
  ) {

    delay(500);

    ESP.restart();
  }


  // ===================================================
  // KEEP HOTSPOT ALIVE
  // ===================================================

  if (
    hotspotMode
  ) {

    server.handleClient();


    if (
      WiFi.softAPIP()
      ==
      IPAddress(0, 0, 0, 0)
    ) {

      Serial.println(
        "[Hotspot] AP stopped; restarting"
      );


      hotspotMode =
          false;
    }
  }


  // ===================================================
  // RESTART HOTSPOT IF NEEDED
  // ===================================================

  if (
    !hotspotMode
    &&
    millis() - lastHotspotAttempt >= 10000
  ) {

    lastHotspotAttempt =
        millis();


    startHotspotMode();
  }


  // ===================================================
  // NOT PROVISIONED
  // ===================================================

  if (
    !deviceCreds.isProvisioned
  ) {

    delay(10);

    return;
  }


  // ===================================================
  // WIFI RECONNECT
  // ===================================================

  if (
    WiFi.status() != WL_CONNECTED
  ) {

    if (
      lastWiFiRetry == 0
      ||
      millis() - lastWiFiRetry >= 15000
    ) {

      lastWiFiRetry =
          millis();


      Serial.println(
        "[WiFi] Disconnected; retrying saved network"
      );


      WiFi.mode(
        WIFI_AP_STA
      );


      WiFi.begin(
        deviceCreds.wifiSsid.c_str(),
        deviceCreds.wifiPassword.c_str()
      );
    }


    delay(10);

    return;
  }


  // ===================================================
  // REGISTRATION RETRY
  // ===================================================

  if (
    !deviceCreds.isRegistered
  ) {

    if (
      lastRegistrationAttempt == 0
      ||
      millis() - lastRegistrationAttempt >= 15000
    ) {

      lastRegistrationAttempt =
          millis();


      Serial.println(
        "[Registration] Retrying backend connection..."
      );


      registerDeviceWithBackend();
    }


    if (
      !deviceCreds.isRegistered
    ) {

      delay(10);

      return;
    }
  }


  // ===================================================
  // FIREBASE AUTH RETRY
  // ===================================================

  if (
    !firebaseInitialized
  ) {

    if (
      lastFirebaseAttempt == 0
      ||
      millis() - lastFirebaseAttempt >= 15000
    ) {

      lastFirebaseAttempt =
          millis();


      Serial.println(
        "[Firebase] Retrying authentication..."
      );


      bool ready =
          setupFirebase();


      if (
        ready
      ) {

        if (
          !Firebase.RTDB.setBool(
            &firebaseData,

            (
              "/containers/"
              + CONTAINER_ID
              + "/online"
            ).c_str(),

            true
          )
        ) {

          Serial.print(
            "[Firebase] Online status write failed: "
          );


          Serial.println(
            firebaseData.errorReason()
          );
        }


        startFirebaseStream();

        checkCommandFallback();
      }
    }


    return;
  }


  // ===================================================
  // FIREBASE NOT READY
  // ===================================================

  if (
    !Firebase.ready()
  ) {

    return;
  }


  // ===================================================
  // FALLBACK COMMAND
  // ===================================================

  checkCommandFallback();


  // ===================================================
  // FIREBASE STREAM
  // ===================================================

  if (
    !Firebase.RTDB.readStream(
      &stream
    )
  ) {

    if (
      millis() - lastStreamErrorAt > 5000
    ) {

      lastStreamErrorAt =
          millis();


      Serial.print(
        "[Firebase Stream Error] "
      );


      Serial.println(
        stream.errorReason()
      );
    }
  }


  // ===================================================
  // STREAM RECONNECT
  // ===================================================

  if (
    !stream.httpConnected()
  ) {

    if (
      millis() - lastReconnectAttempt > 5000
    ) {

      lastReconnectAttempt =
          millis();


      Serial.println(
        "[Firebase] Reconnecting stream..."
      );


      startFirebaseStream();
    }
  }


  // ===================================================
  // AUTO STOP AFTER 2 SECONDS
  // ===================================================

  if (
    lastCommandAt != 0
    &&
    millis() - lastCommandAt > 2000
  ) {

    Serial.println(
      "[Safety] Auto STOP"
    );


    stopMotors();


    lastCommand =
        "STOP";


    lastCommandAt =
        0;
  }
}