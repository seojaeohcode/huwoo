/*
 * Hoowoo - Arduino Mega 호흡 알람 시계
 * RTC 시간(앱+TFT), IR 호흡→0~100, 알람(부저), NeoPixel, 블루투스(Serial1)
 * TFT: USE_TFT=1 시 MCUFRIEND_kbv + Adafruit_GFX 필요. 0이면 라이브러리 없이 컴파일.
 */
#define USE_TFT 1   // 0=미사용(라이브러리 없이 컴파일), 1=MCUFRIEND_kbv TFT
#define DEBUG  0

#include <Adafruit_NeoPixel.h>
#include <virtuabotixRTC.h>
#if USE_TFT
#include <MCUFRIEND_kbv.h>
#include <Adafruit_GFX.h>
#endif

// ---- 핀 ----
#define RTC_CLK 22
#define RTC_DAT 23
#define RTC_RST 24
#define NEO_PIN 25
#define NUM_PIXELS 8
#define BUZZER_PIN 26
#define IR_SENSOR_PIN 20
#if USE_TFT
// TFT (테스트 시 사용한 핀 구성)
#define LCD_RD  A0
#define LCD_WR  A1
#define LCD_RS  A2
#define LCD_CS  A3
#define LCD_RST A4
const int TFT_DATA_PINS[8] = {8, 9, 2, 3, 4, 5, 6, 7};
#endif

Adafruit_NeoPixel pixels(NUM_PIXELS, NEO_PIN, NEO_GRB + NEO_KHZ800);
virtuabotixRTC myRTC(RTC_CLK, RTC_DAT, RTC_RST);
#if USE_TFT
MCUFRIEND_kbv tft;
#endif

// ---- NeoPixel ----
int neoRed = 0, neoGreen = 0, neoBlue = 0;
bool neoColorSet = false;

// ---- 호흡 (RPM: 1초당 펄스 → 0~100) ----
int irLastState = HIGH;
unsigned long lastPulseTime = 0;
#define DEBOUNCE_MS 80
#define PULSE_WINDOW_MS 1000
#define PULSES_PER_100 10
#define PULSE_BUF_SIZE 32
unsigned long pulseTimes[PULSE_BUF_SIZE];
uint8_t pulseBufIdx = 0;
bool pulseBufFilled = false;

// ---- 알람 ----
int alarmYear = -1, alarmMonth = -1, alarmDay = -1, alarmHour = -1, alarmMinute = -1;
bool alarmRinging = false;
bool alarmTriggered = false;
bool alarmFirstCycleDone = false;
int melodyIndex = 0;
unsigned long alarmNoteStart = 0;
int alarmNoteIndex = 0;

const int MELODY0_FREQ[] = {880, 0, 440, 0, 880, 0, 440, 0};
const int MELODY0_DUR[]  = {180, 80, 180, 80, 180, 80, 180, 400};
const int MELODY0_LEN = 8;
const int MELODY1_FREQ[] = {262, 294, 330, 349, 392, 392, 330, 262};
const int MELODY1_DUR[]  = {200, 200, 200, 200, 300, 200, 200, 400};
const int MELODY1_LEN = 8;
const int MELODY2_FREQ[] = {1200, 0, 1200, 0, 1200, 0};
const int MELODY2_DUR[]  = {120, 120, 120, 120, 120, 300};
const int MELODY2_LEN = 6;

// ---- RTC/호흡 전송 ----
unsigned long lastSendTime = 0;
unsigned long lastSendBreath = 0;
unsigned long lastAlarmLogTime = 0;
#if USE_TFT
unsigned long lastTFTUpdate = 0;
static void tftPrint2d(int v) {
  if (v < 10) tft.print('0');
  tft.print(v);
}
void tftDisplayTime(int h, int m, int s) {
  h = constrain(h, 0, 23);
  m = constrain(m, 0, 59);
  s = constrain(s, 0, 59);
  tft.fillRect(10, 60, 300, 70, 0x0000);
  tft.setTextColor(0xFFFF, 0x0000);
  tft.setTextSize(4);
  tft.setCursor(10, 75);
  tftPrint2d(h); tft.print(':');
  tftPrint2d(m); tft.print(':');
  tftPrint2d(s);
}
#endif

void playAlarmNote() {
  int freq = 0;
  if (melodyIndex == 0) freq = MELODY0_FREQ[alarmNoteIndex];
  else if (melodyIndex == 1) freq = MELODY1_FREQ[alarmNoteIndex];
  else freq = MELODY2_FREQ[alarmNoteIndex];
  if (freq > 0) tone(BUZZER_PIN, freq);
  else noTone(BUZZER_PIN);
}

void nextAlarmNote() {
  int len = (melodyIndex == 0) ? MELODY0_LEN : (melodyIndex == 1) ? MELODY1_LEN : MELODY2_LEN;
  alarmNoteIndex++;
  if (alarmNoteIndex >= len) {
    alarmNoteIndex = 0;
    alarmFirstCycleDone = true;
  }
  alarmNoteStart = millis();
  playAlarmNote();
}

int getCurrentNoteDuration() {
  if (melodyIndex == 0) return MELODY0_DUR[alarmNoteIndex];
  if (melodyIndex == 1) return MELODY1_DUR[alarmNoteIndex];
  return MELODY2_DUR[alarmNoteIndex];
}

void setup() {
  Serial.begin(9600);
  Serial1.begin(9600);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(IR_SENSOR_PIN, INPUT_PULLUP);
  pixels.begin();
  pixels.clear();
  pixels.show();
  Serial.println("[OK] Hoowoo");
  tone(BUZZER_PIN, 1000, 200);
  delay(300);
  tone(BUZZER_PIN, 1500, 200);
  delay(500);
#if USE_TFT
  pinMode(LCD_RD, OUTPUT);
  pinMode(LCD_WR, OUTPUT);
  pinMode(LCD_RS, OUTPUT);
  pinMode(LCD_CS, OUTPUT);
  pinMode(LCD_RST, OUTPUT);
  for (int i = 0; i < 8; i++) pinMode(TFT_DATA_PINS[i], OUTPUT);
  digitalWrite(LCD_RD, HIGH);
  digitalWrite(LCD_WR, HIGH);
  digitalWrite(LCD_CS, HIGH);
  digitalWrite(LCD_RST, HIGH);
  uint16_t id = tft.readID();
  Serial.print("[TFT] ID=0x"); Serial.println(id, HEX);
  tft.begin(id);
  tft.setRotation(1);
  tft.fillScreen(0x0000);
  tft.setTextColor(0xFFFF, 0x0000);
  tft.setTextSize(2);
  tft.setCursor(10, 10);
  tft.print("RTC TIME (DS1302)");
  tftDisplayTime(0, 0, 0);
  Serial.println("[OK] TFT");
#else
  Serial.println("[OK] TFT off (USE_TFT=0)");
#endif
}

void loop() {
  unsigned long now = millis();

  // 1. RTC → 앱(Serial1)
  myRTC.updateTime();
  if (now - lastSendTime >= 1000) {
    lastSendTime = now;
    Serial1.print("Time: ");
    Serial1.print(myRTC.hours);
    Serial1.print(":");
    Serial1.print(myRTC.minutes);
    Serial1.print(":");
    Serial1.println(myRTC.seconds);
  }

#if USE_TFT
  if (now - lastTFTUpdate >= 500) {
    lastTFTUpdate = now;
    tftDisplayTime((int)myRTC.hours, (int)myRTC.minutes, (int)myRTC.seconds);
  }
#endif

  // 2. IR 호흡 → 0~100 전송
  int irState = digitalRead(IR_SENSOR_PIN);
  if (irLastState == LOW && irState == HIGH && (now - lastPulseTime >= DEBOUNCE_MS)) {
    lastPulseTime = now;
    pulseTimes[pulseBufIdx % PULSE_BUF_SIZE] = now;
    pulseBufIdx++;
    if (pulseBufIdx >= PULSE_BUF_SIZE) pulseBufFilled = true;
#if DEBUG
    Serial.println("[IR] PULSE");
#endif
    if (alarmRinging && alarmFirstCycleDone) {
      noTone(BUZZER_PIN);
      alarmRinging = false;
      alarmTriggered = true;
      alarmFirstCycleDone = false;
      Serial1.println("ALARM_OFF");
    }
  }
  irLastState = irState;

  if (now - lastSendBreath >= 100) {
    lastSendBreath = now;
    unsigned long cutoff = (now >= PULSE_WINDOW_MS) ? (now - PULSE_WINDOW_MS) : 0;
    int n = pulseBufFilled ? PULSE_BUF_SIZE : min((int)pulseBufIdx, PULSE_BUF_SIZE);
    int count = 0;
    for (int i = 0; i < n; i++)
      if (pulseTimes[i] >= cutoff) count++;
    int sendVal = min(count * (100 / PULSES_PER_100), 100);
    Serial1.println(sendVal);
  }

  // 3. 알람 울리기 (RTC 시각 == 설정 시각일 때 부저, 1바퀴 울린 뒤 호흡으로 끄기)
  if (alarmRinging) {
    if (now - alarmNoteStart >= (unsigned long)getCurrentNoteDuration())
      nextAlarmNote();
  } else if (alarmYear >= 0 && alarmMonth >= 0 && alarmDay >= 0 && alarmHour >= 0 && alarmMinute >= 0 && !alarmTriggered) {
    // RTC 연도: DS1302는 보통 0~99, 라이브러리에 따라 2000+ 반환 가능 → 둘 다 비교
    int rtcY = (int)myRTC.year;
    int cmpY = (alarmYear > 100) ? (alarmYear % 100) : alarmYear;
    bool match = (rtcY == cmpY || rtcY == alarmYear) &&
        (int)myRTC.month == alarmMonth && (int)myRTC.dayofmonth == alarmDay &&
        (int)myRTC.hours == alarmHour && (int)myRTC.minutes == alarmMinute;
    if (now - lastAlarmLogTime >= 5000) {
      lastAlarmLogTime = now;
      Serial.print("[알람] RTC="); Serial.print(rtcY); Serial.print("/"); Serial.print((int)myRTC.month);
      Serial.print("/"); Serial.print((int)myRTC.dayofmonth); Serial.print(" ");
      Serial.print((int)myRTC.hours); Serial.print(":"); Serial.print((int)myRTC.minutes);
      Serial.print("  설정="); Serial.print(alarmYear); Serial.print("/"); Serial.print(alarmMonth);
      Serial.print("/"); Serial.print(alarmDay); Serial.print(" "); Serial.print(alarmHour);
      Serial.print(":"); Serial.println(alarmMinute);
    }
    if (match) {
      alarmRinging = true;
      alarmFirstCycleDone = false;
      alarmNoteIndex = 0;
      alarmNoteStart = now;
      playAlarmNote();
      Serial.println("[알람] 울림 (호흡 감지 시 끄기)");
    }
  }

  // 4. 블루투스 수신
  if (Serial1.available()) {
    String buffer = "";
    while (Serial1.available()) {
      buffer += (char)Serial1.read();
      delay(5);
    }
    int from = 0;
    while (from < (int)buffer.length()) {
      int idx = buffer.indexOf('\n', from);
      String line = (idx < 0) ? buffer.substring(from) : buffer.substring(from, idx);
      line.trim();
      from = (idx >= 0) ? idx + 1 : buffer.length();
      if (line.length() == 0) continue;

      if (line.startsWith("RGB:")) {
        int c1 = line.indexOf(',', 4);
        int c2 = line.indexOf(',', c1 + 1);
        if (c1 > 4 && c2 > c1) {
          neoRed   = constrain(line.substring(4, c1).toInt(), 0, 255);
          neoGreen = constrain(line.substring(c1 + 1, c2).toInt(), 0, 255);
          neoBlue  = constrain(line.substring(c2 + 1).toInt(), 0, 255);
          for (int i = 0; i < NUM_PIXELS; i++)
            pixels.setPixelColor(i, pixels.Color(neoRed, neoGreen, neoBlue));
          pixels.show();
          neoColorSet = true;
        }
      } else if (line.startsWith("SET_RTC:")) {
        // 폰 시간으로 RTC 동기화. 형식: SET_RTC:YYYY:MM:DD:HH:MM:SS:DOW (7값)
        String data = line.substring(8);
        int v[7] = {-1, -1, -1, -1, -1, -1, -1};
        int p = 0;
        for (int i = 0; i < 7; i++) {
          int next = data.indexOf(':', p);
          if (next < 0) {
            if (p < (int)data.length()) v[i] = data.substring(p).toInt();
            break;
          }
          v[i] = data.substring(p, next).toInt();
          p = next + 1;
        }
        if (v[0] >= 2000 && v[0] <= 2099 && v[1] >= 1 && v[1] <= 12 && v[2] >= 1 && v[2] <= 31 &&
            v[3] >= 0 && v[3] <= 23 && v[4] >= 0 && v[4] <= 59 && v[5] >= 0 && v[5] <= 59 &&
            v[6] >= 1 && v[6] <= 7) {
          int y = v[0], mo = v[1], d = v[2], h = v[3], mi = v[4], s = v[5];
          int dow = (v[6] == 7) ? 1 : (v[6] + 1);
          // virtuabotixRTC setDS1302Time(..., int year): 풀 연도(2026) 전달. 라이브러리가 칩에 0~99로 기록.
          myRTC.setDS1302Time(s, mi, h, dow, d, mo, y);
          Serial.print("[RTC] 동기화됨 "); Serial.print(y); Serial.print("/"); Serial.print(mo);
          Serial.print("/"); Serial.print(d); Serial.print(" "); Serial.print(h);
          Serial.print(":"); Serial.print(mi); Serial.print(":"); Serial.println(s);
        } else {
          Serial.print("[RTC] 수신했으나 검증실패 len="); Serial.print(data.length());
          Serial.print(" v0="); Serial.print(v[0]); Serial.print(" v6="); Serial.println(v[6]);
        }
      } else if (line.startsWith("SET_ALARM:")) {
        String data = line.substring(10);
        int vals[5] = {-1, -1, -1, -1, -1};
        int p = 0;
        for (int i = 0; i < 5; i++) {
          int next = data.indexOf(':', p);
          if (next < 0) {
            if (p < (int)data.length()) vals[i] = data.substring(p).toInt();
            break;
          }
          vals[i] = data.substring(p, next).toInt();
          p = next + 1;
        }
        if (vals[0] >= 0 && vals[1] >= 0 && vals[2] >= 0 && vals[3] >= 0 && vals[4] >= 0) {
          alarmYear = vals[0]; alarmMonth = vals[1]; alarmDay = vals[2];
          alarmHour = vals[3]; alarmMinute = vals[4];
          alarmTriggered = false;
          alarmRinging = false;
          alarmFirstCycleDone = false;
          noTone(BUZZER_PIN);
          Serial.print("[알람] 수신 "); Serial.print(alarmYear); Serial.print("/"); Serial.print(alarmMonth);
          Serial.print("/"); Serial.print(alarmDay); Serial.print(" "); Serial.print(alarmHour);
          Serial.print(":"); Serial.println(alarmMinute);
        }
      } else if (line.startsWith("MELODY:")) {
        int n = line.substring(7).toInt();
        if (n >= 0 && n <= 2) melodyIndex = n;
      }
    }
  }

  delay(20);
}
