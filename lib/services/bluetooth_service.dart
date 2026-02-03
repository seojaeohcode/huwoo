import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothService {
  // Singleton instance
  static final BluetoothService _instance = BluetoothService._internal();

  factory BluetoothService() {
    return _instance;
  }

  BluetoothService._internal();

  BluetoothConnection? _connection;
  bool isConnected = false;
  
  // Stream for incoming data (Line based)
  final StreamController<String> _dataStreamController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;
  
  // Stream for connection status
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  // Stream for Debug Logs
  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  // Buffer for incoming data
  String _buffer = '';

  Future<void> init() async {
    await _requestPermissions();
    // 자동 연결하지 않음 - 사용자가 기기 목록에서 선택
  }

  /// 페어링된(등록된) 기기 목록 반환
  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      debugPrint("getBondedDevices error: $e");
      return [];
    }
  }

  /// 스캔 시작 - 발견되는 기기 스트림 반환 (기기 목록에서 선택용)
  Stream<BluetoothDiscoveryResult> startDiscoveryStream() {
    return FlutterBluetoothSerial.instance.startDiscovery();
  }

  /// 스캔 취소
  Future<void> cancelDiscovery() async {
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (e) {
      debugPrint("cancelDiscovery error: $e");
    }
  }

  Future<void> _requestPermissions() async {
    // Request multiple permissions required for Bluetooth scanning and connection
    // Especially for Android 12+ (API 31+)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Often required for scanning on older Android
    ].request();
    
    // Log statuses if needed
    debugPrint("Permissions status: $statuses");
  }

  /// 기기 목록에서 선택 후 연결 시 사용 (자동 연결 없음)
  Future<void> scanAndAutoConnect() async {
    if (isConnected) return;
    try {
      List<BluetoothDevice> bonded = await getBondedDevices();
      for (BluetoothDevice d in bonded) {
        if (d.name == 'HC-06' || d.name?.contains('HC-06') == true) {
          await connect(d);
          return;
        }
      }
      _logController.add("페어링된 HC-06이 없습니다. 기기 선택에서 시계를 골라주세요.");
    } catch (e) {
      _logController.add("연결 오류: $e");
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    if (isConnected) {
      debugPrint("Already connected to a device");
      return;
    }

    // Stop scanning before connecting
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (e) {
      debugPrint("Error canceling discovery: $e");
    }

    _logController.add("${device.name}에 연결 중...");
    debugPrint('Attempting to connect to ${device.name} (${device.address})');

    try {
      // Try to connect with timeout
      _connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 10));
      
      isConnected = true;
      _connectionStatusController.add(true);
      _logController.add("${device.name}에 연결되었습니다!");
      debugPrint('Successfully connected to ${device.name}');

      // RTC를 폰 시간으로 동기화 (여러 번 전송해 수신 확률 높임)
      for (int i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: 400 + i * 800), () {
          if (isConnected && _connection != null) {
            sendSetRTC(DateTime.now());
          }
        });
      }

      // Listen for incoming data
      _connection!.input!.listen(
        _onDataReceived,
        onDone: () {
          isConnected = false;
          _connectionStatusController.add(false);
          _logController.add("연결이 끊어졌습니다");
          debugPrint('Disconnected by remote request');
          _connection = null;
        },
        onError: (error) {
          debugPrint('Connection input error: $error');
          _logController.add("연결 오류: $error");
          isConnected = false;
          _connectionStatusController.add(false);
          _connection = null;
        },
      );
    } on TimeoutException {
      debugPrint('Connection timeout');
      _logController.add("연결 시간 초과. 다시 시도해주세요.");
      isConnected = false;
      _connectionStatusController.add(false);
      _connection = null;
    } catch (e) {
      debugPrint('Cannot connect, exception occurred: $e');
      _logController.add("연결 실패: $e");
      isConnected = false;
      _connectionStatusController.add(false);
      _connection = null;
    }
  }

  /// 연결 해제
  void disconnect() {
    if (_connection != null) {
      _connection?.dispose();
      _connection = null;
      isConnected = false;
      _connectionStatusController.add(false);
      _logController.add("연결 해제됨");
    }
  }

  void _onDataReceived(Uint8List data) {
    // Decode incoming bytes to string and append to buffer
    String chunk = utf8.decode(data);
    _buffer += chunk;

    // Check for newline characters to split messages
    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String message = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);
      
      if (message.isNotEmpty) {
        // print("Received: $message"); // Too noisy for console
        _dataStreamController.add(message);
        // _logController.add("RX: $message"); // Optional: log all RX? Might be too fast for UI.
      }
    }
  }
  
  void _sendData(String message) {
     if (!isConnected || _connection == null) {
      _logController.add("Error: Not connected");
      return;
    }
    
    try {
      _connection!.output.add(utf8.encode(message));
      _connection!.output.allSent.then((v) {
        _logController.add("TX: ${message.trim()}");
      });
    } catch (e) {
      _logController.add("Error sending: $e");
    }
  }

  /// RTC를 폰 현재 시간으로 동기화 (연결 직후 호출). 형식: SET_RTC:YYYY:MM:DD:HH:MM:SS:DOW
  void sendSetRTC(DateTime now) {
    int dow = now.weekday;
    String message = "SET_RTC:${now.year}:${now.month.toString().padLeft(2, '0')}:${now.day.toString().padLeft(2, '0')}:"
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}:$dow\n";
    _sendData(message);
  }

  /// 알람 시간만 전송 (기존 호환)
  void sendAlarmTime(int hour, int minute) {
    final now = DateTime.now();
    sendAlarmDateTime(now.year, now.month, now.day, hour, minute);
  }

  /// 알람 날짜+시간 전송 (YYYY:MM:DD:HH:MM)
  void sendAlarmDateTime(int year, int month, int day, int hour, int minute) {
    String message = "SET_ALARM:$year:${month.toString().padLeft(2, '0')}:${day.toString().padLeft(2, '0')}:${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}\n";
    _sendData(message);
  }

  /// 벨소리 종류 전송 (0=클래식, 1=아침멜로디, 2=디지털비프)
  void sendMelodyIndex(int index) {
    String message = "MELODY:$index\n";
    _sendData(message);
  }

  void sendRGB(int r, int g, int b) {
    String message = "RGB:$r,$g,$b\n";
    _sendData(message);
  }

  void dispose() {
    _connection?.dispose();
    _connection = null;
    _dataStreamController.close();
    _connectionStatusController.close();
    _logController.close();
  }
}
