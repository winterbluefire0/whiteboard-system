#include <WiFi.h>
#include <WebServer.h>
#include "esp_camera.h"
#include "secrets.h"

// XIAO ESP32-S3 Sense camera pins, following Seeed's pin map.
WebServer server(80);
bool cameraReady = false;
bool apReady = false;
uint16_t sensorPid = 0;
String command;

const char PAGE[] PROGMEM = R"HTML(<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>白板摄像头</title><style>body{font:18px system-ui;margin:24px;background:#fafafa}button,a{padding:12px;display:inline-block}img{display:block;max-width:100%;margin-top:16px}</style>
<h1>白板摄像头</h1><p>调整镜头方向后，点击拍照查看。</p>
<button onclick="document.getElementById('photo').src='/capture?t='+Date.now()">拍照 / 刷新</button>
<a href="/capture" download="whiteboard.jpg">下载照片</a><p id="status">正在检查设备…</p>
<img id="photo" alt="点击拍照后显示画面">
<script>fetch('/status').then(r=>r.json()).then(s=>{document.getElementById('status').textContent=s.camera_ready?'摄像头已就绪':'摄像头初始化失败，请检查扩展板连接';}).catch(()=>{document.getElementById('status').textContent='连接失败，请检查设备热点';});</script></html>)HTML";

String statusJson() {
  return String("{\"firmware\":\"whiteboard-camera-1\",\"camera_ready\":") +
    (cameraReady ? "true" : "false") + ",\"ap_ready\":" + (apReady ? "true" : "false") +
    ",\"sensor_pid\":" + String(sensorPid) + ",\"psram_bytes\":" + String(ESP.getPsramSize()) +
    ",\"clients\":" + String(WiFi.softAPgetStationNum()) + ",\"ip\":\"" + WiFi.softAPIP().toString() + "\"}";
}

camera_fb_t *freshFrame() {
  if (!cameraReady) return nullptr;
  camera_fb_t *old = esp_camera_fb_get();
  if (old) esp_camera_fb_return(old);
  return esp_camera_fb_get();
}

void setup() {
  Serial.begin(115200);
  delay(1200);
  Serial.println("\nWHITEBOARD CAMERA v1");
  WiFi.mode(WIFI_AP);
  apReady = WiFi.softAP(WHITEBOARD_AP_NAME, WHITEBOARD_AP_PASSWORD, 6, false, 2);
  Serial.printf("AP: %s, started=%s\n", WHITEBOARD_AP_NAME, apReady ? "yes" : "no");
  Serial.print("URL: http://"); Serial.println(WiFi.softAPIP());

  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = 15; config.pin_d1 = 17; config.pin_d2 = 18; config.pin_d3 = 16;
  config.pin_d4 = 14; config.pin_d5 = 12; config.pin_d6 = 11; config.pin_d7 = 48;
  config.pin_xclk = 10; config.pin_pclk = 13;
  config.pin_vsync = 38; config.pin_href = 47;
  config.pin_sccb_sda = 40; config.pin_sccb_scl = 39;
  config.pin_pwdn = -1; config.pin_reset = -1;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = psramFound() ? FRAMESIZE_UXGA : FRAMESIZE_VGA;
  config.jpeg_quality = 12;
  config.fb_count = 1;
  config.fb_location = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  esp_err_t result = esp_camera_init(&config);
  cameraReady = result == ESP_OK;
  Serial.printf("CAMERA_INIT: 0x%x\n", result);
  if (cameraReady) {
    sensor_t *sensor = esp_camera_sensor_get();
    sensorPid = sensor->id.PID;
    sensor->set_hmirror(sensor, 1);
    delay(600);
    camera_fb_t *frame = freshFrame();
    if (frame) {
      Serial.printf("SELF_TEST: JPEG %ux%u, %u bytes\n", frame->width, frame->height, (unsigned)frame->len);
      esp_camera_fb_return(frame);
    } else Serial.println("SELF_TEST: frame capture failed");
  }
  server.on("/", HTTP_GET, []() { server.send_P(200, "text/html; charset=utf-8", PAGE); });
  server.on("/status", HTTP_GET, []() { server.send(200, "application/json", statusJson()); });
  server.on("/capture", HTTP_GET, []() {
    camera_fb_t *frame = freshFrame();
    if (!frame) { server.send(503, "text/plain", "Camera capture failed"); return; }
    server.sendHeader("Cache-Control", "no-store");
    server.send_P(200, "image/jpeg", reinterpret_cast<const char *>(frame->buf), frame->len);
    esp_camera_fb_return(frame);
  });
  server.begin();
  Serial.println("READY. USB commands: STATUS or PHOTO");
}

void loop() {
  server.handleClient();
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') {
      command.trim();
      if (command == "STATUS") Serial.println(statusJson());
      else if (command == "PHOTO") {
        camera_fb_t *frame = freshFrame();
        if (frame) {
          Serial.printf("PHOTO_BEGIN %u\n", (unsigned)frame->len);
          Serial.write(frame->buf, frame->len);
          Serial.print("\nPHOTO_END\n");
          esp_camera_fb_return(frame);
        } else Serial.println("PHOTO_ERROR");
      }
      command = "";
    } else if (command.length() < 32) command += c;
  }
  delay(2);
}
