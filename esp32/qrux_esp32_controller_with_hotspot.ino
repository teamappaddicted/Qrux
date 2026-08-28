#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include <SPIFFS.h>
#include <ArduinoJson.h>
#include <WebServer.h>

// ===== WiFi Configuration =====
#define WIFI_SSID "your_wifi_network_name"          // Your WiFi SSID
#define WIFI_PASSWORD "your_wifi_password"          // Your WiFi password

// ===== Firebase Configuration =====
#define DATABASE_URL "https://qrux-11a39-default-rtdb.firebaseio.com/"
#define FIREBASE_API_KEY "NQuxxjrOvfgtuklpaVmtC5ow6OSrghJdzMk7725r"

// ===== Backend Configuration =====
#define REGISTRATION_SERVER "armor-aspects-crossword-pearl.trycloudflare.com"
#define REGISTRATION_ENDPOINT "/api/devices/register"
#define REGISTRATION_PORT 443

// ===== Device Identifiers =====
String DEVICE_ID;
String DEVICE_NAME = "QRUX_ESP32_Controller";
String CONTAINER_ID;

// ===== Hotspot Configuration (For Admin Provisioning) =====
#define HOTSPOT_SSID_PREFIX "QRUX-"
#define HOTSPOT_PASSWORD "12345678"
WebServer server(80);

// Credentials storage
#define CREDENTIALS_FILE "/device_creds.json"

// Motor pins
#define MOTOR_LEFT_FORWARD 26
#define MOTOR_LEFT_BACKWARD 27
#define MOTOR_RIGHT_FORWARD 14
#define MOTOR_RIGHT_BACKWARD 25
#define MOTOR_LEFT_ENABLE 13
#define MOTOR_RIGHT_ENABLE 12

// Device state
struct DeviceCredentials {
  String email;
  String password;
  String containerId;
  String adminId;      // ← NEW: Admin who owns this device
  String wifiSsid;
  String wifiPassword;
  String backendUrl;
  int backendPort;
  String qrCodeId;
  bool isProvisioned;
  bool isRegistered;
} deviceCreds;

struct ProvisioningData {
  String adminId;
  String backendUrl;
  int backendPort;
  String qrCodeId;
} provisioningData;

// Connection state
FirebaseData stream;
FirebaseAuth auth;
FirebaseConfig config;
String lastCommand;
unsigned long lastCommandAt = 0;
bool firebaseConnected = false;
bool deviceRegistered = false;
bool hotspotMode = false;  // ← Is device in hotspot provisioning mode?
unsigned long hotspotTimeout = 0;
bool provisioningRestartPending = false;
unsigned long provisioningRestartAt = 0;

// ========== UTILITY FUNCTIONS ==========

String generateDeviceID() {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char macStr[18];
  sprintf(macStr, "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(macStr);
}

// ===== HOTSPOT MODE (For Admin Provisioning) =====

void startHotspotMode() {
  Serial.println("\n[Hotspot] Starting WiFi Access Point for admin provisioning...");
  
  // Stop normal WiFi
  WiFi.disconnect(true);  // Turn off WiFi radio
  delay(100);
  
  // Create hotspot SSID: QRUX-A1B2C3D4E5F6
  String hotspotSSID = HOTSPOT_SSID_PREFIX + DEVICE_ID;
  
  Serial.print("[Hotspot] SSID: ");
  Serial.println(hotspotSSID);
  Serial.print("[Hotspot] Password: ");
  Serial.println(HOTSPOT_PASSWORD);
  
  // Start access point
  WiFi.softAP(hotspotSSID.c_str(), HOTSPOT_PASSWORD);
  
  Serial.print("[Hotspot] IP Address: ");
  Serial.println(WiFi.softAPIP());  // Usually 192.168.4.1
  
  hotspotMode = true;
  hotspotTimeout = millis();
  
  // Setup web server endpoints
  setupHotspotServer();
  
  Serial.println("[Hotspot] ✓ Ready! Admin can now connect from mobile app.");
}

void setupHotspotServer() {
  // Endpoint for admin to provision this device
  server.on("/api/provision", HTTP_POST, handleProvisioningRequest);
  
  // Endpoint for admin to get device info
  server.on("/api/device-info", HTTP_GET, handleDeviceInfoRequest);
  
  // Endpoint for admin to check connection
  server.on("/health", HTTP_GET, []() {
    server.send(200, "application/json", "{\"status\":\"online\"}");
  });
  
  server.begin();
  Serial.println("[Hotspot Server] Started on port 80");
}

// Admin sends provisioning data via this endpoint
void handleProvisioningRequest() {
  Serial.println("[Hotspot] Received provisioning request from admin...");
  
  if (server.method() != HTTP_POST) {
    server.send(405, "application/json", "{\"success\":false,\"error\":\"Method not allowed\"}");
    return;
  }
  
  String body = server.arg("plain");
  Serial.print("[Hotspot] Payload: ");
  Serial.println(body);
  
  StaticJsonDocument<512> doc;
  DeserializationError error = deserializeJson(doc, body);
  
  if (error) {
    Serial.print("[Hotspot] JSON parse error: ");
    Serial.println(error.c_str());
    server.send(400, "application/json", "{\"success\":false,\"error\":\"Invalid JSON\"}");
    return;
  }
  
  // Extract provisioning data from admin
  provisioningData.adminId = doc["adminId"].as<String>();
  provisioningData.backendUrl = doc["backendUrl"].as<String>();
  provisioningData.backendPort = doc["backendPort"] | 5000;
  provisioningData.qrCodeId = doc["qrCodeId"].as<String>();
  String wifiSsid = doc["wifiSsid"].as<String>();
  String wifiPassword = doc["wifiPassword"].as<String>();
  String requestedDeviceId = doc["deviceId"].as<String>();

  if (requestedDeviceId != DEVICE_ID) {
    server.send(409, "application/json", "{\"success\":false,\"error\":\"This provisioning request is for another ESP32\"}");
    return;
  }
  if (provisioningData.adminId.isEmpty() || wifiSsid.isEmpty() || wifiPassword.isEmpty()) {
    server.send(400, "application/json", "{\"success\":false,\"error\":\"adminId, deviceId, wifiSsid and wifiPassword are required\"}");
    return;
  }
  
  Serial.println("[Hotspot] ✓ Provisioning data received:");
  Serial.print("  Admin ID: ");
  Serial.println(provisioningData.adminId);
  Serial.print("  Backend: ");
  Serial.print(provisioningData.backendUrl);
  Serial.print(":");
  Serial.println(provisioningData.backendPort);
  
  // Save admin info locally
  deviceCreds.adminId = provisioningData.adminId;
  deviceCreds.wifiSsid = wifiSsid;
  deviceCreds.wifiPassword = wifiPassword;
  deviceCreds.backendUrl = provisioningData.backendUrl;
  deviceCreds.backendPort = provisioningData.backendPort;
  deviceCreds.qrCodeId = provisioningData.qrCodeId;
  deviceCreds.isProvisioned = true;

  if (!saveCredentialsToFile(deviceCreds)) {
    server.send(500, "application/json", "{\"success\":false,\"error\":\"Could not save provisioning data\"}");
    return;
  }
  
  // Respond to admin
  server.send(200, "application/json", "{\"success\":true,\"message\":\"Device provisioning received. Reconnecting to backend...\"}");
  
  // Restart after the HTTP response has had time to reach the app.
  provisioningRestartPending = true;
  provisioningRestartAt = millis() + 1000;
}

// Admin can check device info
void handleDeviceInfoRequest() {
  StaticJsonDocument<256> doc;
  doc["deviceId"] = DEVICE_ID;
  doc["deviceName"] = DEVICE_NAME;
  doc["firmwareVersion"] = "1.0.0";
  doc["macAddress"] = WiFi.macAddress();
  doc["registered"] = deviceRegistered;
  doc["adminId"] = deviceCreds.adminId;
  
  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

// ===== NORMAL REGISTRATION FLOW =====

bool saveCredentialsToFile(const DeviceCredentials& creds) {
  StaticJsonDocument<768> doc;
  doc["email"] = creds.email;
  doc["password"] = creds.password;
  doc["containerId"] = creds.containerId;
  doc["adminId"] = creds.adminId;
  doc["wifiSsid"] = creds.wifiSsid;
  doc["wifiPassword"] = creds.wifiPassword;
  doc["backendUrl"] = creds.backendUrl;
  doc["backendPort"] = creds.backendPort;
  doc["qrCodeId"] = creds.qrCodeId;
  doc["isProvisioned"] = creds.isProvisioned;
  doc["deviceId"] = DEVICE_ID;
  doc["isRegistered"] = creds.isRegistered;

  File file = SPIFFS.open(CREDENTIALS_FILE, "w");
  if (!file) {
    Serial.println("[Storage] Failed to open credentials file");
    return false;
  }

  if (serializeJson(doc, file) == 0) {
    Serial.println("[Storage] Failed to write credentials");
    file.close();
    return false;
  }

  file.close();
  Serial.println("[Storage] ✓ Credentials saved with admin link");
  return true;
}

bool loadCredentialsFromFile(DeviceCredentials& creds) {
  if (!SPIFFS.exists(CREDENTIALS_FILE)) {
    Serial.println("[Storage] No credentials file found");
    return false;
  }

  File file = SPIFFS.open(CREDENTIALS_FILE, "r");
  if (!file) {
    Serial.println("[Storage] Failed to open credentials file");
    return false;
  }

  StaticJsonDocument<768> doc;
  DeserializationError error = deserializeJson(doc, file);
  file.close();

  if (error) {
    Serial.println("[Storage] JSON parse error");
    return false;
  }

  creds.email = doc["email"].as<String>();
  creds.password = doc["password"].as<String>();
  creds.containerId = doc["containerId"].as<String>();
  creds.adminId = doc["adminId"].as<String>();
  creds.wifiSsid = doc["wifiSsid"].as<String>();
  creds.wifiPassword = doc["wifiPassword"].as<String>();
  creds.backendUrl = doc["backendUrl"].as<String>();
  creds.backendPort = doc["backendPort"] | 5000;
  creds.qrCodeId = doc["qrCodeId"].as<String>();
  creds.isProvisioned = doc["isProvisioned"] | false;
  creds.isRegistered = doc["isRegistered"] | false;

  Serial.println("[Storage] ✓ Credentials loaded");
  return true;
}

bool registerDeviceWithBackend() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[Registration] WiFi not connected");
    return false;
  }

  Serial.println("[Registration] Registering with backend...");
  
  WiFiClientSecure client;
  client.setInsecure();
  
  String backendUrl = provisioningData.backendUrl.length() > 0
    ? provisioningData.backendUrl
    : String(REGISTRATION_SERVER);
  int backendPort = provisioningData.backendPort > 0
    ? provisioningData.backendPort
    : REGISTRATION_PORT;

  if (!client.connect(backendUrl.c_str(), backendPort)) {
    Serial.println("[Registration] Failed to connect to backend");
    return false;
  }

  StaticJsonDocument<256> payload;
  payload["deviceId"] = DEVICE_ID;
  payload["deviceName"] = DEVICE_NAME;
  payload["macAddress"] = WiFi.macAddress();
  payload["firmwareVersion"] = "1.0.0";
  payload["qrCodeId"] = provisioningData.qrCodeId;
  payload["adminId"] = provisioningData.adminId;  // ← Include admin info

  String jsonStr;
  serializeJson(payload, jsonStr);

  String request = "POST " + String(REGISTRATION_ENDPOINT) + " HTTP/1.1\r\n";
  request += "Host: " + backendUrl + "\r\n";
  request += "Content-Type: application/json\r\n";
  request += "Content-Length: " + String(jsonStr.length()) + "\r\n";
  request += "Connection: close\r\n\r\n";
  request += jsonStr;

  client.print(request);

  String response = "";
  while (client.connected() || client.available()) {
    if (client.available()) {
      response += client.readStringUntil('\n');
    }
  }
  client.stop();

  int bodyStart = response.indexOf("\r\n\r\n");
  if (bodyStart == -1) bodyStart = response.lastIndexOf('}');
  String jsonResponse = response.substring(bodyStart + 4);

  StaticJsonDocument<256> responseDoc;
  DeserializationError error = deserializeJson(responseDoc, jsonResponse);

  if (error) {
    Serial.println("[Registration] Parse error");
    return false;
  }

  if (responseDoc["success"]) {
    deviceCreds.email = responseDoc["credentials"]["email"].as<String>();
    deviceCreds.password = responseDoc["credentials"]["password"].as<String>();
    deviceCreds.containerId = responseDoc["containerId"].as<String>();
    deviceCreds.isRegistered = true;

    CONTAINER_ID = deviceCreds.containerId;

    Serial.println("[Registration] ✓ Device registered!");
    Serial.print("[Registration] Admin: ");
    Serial.println(deviceCreds.adminId);

    return saveCredentialsToFile(deviceCreds);
  }

  Serial.println("[Registration] Backend rejected registration");
  return false;
}

void printWifiStatus() {
  Serial.print("[WiFi] SSID: ");
  Serial.print(WiFi.SSID());
  Serial.print(" | IP: ");
  Serial.print(WiFi.localIP());
  Serial.print(" | Signal: ");
  Serial.print(WiFi.RSSI());
  Serial.println(" dBm");
}

void printFirebaseStatus() {
  Serial.print("[Firebase] Connected: ");
  Serial.print(firebaseConnected ? "YES" : "NO");
  Serial.print(" | Stream: ");
  Serial.print(stream.httpConnected() ? "ACTIVE" : "INACTIVE");
  Serial.print(" | Admin: ");
  Serial.println(deviceCreds.adminId);
}

void stopMotors() {
  digitalWrite(MOTOR_LEFT_FORWARD, LOW);
  digitalWrite(MOTOR_LEFT_BACKWARD, LOW);
  digitalWrite(MOTOR_RIGHT_FORWARD, LOW);
  digitalWrite(MOTOR_RIGHT_BACKWARD, LOW);
  digitalWrite(MOTOR_LEFT_ENABLE, LOW);
  digitalWrite(MOTOR_RIGHT_ENABLE, LOW);
}

void applyCommand(const String& command) {
  stopMotors();
  lastCommandAt = millis();
  if (command == "FORWARD") {
    digitalWrite(MOTOR_LEFT_ENABLE, HIGH);
    digitalWrite(MOTOR_RIGHT_ENABLE, HIGH);
    digitalWrite(MOTOR_LEFT_FORWARD, HIGH);
    digitalWrite(MOTOR_RIGHT_FORWARD, HIGH);
  } else if (command == "BACKWARD") {
    digitalWrite(MOTOR_LEFT_ENABLE, HIGH);
    digitalWrite(MOTOR_RIGHT_ENABLE, HIGH);
    digitalWrite(MOTOR_LEFT_BACKWARD, HIGH);
    digitalWrite(MOTOR_RIGHT_BACKWARD, HIGH);
  } else if (command == "LEFT") {
    digitalWrite(MOTOR_RIGHT_ENABLE, HIGH);
    digitalWrite(MOTOR_RIGHT_FORWARD, HIGH);
  } else if (command == "RIGHT") {
    digitalWrite(MOTOR_LEFT_ENABLE, HIGH);
    digitalWrite(MOTOR_LEFT_FORWARD, HIGH);
  }
}

void streamCallback(FirebaseStream data) {
  if (data.dataType() != "json") return;
  FirebaseJson json = data.to<FirebaseJson>();
  FirebaseJsonData value;
  if (json.get(value, "value") && value.type == "string") {
    String command = value.stringValue;
    if (command != lastCommand) {
      lastCommand = command;
      applyCommand(command);
      Firebase.RTDB.setBool(&stream, String("containers/") + CONTAINER_ID + "/online", true);
    }
  }
}

void streamTimeoutCallback(bool timeout) {
  if (timeout) Serial.println("[Firebase] Stream timeout");
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n=== QRUX ESP32 Controller (With Admin Provisioning) ===\n");
  
  if (!SPIFFS.begin(true)) {
    Serial.println("[SPIFFS] Mount failed");
    return;
  }

  DEVICE_ID = generateDeviceID();
  Serial.print("[Device] ID: ");
  Serial.println(DEVICE_ID);

  pinMode(MOTOR_LEFT_FORWARD, OUTPUT);
  pinMode(MOTOR_LEFT_BACKWARD, OUTPUT);
  pinMode(MOTOR_RIGHT_FORWARD, OUTPUT);
  pinMode(MOTOR_RIGHT_BACKWARD, OUTPUT);
  pinMode(MOTOR_LEFT_ENABLE, OUTPUT);
  pinMode(MOTOR_RIGHT_ENABLE, OUTPUT);
  stopMotors();

  // Try to load existing credentials
  if (loadCredentialsFromFile(deviceCreds) && (deviceCreds.isProvisioned || deviceCreds.isRegistered)) {
    Serial.println("[Credentials] Loaded existing credentials");
    Serial.print("[Credentials] Linked to Admin: ");
    Serial.println(deviceCreds.adminId);
    deviceRegistered = deviceCreds.isRegistered;
    CONTAINER_ID = deviceCreds.containerId;
    provisioningData.adminId = deviceCreds.adminId;
    provisioningData.backendUrl = deviceCreds.backendUrl;
    provisioningData.backendPort = deviceCreds.backendPort;
    provisioningData.qrCodeId = deviceCreds.qrCodeId;
  } else {
    // No credentials - Start hotspot for admin provisioning
    Serial.println("[Setup] No credentials found!");
    Serial.println("[Setup] Starting WiFi hotspot for admin provisioning...");
    startHotspotMode();
    return;  // Wait in hotspot mode for admin provisioning
  }

  // Connect to normal WiFi
  String wifiSsid = deviceCreds.wifiSsid.length() > 0
    ? deviceCreds.wifiSsid
    : String(WIFI_SSID);
  String wifiPassword = deviceCreds.wifiPassword.length() > 0
    ? deviceCreds.wifiPassword
    : String(WIFI_PASSWORD);

  Serial.print("[WiFi] Connecting to ");
  Serial.println(wifiSsid);
  WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WiFi] ✓ Connected!");
    printWifiStatus();
  } else {
    Serial.println("\n[WiFi] Connection failed!");
    return;
  }

  // A provisioned device gets Firebase credentials from the backend once.
  if (!deviceCreds.isRegistered) {
    if (!registerDeviceWithBackend()) {
      Serial.println("[Registration] Registration failed; retry after restart");
      return;
    }
    deviceRegistered = true;
  }

  // Configure Firebase
  config.api_key = FIREBASE_API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = deviceCreds.email;
  auth.user.password = deviceCreds.password;
  config.token_status_callback = tokenStatusCallback;
  
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  String path = String("/containers/") + CONTAINER_ID + "/command";
  Serial.print("[Firebase] Listening to: ");
  Serial.println(path);
  
  if (Firebase.RTDB.beginStream(&stream, path.c_str())) {
    Serial.println("[Firebase] ✓ Stream started!");
    Firebase.RTDB.setStreamCallback(&stream, streamCallback, streamTimeoutCallback);
    firebaseConnected = true;
  } else {
    Serial.print("[Firebase] Stream error: ");
    Serial.println(stream.errorReason());
  }
  
  String onlinePath = String("/containers/") + CONTAINER_ID + "/online";
  Firebase.RTDB.setBool(&stream, onlinePath.c_str(), true);
  
  Serial.println("\n=== Setup Complete ===\n");
  printFirebaseStatus();
}

void loop() {
  if (provisioningRestartPending && millis() >= provisioningRestartAt) {
    ESP.restart();
  }

  // If in hotspot mode, handle web server requests
  if (hotspotMode) {
    server.handleClient();
    
    // Check for timeout (30 seconds) - go back to normal startup
    if (millis() - hotspotTimeout > 30000) {
      Serial.println("[Hotspot] Timeout! Provisioning data received?");
      if (!provisioningData.adminId.isEmpty()) {
        Serial.println("[Hotspot] Yes! Received admin data. Restarting...");
        ESP.restart();  // Restart to continue with provisioning
      }
    }
    return;
  }

  // Auto-stop motors
  if (lastCommandAt != 0 && millis() - lastCommandAt > 2000) {
    stopMotors();
    lastCommandAt = 0;
  }

  if (!Firebase.ready()) {
    Serial.println("[Firebase] Not ready");
    return;
  }

  if (!stream.httpConnected()) {
    if (millis() % 5000 == 0) {  // Try every 5 seconds
      String path = String("/containers/") + CONTAINER_ID + "/command";
      if (Firebase.RTDB.beginStream(&stream, path.c_str())) {
        Serial.println("[Stream] ✓ Reconnected!");
        Firebase.RTDB.setStreamCallback(&stream, streamCallback, streamTimeoutCallback);
        firebaseConnected = true;
      }
    }
  }
}
