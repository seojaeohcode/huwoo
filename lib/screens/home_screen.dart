import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:hoowoo/services/bluetooth_service.dart';
import 'package:hoowoo/widgets/breathing_game_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BluetoothService _bluetoothService = BluetoothService();
  
  // Breathing data for game
  double _currentBreathingValue = 0.0;
  
  // Connection state
  bool _isConnected = false;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;

  // Selected Alarm (날짜+시간)
  DateTime? _selectedAlarmDateTime;
  // 벨소리 종류: 0=클래식(기본), 1=아침멜로디, 2=디지털비프
  int _selectedMelodyIndex = 0;

  // RTC Time from Arduino
  String _rtcTime = "--:--:--";
  DateTime? _rtcDateTime;

  // LED Color
  Color _ledColor = Colors.blue;

  // Success State
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }
  
  Future<void> _initBluetooth() async {
    await _bluetoothService.init();
    
    // Listen to connection status
    _connectionSubscription = _bluetoothService.connectionStatusStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
          if (!isConnected) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("시계 연결이 끊어졌습니다.")),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("시계에 연결되었습니다.")),
              );
            }
          }
        });
      }
    });

    // Listen to data
    _dataSubscription = _bluetoothService.dataStream.listen((data) {
      _processData(data);
    });
  }

  void _processData(String data) {
    // Parse RTC time data from Arduino (format: "Time: HH:MM:SS")
    if (data.startsWith("Time: ")) {
      try {
        String timeStr = data.substring(6).trim(); // Remove "Time: " prefix
        List<String> parts = timeStr.split(":");
        
        if (parts.length >= 2) {
          int hour = int.parse(parts[0]);
          int minute = int.parse(parts[1]);
          int second = parts.length >= 3 ? int.parse(parts[2]) : 0;
          
          // Update RTC time
          if (mounted) {
            setState(() {
              _rtcTime = "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}";
              _rtcDateTime = DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
                hour,
                minute,
                second,
              );
            });
          }
        }
      } catch (e) {
        debugPrint("Error parsing RTC time: $data, error: $e");
      }
      return;
    }
    
    // 아두이노: 실제로 호흡으로 알람을 껐을 때만 "ALARM_OFF" 전송 → 그때만 성공 다이얼로그
    if (data.trim() == "ALARM_OFF") {
      if (mounted) {
        setState(() {
          _isSuccess = true;
          _showSuccessDialog();
        });
      }
      return;
    }

    // 아두이노: 1초당 펄스 수(RPM)를 0~100으로 보낸 값 → 미니게임 배 속도
    try {
      double value = double.parse(data.trim());
      if (value < 0 || value > 100) return;
      if (mounted) {
        setState(() {
          _currentBreathingValue = value;
        });
      }
    } catch (e) {
      debugPrint("Error parsing data: $data");
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "성공!",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "알람 끄기 성공!\n상쾌한 아침입니다.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _isSuccess = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "확인",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 알람 날짜+시간 선택 (날짜 먼저, 그다음 시간)
  Future<void> _pickAlarmDateTime() async {
    final now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedAlarmDateTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _selectedAlarmDateTime != null
          ? TimeOfDay(hour: _selectedAlarmDateTime!.hour, minute: _selectedAlarmDateTime!.minute)
          : TimeOfDay.now(),
    );
    if (time != null && mounted) {
      setState(() {
        _selectedAlarmDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      });
    }
  }

  void _sendAlarm() {
    if (_selectedAlarmDateTime != null) {
      final d = _selectedAlarmDateTime!;
      _bluetoothService.sendMelodyIndex(_selectedMelodyIndex);
      _bluetoothService.sendAlarmDateTime(d.year, d.month, d.day, d.hour, d.minute);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "알람 설정: ${d.month}월 ${d.day}일 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} (벨소리 ${_getMelodyName(_selectedMelodyIndex)})",
            ),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("날짜와 시간을 선택해주세요.")),
      );
    }
  }

  String _getMelodyName(int index) {
    switch (index) {
      case 0: return "벨소리1";
      case 1: return "벨소리2";
      case 2: return "벨소리3";
      default: return "벨소리1";
    }
  }

  /// 블루투스 기기 목록 표시 후 선택 연결
  Future<void> _showDevicePicker(BuildContext context) async {
    List<BluetoothDevice> devices = await _bluetoothService.getBondedDevices();
    Set<String> addresses = {for (var d in devices) d.address};
    StreamSubscription? discoverySub;
    void Function(void Function())? dialogSetState;
    bool discoveryStarted = false;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            dialogSetState = setDialogState;
            if (!discoveryStarted) {
              discoveryStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                discoverySub = _bluetoothService.startDiscoveryStream().listen((result) {
                  if (!addresses.contains(result.device.address)) {
                    addresses.add(result.device.address);
                    devices.add(result.device);
                    dialogSetState?.call(() {});
                  }
                });
              });
            }
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.bluetooth),
                  const SizedBox(width: 8),
                  const Text("시계 선택"),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "연결할 기기를 탭하세요. (페어링된 기기 + 검색 중)",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: devices.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  "페어링된 기기가 없습니다.\n휴대폰 설정에서 블루투스로\n시계(HC-06)를 먼저 페어링해주세요.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: devices.length,
                              itemBuilder: (context, index) {
                                final d = devices[index];
                                return ListTile(
                                  leading: const Icon(Icons.watch),
                                  title: Text(d.name ?? "(이름 없음)"),
                                  subtitle: Text(d.address),
                                  onTap: () async {
                                    Navigator.of(ctx).pop();
                                    discoverySub?.cancel();
                                    await _bluetoothService.cancelDiscovery();
                                    await _bluetoothService.connect(d);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    discoverySub?.cancel();
                    _bluetoothService.cancelDiscovery();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text("취소"),
                ),
              ],
            );
          },
        );
      },
    );

    discoverySub?.cancel();
    await _bluetoothService.cancelDiscovery();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.3),
              colorScheme.secondaryContainer.withValues(alpha: 0.2),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Hoowoo",
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "호흡 기반 알람 시스템",
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: _isConnected 
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isConnected 
                            ? Icons.bluetooth_connected 
                            : Icons.bluetooth_disabled,
                          color: _isConnected ? Colors.green : Colors.grey,
                        ),
                        onPressed: () {
                          if (!_isConnected) {
                            _showDevicePicker(context);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // Status Card
                      _buildStatusCard(context, colorScheme),
                      const SizedBox(height: 24),
                      
                      // Chart Card
                      _buildChartCard(context, colorScheme),
                      const SizedBox(height: 24),
                      
                      // Alarm Card
                      _buildAlarmCard(context, colorScheme),
                      const SizedBox(height: 24),
                      
                      // LED Color Card
                      _buildLEDColorCard(context, colorScheme),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _isConnected 
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isConnected ? Icons.check_circle : Icons.sync,
                  color: _isConnected ? Colors.green : Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isConnected ? "연결됨" : "연결 끊김",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isConnected ? "시계 연결됨" : "시계를 선택해주세요",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isConnected)
                FilledButton.icon(
                  onPressed: () => _showDevicePicker(context),
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text("기기 선택"),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                )
              else
                TextButton(
                  onPressed: () async {
                    _bluetoothService.disconnect();
                  },
                  child: const Text("연결 해제"),
                ),
            ],
          ),
          // RTC Time Display + 수동 동기화
          if (_isConnected) ...[
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "RTC 현재 시간",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _rtcTime,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                          fontFeatures: [
                            const FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _bluetoothService.sendSetRTC(DateTime.now());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("RTC 동기화 전송함 (시리얼에서 [RTC] 동기화됨 확인)")),
                    );
                  },
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text("RTC 동기화"),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.sailing,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "호흡 미니게임",
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "1초당 감지 횟수(RPM)에 따라 배 속도 변함",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          BreathingGameWidget(
            breathingValue: _currentBreathingValue,
            isConnected: _isConnected,
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.alarm,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "알람 설정",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "설정된 알람 (연·월·일·시·분)",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickAlarmDateTime,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    _selectedAlarmDateTime != null
                        ? "${_selectedAlarmDateTime!.year}년 ${_selectedAlarmDateTime!.month}월 ${_selectedAlarmDateTime!.day}일"
                        : "날짜 선택 (탭)",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _selectedAlarmDateTime != null
                            ? "${_selectedAlarmDateTime!.hour.toString().padLeft(2, '0')}:${_selectedAlarmDateTime!.minute.toString().padLeft(2, '0')}"
                            : "--:--",
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "바람을 불면 알람이 꺼져요",
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "벨소리",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [0, 1, 2].map((index) {
              final isSelected = _selectedMelodyIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    "벨소리${index + 1}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15,
                      shadows: [
                        Shadow(color: Colors.black.withValues(alpha: 0.6), offset: const Offset(0, 1), blurRadius: 1),
                        Shadow(color: Colors.black.withValues(alpha: 0.4), offset: const Offset(0, 0), blurRadius: 2),
                      ],
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (v) {
                    setState(() {
                      _selectedMelodyIndex = index;
                    });
                  },
                  backgroundColor: const Color(0xFF1a237e),
                  selectedColor: const Color(0xFF283593),
                  checkmarkColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _isConnected && _selectedAlarmDateTime != null
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.white.withValues(alpha: 0.95),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _sendAlarm,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.send_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "알람 시간 전송",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "알람 시간 전송",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLEDColorCard(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.lightbulb,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "LED 색상 설정",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _isConnected ? () => _showColorPicker(context, colorScheme) : null,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: _ledColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _ledColor.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.palette_rounded,
                      color: _ledColor.computeLuminance() > 0.5 
                        ? Colors.black 
                        : Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isConnected ? "탭하여 색상 변경" : "연결 필요",
                      style: TextStyle(
                        color: _ledColor.computeLuminance() > 0.5 
                          ? Colors.black 
                          : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("LED 색상 선택"),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _ledColor,
            onColorChanged: (color) {
              setState(() {
                _ledColor = color;
              });
            },
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              "취소",
              style: TextStyle(color: Colors.grey[600]),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextButton(
              child: const Text(
                "설정",
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () {
                _sendLEDColor();
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("LED 색상이 전송되었습니다"),
                    backgroundColor: _ledColor,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _sendLEDColor() {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("블루투스가 연결되지 않았습니다.")),
      );
      return;
    }

    final r = (_ledColor.r * 255.0).round().clamp(0, 255);
    final g = (_ledColor.g * 255.0).round().clamp(0, 255);
    final b = (_ledColor.b * 255.0).round().clamp(0, 255);
    
    _bluetoothService.sendRGB(r, g, b);
  }
}
