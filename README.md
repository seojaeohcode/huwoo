**2025 AI기반 창업창의력 Jump-UP 대상(전남대학교 총장상)**

# Hoowoo (후우)

**Arduino Mega 기반 호흡 감지 알람 시계**와 **Flutter 블루투스 앱**으로 동작하는 스마트 알람 프로젝트입니다.  
알람이 울리면 **호흡(IR 센서)**으로 끄고, 앱에서 시간 동기화·알람·LED 색상·벨소리를 제어할 수 있습니다.

---

## 주요 기능

### 하드웨어 (Arduino Mega)

| 기능 | 설명 |
|------|------|
| **RTC 시계** | DS1302로 현재 시각 유지. 앱 연결 시 폰 시간으로 자동 동기화 |
| **TFT 디스플레이** | 2.4인치 TFT(MAR 2406 / ILI9341)에 `HH:MM:SS` 표시 |
| **호흡 감지** | HW-488 IR 장애물 센서로 호흡 펄스 감지 → 1초당 펄스 수를 0~100 값으로 앱에 전송 |
| **알람** | 설정한 날짜·시간에 부저로 멜로디 재생. **한 바퀴 울린 뒤 호흡 감지 시 알람 해제** |
| **NeoPixel LED** | 앱에서 RGB 색상 제어 (8구) |
| **블루투스** | HC-06, Serial1로 앱과 시리얼 통신 |

### 앱 (Flutter · Android)

- **블루투스 연결**: 페어링된 기기 목록에서 시계(HC-06) 선택 후 연결
- **RTC 동기화**: 연결 시 폰 시간으로 RTC 자동 동기화 + 수동 「RTC 동기화」 버튼
- **알람 설정**: 날짜·시간 선택, 벨소리 3종(클래식 / 아침멜로디 / 디지털비프) 선택
- **호흡 게임**: Arduino에서 보내는 0~100 호흡 값을 실시간 차트로 표시
- **LED 색상**: 컬러 피커로 NeoPixel 색상 변경

---

## 하드웨어 구성

| 부품 | 연결 |
|------|------|
| **Arduino Mega 2560** | 메인 보드 |
| **HC-06** | 블루투스, Serial1 (TX1=18, RX1=19) |
| **DS1302** | RTC (CLK=22, DAT=23, RST=24) |
| **NeoPixel 8구** | 데이터 핀 25 |
| **부저** | 26 |
| **IR 센서 (HW-488)** | 20 |
| **TFT 2.4" (MAR 2406)** | RD=A0, WR=A1, RS=A2, CS=A3, RST=A4, 데이터 8,9,2,3,4,5,6,7 |

---

## 프로젝트 구조

```
hoowoo/
├── test.ino              # Arduino Mega 스케치 (RTC, TFT, 알람, 호흡, NeoPixel, Serial1)
├── lib/                  # Flutter 앱
│   ├── main.dart
│   ├── screens/
│   │   └── home_screen.dart   # 메인 화면 (연결, RTC, 알람, LED, 호흡 게임)
│   ├── services/
│   │   └── bluetooth_service.dart
│   └── widgets/
│       └── breathing_game_widget.dart
├── pubspec.yaml
└── README.md
```

---

## 시작하기

### 1. Arduino 쪽

1. **Arduino IDE**에서 `test.ino` 열기.
2. **라이브러리 설치**  
   - **필수**: `Adafruit NeoPixel`, `virtuabotixRTC`  
   - **TFT 사용 시** (`USE_TFT 1`): `MCUFRIEND_kbv`, `Adafruit_GFX`
3. TFT를 쓰지 않으면 `test.ino` 상단에서 `#define USE_TFT 0`으로 두면 TFT 라이브러리 없이 컴파일 가능.
4. 보드: **Arduino Mega 2560**, 포트 선택 후 업로드.

### 2. Flutter 앱 (Android)

```bash
flutter pub get
flutter run
# 또는 APK: flutter build apk --debug
```

- **권한**: 블루투스 스캔/연결, (필요 시) 위치 권한 요청됨.
- 디버그 APK: `build/app/outputs/flutter-apk/app-debug.apk`

---

## 앱 ↔ Arduino 프로토콜 (요약)

| 방향 | 형식 | 설명 |
|------|------|------|
| 앱 → Arduino | `SET_RTC:YYYY:MM:DD:HH:MM:SS:DOW` | RTC 동기화 (요일 1=일~7=토) |
| 앱 → Arduino | `SET_ALARM:YYYY:MM:DD:HH:MM` | 알람 설정 |
| 앱 → Arduino | `MELODY:n` | 벨소리 선택 (0, 1, 2) |
| 앱 → Arduino | `RGB:R,G,B` | NeoPixel 색 (0–255) |
| Arduino → 앱 | `Time:HH:MM:SS` | 현재 RTC 시각 |
| Arduino → 앱 | `0`~`100` (한 줄 정수) | 호흡 값 (RPM 기반 0~100) |
| Arduino → 앱 | `ALARM_OFF` | 호흡으로 알람 해제됨 |

---

## 라이선스 / 저장소

- 저장소: [https://github.com/seojaeohcode/huwoo](https://github.com/seojaeohcode/huwoo)
