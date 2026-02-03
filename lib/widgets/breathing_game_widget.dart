import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 호흡 빈도(RPM): 아두이노에서 1초당 펄스 수를 0~100으로 보낸 값.
/// 값이 클수록 1초에 더 자주 감지됨 → 배 속도·바람 세기 반영.
class BreathingGameWidget extends StatefulWidget {
  final double breathingValue; // 0-100 (RPM 스타일: 1초당 감지 횟수에 비례)
  final bool isConnected;

  const BreathingGameWidget({
    super.key,
    required this.breathingValue,
    required this.isConnected,
  });

  @override
  State<BreathingGameWidget> createState() => _BreathingGameWidgetState();
}

class _BreathingGameWidgetState extends State<BreathingGameWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _boatAnimation;
  late Animation<double> _waveAnimation;
  
  double _boatPosition = 0.0;
  double _lastBreathingValue = 0.0;
  double _smoothedRate = 0.0;  // RPM 값이 갑자기 떨어질 때 배 속도 부드럽게 감쇠
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    
    // Wave animation (continuous)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _waveAnimation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.linear,
      ),
    );

    // Update boat position based on breathing value
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted && widget.isConnected) {
        _updateBoatPosition();
      }
    });
  }

  void _updateBoatPosition() {
    if (!mounted) return;
    // RPM 값은 1초 단위로 바뀌므로, 급격히 떨어질 때 부드럽게 감쇠
    _smoothedRate = _smoothedRate * 0.85 + widget.breathingValue * 0.15;
    double speed = (_smoothedRate / 100.0) * 2.0; // 빈도 높을수록 배 빠름
    
    setState(() {
      _boatPosition += speed;
      _lastBreathingValue = widget.breathingValue;
      if (_boatPosition > 100) _boatPosition = 0.0;
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gameWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _waveAnimation,
          builder: (context, child) {
            return Container(
              height: 250,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF87CEEB), // Sky blue
                    const Color(0xFF4682B4), // Steel blue
                    const Color(0xFF1E90FF), // Dodger blue
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Animated waves
                    _buildWaves(),
                    // Boat (호흡 값에 따라 속도·크기 반영)
                    if (widget.isConnected && widget.breathingValue > 0)
                      _buildBoat(gameWidth)
                    else
                      _buildWaitingState(),
                    // Breathing value indicator
                    _buildBreathingIndicator(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWaves() {
    return CustomPaint(
      size: Size.infinite,
      painter: WavePainter(_waveAnimation.value),
    );
  }

  Widget _buildBoat(double gameWidth) {
    double leftPosition = _boatPosition.clamp(0.0, 100.0);
    double rate = _smoothedRate.clamp(0.0, 100.0);
    double boatWidth = 52 + (rate / 100.0 * 16);
    double boatHeight = 48 + (rate / 100.0 * 14);
    double boatTilt = (rate - 50) / 50.0 * 0.15;

    return Positioned(
      left: leftPosition * 0.01 * (gameWidth - boatWidth).clamp(0.0, double.infinity),
      top: 178 - boatHeight,
      child: Transform.rotate(
        angle: boatTilt,
        child: CustomPaint(
          size: Size(boatWidth, boatHeight),
          painter: SailboatPainter(),
        ),
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sailing,
            size: 64,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            "호흡 데이터 대기 중...",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "1초당 감지 횟수(RPM)에 따라 배 속도가 달라져요",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreathingIndicator() {
    // 0~100 = RPM 스타일 (10 pulse/s → 100). 대략 "회/초"는 value/10
    int approxPerSec = (widget.breathingValue / 10).round().clamp(0, 10);
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              size: 18,
              color: _getBreathingColor(),
            ),
            const SizedBox(width: 6),
            Text(
              "빈도 ${widget.breathingValue.toInt()} (~${approxPerSec}회/초)",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _getBreathingColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBreathingColor() {
    if (widget.breathingValue < 30) {
      return Colors.blue;
    } else if (widget.breathingValue < 70) {
      return Colors.green;
    } else {
      return Colors.orange;
    }
  }
}

// Custom painter for animated waves
class WavePainter extends CustomPainter {
  final double animationValue;

  WavePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // Draw multiple waves
    for (int i = 0; i < 3; i++) {
      final waveHeight = 15.0 + i * 5.0;
      final waveOffset = animationValue + i * 0.5;
      
      path.reset();
      path.moveTo(0, size.height * 0.7 + waveHeight);
      
      for (double x = 0; x < size.width; x += 1) {
        final y = size.height * 0.7 +
            math.sin((x / size.width * 4 * math.pi) + waveOffset) * waveHeight;
        path.lineTo(x, y);
      }
      
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

/// 돛단배: 선체(둥근 배 밑) + 돛대 + 삼각형 돛
class SailboatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 그림자
    final shadowPath = Path()
      ..moveTo(w * 0.08, h * 0.82)
      ..quadraticBezierTo(w * 0.2, h * 0.95, w * 0.5, h * 0.88)
      ..quadraticBezierTo(w * 0.8, h * 0.95, w * 0.92, h * 0.82)
      ..lineTo(w * 0.88, h)
      ..quadraticBezierTo(w * 0.5, h * 0.92, w * 0.12, h)
      ..close();
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );

    // 선체 (배 밑동 - 둥근 보트 형태)
    final hullPath = Path()
      ..moveTo(w * 0.1, h * 0.78)
      ..quadraticBezierTo(w * 0.22, h * 0.88, w * 0.5, h * 0.84)
      ..quadraticBezierTo(w * 0.78, h * 0.88, w * 0.9, h * 0.78)
      ..lineTo(w * 0.86, h * 0.98)
      ..quadraticBezierTo(w * 0.5, h * 0.94, w * 0.14, h * 0.98)
      ..close();
    canvas.drawPath(
      hullPath,
      Paint()
        ..color = const Color(0xFF5D4037)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      hullPath,
      Paint()
        ..color = const Color(0xFF3E2723)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 돛대
    final mastTop = h * 0.12;
    final mastBottom = h * 0.82;
    canvas.drawLine(
      Offset(w * 0.5, mastBottom),
      Offset(w * 0.5, mastTop),
      Paint()
        ..color = const Color(0xFF4E342E)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 삼각형 돛 (흰색)
    final sailPath = Path()
      ..moveTo(w * 0.5, mastTop + 2)
      ..lineTo(w * 0.5, mastBottom - 4)
      ..lineTo(w * 0.88, h * 0.5)
      ..close();
    canvas.drawPath(
      sailPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      sailPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 깃발(작은 삼각형) - 돛대 꼭대기
    final flagPath = Path()
      ..moveTo(w * 0.5, mastTop)
      ..lineTo(w * 0.5, mastTop + h * 0.12)
      ..lineTo(w * 0.72, mastTop + h * 0.06)
      ..close();
    canvas.drawPath(
      flagPath,
      Paint()
        ..color = const Color(0xFFE53935)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
