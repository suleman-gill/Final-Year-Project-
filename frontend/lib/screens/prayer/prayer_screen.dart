import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../config/theme.dart';
import '../../services/prayer_service.dart';
import '../../widgets/common/app_header.dart';

class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});
  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  late final List<PrayerTime> _prayers;
  PrayerTime? _next;
  Duration _countdown = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _prayers = PrayerService.getTodayPrayers();
    _next    = PrayerService.getNextPrayer(_prayers);
    _updateCountdown();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCountdown(),
    );
    
    _requestNotificationPermission();
  }

  Future<void> _requestNotificationPermission() async {
    await Permission.notification.request();
  }

  void _updateCountdown() {
    if (_next != null && mounted) {
      setState(() => _countdown = _next!.timeUntil);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final h = _countdown.inHours;
    final m = _countdown.inMinutes % 60;
    final s = _countdown.inSeconds % 60;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: AppHeader(
              bottomPadding: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Prayer Times',
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
                            Text('Mecca, SA',
                                style: AppText.caption(color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_next != null) ...[
                    const SizedBox(height: 20),
                    // Countdown card
                    Container(
                      padding:     const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color:        Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.gold.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'NEXT PRAYER',
                            style: AppText.caption(color: AppColors.gold)
                                .copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _next!.name,
                            style: AppText.heading1(color: Colors.white)
                                .copyWith(fontSize: 28),
                          ),
                          Text(_next!.time,
                              style: TextStyle(color: Colors.white.withOpacity(0.7))),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _CountdownBox(_pad(h), 'HRS'),
                              const _CountdownSep(),
                              _CountdownBox(_pad(m), 'MIN'),
                              const _CountdownSep(),
                              _CountdownBox(_pad(s), 'SEC'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Prayer list ────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                ..._prayers.map((p) => _PrayerTile(prayer: p)),
                const SizedBox(height: 20),
                const _NotifSettings(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrayerTile extends StatefulWidget {
  final PrayerTime prayer;
  const _PrayerTile({required this.prayer});
  @override
  State<_PrayerTile> createState() => _PrayerTileState();
}

class _PrayerTileState extends State<_PrayerTile> {
  bool _notif = true;

  @override
  Widget build(BuildContext context) {
    final p = widget.prayer;
    return Container(
      margin:     const EdgeInsets.only(bottom: 12),
      padding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        p.isNext ? AppColors.gold.withOpacity(0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(Dims.radius),
        border: Border.all(
          color: p.isNext ? AppColors.gold : Colors.white.withOpacity(0.04),
          width: p.isNext ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: p.isPast ? p.color.withOpacity(0.3) : p.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),

          // Name + Arabic
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: AppText.heading3(
                    color: p.isPast
                        ? AppColors.textMuted
                        : Colors.white,
                  ),
                ),
                Text(
                  p.arabic,
                  style: TextStyle(
                    fontFamily: 'Scheherazade',
                    fontSize:   14,
                    color:      p.isPast ? AppColors.textMuted : AppColors.gold,
                  ),
                ),
              ],
            ),
          ),

          // Next badge
          if (p.isNext)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        AppColors.gold,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Next',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ),

          // Time
          Text(
            p.time,
            style: AppText.heading3(
              color: p.isPast
                  ? AppColors.textMuted
                  : Colors.white,
            ),
          ),
          const SizedBox(width: 12),

          // Notification toggle
          GestureDetector(
            onTap: () {
              setState(() => _notif = !_notif);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_notif ? "Reminders enabled for ${p.name}." : "Reminders muted for ${p.name}."),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Icon(
              _notif
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined,
              size:  20,
              color: _notif ? AppColors.gold : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifSettings extends StatelessWidget {
  const _NotifSettings();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(Dims.radius),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notification Settings', style: AppText.heading3(color: Colors.white)),
          const SizedBox(height: 12),
          const _NRow(
            icon:  Icons.notifications_active_rounded,
            label: 'Adhan Alert',
            sub:   'Full adhan audio',
            color: AppColors.emerald,
          ),
          const Divider(height: 1, color: Colors.white10),
          const _NRow(
            icon:  Icons.alarm_rounded,
            label: '15 Min Reminder',
            sub:   'Before prayer time',
            color: AppColors.gold,
          ),
          const Divider(height: 1, color: Colors.white10),
          const _NRow(
            icon:  Icons.vibration_rounded,
            label: 'Vibration',
            sub:   'Vibrate on adhan',
            color: Colors.purpleAccent,
          ),
        ],
      ),
    );
  }
}

class _NRow extends StatefulWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  const _NRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
  });
  @override
  State<_NRow> createState() => _NRowState();
}

class _NRowState extends State<_NRow> {
  bool _val = true;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        widget.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 18, color: widget.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(widget.sub, style: AppText.caption()),
              ],
            ),
          ),
          Switch.adaptive(
            value:       _val,
            activeColor: widget.color,
            onChanged:   (v) => setState(() => _val = v),
          ),
        ],
      ),
    );
  }
}

class _CountdownBox extends StatelessWidget {
  final String value, label;
  const _CountdownBox(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color:        Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize:    26,
                fontWeight:  FontWeight.w900,
                color:       Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize:      9,
              color:         Colors.white.withOpacity(0.5),
              letterSpacing: 1.5,
            ),
          ),
        ],
      );
}

class _CountdownSep extends StatelessWidget {
  const _CountdownSep();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 16, left: 8, right: 8),
        child: Text(
          ':',
          style: TextStyle(
            fontSize:   26,
            fontWeight: FontWeight.w900,
            color:      Colors.white,
          ),
        ),
      );
}
