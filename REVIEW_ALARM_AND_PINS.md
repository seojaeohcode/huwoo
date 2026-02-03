# 코드 검토: 참고 테스트 코드 vs 현재 test.ino

## 1. 핀 구성 비교

| 항목 | 참고 코드 | 현재 test.ino | 비고 |
|------|-----------|----------------|------|
| RTC | CLK 22, DAT 23, RST 24 | 동일 | ✓ |
| NeoPixel | NEO 25, 8개 | 동일 | ✓ |
| Buzzer | 26 | 동일 | ✓ |
| TFT 제어 | RD A0, WR A1, RS A2, CS A3, RST A4 | 동일 (LCD_RD ~ LCD_RST) | ✓ |
| TFT 데이터 | dataPins[8] = 8,9,2,3,4,5,6,7 | TFT_DATA_PINS[8] 동일 | ✓ |
| 블루투스 | BT_RX 19, BT_TX 18 (Serial1) | Mega 기본 Serial1 사용 | ✓ |
| IR/호흡 | OBST_PIN 2 (인터럽트) | IR_SENSOR_PIN 20 (폴링) | 설계 차이: 현재는 20번으로 폴링 |

---

## 2. 알람 로직 검토 (제대로 울리는지)

### 2.1 트리거 조건

- **조건:** `alarmYear~alarmMinute` 가 모두 ≥ 0 이고, `!alarmTriggered` 일 때만 “설정 시각인지” 비교.
- **비교:** RTC 연·월·일·시·분 == 앱에서 받은 알람 연·월·일·시·분.

### 2.2 RTC 연도 처리 (DS1302)

- DS1302는 보통 연도를 **0~99** 로 저장.
- virtuabotixRTC는 **0~99** 또는 **2000+** 중 하나로 반환할 수 있음.
- **현재 코드:**  
  `cmpY = (alarmYear > 100) ? (alarmYear % 100) : alarmYear`  
  `match = (rtcY == cmpY || rtcY == alarmYear) && ...`
- 따라서 RTC가 **25** 또는 **2025** 를 반환해도, 앱에서 **2025** 로 설정하면 둘 다 올바르게 매칭됨. ✓

### 2.3 같은 분 안에서 여러 번 트리거 방지

- `match` 가 true 가 되면 `alarmRinging = true` 로만 바꿈.
- 그 다음 루프부터는 **항상** `if (alarmRinging)` 블록으로 들어가고, `else if (... !alarmTriggered)` 는 타지 않음.
- 따라서 **같은 분(예: 14:30:00 ~ 14:30:59)** 에서 알람이 여러 번 켜지지 않음. ✓

### 2.4 멜로디 재생

- `playAlarmNote()` → 현재 `alarmNoteIndex` 에 해당하는 주파수/무음 재생.
- `getCurrentNoteDuration()` 만큼 시간이 지나면 `nextAlarmNote()` 호출 → 인덱스 증가, 한 바퀴 돌면 `alarmFirstCycleDone = true`.
- 1바퀴가 끝난 뒤부터만 호흡 감지 시 알람 끄기 가능. ✓

### 2.5 호흡으로 끄기

- `alarmRinging && alarmFirstCycleDone` 일 때만 호흡(IR 펄스)으로 끔.
- 끄면: `alarmRinging = false`, `alarmTriggered = true`, `Serial1.println("ALARM_OFF")` → 앱에 전달. ✓

### 2.6 다음 날/새 알람

- **같은 알람:** 호흡으로 끄면 `alarmTriggered = true` 이므로, 다음 날 같은 시각에도 **다시 울리지 않음** (의도: “이번 설정에 대해 한 번만 울림”).
- **새 알람:** 앱에서 `SET_ALARM:YYYY:MM:DD:HH:MM` 를 다시 보내면 `alarmTriggered = false` 로 초기화되므로, 새로 설정한 시각에 정상적으로 울림. ✓

---

## 3. 결론

- **핀:** 참고 테스트 코드와 TFT·RTC·NeoPixel·Buzzer 핀 구성이 일치하며, IR만 20번 폴링으로 다름.
- **알람:**  
  - 설정 시각과 RTC 시각(연·월·일·시·분)이 일치할 때 한 번만 울리기 시작하고,  
  - 같은 분에 재트리거되지 않으며,  
  - 1바퀴 울린 뒤 호흡으로 끄고,  
  - 끄면 `alarmTriggered` 로 같은 설정에 대해 재울림을 막고,  
  - 새 `SET_ALARM` 수신 시 다시 울리게 되어 있음.  

**알람은 현재 로직대로 제대로 울리도록 되어 있음.**  
테스트 시 시리얼에 `[알람] 울림 (호흡 감지 시 끄기)` 가 한 번 출력되는지 확인하면 트리거 여부를 쉽게 볼 수 있음.
