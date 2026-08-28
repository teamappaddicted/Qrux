#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

#define WIFI_SSID "YOUR_WIFI_NAME"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"
#define API_KEY "YOUR_FIREBASE_WEB_API_KEY"
#define DATABASE_URL "https://qrux-11a39-default-rtdb.firebaseio.com/"
#define DEVICE_EMAIL "esp32-device@example.com"
#define DEVICE_PASSWORD "USE_A_LONG_RANDOM_PASSWORD"
#define CONTAINER_ID "REPLACE_WITH_FIRESTORE_CONTAINER_ID"

#define MOTOR_LEFT_FORWARD 26  // L298N IN1
#define MOTOR_LEFT_BACKWARD 27 // L298N IN2
#define MOTOR_RIGHT_FORWARD 14 // L298N IN3
#define MOTOR_RIGHT_BACKWARD 25 // L298N IN4
#define MOTOR_LEFT_ENABLE 13   // L298N ENA
#define MOTOR_RIGHT_ENABLE 12  // L298N ENB

FirebaseData stream;
FirebaseAuth auth;
FirebaseConfig config;
String lastCommand;
unsigned long lastCommandAt = 0;

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
  if (timeout) Serial.println("RTDB stream timeout; reconnecting");
}

void setup() {
  Serial.begin(115200);
  pinMode(MOTOR_LEFT_FORWARD, OUTPUT);
  pinMode(MOTOR_LEFT_BACKWARD, OUTPUT);
  pinMode(MOTOR_RIGHT_FORWARD, OUTPUT);
  pinMode(MOTOR_RIGHT_BACKWARD, OUTPUT);
  pinMode(MOTOR_LEFT_ENABLE, OUTPUT);
  pinMode(MOTOR_RIGHT_ENABLE, OUTPUT);
  stopMotors();

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) delay(250);

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = DEVICE_EMAIL;
  auth.user.password = DEVICE_PASSWORD;
  config.token_status_callback = tokenStatusCallback;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  String path = String("/containers/") + CONTAINER_ID + "/command";
  if (!Firebase.RTDB.beginStream(&stream, path.c_str())) {
    Serial.println(stream.errorReason());
  }
  Firebase.RTDB.setStreamCallback(&stream, streamCallback, streamTimeoutCallback);
  Firebase.RTDB.setBool(&stream, String("containers/") + CONTAINER_ID + "/online", true);
}

void loop() {
  if (lastCommandAt != 0 && millis() - lastCommandAt > 2000) {
    stopMotors();
    lastCommandAt = 0;
  }
  if (!Firebase.ready()) return;
  if (!stream.httpConnected()) {
    String path = String("/containers/") + CONTAINER_ID + "/command";
    Firebase.RTDB.beginStream(&stream, path.c_str());
  }
}
