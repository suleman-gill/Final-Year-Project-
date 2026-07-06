import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../config/theme.dart';
import '../../widgets/common/app_header.dart';

class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});
  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  double _deviceHeading = 0.0;
  double _qiblaAngle = 0.0; // Angle relative to North
  double _distanceToKaaba = 0.0;
  String _locationName = "Loading position...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initQibla();
  }

  Future<void> _initQibla() async {
    bool hasPermission = false;
    
    try {
      if (kIsWeb) {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        hasPermission = (perm == LocationPermission.whileInUse || perm == LocationPermission.always);
      } else {
        final permission = await Permission.location.request();
        hasPermission = permission.isGranted;
      }
      
      if (hasPermission) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        );
        _calculateQibla(pos.latitude, pos.longitude);
      } else {
        _calculateQibla(25.2048, 55.2708);
      }
    } catch (e) {
      print('Qibla initialization error: $e');
      _calculateQibla(25.2048, 55.2708);
    }

    // Subscribe to device compass changes
    FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {
          _deviceHeading = event.heading ?? 0.0;
        });
      }
    });
  }

  void _calculateQibla(double lat, double lng) {
    // Kaaba coordinates
    const kaabaLat = 21.4225;
    const kaabaLng = 39.8262;

    final lat1 = lat * pi / 180;
    final lng1 = lng * pi / 180;
    final lat2 = kaabaLat * pi / 180;
    final lng2 = kaabaLng * pi / 180;

    final dLng = lng2 - lng1;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    
    final bearing = atan2(y, x) * 180 / pi;
    final qibla = (bearing + 360) % 360;

    final distance = Geolocator.distanceBetween(lat, lng, kaabaLat, kaabaLng) / 1000;

    if (mounted) {
      setState(() {
        _qiblaAngle = qibla;
        _distanceToKaaba = distance;
        _locationName = "Lat: ${lat.toStringAsFixed(2)}, Lng: ${lng.toStringAsFixed(2)}";
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Compass needle angle relative to the phone's top direction
    // Needle Angle = Qibla Direction - Device Heading
    final needleAngleRad = (_qiblaAngle - _deviceHeading) * pi / 180;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppHeader(
              bottomPadding: 28,
              child: Row(
                children: [
                  Text('Qibla Direction',
                      style: AppText.heading2(color: Colors.white)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: AppColors.gold, size: 14),
                        const SizedBox(width: 4),
                        Text(_isLoading ? 'Locating...' : 'Qibla: ${_qiblaAngle.toStringAsFixed(0)}°',
                            style: AppText.caption(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Animated compass ────────────────────────
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulse ring
                        Container(
                          width:  280 + _pulseCtrl.value * 10,
                          height: 280 + _pulseCtrl.value * 10,
                          decoration: BoxDecoration(
                            shape:  BoxShape.circle,
                            border: Border.all(
                              color: AppColors.gold.withOpacity(
                                  0.15 - _pulseCtrl.value * 0.1),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // Compass needle rotated to Qibla
                        Transform.rotate(
                          angle: needleAngleRad,
                          child: CustomPaint(
                            size:    const Size(260, 260),
                            painter: _CompassPainter(),
                          ),
                        ),
                        // Kaaba icon at centre
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color:     AppColors.surface,
                            shape:     BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Color(0x22000000), blurRadius: 10),
                            ],
                          ),
                          child: const Icon(Icons.nights_stay_rounded,
                              color: AppColors.gold, size: 28),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Info card ───────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color:        AppColors.surface,
                    borderRadius: BorderRadius.circular(Dims.radius),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      _InfoRow(
                        label: 'Qibla Bearing',
                        value: '${_qiblaAngle.toStringAsFixed(1)}°',
                        icon:  Icons.explore_rounded,
                      ),
                      const Divider(height: 20, color: Colors.white10),
                      _InfoRow(
                        label: 'Coordinates',
                        value: _locationName,
                        icon:  Icons.location_on_rounded,
                      ),
                      const Divider(height: 20, color: Colors.white10),
                      _InfoRow(
                        label: 'Distance to Kaaba',
                        value: '${_distanceToKaaba.toStringAsFixed(0)} km',
                        icon:  Icons.straighten_rounded,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Notice ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:        AppColors.emerald.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(Dims.radius),
                    border: Border.all(color: AppColors.emerald.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.emerald, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Hold your phone flat. Align the golden arrow to point straight up to target the Kaaba.",
                          style: AppText.body(color: Colors.white.withOpacity(0.85)),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        AppColors.gold.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.gold, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppText.body(color: Colors.white70))),
          Text(value, style: AppText.heading3(color: AppColors.gold)),
        ],
      );
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = AppColors.gold.withOpacity(0.05)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color       = AppColors.gold.withOpacity(0.15)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Cardinal direction labels
    const dirs = {'N': 0.0, 'E': 90.0, 'S': 180.0, 'W': 270.0};
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final entry in dirs.entries) {
      final angle = entry.value * pi / 180 - pi / 2;
      final x = center.dx + (radius - 20) * cos(angle);
      final y = center.dy + (radius - 20) * sin(angle);
      tp.text = TextSpan(
        text:  entry.key,
        style: TextStyle(
          fontSize:   12,
          fontWeight: FontWeight.bold,
          color: entry.key == 'N'
              ? const Color(0xFFEF4444)
              : AppColors.gold,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    // Tick marks
    final tickPaint = Paint()
      ..color       = AppColors.gold.withOpacity(0.2)
      ..strokeWidth = 1.2;
    for (int i = 0; i < 72; i++) {
      final angle = i * 5 * pi / 180;
      final len   = (i % 9 == 0) ? 14.0 : 7.0;
      final inner = radius - 30 - len;
      final outer = radius - 30;
      canvas.drawLine(
        Offset(center.dx + inner * cos(angle), center.dy + inner * sin(angle)),
        Offset(center.dx + outer * cos(angle), center.dy + outer * sin(angle)),
        tickPaint,
      );
    }

    // Gold Qibla pointer arrow
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy - radius + 35)
        ..lineTo(center.dx - 9, center.dy - 30)
        ..lineTo(center.dx + 9, center.dy - 30)
        ..close(),
      Paint()
        ..color = AppColors.gold
        ..style = PaintingStyle.fill,
    );

    // Muted grey tail
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy + radius - 35)
        ..lineTo(center.dx - 7, center.dy + 30)
        ..lineTo(center.dx + 7, center.dy + 30)
        ..close(),
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
