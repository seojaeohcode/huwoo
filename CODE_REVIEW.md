# Hoowoo 전체 코드 검토

검토일: 2025-01-23  
대상: Arduino Mega 스케치(`test.ino`), Flutter 앱(`lib/`), 블루투스·호흡·알람·TFT·NeoPixel 연동.

---

## 1. 아키텍처 요약

| 구분 | 역할 |
|------|------|
| **Arduino Mega** | RTC 시간, TFT(MAR 2406) 시간 표시, IR 호흡 감지(RPM→0~100), NeoPixel, 부저 알람, 블루투스(Serial1) 수신/송신 |
| **Flutter 앱** | 블루투스 연결, RTC 시간 표시, 호흡 미니게임, 알람 설정·전송, LED 색상 전송, ALARM_OFF 수신 시 성공 다이얼로그 |

**통신 규약**
- 앱 → 아두이노: `SET_ALARM:YYYY:MM:DD:HH:MM\n`, `MELODY:n\n`, `RGB:r,g,b\n`
- 아두이노 → 앱: `Time: HH:MM:SS\n`, `ALARM_OFF\n`, 호흡값 `0~100`(줄 단위)

---

## 2. Arduino (`test.ino`) 검토

### 잘 된 점
- **RTC·TFT·호흡·알람·NeoPixel·블루투스**가 한 루프에서 역할 분리되어 처리됨.
- **호흡 로직**: 1초 윈도우 펄스 수 → 0~100 전송, 디바운스(80ms), 원형 버퍼로 구현 적절.
- **알람**: RTC 연도 2자리/4자리 모두 고려, 1바퀴 울린 뒤에만 호흡으로 끄기 허용.
- **블루투스**: `\n` 기준 줄 단위 파싱으로 여러 명령 동시 수신 대응.
- **SET_ALARM 파싱**: 5값(연·월·일·시·분)이 모두 유효할 때만 적용·상태 초기화하도록 보강됨.

### 개선·참고 사항
1. **TFT 라이브러리**  
   MAR 2406은 2.4" ILI9341 8비트 병렬. **LCDWIKI_kbv** 설치 필요.  
   Mega 직접 꽂기 시 라이브러리 내 `mcu_8bit_*`(Mega 2560) 핀맵이 제품과 일치하는지 확인할 것.

2. **RTC 초기값**  
   `setup()`에서 RTC에 초기 시각을 넣지 않음.  
   첫 사용 전에 별도 스케치나 앱으로 RTC 설정이 필요함(문서화 권장).

3. **블루투스 수신 `delay(5)`**  
   바이트마다 `delay(5)` 사용으로 긴 패킷 시 루프 지연 가능.  
   트래픽이 많지 않으면 현실적으로 문제 적으나, 나중에 버퍼+타임아웃 방식으로 바꿀 여지 있음.

4. **NeoPixel 갱신**  
   `neoColorSet`일 때 매 루프마다 `pixels.show()` 호출.  
   색 변경은 수신 시에만 하면 되므로, 필요 시 “색이 바뀐 경우에만 show”로 줄이면 CPU 사용을 조금 줄일 수 있음(선택).

---

## 3. Flutter 앱 검토

### 3.1 `main.dart`
- Material 3, 테마·카드·버튼 스타일 일관됨.
- `HomeScreen` 단일 진입점으로 구조 단순.

### 3.2 `bluetooth_service.dart`
- **싱글톤**, `dataStream`(줄 단위), `connectionStatusStream`, `logStream` 구조 적절.
- Android 12+ 권한: `bluetooth`, `bluetoothScan`, `bluetoothConnect`, `location` 요청.
- 수신: `\n` 기준 버퍼 분리 후 `_dataStreamController.add(message)`.
- `sendAlarmDateTime`, `sendMelodyIndex`, `sendRGB` 프로토콜이 아두이노와 일치.
- **참고**: `sendSensitivity`는 구현되어 있으나, 현재 `test.ino`에서는 **SENSITIVITY** 명령을 처리하지 않음.  
  `dashboard_screen`에서만 사용 중이면, 아두이노에 감도 처리 추가 또는 앱에서 제거 중 택일 가능.

### 3.3 `home_screen.dart`
- **데이터 처리**
  - `Time: HH:MM:SS` → `_rtcTime`, `_rtcDateTime` 반영.
  - `ALARM_OFF` → 성공 다이얼로그만 표시(의도대로).
  - 숫자 한 줄 → 0~100 호흡값으로 파싱, 예외 처리 있음.
- **알람**: 날짜/시간 피커 → `_selectedAlarmDateTime` → `sendAlarmDateTime` + `sendMelodyIndex` 호출 순서·형식 적절.
- **기기 선택 다이얼로그**: `StatefulBuilder` + `dialogSetState`로 스캔 결과 갱신, `discoverySub` 취소·정리 처리됨.
- **dispose**: `_connectionSubscription`, `_dataSubscription` 취소로 누수 방지.
- **색상 피커**: `onColorChanged`에서 `setState`로 `_ledColor` 갱신 후, “설정” 시 `_sendLEDColor()` 호출 구조 적절.

### 3.4 `breathing_game_widget.dart`
- 호흡값 0~100(RPM 스타일)을 배 속도·크기·기울기로 반영.
- `_smoothedRate = _smoothedRate * 0.85 + widget.breathingValue * 0.15`로 급격한 하락 완화.
- `SailboatPainter`로 돛단배·파도 표현, `WavePainter`로 파 애니메이션.
- `Timer.periodic` 50ms, `AnimationController` repeat, `dispose`에서 정리됨.

---

## 4. 프로토콜·동작 일치 여부

| 항목 | 앱 | 아두이노 | 비고 |
|------|-----|----------|------|
| Time | 수신 파싱 | 1초마다 `Time: H:M:S` 전송 | 일치 |
| ALARM_OFF | 수신 시 성공 다이얼로그 | 호흡으로 끌 때만 전송 | 일치 |
| SET_ALARM | `YYYY:MM:DD:HH:MM` 전송 | 5값 검증 후 적용 | 일치 |
| MELODY | 0,1,2 전송 | 0,1,2 처리 | 일치 |
| RGB | r,g,b 전송 | NeoPixel 8개 동일 색 | 일치 |
| 호흡값 | 0~100 수신 → 미니게임 | 1초 윈도우 펄스→0~100 전송 | 일치 |
| SENSITIVITY | `dashboard_screen`에서 전송 | 미처리 | 선택 사항 |

---

## 5. 수정 반영 사항(이번 검토에서 적용)

- **SET_ALARM 파싱**: 5값이 모두 `>= 0`일 때만 `alarmYear~alarmMinute` 대입 및 알람 상태 초기화·로그·`noTone` 수행.  
  잘못된 패킷으로 기존 알람이 초기화되지 않도록 보강.

---

## 6. 권장 체크리스트(배포·테스트 전)

- [ ] Arduino: LCDWIKI_kbv 설치 후 TFT에 시간 정상 표시 확인.
- [ ] Arduino: RTC 초기 시각 설정 방법 문서화 또는 별도 설정 스케치 사용.
- [ ] 실제 기기에서 알람 시각 일치 시 부저 울림, 호흡으로 ALARM_OFF 수신 후 앱 다이얼로그 확인.
- [ ] IR 센서 배치·감도에 따라 호흡값 0~100이 미니게임과 체감에 맞는지 확인.
- [ ] (선택) SENSITIVITY: 아두이노에서 감도 파라미터 사용할 계획이 있으면 수신 처리 추가, 없으면 앱 전송 제거 또는 유지만 문서화.

---

## 7. 요약

- **Arduino**: RTC·TFT·호흡·알람·NeoPixel·블루투스 역할이 명확하고, SET_ALARM 파싱이 안전하게 보강된 상태.
- **Flutter**: 블루투스 서비스·스트림·권한·dispose 처리와 프로토콜 해석이 아두이노와 맞게 구현되어 있음.
- **호흡 미니게임**: RPM 값과 스무딩으로 배 속도가 자연스럽게 반영되도록 되어 있음.

TFT 라이브러리·핀맵과 RTC 초기 설정만 실제 하드웨어에서 확인하면, 전체 흐름은 일관되고 안정적으로 동작할 구조입니다.
