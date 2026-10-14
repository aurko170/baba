import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tzloc;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const HobuBabaApp());
}

class HobuBabaApp extends StatelessWidget {
  const HobuBabaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'হবু বাবা',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF059669),
          primary: const Color(0xFF059669),
          secondary: const Color(0xFF0D9488),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        textTheme: GoogleFonts.hindSiliguriTextTheme(
          Theme.of(context).textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          iconTheme: IconThemeData(color: Color(0xFF0F172A)),
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const AppEntryScreen(),
    );
  }
}


// Onboarding stores dates on-device. EDD assumes 40 weeks (280 days).
class AppEntryScreen extends StatefulWidget {
  const AppEntryScreen({super.key});
  @override State<AppEntryScreen> createState() => _AppEntryScreenState();
}
class _AppEntryScreenState extends State<AppEntryScreen> {
  bool loading = true;
  String? mode;
  DateTime? date;
  @override void initState() {super.initState(); _load();}
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('baby_date');
    if (!mounted) return;
    setState(() {mode = prefs.getString('baby_mode'); date = value == null ? null : DateTime.tryParse(value); loading = false;});
    if (mode != null && date != null) {
      unawaited(BabyNotificationService.instance.reschedule().catchError((Object error) {
        debugPrint('Notification scheduling failed: $error');
      }));
    }
  }
  Future<void> _setDate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(context: context, initialDate: date ?? (mode == 'born' ? now : now.add(const Duration(days: 90))), firstDate: DateTime(2020), lastDate: now.add(const Duration(days: 320)));
    if (picked != null) setState(() => date = picked);
  }
  Future<void> _save() async {
    if (date == null || mode == null) return;
    final prefs = await SharedPreferences.getInstance();
    final modeSaved = await prefs.setString('baby_mode', mode!);
    final dateSaved = await prefs.setString('baby_date', date!.toIso8601String());
    if (!modeSaved || !dateSaved) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('তারিখ সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।')));
      return;
    }
    // Navigate immediately; notification permissions and scheduling must not block saving EDD.
    if (mounted) setState(() {});
    unawaited(BabyNotificationService.instance.reschedule().catchError((Object error) {
      debugPrint('Notification scheduling failed: $error');
    }));
  }
  @override Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (date != null && mode != null) return const MainNavigationScreen();
    return Scaffold(appBar: AppBar(title: const Text('হবু বাবা — শুরু করি')), body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Image.asset('assets/branding/logo.png', height: 160),
      const SizedBox(height: 24),
      const Text('স্বাগতম! আপনার সন্তানের তথ্য দিন', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      RadioListTile<String>(title: const Text('বাবু এখনো গর্ভে আছে'), value: 'pregnancy', groupValue: mode, onChanged: (v) => setState(() {mode = v;date = null;})),
      RadioListTile<String>(title: const Text('বাবু জন্মগ্রহণ করেছে'), value: 'born', groupValue: mode, onChanged: (v) => setState(() {mode = v;date = null;})),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: mode == null ? null : _setDate, icon: const Icon(Icons.calendar_today), label: Text(date == null ? (mode == 'born' ? 'জন্মতারিখ (DOB) নির্বাচন করুন' : 'সম্ভাব্য প্রসবের তারিখ (EDD) দিন') : '${date!.day}/${date!.month}/${date!.year}')),
      const SizedBox(height: 16),
      FilledButton(onPressed: date == null ? null : _save, child: const Text('অ্যাপ শুরু করুন')),
      const SizedBox(height: 12),
      const Text('আপনার দেওয়া তারিখ ফোনে সংরক্ষিত থাকবে; Settings থেকে পরিবর্তন করা যাবে।', textAlign: TextAlign.center),
    ]))));
  }
}

class BabyNotificationService {
  BabyNotificationService._();
  static final instance = BabyNotificationService._();
  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;

  Future<void> initialize() async {
    if (initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android));
    initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    return await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission() ?? true;
  }

  Future<void> testNotification() async {
    await initialize();
    final allowed = await requestPermission();
    if (!allowed) throw StateError('Notification permission denied');
    await plugin.show(
      987654,
      'হবু বাবা — টেস্ট নোটিফিকেশন',
      'নোটিফিকেশন চালু আছে। প্রতি ঘণ্টায় নতুন পরামর্শ আসবে।',
      const NotificationDetails(android: AndroidNotificationDetails(
        'parenting_tips_hourly_v2', 'Hourly parenting tips',
        channelDescription: 'Baby, mother and father care reminders',
        importance: Importance.high, priority: Priority.high,
      )),
    );
  }

  Future<void> reschedule() async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await plugin.cancelAll();
    if (!(prefs.getBool('notifications_enabled') ?? true)) return;
    if (!await requestPermission()) return;
    final mode = prefs.getString('baby_mode') ?? 'pregnancy';
    final date = DateTime.tryParse(prefs.getString('baby_date') ?? '');
    if (date == null) return;

    final content = jsonDecode(
      await rootBundle.loadString('assets/data/rotating_tips.json'),
    ) as List<dynamic>;
    final allTips = <Map<String, dynamic>>[];
    for (final item in content) {
      final m = Map<String, dynamic>.from(item as Map);
      if (m['mode'] == 'both' || m['mode'] == mode) allTips.add(m);
    }
    if (allTips.isEmpty) return;

    final now = DateTime.now();
    final everyHour = prefs.getBool('notifications_hourly') ?? true;
    // 14 days x 24 = 336 notifications. Android plugin enforces limits
    // on some devices; refresh these slots every time the app is opened.
    final hours = everyHour ? List<int>.generate(24, (i) => i)
        : <int>[9, 14, 20];
    var notificationId = 1000;
    var tipIndex = prefs.getInt('notification_rotation_index') ?? 0;
    final today = DateUtils.dateOnly(now);
    for (var day = 0; day < 14; day++) {
      final dayDate = today.add(Duration(days: day));
      final ageDays = dayDate.difference(DateUtils.dateOnly(date)).inDays;
      final gestDays = 280 - DateUtils.dateOnly(date).difference(dayDate).inDays;
      if (mode == 'born' && ageDays < 0) continue;
      if (mode == 'pregnancy' && (gestDays < 0 || gestDays > 294)) continue;
      for (final hour in hours) {
        final target = DateTime(dayDate.year, dayDate.month, dayDate.day, hour);
        if (!target.isAfter(now.add(const Duration(minutes: 1)))) continue;
        final tip = allTips[tipIndex % allTips.length];
        tipIndex++;
        final age = mode == 'born'
            ? '$ageDays দিন'
            : '${gestDays ~/ 7} সপ্তাহ ${gestDays % 7} দিন';
        final body = (tip['message'] as String)
            .replaceAll('{age}', age).replaceAll('\${age}', age);
        await plugin.zonedSchedule(
          notificationId++, tip['title'] as String, body,
          tzloc.TZDateTime.from(target.toUtc(), tzloc.UTC),
          const NotificationDetails(android: AndroidNotificationDetails(
            'parenting_tips_hourly_v2', 'Hourly parenting tips',
            channelDescription: 'Baby, mother and father care reminders',
            importance: Importance.high, priority: Priority.high,
          )),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
    // On the next open, start content rotation from a fresh place.
    await prefs.setInt('notification_rotation_index', tipIndex % allTips.length);
  }
}

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});
  @override State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}
class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  String mode = 'pregnancy';
  DateTime? date;
  bool enabled = true;
  bool hourly = true;
  bool saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      mode = p.getString('baby_mode') ?? 'pregnancy';
      date = DateTime.tryParse(p.getString('baby_date') ?? '');
      enabled = p.getBool('notifications_enabled') ?? true;
      hourly = p.getBool('notifications_hourly') ?? true;
    });
  }

  Future<void> _datePick() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: date ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 320)),
    );
    if (value != null) setState(() => date = value);
  }

  Future<void> _save() async {
    if (date == null || saving) return;
    setState(() => saving = true);
    final p = await SharedPreferences.getInstance();
    await p.setString('baby_mode', mode);
    await p.setString('baby_date', date!.toIso8601String());
    await p.setBool('notifications_enabled', enabled);
    await p.setBool('notifications_hourly', hourly);
    if (!mounted) return;
    // Do not block saving the profile while Android schedules notifications.
    Navigator.pop(context, true);
    unawaited(BabyNotificationService.instance.reschedule().catchError((Object error) {
      debugPrint('Notification scheduling failed: $error');
    }));
  }

  Future<void> _test() async {
    try {
      await BabyNotificationService.instance.testNotification();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('টেস্ট নোটিফিকেশন পাঠানো হয়েছে।')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('নোটিফিকেশন চালু হয়নি: $error'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('প্রোফাইল ও নোটিফিকেশন')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(
        initialValue: mode,
        decoration: const InputDecoration(labelText: 'মোড'),
        items: const [
          DropdownMenuItem(value: 'pregnancy', child: Text('গর্ভাবস্থা')),
          DropdownMenuItem(value: 'born', child: Text('বাবু জন্মেছে')),
        ],
        onChanged: (v) => setState(() => mode = v ?? mode),
      ),
      ListTile(
        title: Text(date == null ? 'তারিখ দিন' : '${date!.day}/${date!.month}/${date!.year}'),
        subtitle: Text(mode == 'born' ? 'জন্মতারিখ (DOB)' : 'সম্ভাব্য প্রসবের তারিখ (EDD)'),
        trailing: const Icon(Icons.edit_calendar),
        onTap: _datePick,
      ),
      SwitchListTile(
        title: const Text('Notification চালু'), value: enabled,
        onChanged: (v) => setState(() => enabled = v),
      ),
      SwitchListTile(
        title: const Text('প্রতি ঘণ্টায় Notification'),
        subtitle: const Text('দিন-রাত প্রতি ঘণ্টায়; বন্ধ করলে দিনে ৩ বার'),
        value: hourly,
        onChanged: (v) => setState(() => hourly = v),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: saving ? null : _save,
        child: Text(saving ? 'সংরক্ষণ হচ্ছে...' : 'পরিবর্তন সংরক্ষণ'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _test,
        icon: const Icon(Icons.notifications_active),
        label: const Text('এখনই Test Notification পাঠাও'),
      ),
      const SizedBox(height: 12),
      const Text('Android Settings থেকে Notifications Allow করতে হবে। '
          'Battery restrictions থাকলে সময় দেরি হতে পারে। '
          'আগামী ১৪ দিনের notification schedule হয়; '
          'অ্যাপ খুললে পরবর্তী ১৪ দিন আবার schedule হবে।'),
    ]),
  );
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  int _currentWeek = 20;

  @override
  void initState() {
    super.initState();
    _loadSavedWeek();
  }

  Future<void> _loadSavedWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final date = DateTime.tryParse(prefs.getString('baby_date') ?? '');
    if (!mounted) return;
    setState(() {
      _currentWeek = date != null && prefs.getString('baby_mode') == 'pregnancy'
          ? ((280 - DateUtils.dateOnly(date).difference(DateUtils.dateOnly(DateTime.now())).inDays) ~/ 7).clamp(1, 40).toInt()
          : (prefs.getInt('current_week') ?? 20);
    });
  }

  Future<void> _saveWeek(int week) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('current_week', week);
    setState(() {
      _currentWeek = week;
    });
  }

  void _navigateToChatWithWeek(int week) {
    _saveWeek(week);
    setState(() {
      _currentIndex = 1; // Chat Tab
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      WeekTrackerScreen(
        currentWeek: _currentWeek,
        onWeekChanged: _saveWeek,
        onAskAI: _navigateToChatWithWeek,
      ),
      AIChatScreen(currentWeek: _currentWeek),
      const HospitalBagScreen(),
      const BudgetCalculatorScreen(),
      const EmergencyScreen(),
      const DailyMotivationScreen(),
      const NearbyHospitalsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(toolbarHeight: 52, title: const Text('হবু বাবা'), actions: [IconButton(tooltip:'প্রোফাইল ও সেটিংস', icon: const Icon(Icons.settings_outlined), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen())); _loadSavedWeek(); })]),
      body: screens[_currentIndex],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          height: 74,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _navButton(0, Icons.calendar_month, 'ট্র্যাকার'),
                _navButton(1, Icons.chat_bubble, 'এআই গাইড'),
                _navButton(2, Icons.shopping_bag, 'ব্যাগ'),
                _navButton(3, Icons.account_balance_wallet, 'বাজেট'),
                _navButton(4, Icons.warning_amber_rounded, 'জরুরি'),
                _navButton(5, Icons.favorite, 'অনুপ্রেরণা'),
                _navButton(6, Icons.local_hospital, 'হাসপাতাল'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton(int index, IconData icon, String label) {
    final active = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        constraints: const BoxConstraints(minWidth: 86),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFD1FAE5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 23, color: active ? const Color(0xFF059669) : const Color(0xFF64748B)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: active ? const Color(0xFF047857) : const Color(0xFF64748B))),
        ]),
      ),
    );
  }

}

// ==========================================
// 1. WEEK TRACKER SCREEN
// ==========================================
class WeekTrackerScreen extends StatefulWidget {
  final int currentWeek;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<int> onAskAI;

  const WeekTrackerScreen({
    super.key,
    required this.currentWeek,
    required this.onWeekChanged,
    required this.onAskAI,
  });

  @override
  State<WeekTrackerScreen> createState() => _WeekTrackerScreenState();
}

class _WeekTrackerScreenState extends State<WeekTrackerScreen> {
  Map<String, bool> _completedTasks = {};

  final List<Map<String, dynamic>> _weeksData = [
    {
      'week': 4,
      'trimester': 1,
      'fruit': 'পোস্তদানা',
      'length': '১ মিমি',
      'weight': '< ১ গ্রাম',
      'development': 'নিষিক্ত ডিম্বাণু জরায়ুতে প্রতিস্থাপিত হয়েছে। প্লাসেন্টা গঠন শুরু।',
      'symptoms': 'পিরিয়ড মিস হওয়া, মৃদু ক্লান্তি ও মেজাজ পরিবর্তন।',
      'nutrition': 'ফলিক অ্যাসিড ও প্রচুর পানি নিশ্চিত করুন।',
      'dadTasks': [
        'টেস্ট পজিটিভ হলে স্ত্রীকে জড়িয়ে ধরে মানসিক ভরসা দিন।',
        'প্রথম গাইনী ডাক্তারের অ্যাপয়েন্টমেন্ট বুক করুন।',
        'ফলিক অ্যাসিড সাপ্লিমেন্ট নিয়মিত খাওয়া নিশ্চিত করুন।'
      ]
    },
    {
      'week': 8,
      'trimester': 1,
      'fruit': 'শিমের বিচি',
      'length': '১.৬ সেমি',
      'weight': '১ গ্রাম',
      'development': 'হাতের আঙুল, চোখের পাতা ও প্রধান অঙ্গ গঠিত হচ্ছে।',
      'symptoms': 'মর্নিং সিকনেস, খাবারের গন্ধে বমি ভাব, কোষ্ঠকাঠিন্য।',
      'nutrition': 'ভিটামিন বি৬ সমৃদ্ধ খাবার (কলা, বাদাম) দিন।',
      'dadTasks': [
        'সকালে ঘুম ভাঙার সাথে সাথে লেবু জল বা ড্রাই টোস্ট দিন।',
        'রান্নার কড়া গন্ধ থেকে স্ত্রীকে দূরে রাখুন।',
        'ঘরের ভারী কাজের দায়িত্ব নিজে গ্রহণ করুন।'
      ]
    },
    {
      'week': 12,
      'trimester': 1,
      'fruit': 'লেবু',
      'length': '৫.৪ সেমি',
      'weight': '১৪ গ্রাম',
      'development': 'শিশুর প্রতিবর্ত ক্রিয়া শুরু হয়েছে। প্রথম ট্রাইমেস্টার সমাপ্তির পথে।',
      'symptoms': 'বমি ভাব কিছুটা হ্রাস, পেটে গ্যাস বা মাথাব্যথা।',
      'nutrition': 'আঁশযুক্ত খাবার ও শাকসবজি বাড়িয়ে দিন।',
      'dadTasks': [
        '১ম ট্রাইমেস্টার সফলভাবে পার হওয়ায় স্ত্রীকে প্রশংসা করুন।',
        'ডেলিভারি ফান্ডের জন্য আলাদা সঞ্চয় হিসাব শুরু করুন।',
        'ফার্স্ট ট্রাইমেস্টার স্ক্রীনিং ও আল্ট্রাসাউন্ড টেস্ট করান।'
      ]
    },
    {
      'week': 16,
      'trimester': 2,
      'fruit': 'ডালিম / অ্যাভোকাডো',
      'length': '১১.৬ সেমি',
      'weight': '১০০ গ্রাম',
      'development': 'চোখ আলোর প্রতি সংবেদনশীল, ত্বক মসৃণ হচ্ছে।',
      'symptoms': 'এনার্জি ফিরে আসা, ত্বক উজ্জ্বল হওয়া, পিঠে মৃদু টান।',
      'nutrition': 'ক্যালসিয়াম ও আয়রন দ্বিগুণ করুন (দুধ, ডিম, তিল)।',
      'dadTasks': [
        'একটি আরামদায়ক প্রেগন্যান্সি পিলো (Pillow) উপহার দিন।',
        'বিকেলে স্ত্রীকে নিয়ে উন্মুক্ত নির্মল বাতাসে হাঁটুন।',
        'ভালো ভালো বই বা অনুপ্রেরণামূলক গল্প পড়ে শোনান।'
      ]
    },
    {
      'week': 20,
      'trimester': 2,
      'fruit': 'কলা',
      'length': '২৫ সেমি',
      'weight': '৩০০ গ্রাম',
      'development': 'অর্ধেক পথ শেষ! শিশু শব্দ শুনতে পায় ও নড়াচড়া করে।',
      'symptoms': 'বাচ্চার প্রথম নড়াচড়া অনুভব, পেটের ত্বকে চুলকানি।',
      'nutrition': 'ওমেগা-৩ ও বাদাম জাতীয় পুষ্টিকর খাবার খাওয়ান।',
      'dadTasks': [
        'স্ত্রীর পেটে হাত রেখে বাচ্চার নড়াচড়া অনুভব করুন।',
        'পেটে আলতো করে ময়েশ্চারাইজার বা নারিকেল তেল মালিশ করুন।',
        'অ্যানোমালি স্ক্যানে অবশ্যই নিজে উপস্থিত থাকুন।'
      ]
    },
    {
      'week': 28,
      'trimester': 3,
      'fruit': 'লাল বাঁধাকপি',
      'length': '৩৭ সেমি',
      'weight': '১ কেজি',
      'development': 'শেষ ট্রাইমেস্টারে প্রবেশ! শিশুর চোখের পলক পড়ে।',
      'symptoms': 'দ্রুত হাঁপিয়ে ওঠা, ঘুমের অসুবিধা, পেটের ভারী ভাব।',
      'nutrition': 'রক্তস্বল্পতা এড়াতে আয়রন ও ডালিম নিশ্চিত করুন।',
      'dadTasks': [
        'বাচ্চার নড়াচড়ার হিসাব (Kick Count) রাখতে স্ত্রীকে সাহায্য করুন।',
        'সিজারিয়ান বনাম নরমাল ডেলিভারির আর্থিক ফান্ড নিশ্চিত করুন।',
        'রক্তক্ষরণ বা পানি ভাঙার মতো লক্ষণ দেখা দিলে সতর্ক থাকুন।'
      ]
    },
    {
      'week': 36,
      'trimester': 3,
      'fruit': 'বড় পেঁপে / তরমুজ',
      'length': '৪৭ সেমি',
      'weight': '২.৬ কেজি',
      'development': 'মাথা নিচের দিকে নামছে। প্রসবের জন্য প্রস্তুত।',
      'symptoms': 'ফলস পেইন (Braxton Hicks), ঘুমের সমস্যা, প্রসবভীতি।',
      'nutrition': 'সহজে হজম হয় এমন তরল স্যুপ ও পুষ্টিকর খাবার দিন।',
      'dadTasks': [
        'হসপিটাল ব্যাগ পুরোপুরি প্রস্তুত করে রাখুন।',
        'স্ত্রীর মানসিক সাহস ও আত্মবিশ্বাস বাড়ান।',
        'হাসপাতালে যাওয়ার দ্রুততম যাতায়াত গাড়ি ঠিক রাখুন।'
      ]
    },
    {
      'week': 40,
      'trimester': 3,
      'fruit': 'পূর্ণাঙ্গ তরমুজ',
      'length': '৫০ সেমি',
      'weight': '৩.৩ কেজি',
      'development': 'পূর্ণাঙ্গ সন্তান! যেকোনো দিন কোলে আসবে নতুন অতিথি।',
      'symptoms': 'প্রসব বেদনা শুরু হওয়া, পানি ভাঙা বা নিয়মিত সংকোচন।',
      'nutrition': 'হাসপাতালে সহজে খাওয়ার শুকনো স্ন্যাক্স রাখুন।',
      'dadTasks': [
        'ধৈর্য ধরুন, প্যানিক না করে হাসপাতালে পৌঁছান।',
        'ডেলিভারি রুমে স্ত্রীর পরম ভরসা হয়ে থাকুন।',
        'আপনি একজন গর্বিত ও দায়িত্ববান বাবা হতে যাচ্ছেন!'
      ]
    }
  ];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('dad_tasks');
    if (data != null) {
      setState(() {
        _completedTasks = Map<String, bool>.from(jsonDecode(data));
      });
    }
  }

  Future<void> _toggleTask(String key) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _completedTasks[key] = !(_completedTasks[key] ?? false);
    });
    await prefs.setString('dad_tasks', jsonEncode(_completedTasks));
  }

  @override
  Widget build(BuildContext context) {
    final weekInfo = _weeksData.firstWhere(
      (w) => w['week'] == widget.currentWeek,
      orElse: () => _weeksData.reduce((curr, next) =>
          (curr['week'] - widget.currentWeek).abs() < (next['week'] - widget.currentWeek).abs()
              ? curr
              : next),
    );

    final trimesterText = weekInfo['trimester'] == 1
        ? '১ম ট্রাইমেস্টার (১-১৩ সপ্তাহ)'
        : weekInfo['trimester'] == 2
            ? '২য় ট্রাইমেস্টার (১৪-২৭ সপ্তাহ)'
            : '৩য় ট্রাইমেস্টার (২৮-৪০ সপ্তাহ)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('সাপ্তাহিক ট্র্যাকার'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${widget.currentWeek}তম সপ্তাহ',
              style: const TextStyle(
                color: Color(0xFF065F46),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Hero Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF0F766E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF059669).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trimesterText,
                    style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'গর্ভাবস্থার ${weekInfo['week']}তম সপ্তাহ',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'শিশুর বর্তমান আকার: ${weekInfo['fruit']}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (weekInfo['week'] as int) / 40.0,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFDE047)),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Week Selector Chips
            const Text(
              'সপ্তাহ নির্বাচন করুন:',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _weeksData.length,
                itemBuilder: (context, index) {
                  final w = _weeksData[index]['week'] as int;
                  final isSelected = w == widget.currentWeek;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$w সপ্তাহ'),
                      selected: isSelected,
                      selectedColor: const Color(0xFF059669),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF1E293B),
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (selected) {
                        if (selected) widget.onWeekChanged(w);
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Baby & Mom Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.child_care, color: Color(0xFFD97706)),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'শিশুর বৃদ্ধি ও শারীরিক পরিবর্তন',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('দৈর্ঘ্য: ${weekInfo['length']}  |  ওজন: ${weekInfo['weight']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    Text(weekInfo['development'], style: const TextStyle(fontSize: 14, color: Color(0xFF334155))),
                    const Divider(height: 24),
                    const Text('মায়ের শরীরে অনুভূতি:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFBE123C))),
                    const SizedBox(height: 4),
                    Text(weekInfo['symptoms'], style: const TextStyle(fontSize: 14, color: Color(0xFF334155))),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Dad's Checklist Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFA7F3D0)),
              ),
              color: const Color(0xFFF0FDF4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.shield_outlined, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'বাবার মিশন ও সাপ্তাহিক দায়িত্ব',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...List.generate((weekInfo['dadTasks'] as List).length, (idx) {
                      final task = weekInfo['dadTasks'][idx] as String;
                      final key = 'w${weekInfo['week']}_t$idx';
                      final isDone = _completedTasks[key] ?? false;

                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isDone,
                        title: Text(
                          task,
                          style: TextStyle(
                            fontSize: 14,
                            decoration: isDone ? TextDecoration.lineThrough : null,
                            color: isDone ? Colors.grey : const Color(0xFF0F172A),
                          ),
                        ),
                        activeColor: const Color(0xFF059669),
                        onChanged: (_) => _toggleTask(key),
                      );
                    }),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => widget.onAskAI(weekInfo['week'] as int),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('এই সপ্তাহের বিষয়ে এআই গাইডকে প্রশ্ন করুন'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. AI CHAT GUIDE SCREEN
// ==========================================
class AIChatScreen extends StatefulWidget {
  final int currentWeek;
  const AIChatScreen({super.key, required this.currentWeek});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  static const _keyStore = FlutterSecureStorage();
  static const _geminiModel = 'gemini-3.5-flash-lite';
  String _geminiKey = '';
  bool _keyLoading = true;
  final String _systemInstruction = '''
তুমি হচ্ছো 'হবু বাবা' অ্যাপের একজন এক্সপার্ট গাইড ও শুভাকাঙ্ক্ষী বন্ধু। 
তোমার কাজ হলো গর্ভাবস্থায় হবু বাবাদের বিভিন্ন পরামর্শ দেওয়া। 
তুমি বাংলায় খুব সুন্দর, আন্তরিক এবং বন্ধুর মতো করে উত্তর দেবে। 

তোমার মূল দায়িত্বসমূহ:
১. বাবারা কীভাবে স্ত্রীর শারীরিক ও মানসিক যত্ন নেবে তা সহজ ও বাস্তবমুখী পদক্ষেপে বুঝিয়ে বলা।
২. গর্ভাবস্থার বিভিন্ন ধাপে (প্রথম, দ্বিতীয় ও তৃতীয় ট্রাইমেস্টার) কী কী প্রস্তুতি ও চেকআপ লাগবে তা জানানো।
৩. ডেলিভারির প্রস্তুতি, হসপিটাল ব্যাগ গোছানো এবং বাস্তবসম্মত বাজেট বা সঞ্চয় পরিকল্পনার পরামর্শ দেওয়া।
৪. মেডিকেল ইমার্জেন্সি সতর্কতা: যদি কোনো লক্ষণ যেমন অতিরিক্ত রক্তক্ষরণ, তীব্র তলপেটে ব্যথা, পানি ভেঙে যাওয়া, খিঁচুনি বা বাচ্চার নড়াচড়া হঠাৎ কমে যাওয়ার কথা উল্লেখ থাকে—তবে অবশ্যই লাল সতর্কবার্তা সহ তৎক্ষণাৎ নিকটস্থ হাসপাতালে বা গাইনী বিশেষজ্ঞের কাছে যাওয়ার জোরালো পরামর্শ দেবে।
''';

  @override
  void initState() {
    super.initState();

    _loadGeminiKey();
    _messages.add({
      'role': 'assistant',
      'text': 'আসসালামু আলাইকুম প্রিয় ভাই! ‘হবু বাবা’ অ্যাপে আপনাকে স্বাগতম। 💐\n\nআপনি এখন আপনার স্ত্রীর গর্ভাবস্থার ${widget.currentWeek}তম সপ্তাহে আছেন। স্ত্রীর যত্ন, পুষ্টি, ডেলিভারি বাজেট বা হসপিটাল ব্যাগ গোছানো নিয়ে যেকোনো প্রশ্ন আমাকে বন্ধুর মতো করতে পারেন।\n\n📌 মনে রাখবেন: কোনো জরুরি বিপদচিহ্ন দেখা দিলে অবশ্যই তৎক্ষণাৎ ডাক্তার দেখাবেন।',
      'isEmergency': false,
    });
  }

  Future<void> _loadGeminiKey() async {
    try {
      final stored = await _keyStore.read(key: 'hobu_gemini_key') ?? '';
      if (mounted) setState(() { _geminiKey = stored; _keyLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _keyLoading = false; });
    }
  }

  Future<void> _setApiKeyDialog() async {
    final field = TextEditingController(text: _geminiKey);
    bool obscure = true;
    final newKey = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => AlertDialog(
        title: const Text('Gemini AI সেটআপ'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Google AI Studio থেকে পাওয়া API Key এখানে বসান। শুধু নিজের ফোনে পরীক্ষার জন্য ব্যবহার করুন।'),
          const SizedBox(height: 12),
          TextField(controller: field, obscureText: obscure,
            autocorrect: false, enableSuggestions: false,
            decoration: InputDecoration(labelText: 'Gemini API Key', border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => redraw(() => obscure = !obscure))),
          ),
          const SizedBox(height: 8),
          const Text('Key ফোনে encrypted storage-এ রাখা হবে। Direct API key app-এর network requests থেকে উদ্ধার করা সম্ভব; অন্যকে APK বা key দেবেন না।',
            style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
          if (_geminiKey.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(ctx, '__REMOVE__'), child: const Text('Key মুছুন')),
          FilledButton(onPressed: () => Navigator.pop(ctx, field.text.trim()), child: const Text('সেভ করুন')),
        ],
      )),
    );
    field.dispose();
    if (newKey == null || !mounted) return;
    try {
      if (newKey == '__REMOVE__' || newKey.isEmpty) {
        await _keyStore.delete(key: 'hobu_gemini_key');
        if (mounted) setState(() => _geminiKey = '');
      } else {
        await _keyStore.write(key: 'hobu_gemini_key', value: newKey);
        if (mounted) setState(() => _geminiKey = newKey);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini API সেটিং সংরক্ষিত হয়েছে')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key সংরক্ষণ করা যায়নি। আবার চেষ্টা করুন।')),
      );
    }
  }

  Future<void> _sendMessage([String? prefilledText]) async {
    final query = prefilledText ?? _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': query, 'isEmergency': false});
      _isLoading = true;
    });
    if (prefilledText == null) _controller.clear();
    _scrollToBottom();

    final isEmergencyQuery = RegExp(r'(রক্ত|ব্লিডিং|খিঁচুনি|তীব্র ব্যথা|পানি ভেঙে|নড়াচড়া কমে|ঝাপসা)').hasMatch(query);

    try {
      String replyText = '';
      if (_geminiKey.isEmpty) {
        replyText = isEmergencyQuery
            ? '⚠️ এটি জরুরি লক্ষণ হতে পারে। এখনই চিকিৎসক বা নিকটস্থ জরুরি বিভাগে যোগাযোগ করুন।'
            : 'লাইভ AI চালু করতে উপরের 🔑 আইকনে চাপ দিয়ে Gemini API Key সেভ করুন।';
      } else {
        final history = _messages
            .where((m) => m['role'] == 'user' || (m['role'] == 'assistant' && m['generated'] == true))
            .toList();
        final contents = history.skip(history.length > 16 ? history.length - 16 : 0).map((m) => <String, dynamic>{
          'role': m['role'] == 'assistant' ? 'model' : 'user',
          'parts': [ {'text': m['text'].toString().length > 2500 ? m['text'].toString().substring(0, 2500) : m['text'].toString()} ],
        }).toList();
        final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent');
        final result = await http.post(uri,
          headers: { 'Content-Type': 'application/json', 'x-goog-api-key': _geminiKey },
          body: jsonEncode({
            'systemInstruction': {'parts': [{'text': '$_systemInstruction\nবর্তমান গর্ভকাল: ${widget.currentWeek} সপ্তাহ। ব্যক্তিগত রোগ নির্ণয় নয়; নবজাতকের জ্বর (৩ মাসের কম), শ্বাসকষ্ট, খিঁচুনি, গর্ভাবস্থায় রক্তক্ষরণ বা শিশুর নড়াচড়া কমলে জরুরি চিকিৎসা নিতে বলবে।'}]},
            'contents': contents,
            'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
          }),
        ).timeout(const Duration(seconds: 45));
        if (result.statusCode != 200) {
          if (result.statusCode == 400 || result.statusCode == 403) throw Exception('API Key বা API access যাচাই করুন (${result.statusCode})');
          if (result.statusCode == 429) throw Exception('Free Tier limit শেষ হয়েছে। পরে চেষ্টা করুন।');
          if (result.statusCode == 404) throw Exception('এই API Key-তে $_geminiModel মডেলটি পাওয়া যাচ্ছে না (404)। Google AI Studio-তে মডেলের অ্যাক্সেস পরীক্ষা করুন।');
          throw Exception('Gemini সাড়া দেয়নি (${result.statusCode})');
        }
        final parsed = jsonDecode(utf8.decode(result.bodyBytes)) as Map<String, dynamic>;
        final candidates = parsed['candidates'] as List<dynamic>? ?? [];
        if (candidates.isEmpty) throw Exception('Gemini কোনো উত্তর দেয়নি');
        final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>? ?? [];
        replyText = parts.whereType<Map<String, dynamic>>()
            .map((p) => p['text']?.toString() ?? '').join('\n').trim();
        if (replyText.isEmpty) throw Exception('Gemini উত্তরটি দেখাতে পারেনি');
      }

      final isEmergencyReply = isEmergencyQuery || RegExp(r'(রক্ত|জরুরি|বিপদচিহ্ন|অবিলম্বে হাসপাতাল)').hasMatch(replyText);

      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': replyText,
          'isEmergency': isEmergencyReply,
          'generated': _geminiKey.isNotEmpty,
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': 'পরামর্শ আনতে সমস্যা হয়েছে: $e',
          'isEmergency': false,
        });
      });
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('এআই এক্সপার্ট গাইড'),
        actions: [
          IconButton(
            icon: Icon(
              _geminiKey.isEmpty ? Icons.vpn_key_outlined : Icons.vpn_key,
              color: _geminiKey.isEmpty ? Colors.amber : const Color(0xFF059669),
            ),
            tooltip: _keyLoading ? 'Key loading...' : 'Gemini API Key সেট করুন',
            onPressed: _setApiKeyDialog,
          )
        ],
      ),
      body: Column(
        children: [
          // Prompt suggestions
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildPromptChip('মর্নিং সিকনেস দূর করার উপায়?'),
                _buildPromptChip('হসপিটাল ব্যাগে বাবার কী লাগবে?'),
                _buildPromptChip('নরমাল ডেলিভারির আনুমানিক খরচ কত?'),
                _buildPromptChip('স্ত্রীর মুড সুইং সামলানোর টিপস'),
              ],
            ),
          ),

          // Chat Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                final isEmergency = msg['isEmergency'] as bool;

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF059669)
                          : isEmergency
                              ? const Color(0xFFFFF1F2)
                              : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: isEmergency ? Border.all(color: const Color(0xFFE11D48), width: 1.5) : Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isEmergency && !isUser) ...[
                          const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: const Color(0xFFE11D48), size: 18),
                              SizedBox(width: 6),
                              Text(
                                'জরুরি মেডিকেল সতর্কতা:',
                                style: TextStyle(color: const Color(0xFFE11D48), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          msg['text'] as String,
                          style: TextStyle(
                            color: isUser ? Colors.white : const Color(0xFF1E293B),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('পরামর্শ তৈরি হচ্ছে...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),

          // Input field
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'বাংলায় প্রশ্ন লিখুন...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _sendMessage(),
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(text, style: const TextStyle(fontSize: 12)),
        backgroundColor: const Color(0xFFECFDF5),
        side: const BorderSide(color: Color(0xFFA7F3D0)),
        onPressed: () => _sendMessage(text),
      ),
    );
  }
}

// ==========================================
// 3. HOSPITAL BAG CHECKLIST SCREEN
// ==========================================
class HospitalBagScreen extends StatefulWidget {
  const HospitalBagScreen({super.key});

  @override
  State<HospitalBagScreen> createState() => _HospitalBagScreenState();
}

class _HospitalBagScreenState extends State<HospitalBagScreen> {
  String _activeCategory = 'all';
  List<Map<String, dynamic>> _items = [];

  final List<Map<String, dynamic>> _defaultItems = [
    {'id': 'm1', 'title': 'মায়ের আরামদায়ক সুতি গাউন (৩-৪ সেট)', 'cat': 'mother', 'done': false},
    {'id': 'm2', 'title': 'ম্যাটারনিটি স্যানিটারি প্যাড (২ প্যাকেট)', 'cat': 'mother', 'done': false},
    {'id': 'm3', 'title': 'চিকিৎসকের প্রেসক্রিপশন ও আল্ট্রাসাউন্ড ফাইল', 'cat': 'mother', 'done': false},
    {'id': 'm4', 'title': 'ডিসপোজেবল আন্ডারওয়্যার ও স্লিপার', 'cat': 'mother', 'done': false},
    {'id': 'b1', 'title': 'নবজাতকের নরম সুতি কাঁথা ও র‍্যাপার (৪-৫টি)', 'cat': 'baby', 'done': false},
    {'id': 'b2', 'title': 'নিউবর্ন সাইজ ডায়াপার ও বেবি ওয়াইপস', 'cat': 'baby', 'done': false},
    {'id': 'b3', 'title': 'নবজাতকের ফ্রন্ট-ওপেন জামা ও টুপি-মোজা', 'cat': 'baby', 'done': false},
    {'id': 'd1', 'title': 'হাসপাতালের অ্যাডমিশন ফি ও পর্যাপ্ত ক্যাশ টাকা', 'cat': 'father', 'done': false},
    {'id': 'd2', 'title': 'জাতীয় পরিচয়পত্র (NID) ও স্বাস্থ্য কার্ড', 'cat': 'father', 'done': false},
    {'id': 'd3', 'title': 'মোবাইল ফোন ও ফুল চার্জড পাওয়ার ব্যাংক', 'cat': 'father', 'done': false},
    {'id': 'd4', 'title': 'জরুরি রক্তের ডোনারের যোগাযোগের নম্বর', 'cat': 'father', 'done': false},
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('hospital_bag_items');
    if (data != null) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(jsonDecode(data));
      });
    } else {
      setState(() {
        _items = List.from(_defaultItems);
      });
    }
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hospital_bag_items', jsonEncode(_items));
  }

  void _toggleDone(int index) {
    setState(() {
      _items[index]['done'] = !(_items[index]['done'] as bool);
    });
    _saveItems();
  }

  void _addNewItemDialog() {
    final textController = TextEditingController();
    String category = 'mother';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('নতুন সামগ্রী যোগ করুন'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'জিনিসের নাম',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'mother', child: Text('মায়ের জন্য')),
                  DropdownMenuItem(value: 'baby', child: Text('নবজাতকের জন্য')),
                  DropdownMenuItem(value: 'father', child: Text('বাবার জন্য')),
                ],
                onChanged: (val) {
                  if (val != null) setModalState(() => category = val);
                },
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('বাতিল')),
            ElevatedButton(
              onPressed: () {
                if (textController.text.trim().isNotEmpty) {
                  setState(() {
                    _items.insert(0, {
                      'id': 'c_${DateTime.now().millisecondsSinceEpoch}',
                      'title': textController.text.trim(),
                      'cat': category,
                      'done': false,
                    });
                  });
                  _saveItems();
                  Navigator.pop(context);
                }
              },
              child: const Text('যোগ করুন'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((i) => _activeCategory == 'all' || i['cat'] == _activeCategory).toList();
    final doneCount = _items.where((i) => i['done'] == true).length;
    final progress = _items.isEmpty ? 0.0 : doneCount / _items.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('হসপিটাল ব্যাগ চেকলিস্ট'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addNewItemDialog),
        ],
      ),
      body: Column(
        children: [
          // Progress summary
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('প্রস্তুতির অগ্রগতি: $doneCount/${_items.length} সম্পন্ন',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${(progress * 100).round()}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF059669)),
                  ),
                ),
              ],
            ),
          ),

          // Category filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildCatChip('all', 'সবগুলো'),
                _buildCatChip('mother', 'মায়ের জন্য'),
                _buildCatChip('baby', 'নবজাতকের জন্য'),
                _buildCatChip('father', 'বাবার জন্য'),
              ],
            ),
          ),

          // Items List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                final realIndex = _items.indexOf(item);
                final isDone = item['done'] as bool;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: CheckboxListTile(
                    value: isDone,
                    title: Text(
                      item['title'] as String,
                      style: TextStyle(
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : const Color(0xFF0F172A),
                      ),
                    ),
                    activeColor: const Color(0xFF059669),
                    onChanged: (_) => _toggleDone(realIndex),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatChip(String key, String label) {
    final isSelected = _activeCategory == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFFD1FAE5),
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFF065F46) : const Color(0xFF475569),
          fontWeight: FontWeight.bold,
        ),
        onSelected: (_) {
          setState(() {
            _activeCategory = key;
          });
        },
      ),
    );
  }
}

// ==========================================
// 4. DELIVERY BUDGET SCREEN
// ==========================================
class BudgetCalculatorScreen extends StatefulWidget {
  const BudgetCalculatorScreen({super.key});

  @override
  State<BudgetCalculatorScreen> createState() => _BudgetCalculatorScreenState();
}

class _BudgetCalculatorScreenState extends State<BudgetCalculatorScreen> {
  bool _isNormal = true;
  int _savedAmount = 25000;
  int _monthsLeft = 4;

  final Map<String, int> _normalCosts = {
    'হাসপাতাল ও ওটি/ডেলিভারি চার্জ': 20000,
    'ডক্টরস ও গাইনী স্পেশালিস্ট ফি': 10000,
    'ওষুধ ও স্যালাইন সামগ্রী': 5000,
    'প্যাথলজি ও ল্যাব পরীক্ষা': 4000,
    'নবজাতকের প্রাথমিক যত্ন ও টিকা': 5000,
    'যাতায়াত ও অ্যাম্বুলেন্স': 4000,
    'পোস্ট-ডেলিভারি প্রয়োজনীয় বাজার': 7000,
    'জরুরি আপদকালীন বাফার ফান্ড': 15000,
  };

  final Map<String, int> _cSectionCosts = {
    'হাসপাতাল কেবিন ও ওটি চার্জ': 45000,
    'সার্জন ও অ্যানেস্থেটিস্ট ফি': 25000,
    'ওষুধ ও পোস্ট-অপারেটিভ স্যালাইন': 15000,
    'প্যাথলজি ও জরুরি পরীক্ষা': 8000,
    'নবজাতকের প্রাথমিক যত্ন ও টিকা': 8000,
    'যাতায়াত ও অ্যাম্বুলেন্স': 5000,
    'পোস্ট-ডেলিভারি প্রয়োজনীয় বাজার': 9000,
    'জরুরি আপদকালীন বাফার ফান্ড': 25000,
  };

  @override
  Widget build(BuildContext context) {
    final currentCosts = _isNormal ? _normalCosts : _cSectionCosts;
    final totalCost = currentCosts.values.reduce((a, b) => a + b);
    final deficit = (totalCost - _savedAmount).clamp(0, 9999999);
    final monthlySaving = _monthsLeft > 0 ? (deficit / _monthsLeft).ceil() : deficit;

    return Scaffold(
      appBar: AppBar(title: const Text('ডেলিভারি বাজেট ও সেভিংস')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Normal vs C-Section toggle
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('নরমাল ডেলিভারি')),
                ButtonSegment(value: false, label: Text('সিজারিয়ান (C-Section)')),
              ],
              selected: {_isNormal},
              onSelectionChanged: (set) {
                setState(() {
                  _isNormal = set.first;
                });
              },
            ),

            const SizedBox(height: 16),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF115E59)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Text('প্রাক্কলিত মোট খরচ', style: TextStyle(color: Colors.white70)),
                  Text(
                    '৳ $totalCost',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('বর্তমানে জমানো', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('৳ $_savedAmount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('মাসিক জমার টার্গেট ($_monthsLeft মাস)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('৳ $monthlySaving / মাস', style: const TextStyle(color: Color(0xFFFDE047), fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Edit saved amount
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('আপনার আর্থিক তথ্য আপডেট করুন:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('জমানো টাকা: ৳ '),
                        Expanded(
                          child: Slider(
                            value: _savedAmount.toDouble(),
                            min: 0,
                            max: 150000,
                            divisions: 30,
                            label: '৳ $_savedAmount',
                            activeColor: const Color(0xFF059669),
                            onChanged: (val) => setState(() => _savedAmount = val.round()),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('বাকি মাস: '),
                        Expanded(
                          child: Slider(
                            value: _monthsLeft.toDouble(),
                            min: 1,
                            max: 9,
                            divisions: 8,
                            label: '$_monthsLeft মাস',
                            activeColor: const Color(0xFF059669),
                            onChanged: (val) => setState(() => _monthsLeft = val.round()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Cost items
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('খরচের বিস্তারিত খাতসমূহ:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),

            ...currentCosts.entries.map((e) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: ListTile(
                    title: Text(e.key, style: const TextStyle(fontSize: 14)),
                    trailing: Text('৳ ${e.value}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. EMERGENCY & DANGER SIGNS SCREEN
// ==========================================
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  Future<void> _makeCall(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('জরুরি বিপদচিহ্ন ও হটলাইন', style: TextStyle(color: const Color(0xFFE11D48))),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Urgent Header
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDA4AF)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: const Color(0xFFE11D48), size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'নিচের যেকোনো একটি লক্ষণ দেখা দিলে কালবিলম্ব না করে অবিলম্বে হাসপাতালে যান!',
                      style: TextStyle(color: const Color(0xFFE11D48), fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Danger Signs
            const Text('৬টি প্রধান লাল বিপদচিহ্ন:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            _buildDangerTile('১. যোনিপথে রক্তপাত বা লালচে স্রাব', 'প্লাসেন্টা জটিলতা বা প্রসবপূর্ব ঝুঁকির স্পষ্ট লক্ষণ।'),
            _buildDangerTile('২. তলপেটে প্রচণ্ড তীব্র ব্যথা বা টান', 'স্বাভাবিক টান ছাড়া অতিরিক্ত তীব্র কামড়ে ধরা ব্যথা।'),
            _buildDangerTile('৩. সময়ের আগেই পানি ভেঙে যাওয়া', 'অ্যামনিওটিক ফ্লুইড ফেটে যাওয়া, ইনফেকশনের চরম ঝুঁকি।'),
            _buildDangerTile('৪. বাচ্চার নড়াচড়া লক্ষণীয়ভাবে কমে যাওয়া', 'দিনে ১০ বারের কম নড়াচড়া বা হঠাৎ স্তব্ধ হয়ে যাওয়া।'),
            _buildDangerTile('৫. তীব্র মাথাব্যথা, চোখে ঝাপসা দেখা', 'প্রি-এক্লাম্পসিয়া ও উচ্চ রক্তচাপের লক্ষণ।'),
            _buildDangerTile('৬. খিঁচুনি বা অজ্ঞান হয়ে যাওয়া', 'তাৎক্ষণিক ইমার্জেন্সি লাইফ সাপোর্ট প্রয়োজন।'),

            const SizedBox(height: 24),

            // Direct Call Hotlines
            const Text('এক ক্লিকে জরুরি কল দিন:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: const Color(0xFFE11D48), child: Icon(Icons.phone, color: Colors.white)),
                    title: const Text('জাতীয় জরুরি সেবা (৯৯৯)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('পুলিশ ও অ্যাম্বুলেন্স সহায়তা'),
                    trailing: ElevatedButton(
                      onPressed: () => _makeCall('999'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48), foregroundColor: Colors.white),
                      child: const Text('কল ৯৯৯'),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const CircleAvatar(backgroundColor: Color(0xFF059669), child: Icon(Icons.medical_services, color: Colors.white)),
                    title: const Text('স্বাস্থ্য বাতায়ন (১৬২৬৩)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('২৪ ঘণ্টা সরকারি ডাক্তার পরামর্শ'),
                    trailing: ElevatedButton(
                      onPressed: () => _makeCall('16263'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                      child: const Text('কল ১৬২৬৩'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerTile(String title, String desc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFECDD3)),
      ),
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: const Color(0xFFE11D48)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
      ),
    );
  }
}


// 6. Daily motivation: content transferred from React application's data.
class DailyMotivationScreen extends StatefulWidget {
  const DailyMotivationScreen({super.key});
  @override
  State<DailyMotivationScreen> createState() => _DailyMotivationScreenState();
}
class _DailyMotivationScreenState extends State<DailyMotivationScreen> {
  List<dynamic> items = [];
  String category = 'all';
  Set<String> readIds = {};
  @override
  void initState() {super.initState(); _load();}
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = jsonDecode(await rootBundle.loadString('assets/data/notifications.json')) as List<dynamic>;
    if (!mounted) return;
    setState(() {items = loaded; readIds = (prefs.getStringList('read_motivation_ids') ?? []).toSet();});
  }
  Future<void> _markRead(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => readIds.add(id));
    await prefs.setStringList('read_motivation_ids', readIds.toList());
  }
  @override
  Widget build(BuildContext context) {
    final visible = items.where((x) => category == 'all' || x['category'] == category).toList();
    return Scaffold(appBar: AppBar(title: const Text('প্রতিদিনের অনুপ্রেরণা')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final option in const [('all','সব'),('mental_health','মানসিক স্বাস্থ্য'),('religious','ধর্মীয়'),('habit','অভ্যাস')])
            ChoiceChip(label: Text(option.$2), selected: category == option.$1, onSelected: (_) => setState(() => category = option.$1)),
        ])),
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: visible.length, itemBuilder: (ctx, i) {
          final x = visible[i] as Map<String,dynamic>;
          final id = x['id'] as String;
          return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.favorite, color: Color(0xFF059669)), const SizedBox(width: 8), Expanded(child: Text(x['categoryBangla'] ?? '', style: const TextStyle(color: Color(0xFF059669)))), if(readIds.contains(id)) const Icon(Icons.check_circle, color: Color(0xFF059669))]),
            const SizedBox(height: 8), Text(x['title'] ?? '',style: const TextStyle(fontSize: 18,fontWeight: FontWeight.bold)),
            const SizedBox(height: 8), Text(x['message'] ?? ''),
            if ((x['sourceOrTip'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 8), Text(x['sourceOrTip'], style: const TextStyle(color: Color(0xFF475569)))],
            if ((x['duaOrAction'] ?? '').toString().isNotEmpty) ...[const SizedBox(height: 8), Text(x['duaOrAction'])],
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _markRead(id), icon: const Icon(Icons.check), label: Text(readIds.contains(id) ? 'পড়া হয়েছে' : 'পড়া হয়েছে চিহ্নিত করুন')))
          ])));
        }))
      ]));
  }
}

// 7. Live GPS search powered by Google Maps' live Places results.
// The app does not claim unverified availability, NICU or opening hours.
class NearbyHospitalsScreen extends StatefulWidget {
  const NearbyHospitalsScreen({super.key});
  @override State<NearbyHospitalsScreen> createState() => _NearbyHospitalsScreenState();
}
class _NearbyHospitalsScreenState extends State<NearbyHospitalsScreen> {
  String category = 'হাসপাতাল'; int radius = 5; bool working = false;
  final manual = TextEditingController();
  @override void dispose() {manual.dispose();super.dispose();}
  Future<void> _openMap({bool useGps = false}) async {
    setState(() => working = true);
    try {
      final keyword = {'হাসপাতাল':'hospital','মাতৃসেবা':'maternity hospital','শিশু হাসপাতাল':'children hospital','জরুরি বিভাগ':'emergency hospital'}[category] ?? 'hospital';
      String q;
      if (useGps) {
        if (!await Geolocator.isLocationServiceEnabled()) throw Exception('ফোনের Location চালু করুন');
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw Exception('Location permission প্রয়োজন');
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
        q = '$keyword near ${pos.latitude},${pos.longitude}';
      } else {
        if (manual.text.trim().isEmpty) throw Exception('একটি শহর বা এলাকার নাম লিখুন');
        q = '$keyword near ${manual.text.trim()}';
      }
      final url = Uri.https('www.google.com','/maps/search/', {'api':'1','query':q});
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw Exception('Google Maps খোলা যাচ্ছে না');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {if(mounted)setState(()=>working=false);}
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title:const Text('কাছের হাসপাতাল')),body: ListView(padding:const EdgeInsets.all(18),children:[
    const Text('আপনি এখন কোথায় আছেন?',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
    const SizedBox(height:10),const Text('GPS অনুমতি দিলে Google Maps-এ আপনার আশেপাশের হাসপাতালের আপডেটেড তালিকা ও দিকনির্দেশনা দেখতে পারবেন।'),
    const SizedBox(height:18),DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'ধরন'),items:['হাসপাতাল','মাতৃসেবা','শিশু হাসপাতাল','জরুরি বিভাগ'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>category=v??category)),
    const SizedBox(height:15),FilledButton.icon(onPressed:working?null:()=>_openMap(useGps:true),icon:const Icon(Icons.my_location),label:Text(working?'খোঁজা হচ্ছে...':'আমার বর্তমান লোকেশনের কাছে খুঁজুন')),
    const SizedBox(height:20),TextField(controller:manual,decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'অথবা এলাকা লিখুন',hintText:'যেমন: Savar, Dhaka')),
    const SizedBox(height:8),OutlinedButton.icon(onPressed:working?null:()=>_openMap(),icon:const Icon(Icons.map),label:const Text('Google Maps-এ খুঁজুন')),
    const SizedBox(height:18),const Text('Google Maps-এর ফলাফলে দূরত্ব, ফোন নম্বর ও directions দেখতে পারবেন। অ্যাপের ভেতর এখনো Places API list বা radius filtering নেই। জরুরি সেবা/NICU/খোলা থাকার সময় ফোন করে নিশ্চিত করুন।',style:TextStyle(color:Color(0xFF92400E))),
  ]));
}
