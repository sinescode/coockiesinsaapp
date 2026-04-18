import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'security_module.dart';

// Background message handler must be a top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

// Initialize Local Notifications Plugin globally for background handler
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Define the High Importance Channel
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'default_channel',
  'High Importance Notifications',
  description: 'This channel is used for important notifications.',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cookies Account Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xff0f172a),
        scaffoldBackgroundColor: const Color(0xff0f172a),
        cardColor: const Color(0xff111827),
        dividerColor: const Color(0xff1f2937),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xffe5e7eb)),
          bodySmall: TextStyle(color: Color(0xff94a3b8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xff0b1220),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xff1f2937)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xff1f2937)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xff3b82f6)),
          ),
          labelStyle:
              const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff22c55e),
            foregroundColor: const Color(0xff0b1220),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xfff97316),
            side: const BorderSide(color: Color(0xfff97316)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Data Models
  List<Map<String, String>> _accounts = [];
  List<Map<String, dynamic>> _logs = [];

  // Staged Jobs — { job_id, username, submitted_at, status, release_in_seconds }
  List<Map<String, dynamic>> _stagedJobs = [];
  // Track which job IDs are currently being checked
  final Set<String> _checkingJobs = {};

  // Settings Variables
  String _webhook1Url = "http://43.173.119.225/api/api/v1/webhook/nRlmI2-8T7x2DAWe1hWxi97qGA1FcCxrNcyCtLTO_Cw/account-push";
  String _webhook2Url = "https://submitwork.org/api/push";
  int _activeWebhook = 1; // 1 = old direct system, 2 = new job_id system
  bool _webhookEnabled = true; // Toggle for webhook functionality
  bool _autoRandomPassword = true; // Toggle for auto random password

  String get _webhookUrl => _activeWebhook == 1 ? _webhook1Url : _webhook2Url;

  String _jsonFilename = "accounts.json";
  String _currentPassword = "";

  // FCM Variables
  String _fcmToken = "Fetching...";

  // Server Status Variables
  String _serverStatus = "Check";
  bool _isChecking = false;

  // Input Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cookiesController = TextEditingController();
  final TextEditingController _webhook1Controller = TextEditingController();
  final TextEditingController _webhook2Controller = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();

  // Keep old single controller as alias for compatibility
  TextEditingController get _webhookController =>
      _activeWebhook == 1 ? _webhook1Controller : _webhook2Controller;

  // Last saved card data (for displaying after save)
  Map<String, String>? _lastSavedEntry;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initFCM();
  }

  // --- FCM Logic ---
  Future<void> _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
    } else {
      print('User declined or has not accepted permission');
    }

    String? token = await messaging.getToken();
    if (token != null) {
      setState(() {
        _fcmToken = token;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
    }

    messaging.onTokenRefresh.listen((newToken) {
      setState(() {
        _fcmToken = newToken;
      });
      _saveFCMToken(newToken);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: android.smallIcon,
              importance: Importance.high,
              priority: Priority.high,
              color: const Color(0xff22c55e),
            ),
          ),
        );
      }
    });
  }

  Future<void> _saveFCMToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
  }

  // --- Data Persistence Logic ---

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedWebhook1 = prefs.getString('webhook1_url');
    final savedWebhook2 = prefs.getString('webhook2_url');
    final savedActiveWebhook = prefs.getInt('active_webhook');
    final savedWebhookEnabled = prefs.getBool('webhook_enabled');
    final savedAutoPassword = prefs.getBool('auto_random_password');
    final savedFilename = prefs.getString('json_filename');
    final savedPassword = prefs.getString('current_password');
    final savedToken = prefs.getString('fcm_token');

    setState(() {
      if (savedWebhook1 != null) _webhook1Url = savedWebhook1;
      if (savedWebhook2 != null) _webhook2Url = savedWebhook2;
      if (savedActiveWebhook != null) _activeWebhook = savedActiveWebhook;
      if (savedWebhookEnabled != null) _webhookEnabled = savedWebhookEnabled;
      if (savedAutoPassword != null) _autoRandomPassword = savedAutoPassword;
      if (savedFilename != null) _jsonFilename = savedFilename;
      _currentPassword = savedPassword ?? "";
      if (savedToken != null) _fcmToken = savedToken;

      _webhook1Controller.text = _webhook1Url;
      _webhook2Controller.text = _webhook2Url;
      _filenameController.text = _jsonFilename;
      _passwordController.text = _currentPassword;

      String? accountsStr = prefs.getString('accounts_list');
      if (accountsStr != null && accountsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(accountsStr);
          _accounts =
              decoded.map((e) => Map<String, String>.from(e)).toList();
        } catch (e) {
          _addLog("System", "Error loading saved accounts: $e");
        }
      }

      String? logsStr = prefs.getString('logs_list');
      if (logsStr != null && logsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(logsStr);
          _logs =
              decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (e) {
          print("Error loading logs: $e");
        }
      }

      String? stagedStr = prefs.getString('staged_jobs');
      if (stagedStr != null && stagedStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(stagedStr);
          _stagedJobs =
              decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (e) {
          print("Error loading staged jobs: $e");
        }
      }
    });

    // Only auto-generate password on startup if the feature is enabled
    if (_currentPassword.isEmpty && _autoRandomPassword) {
      _generatePassword();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webhook1_url', _webhook1Url);
    await prefs.setString('webhook2_url', _webhook2Url);
    await prefs.setInt('active_webhook', _activeWebhook);
    await prefs.setBool('webhook_enabled', _webhookEnabled);
    await prefs.setBool('auto_random_password', _autoRandomPassword);
    await prefs.setString('json_filename', _jsonFilename);
    await prefs.setString('current_password', _currentPassword);
    await prefs.setString('accounts_list', json.encode(_accounts));
    await prefs.setString('logs_list', json.encode(_logs));
    await prefs.setString('staged_jobs', json.encode(_stagedJobs));
  }

  // --- Feature Logic ---

  void _generatePassword() {
    const chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    final dateStr = DateFormat('dd').format(DateTime.now());
    final random = Random();
    final length = random.nextInt(5) + 8;
    final letterCount = length - dateStr.length;

    String result = '';
    for (int i = 0; i < letterCount; i++) {
      result += chars[random.nextInt(chars.length)];
    }

    setState(() {
      _currentPassword = result + dateStr;
      _passwordController.text = _currentPassword;
    });
    _saveData();
  }

  void _copyPassword() {
    Clipboard.setData(ClipboardData(text: _currentPassword));
    if (_webhookEnabled) {
      _addLog("System", "Password copied successfully");
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Password copied"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Retry helper — retries up to 3 times on failure/5xx
  // ─────────────────────────────────────────────────────────────────────────────
  Future<http.Response?> _postWithRetry(String url, String body,
      {int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'text/plain'},
              body: body,
            )
            .timeout(const Duration(seconds: 12));

        // Retry on 5xx server errors
        if (response.statusCode >= 500) {
          if (i < retries - 1) {
            await Future.delayed(Duration(seconds: 2 * (i + 1)));
            continue;
          }
        }
        return response;
      } on TimeoutException {
        if (i < retries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
          continue;
        }
        return null;
      } catch (e) {
        if (i < retries - 1) {
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
          continue;
        }
        return null;
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Poll job status — handles TimeoutException gracefully
  // ─────────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────────
  // Save a staging job so it can be checked later from the Saved tab
  // ─────────────────────────────────────────────────────────────────────────────
  void _saveStagedJob(String jobId, String username, int releaseInSeconds) {
    setState(() {
      _stagedJobs.insert(0, {
        "job_id": jobId,
        "username": username,
        "submitted_at": DateFormat.Hms().format(DateTime.now()),
        "status": "staging",
        "release_in_seconds": releaseInSeconds,
      });
    });
    _saveData();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Check a single staged job by job_id and update its status in the list
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _checkSingleStagedJob(int index) async {
    final job = _stagedJobs[index];
    final String jobId = job['job_id'];
    final String username = job['username'] ?? '';

    if (_checkingJobs.contains(jobId)) return;
    setState(() => _checkingJobs.add(jobId));

    try {
      final res = await http
          .get(Uri.parse("https://submitwork.org/api/status/$jobId"))
          .timeout(const Duration(seconds: 12));

      dynamic data;
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        _addLog("Error", "$username \u2192 bad JSON");
        return;
      }

      // ── Job not found (expired / purged by server) ──────────────────────────
      if (res.statusCode == 404 ||
          (data is Map && data.containsKey('error'))) {
        final String errMsg = (data is Map ? data['error'] : null) ?? 'not found';
        setState(() {
          _stagedJobs[index] = {...job, "status": "not_found"};
        });
        _saveData();
        _addLog("Error", "$username \u2192 job expired ($errMsg)");
        return;
      }

      if (res.statusCode != 200) {
        _addLog("Error", "$username \u2192 HTTP ${res.statusCode}");
        setState(() {
          _stagedJobs[index] = {...job, "status": "error"};
        });
        _saveData();
        return;
      }

      final String status = (data['status'] ?? '') as String;
      final dynamic errors = data['errors'];

      if (status == 'done') {
        final int success = (data['data']?['success_count'] ?? 0) as int;
        final int failed = (data['data']?['failed_count'] ?? 0) as int;
        final String result = success > 0 ? "done_ok" : "done_fail";
        setState(() {
          _stagedJobs[index] = {...job, "status": result, "success": success, "failed": failed};
        });
        _saveData();
        _addLog(
          success > 0 ? "Webhook" : "Error",
          "$username \u2192 \u2714 $success | \u2717 $failed",
          style: success > 0 ? "bold" : "normal",
        );
      } else if (status == 'staging' || status == 'processing' || status == 'pending') {
        final int releaseIn = (data['release_in_seconds'] ?? 0) as int;
        setState(() {
          _stagedJobs[index] = {...job, "status": status, "release_in_seconds": releaseIn};
        });
        _saveData();
        _addLog("Webhook", "$username \u2192 $status (${releaseIn}s left)");
      } else if (errors != null) {
        setState(() {
          _stagedJobs[index] = {...job, "status": "error"};
        });
        _saveData();
        _addLog("Error", "$username \u2192 error: $errors");
      } else {
        _addLog("Webhook", "$username \u2192 $status");
      }
    } on TimeoutException {
      _addLog("Error", "$username \u2192 timeout");
    } catch (e) {
      _addLog("Error", "$username \u2192 $e");
    } finally {
      setState(() => _checkingJobs.remove(jobId));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Check ALL staged jobs that are not yet done
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _checkAllStagedJobs() async {
    final pending = <int>[];
    for (int i = 0; i < _stagedJobs.length; i++) {
      final s = _stagedJobs[i]['status'] ?? '';
      if (s != 'done_ok' && s != 'done_fail' && s != 'error' && s != 'not_found') {
        pending.add(i);
      }
    }
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No pending jobs to check"), duration: Duration(seconds: 1)),
      );
      return;
    }
    for (final i in pending) {
      await _checkSingleStagedJob(i);
    }
  }

  Future<void> _pollJobStatus(String jobId, {String username = ''}) async {
    final statusUrl =
        Uri.parse("https://submitwork.org/api/status/$jobId");

    for (int i = 0; i < 40; i++) {
      // max ~120 seconds (staging jobs have push_delay_minutes=2)
      await Future.delayed(const Duration(seconds: 3));

      try {
        final res = await http
            .get(statusUrl)
            .timeout(const Duration(seconds: 12));

        // Server blip — keep polling
        if (res.statusCode >= 500) continue;

        // Job expired / purged by server
        if (res.statusCode == 404) {
          final String displayName = username.isNotEmpty ? username : jobId;
          _addLog("Error", "$displayName \u2192 job expired (not found)");
          final idx = _stagedJobs.indexWhere((j) => j['job_id'] == jobId);
          if (idx != -1) {
            setState(() {
              _stagedJobs[idx] = {..._stagedJobs[idx], "status": "not_found"};
            });
            _saveData();
          }
          return;
        }

        if (res.statusCode != 200) {
          _addLog("Error", "Status check failed: HTTP ${res.statusCode}");
          return;
        }

        dynamic data;
        try {
          data = jsonDecode(res.body);
        } catch (_) {
          continue;
        }

        // Job not found returned as 200 with {"error":"Job not found"}
        if (data is Map && data.containsKey('error')) {
          final String displayName = username.isNotEmpty ? username : jobId;
          final String errMsg = data['error'] ?? 'not found';
          _addLog("Error", "$displayName \u2192 job expired ($errMsg)");
          final idx = _stagedJobs.indexWhere((j) => j['job_id'] == jobId);
          if (idx != -1) {
            setState(() {
              _stagedJobs[idx] = {..._stagedJobs[idx], "status": "not_found"};
            });
            _saveData();
          }
          return;
        }

        final String status = data['status'] ?? '';

        if (status == 'done') {
          final int success = (data['data']?['success_count'] ?? 0) as int;
          final int failed = (data['data']?['failed_count'] ?? 0) as int;
          final dynamic errors = data['errors'];

          final String displayName = username.isNotEmpty ? username : jobId;
          String logMsg = "$displayName \u2192 \u2714 $success | \u2717 $failed";
          if (errors != null && errors is List && errors.isNotEmpty) {
            logMsg += " | ${errors.first}";
          }

          _addLog(
            success > 0 ? "Webhook" : "Error",
            logMsg,
            style: success > 0 ? "bold" : "normal",
          );

          // Update staged job record if it exists
          final idx = _stagedJobs.indexWhere((j) => j['job_id'] == jobId);
          if (idx != -1) {
            setState(() {
              _stagedJobs[idx] = {
                ..._stagedJobs[idx],
                "status": success > 0 ? "done_ok" : "done_fail",
                "success": success,
                "failed": failed,
              };
            });
            _saveData();
          }
          return;
        }

        if (status == 'staging') {
          final int releaseIn = (data['release_in_seconds'] ?? 0) as int;
          // Log once every ~30s to avoid spam
          if (i % 10 == 0) {
            final String displayName = username.isNotEmpty ? username : jobId;
            _addLog("Webhook", "$displayName \u2192 staging (${releaseIn}s left)");
          }
          continue;
        }

        // 'processing', 'pending', or other — keep polling

      } on TimeoutException {
        continue;
      } catch (e) {
        _addLog("Error", "Poll error: $e");
        return;
      }
    }

    // Still staging after timeout — save to staged jobs list for later checking
    final displayName = username.isNotEmpty ? username : jobId;
    _addLog("Webhook", "$displayName \u2192 queued (check later in Saved tab)");
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Server 2: Step 2 — Poll /api/status/{job_id}, errors=null → ONLINE
  // Mirrors Python check_server2_status() exactly.
  // ─────────────────────────────────────────────────────────────────────────────
  Future<String> _checkServer2Status(String jobId) async {
    final statusUrl = Uri.parse("https://submitwork.org/api/status/$jobId");

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await http
            .get(statusUrl)
            .timeout(const Duration(seconds: 10));

        // Bad HTTP — server is down
        if (res.statusCode < 200 || res.statusCode >= 300) {
          debugPrint("[STATUS2] HTTP ${res.statusCode} for job_id=$jobId");
          return "OFF";
        }

        final body = res.body.trim();
        if (body.isEmpty) {
          debugPrint("[STATUS2] Empty response for job_id=$jobId");
          return "OFF";
        }

        dynamic data;
        try {
          data = jsonDecode(body);
        } on FormatException catch (e) {
          debugPrint("[STATUS2] JSON parse error for job_id=$jobId: $e");
          return "OFF";
        }

        // errors=null means server handled the job (even if failed_count>0).
        // failed_count>0 just means the account was invalid, NOT server down.
        final errors = data['errors'];
        final String jobStatus = (data['status'] ?? '') as String;

        if (errors == null &&
            (jobStatus == 'done' ||
             jobStatus == 'processing' ||
             jobStatus == 'pending' ||
             jobStatus == 'staging')) {
          debugPrint("[STATUS2] Server 2 ONLINE — job=$jobId status=$jobStatus");
          return "ON";
        }

        debugPrint("[STATUS2] Server 2 check failed — errors=$errors status=$jobStatus");
        return "OFF";

      } on TimeoutException {
        debugPrint("[STATUS2] Attempt ${attempt + 1}/3 timeout for job_id=$jobId");
      } catch (e) {
        debugPrint("[STATUS2] Attempt ${attempt + 1}/3 error: ${e.runtimeType}: $e");
        return "OFF"; // Non-retryable unexpected error
      }

      if (attempt < 2) {
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }

    debugPrint("[STATUS2] All retries exhausted for job_id=$jobId");
    return "OFF";
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Check server status — mirrors Python check_server_logic() exactly.
  // Server 1: push → success_count or failed_count > 0 → ONLINE
  // Server 2: push → job_id → poll /api/status/{job_id} → errors=null → ONLINE
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _checkServerStatus() async {
    final url = _webhookUrl;
    if (url.isEmpty || !url.startsWith("http")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please set a valid Webhook URL in Settings first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isChecking = true;
      _serverStatus = "Checking...";
    });

    // ── Generate realistic test credentials ───────────────────────────────────
    final random = Random();
    const lowers = "abcdefghijklmnopqrstuvwxyz";
    const digits = "0123456789";
    const uppers = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const allPass = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const hexChars = "0123456789abcdef";
    const b64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    // Username: lowercase + digits, 6–12 chars
    final int uLen = random.nextInt(7) + 6;
    final String randomUser = List.generate(
        uLen, (_) => (lowers + digits)[random.nextInt((lowers + digits).length)]).join();

    // Password: 8–13 chars, guaranteed mix of lower+upper+digit
    final int pLen = random.nextInt(6) + 8;
    final List<String> passChars = [
      ...List.generate(pLen - 3, (_) => allPass[random.nextInt(allPass.length)]),
      lowers[random.nextInt(lowers.length)],
      uppers[random.nextInt(uppers.length)],
      digits[random.nextInt(digits.length)],
    ]..shuffle(random);
    final String randomPass = passChars.join();

    // Cookies: realistic Instagram cookie string
    String rndStr(String src, int len) =>
        List.generate(len, (_) => src[random.nextInt(src.length)]).join();

    final String csrftoken = rndStr(b64Chars, 32);
    final String datr      = rndStr(b64Chars, 24);
    final String igDid     = [
      rndStr(hexChars, 8), rndStr(hexChars, 4),
      rndStr(hexChars, 4), rndStr(hexChars, 4),
      rndStr(hexChars, 12)
    ].join('-').toUpperCase();
    final String mid        = rndStr(b64Chars, 28);
    final int    dsUserId   = 30000000000 + random.nextInt(70000000000);
    final String sessionPart = rndStr(b64Chars, 16);
    final int    sessionNum  = random.nextInt(20);
    final String sessionSfx  = rndStr(b64Chars, 40);
    final String rurHost    = ['NHA', 'FTW', 'LDC', 'ATN'][random.nextInt(4)];
    final int    rurTs      = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 7776000;
    final String rurHash    = rndStr(hexChars, 64);
    final int    wd_w       = 360 + random.nextInt(400);
    final int    wd_h       = 600 + random.nextInt(200);

    final String randomCookie =
        'csrftoken=$csrftoken; datr=$datr; ig_did=$igDid; mid=$mid; '
        'wd=${wd_w}x$wd_h; ds_user_id=$dsUserId; '
        'sessionid=$dsUserId%3A${sessionPart}%3A$sessionNum%3A$sessionSfx; '
        'ps_l=1; ps_n=1; '
        'rur=\\"$rurHost\\\\054$dsUserId\\\\054$rurTs:01f$rurHash\\"';
    // ── End credential generation ─────────────────────────────────────────────

    final String payload =
        "accounts=${base64.encode(utf8.encode("$randomUser:$randomPass|||$randomCookie||"))}";

    try {
      final response = await _postWithRetry(url, payload);

      // Total connection failure after all retries
      if (response == null) {
        debugPrint("[CHECK] Server unreachable: $url");
        setState(() => _serverStatus = "OFF");
        return;
      }

      // Bad HTTP status (502, 503, 504, etc.)
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint("[CHECK] Server returned HTTP ${response.statusCode}");
        setState(() => _serverStatus = "OFF");
        return;
      }

      // Empty body
      if (response.body.trim().isEmpty) {
        debugPrint("[CHECK] Server returned empty body");
        setState(() => _serverStatus = "OFF");
        return;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        debugPrint(
            "[CHECK] Server returned non-JSON: ${response.body.substring(0, min(100, response.body.length))}");
        setState(() => _serverStatus = "OFF");
        return;
      }

      // ── Server 2 logic ─────────────────────────────────────────────────────
      if (_activeWebhook == 2) {
        final String? jobId = decoded['job_id']?.toString().trim();

        if (jobId == null || jobId.isEmpty) {
          debugPrint("[CHECK] Server 2 push response missing job_id: $decoded");
          setState(() => _serverStatus = "OFF");
          return;
        }

        debugPrint("[CHECK] Server 2 push OK — job_id=$jobId. Polling status...");

        // Brief wait for the job to start processing on the server
        await Future.delayed(const Duration(milliseconds: 1500));

        final result = await _checkServer2Status(jobId);
        setState(() => _serverStatus = result);

      // ── Server 1 logic ─────────────────────────────────────────────────────
      } else {
        // Quick win: code=200 in response body
        if (decoded is Map && decoded['code'] == 200) {
          setState(() => _serverStatus = "ON");
          return;
        }

        if (decoded is List && decoded.isNotEmpty) decoded = decoded[0];

        if (decoded is Map) {
          final dynamic dataNode =
              decoded['data'] is Map ? decoded['data'] : decoded;
          if (dataNode is Map) {
            final int successCount = (dataNode['success_count'] ?? 0) as int;
            final int failedCount  = (dataNode['failed_count']  ?? 0) as int;
            setState(() => _serverStatus =
                (successCount > 0 || failedCount > 0) ? "ON" : "OFF");
            return;
          }
        }

        setState(() => _serverStatus = "OFF");
      }
    } catch (e) {
      debugPrint("[CHECK] Unexpected error: $e");
      setState(() => _serverStatus = "OFF");
    } finally {
      setState(() => _isChecking = false);
    }
  }

  // --- Submit: routes to old or new system based on active webhook ---
  Future<void> _submitData() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final cookies = _cookiesController.text.trim();

    _currentPassword = password;
    _jsonFilename = _filenameController.text.trim();
    if (_activeWebhook == 1) {
      _webhook1Url = _webhook1Controller.text.trim();
    } else {
      _webhook2Url = _webhook2Controller.text.trim();
    }

    if (username.isEmpty || password.isEmpty) {
      if (_webhookEnabled) {
        _addLog("Error", "Username and Password required");
      }
      return;
    }

    final newEntry = {
      "email": "",
      "username": username,
      "password": password,
      "auth_code": cookies,
    };

    setState(() {
      _accounts.insert(0, newEntry);
      _lastSavedEntry = newEntry;
    });

    await _saveData();

    // If webhook is disabled, just save and clear inputs
    if (!_webhookEnabled) {
      _usernameController.clear();
      _cookiesController.clear();
      if (_autoRandomPassword) _generatePassword();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Account saved successfully (Webhook OFF)"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    String convertedStr = "$username:$password|||$cookies||";
    String payload =
        "accounts=${base64.encode(utf8.encode(convertedStr))}";

    if (_activeWebhook == 2) {
      // --- New system: job_id polling ---
      final pushResponse = await _postWithRetry(_webhook2Url, payload);

      if (pushResponse == null) {
        _addLog("Error", "Server unreachable after 3 attempts");
        _usernameController.clear();
        _cookiesController.clear();
        if (_autoRandomPassword) _generatePassword();
        return;
      }

      if (pushResponse.body.isEmpty) {
        _addLog("Error", "(${pushResponse.statusCode}) Empty response");
        _usernameController.clear();
        _cookiesController.clear();
        if (_autoRandomPassword) _generatePassword();
        return;
      }

      dynamic pushJson;
      try {
        pushJson = jsonDecode(pushResponse.body);
      } catch (_) {
        _addLog("Error",
            "(${pushResponse.statusCode}) Invalid JSON: ${pushResponse.body}");
        _usernameController.clear();
        _cookiesController.clear();
        if (_autoRandomPassword) _generatePassword();
        return;
      }

      final String? jobId = pushJson['job_id'];
      if (jobId == null) {
        final msg = pushJson['message'] ?? pushResponse.body;
        _addLog("Error", "(${pushResponse.statusCode}) $msg");
        _usernameController.clear();
        _cookiesController.clear();
        if (_autoRandomPassword) _generatePassword();
        return;
      }

      final int releaseIn = (pushJson['release_in_seconds'] ?? 0) as int;
      final String jobStatus = (pushJson['status'] ?? '') as String;

      // ── Immediate job (no staging delay) — poll right now ──────────────────
      if (releaseIn == 0 && jobStatus != 'staging') {
        _addLog("Webhook", "$username \u2192 submitted [$jobId] \u2014 checking...");
        _saveStagedJob(jobId, username, 0);
        unawaited(_pollJobStatus(jobId, username: username));
      } else {
        // ── Staging job (has a release delay) — save and let user check later ─
        _saveStagedJob(jobId, username, releaseIn);
        final String releaseMsg = "~${(releaseIn / 60).ceil()}m";
        _addLog("Webhook",
            "$username \u2192 queued [$jobId] ($releaseMsg) \u2014 check Queued tab");
      }

    } else {
      // --- Old system: direct success_count/failed_count response ---
      try {
        final response = await http.post(
          Uri.parse(_webhook1Url),
          headers: {'Content-Type': 'text/plain'},
          body: payload,
        );

        String logMessage = "Empty response";
        String logStatus = (response.statusCode >= 200 &&
                response.statusCode < 300)
            ? "Webhook"
            : "Error";

        if (response.body.isNotEmpty) {
          try {
            dynamic decoded = jsonDecode(response.body);
            if (decoded is List && decoded.isNotEmpty) decoded = decoded[0];

            if (decoded is Map) {
              dynamic dataNode =
                  decoded['data'] is Map ? decoded['data'] : decoded;
              int successCount = dataNode['success_count'] ?? 0;
              int failedCount = dataNode['failed_count'] ?? 0;

              // FIX: use Unicode escapes to avoid encoding corruption
              logMessage =
                  "\u2714 Success: $successCount | \u2717 Failed: $failedCount";

              String logStyle = "normal";
              if (successCount == 0) {
                logStatus = "Error";
              } else if (failedCount == 0) {
                logStyle = "bold";
              }

              _addLog(logStatus, "(${response.statusCode}) $logMessage",
                  style: logStyle);
            } else {
              logMessage = response.body.trim();
              _addLog(logStatus, "(${response.statusCode}) $logMessage");
            }
          } catch (e) {
            logMessage = "Invalid JSON response";
            _addLog(logStatus, "(${response.statusCode}) $logMessage");
          }
        } else {
          _addLog(logStatus, "(${response.statusCode}) $logMessage");
        }
      } catch (e) {
        _addLog("Error", "Connection error: $e");
      }
    }

    _usernameController.clear();
    _cookiesController.clear();
    if (_autoRandomPassword) _generatePassword();
  }

  // --- Save (formerly Submit) - for non-webhook mode ---
  Future<void> _saveAccount() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final cookies = _cookiesController.text.trim();

    _currentPassword = password;
    _jsonFilename = _filenameController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Username and Password are required"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newEntry = {
      "email": "",
      "username": username,
      "password": password,
      "auth_code": cookies,
    };

    setState(() {
      _accounts.insert(0, newEntry);
      _lastSavedEntry = newEntry;
    });

    await _saveData();

    _usernameController.clear();
    _cookiesController.clear();
    if (_autoRandomPassword) _generatePassword();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Account saved successfully"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _addLog(String status, String message, {String style = "normal"}) {
    setState(() {
      _logs.insert(0, {
        "status": status,
        "message": message,
        "time": DateFormat.Hms().format(DateTime.now()),
        "style": style,
      });
    });
    _saveData();
  }

  // --- DOWNLOAD ENCRYPTED FILE ---
  Future<void> _downloadEncryptedFile() async {
    try {
      final String activePassword =
          _passwordController.text.trim().isNotEmpty
              ? _passwordController.text.trim()
              : _currentPassword;

      final String rawJson = json.encode(_accounts);
      final String encryptedOutput =
          SecureVault.pack(rawJson, activePassword);
      final String fileContent = '$activePassword\n$encryptedOutput';

      if (!Platform.isAndroid) {
        if (_webhookEnabled) {
          _addLog("Error", "Download only supported on Android");
        }
        return;
      }

      var permission = await Permission.manageExternalStorage.status;
      if (!permission.isGranted) {
        permission = await Permission.manageExternalStorage.request();
      }

      Directory saveDir;
      if (permission.isGranted) {
        saveDir = Directory('/storage/emulated/0/Download/insta_saver');
      } else {
        final Directory? privateDir = await getDownloadsDirectory();
        if (privateDir == null) {
          if (_webhookEnabled) {
            _addLog("Error", "Cannot access Downloads directory");
          }
          return;
        }
        saveDir = Directory('${privateDir.path}/insta_saver');
      }

      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final File saveFile = File('${saveDir.path}/$_jsonFilename');
      await saveFile.writeAsString(fileContent);

      if (_webhookEnabled) {
        _addLog("System", "File saved to ${saveFile.path}");
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Downloaded to ${saveFile.path}"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (_webhookEnabled) {
        _addLog("Error", "Download failed: $e");
      }
    }
  }

  // --- ENCRYPTED IMPORT ---
  Future<void> _importFromFile() async {
    if (!Platform.isAndroid) return;

    try {
      var permission = await Permission.manageExternalStorage.status;
      if (!permission.isGranted) {
        permission = await Permission.manageExternalStorage.request();
      }

      Directory saveDir;
      if (permission.isGranted) {
        saveDir = Directory('/storage/emulated/0/Download/insta_saver');
      } else {
        final Directory? privateDir = await getDownloadsDirectory();
        if (privateDir == null) return;
        saveDir = Directory('${privateDir.path}/insta_saver');
      }

      final File file = File('${saveDir.path}/$_jsonFilename');

      if (!await file.exists()) {
        if (_webhookEnabled) {
          _addLog("Error", "No backup file found at ${file.path}");
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No backup file found at ${file.path}"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      String fileContent = await file.readAsString();
      final int newlineIdx = fileContent.indexOf('\n');
      String encryptedContent;
      String filePassword;

      if (newlineIdx != -1) {
        filePassword = fileContent.substring(0, newlineIdx).trim();
        encryptedContent = fileContent.substring(newlineIdx + 1).trim();
      } else {
        filePassword = _passwordController.text.trim().isNotEmpty
            ? _passwordController.text.trim()
            : _currentPassword;
        encryptedContent = fileContent;
      }

      String decryptedJson =
          SecureVault.unpack(encryptedContent, filePassword);

      if (decryptedJson.startsWith("ERROR:")) {
        if (_webhookEnabled) {
          _addLog(
              "Error", "Decryption Failed: Wrong password or tampered file");
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Import Failed: Wrong Password?"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final List<dynamic> decoded = json.decode(decryptedJson);
      setState(() {
        _accounts =
            decoded.map((e) => Map<String, String>.from(e)).toList();
      });

      await _saveData();
      if (_webhookEnabled) {
        _addLog(
            "Success", "Imported ${_accounts.length} accounts from secure backup");
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Imported ${_accounts.length} accounts"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (_webhookEnabled) {
        _addLog("Error", "Import failed: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Account Manager",
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xff111827),
        elevation: 0,
        actions: [
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _serverStatus == "ON"
                    ? Colors.green.withOpacity(0.2)
                    : _serverStatus == "OFF"
                        ? Colors.red.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _serverStatus,
                style: TextStyle(
                  color: _serverStatus == "ON"
                      ? Colors.greenAccent
                      : _serverStatus == "OFF"
                          ? Colors.redAccent
                          : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          _isChecking
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _checkServerStatus,
                  tooltip: "Check Server Status",
                ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildSavedTab(),
          _buildQueuedTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xff111827),
        selectedItemColor: const Color(0xff22c55e),
        unselectedItemColor: const Color(0xff94a3b8),
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home), label: "Home"),
          const BottomNavigationBarItem(
              icon: Icon(Icons.save_alt), label: "Saved"),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.schedule),
                if (_stagedJobs.where((j) {
                  final s = j['status'] ?? '';
                  return s != 'done_ok' && s != 'done_fail' &&
                      s != 'error' && s != 'not_found';
                }).isNotEmpty)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xff3b82f6),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_stagedJobs.where((j) {
                          final s = j['status'] ?? '';
                          return s != 'done_ok' && s != 'done_fail' &&
                              s != 'error' && s != 'not_found';
                        }).length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            label: "Queued",
          ),
          const BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
    );
  }

  // --- TAB 1: HOME ---

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInput("Username", _usernameController, false),
          const SizedBox(height: 15),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Password",
                  style:
                      TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xff0b1220),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Color(0xff1f2937)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                      ),
                    ),
                  ),
                  // Copy & Change buttons only shown when auto random password is ON
                  if (_autoRandomPassword) ...[
                    const SizedBox(width: 5),
                    _buildSmallBtn("Copy", _copyPassword),
                    const SizedBox(width: 5),
                    _buildSmallBtn("Change", _generatePassword),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),

          _buildInput("Cookies", _cookiesController, false),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _buildHoverButton(
                  label: "Clear Inputs",
                  isOutlined: true,
                  onPressed: () {
                    _usernameController.clear();
                    _cookiesController.clear();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _buildHoverButton(
                  label: _webhookEnabled ? "Convert & Push" : "Save",
                  isOutlined: false,
                  onPressed: _webhookEnabled ? _submitData : _saveAccount,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Logs Section - Only show if webhook is enabled
          if (_webhookEnabled) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Logs",
                    style: TextStyle(
                        color: Color(0xff94a3b8),
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    setState(() => _logs.clear());
                    _saveData();
                  },
                  child: const Text("Clear Logs",
                      style:
                          TextStyle(fontSize: 12, color: Colors.red)),
                )
              ],
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: const Color(0xff0b1220),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xff1f2937)),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text("No logs yet",
                          style: TextStyle(
                              color: Color(0xff475569), fontSize: 12)))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        final isError = log['status'] == "Error" ||
                            log['status'] == "Warning";
                        final isWebhook = log['status'] == "Webhook";
                        final isBold = log['style'] == "bold";

                        Color logColor;
                        if (isError) {
                          logColor = Colors.redAccent;
                        } else if (isWebhook) {
                          logColor = Colors.cyanAccent;
                        } else {
                          logColor = Colors.greenAccent;
                        }

                        FontWeight fontWeight =
                            isBold ? FontWeight.bold : FontWeight.normal;

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                          leading: Text(
                            log['time'],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Color(0xff94a3b8),
                            ),
                          ),
                          title: Text(
                            "${log['status']}: ${log['message']}",
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: logColor,
                              fontWeight: fontWeight,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],

          const SizedBox(height: 30),

          // Saved Card (shown after clicking Save) - Only show if webhook is disabled
          if (!_webhookEnabled && _lastSavedEntry != null)
            _buildSavedCard(_lastSavedEntry!),
        ],
      ),
    );
  }

  /// Card shown after saving — username | password | cookies + copy button
  Widget _buildSavedCard(Map<String, String> entry) {
    final username = entry['username'] ?? '';
    final password = entry['password'] ?? '';
    final cookies = entry['auth_code'] ?? '';
    final cardText = "$username|$password|$cookies";

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xff22c55e).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: Color(0xff22c55e), size: 16),
              const SizedBox(width: 6),
              const Text(
                "Saved",
                style: TextStyle(
                  color: Color(0xff22c55e),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _buildHoverIconButton(
                icon: Icons.copy,
                color: const Color(0xff94a3b8),
                tooltip: "Copy username|password|cookies",
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cardText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Copied to clipboard"),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              _buildHoverIconButton(
                icon: Icons.close,
                color: Colors.red,
                tooltip: "Dismiss",
                onPressed: () => setState(() => _lastSavedEntry = null),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildCardRow(Icons.person, "Username", username),
          const SizedBox(height: 6),
          _buildCardRow(Icons.lock, "Password", password),
          const SizedBox(height: 6),
          _buildCardRow(Icons.cookie, "Cookies",
              cookies.isEmpty ? "\u2014" : cookies,
              truncate: true),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _buildHoverButton(
              label: "Copy  username|password|cookies",
              isOutlined: true,
              icon: Icons.copy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: cardText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Copied to clipboard"),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardRow(IconData icon, String label, String value,
      {bool truncate = false}) {
    final display = (truncate && value.length > 40)
        ? '${value.substring(0, 40)}\u2026'
        : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xff94a3b8)),
        const SizedBox(width: 6),
        Text(
          "$label: ",
          style: const TextStyle(
              color: Color(0xff94a3b8), fontSize: 12),
        ),
        Expanded(
          child: Text(
            display,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
      String label, TextEditingController controller, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  /// Small button used next to Password field — with hover effect
  Widget _buildSmallBtn(String text, VoidCallback onTap) {
    return _HoverContainer(
      onTap: onTap,
      defaultColor: const Color(0xff334155),
      hoverColor: const Color(0xff475569),
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  /// Full-width outlined / filled button with hover effect
  Widget _buildHoverButton({
    required String label,
    required bool isOutlined,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    return _HoverContainer(
      onTap: onPressed,
      defaultColor: isOutlined
          ? Colors.transparent
          : const Color(0xff22c55e),
      hoverColor: isOutlined
          ? const Color(0xfff97316).withOpacity(0.12)
          : const Color(0xff16a34a),
      borderRadius: 8,
      border: isOutlined
          ? Border.all(color: const Color(0xfff97316))
          : null,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 15,
                color: isOutlined
                    ? const Color(0xfff97316)
                    : const Color(0xff0b1220)),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: isOutlined
                  ? const Color(0xfff97316)
                  : const Color(0xff0b1220),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Icon button with hover highlight
  Widget _buildHoverIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
    double size = 18,
    double padding = 4,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: _HoverContainer(
        onTap: onPressed,
        defaultColor: Colors.transparent,
        hoverColor: color.withOpacity(0.18),
        borderRadius: 8,
        padding: EdgeInsets.all(padding),
        child: Icon(icon, color: color, size: size),
      ),
    );
  }

  /// Dialog action button with hover effect
  Widget _buildDialogBtn(String label, Color textColor, VoidCallback onTap) {
    return _HoverContainer(
      onTap: onTap,
      defaultColor: Colors.transparent,
      hoverColor: textColor.withOpacity(0.12),
      borderRadius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  // --- TAB 2: SAVED ---

  Widget _buildSavedTab() {
    final Map<String, int> usernameCounts = {};
    for (var acc in _accounts) {
      final user = acc['username'] ?? "";
      if (user.isNotEmpty) {
        usernameCounts[user] = (usernameCounts[user] ?? 0) + 1;
      }
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xff111827),
            border: Border(bottom: BorderSide(color: Color(0xff1f2937))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Saved Accounts: ${_accounts.length}",
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              Row(
                children: [
                  _buildHoverIconButton(
                    icon: Icons.download,
                    color: const Color(0xff22c55e),
                    tooltip: "Download Backup",
                    onPressed: _downloadEncryptedFile,
                    size: 24,
                    padding: 8,
                  ),
                  const SizedBox(width: 8),
                  _buildHoverIconButton(
                    icon: Icons.delete_sweep,
                    color: Colors.red,
                    tooltip: "Clear All Accounts",
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xff1f2937),
                          title: const Text("Delete All Accounts",
                              style: TextStyle(color: Colors.white)),
                          content: const Text(
                            "Are you sure you want to delete ALL saved accounts?",
                            style: TextStyle(color: Color(0xffe5e7eb)),
                          ),
                          actions: [
                            _buildDialogBtn("Cancel", const Color(0xff94a3b8),
                                () => Navigator.pop(context, false)),
                            _buildDialogBtn("Delete All", Colors.redAccent,
                                () => Navigator.pop(context, true)),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        setState(() => _accounts.clear());
                        _saveData();
                        if (_webhookEnabled) {
                          _addLog("System", "All accounts cleared");
                        }
                      }
                    },
                    size: 24,
                    padding: 8,
                  ),
                ],
              ),
            ],
          ),
        ),
        // Accounts list — full Expanded so it scrolls properly
        Expanded(
          child: _accounts.isEmpty
              ? const Center(
                  child: Text("No saved accounts",
                      style: TextStyle(color: Color(0xff475569))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _accounts.length,
                  itemBuilder: (context, index) {
                    final acc = _accounts[index];
                    final currentUsername = acc['username'] ?? "";
                    final bool isDuplicate =
                        (usernameCounts[currentUsername] ?? 0) > 1;
                    final Color cardColor = isDuplicate
                        ? const Color(0xff7f1d1d)
                        : const Color(0xff1f2937);

                    final username = acc['username'] ?? '';
                    final password = acc['password'] ?? '';
                    final cookies = acc['auth_code'] ?? '';
                    final copyText = "$username|$password|$cookies";

                    return Card(
                      color: cardColor,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      if (isDuplicate)
                                        const Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.orangeAccent,
                                            size: 18),
                                      if (isDuplicate)
                                        const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          currentUsername,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    _buildHoverIconButton(
                                      icon: Icons.copy,
                                      color: const Color(0xff94a3b8),
                                      tooltip: "Copy username|password|cookies",
                                      onPressed: () {
                                        Clipboard.setData(
                                            ClipboardData(text: copyText));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                          content: Text("Copied to clipboard"),
                                          backgroundColor: Colors.green,
                                          duration: Duration(seconds: 1),
                                        ));
                                      },
                                    ),
                                    _buildHoverIconButton(
                                      icon: Icons.close,
                                      color: Colors.red,
                                      tooltip: "Delete",
                                      onPressed: () async {
                                        final confirm =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor:
                                                const Color(0xff1f2937),
                                            title: const Text("Delete Account",
                                                style: TextStyle(
                                                    color: Colors.white)),
                                            content: const Text("Are you sure?",
                                                style: TextStyle(
                                                    color:
                                                        Color(0xffe5e7eb))),
                                            actions: [
                                              _buildDialogBtn(
                                                  "Cancel",
                                                  const Color(0xff94a3b8),
                                                  () => Navigator.pop(
                                                      context, false)),
                                              _buildDialogBtn(
                                                  "Delete",
                                                  Colors.redAccent,
                                                  () => Navigator.pop(
                                                      context, true)),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          setState(() =>
                                              _accounts.removeAt(index));
                                          _saveData();
                                          if (_webhookEnabled) {
                                            _addLog("System",
                                                "Account deleted");
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text("Password: $password",
                                style: const TextStyle(
                                    color: Color(0xff94a3b8), fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              "Cookies: ${cookies.isEmpty ? 'None' : '${cookies.substring(0, cookies.length < 30 ? cookies.length : 30)}...'}",
                              style: const TextStyle(
                                  color: Color(0xff94a3b8), fontSize: 11),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: _buildHoverButton(
                                label: "Copy  $username|$password|...",
                                isOutlined: true,
                                icon: Icons.copy,
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: copyText));
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content: Text("Copied to clipboard"),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 1),
                                  ));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- TAB 3: QUEUED ---

  Widget _buildQueuedTab() {
    final int pendingCount = _stagedJobs
        .where((j) {
          final s = j['status'] ?? '';
          return s != 'done_ok' && s != 'done_fail' &&
              s != 'error' && s != 'not_found';
        })
        .length;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xff111827),
            border: Border(bottom: BorderSide(color: Color(0xff1f2937))),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, color: Color(0xff3b82f6), size: 16),
              const SizedBox(width: 8),
              Text(
                "Queued Jobs: ${_stagedJobs.length}"
                "${pendingCount > 0 ? '  ($pendingCount pending)' : ''}",
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const Spacer(),
              // Check all pending
              if (pendingCount > 0)
                _buildHoverIconButton(
                  icon: Icons.sync,
                  color: const Color(0xff3b82f6),
                  tooltip: "Check All Pending ($pendingCount)",
                  onPressed: _checkAllStagedJobs,
                  size: 22,
                  padding: 8,
                ),
              if (pendingCount > 0) const SizedBox(width: 4),
              // Clear completed/expired
              if (_stagedJobs.any((j) {
                final s = j['status'] ?? '';
                return s == 'done_ok' || s == 'done_fail' ||
                    s == 'error' || s == 'not_found';
              }))
                _buildHoverIconButton(
                  icon: Icons.cleaning_services,
                  color: const Color(0xff475569),
                  tooltip: "Clear Done/Expired",
                  onPressed: () {
                    setState(() {
                      _stagedJobs.removeWhere((j) {
                        final s = j['status'] ?? '';
                        return s == 'done_ok' || s == 'done_fail' ||
                            s == 'error' || s == 'not_found';
                      });
                    });
                    _saveData();
                  },
                  size: 22,
                  padding: 8,
                ),
              if (_stagedJobs.isNotEmpty) const SizedBox(width: 4),
              // Clear ALL queued jobs
              if (_stagedJobs.isNotEmpty)
                _buildHoverIconButton(
                  icon: Icons.delete_sweep,
                  color: Colors.red,
                  tooltip: "Clear All Queued",
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xff1f2937),
                        title: const Text("Clear All Queued Jobs",
                            style: TextStyle(color: Colors.white)),
                        content: const Text(
                          "Remove all queued jobs from the list?",
                          style: TextStyle(color: Color(0xffe5e7eb)),
                        ),
                        actions: [
                          _buildDialogBtn("Cancel", const Color(0xff94a3b8),
                              () => Navigator.pop(context, false)),
                          _buildDialogBtn("Clear All", Colors.redAccent,
                              () => Navigator.pop(context, true)),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      setState(() => _stagedJobs.clear());
                      _saveData();
                    }
                  },
                  size: 22,
                  padding: 8,
                ),
            ],
          ),
        ),
        // Full scrollable list of staged jobs
        Expanded(
          child: _stagedJobs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule,
                          color: Color(0xff334155), size: 48),
                      SizedBox(height: 12),
                      Text("No queued jobs",
                          style: TextStyle(
                              color: Color(0xff475569), fontSize: 14)),
                      SizedBox(height: 4),
                      Text("Jobs submitted via Webhook 2 appear here",
                          style: TextStyle(
                              color: Color(0xff334155), fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _stagedJobs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xff1f2937)),
                  itemBuilder: (context, index) =>
                      _buildStagedJobTile(index),
                ),
        ),
      ],
    );
  }



  // ─────────────────────────────────────────────────────────────────────────────
  // Staged Job Tile
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStagedJobTile(int index) {
    final job = _stagedJobs[index];
    final String jobId = job['job_id'] ?? '';
    final String username = job['username'] ?? '';
    final String submittedAt = job['submitted_at'] ?? '';
    final String status = job['status'] ?? 'staging';
    final bool isChecking = _checkingJobs.contains(jobId);

    // Status visuals
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case 'done_ok':
        {
          statusColor = const Color(0xff22c55e);
          statusIcon = Icons.check_circle;
          final int s = (job['success'] ?? 0) as int;
          final int f = (job['failed'] ?? 0) as int;
          statusLabel = "\u2714 $s | \u2717 $f";
          break;
        }
      case 'done_fail':
        {
          statusColor = Colors.redAccent;
          statusIcon = Icons.cancel;
          final int s = (job['success'] ?? 0) as int;
          final int f = (job['failed'] ?? 0) as int;
          statusLabel = "\u2714 $s | \u2717 $f";
          break;
        }
      case 'error':
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_outline;
        statusLabel = "error";
        break;
      case 'not_found':
        statusColor = const Color(0xff6b7280);
        statusIcon = Icons.cloud_off;
        statusLabel = "job expired";
        break;
      case 'processing':
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.hourglass_top;
        statusLabel = "processing";
        break;
      case 'pending':
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.hourglass_empty;
        statusLabel = "pending";
        break;
      default:
        {
          // staging
          statusColor = const Color(0xff3b82f6);
          statusIcon = Icons.schedule;
          final int releaseIn = (job['release_in_seconds'] ?? 0) as int;
          statusLabel =
              releaseIn > 0 ? "~${(releaseIn / 60).ceil()}m left" : "staging";
          break;
        }
    }

    final bool isDone = status == 'done_ok' || status == 'done_fail' ||
        status == 'error' || status == 'not_found';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Status icon
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 8),
          // Username + job info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username.isNotEmpty ? username : jobId,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  "$submittedAt  \u2022  $statusLabel",
                  style: TextStyle(color: statusColor, fontSize: 11),
                ),
              ],
            ),
          ),
          // Action buttons
          if (!isDone)
            isChecking
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xff3b82f6)))
                : _buildHoverIconButton(
                    icon: Icons.refresh,
                    color: const Color(0xff3b82f6),
                    tooltip: "Check this job",
                    size: 18,
                    padding: 4,
                    onPressed: () => _checkSingleStagedJob(index),
                  ),
          const SizedBox(width: 4),
          _buildHoverIconButton(
            icon: Icons.close,
            color: const Color(0xff475569),
            tooltip: "Remove",
            size: 16,
            padding: 4,
            onPressed: () {
              setState(() => _stagedJobs.removeAt(index));
              _saveData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FCM Device Token
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff1f2937)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("FCM Device Token",
                        style: TextStyle(
                            color: Color(0xff94a3b8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    _buildHoverIconButton(
                      icon: Icons.copy,
                      color: const Color(0xff94a3b8),
                      tooltip: "Copy token",
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _fcmToken));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Token copied to clipboard"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _fcmToken,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Auto Random Password Toggle ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff1f2937)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Auto Random Password",
                          style: TextStyle(
                              color: Color(0xff94a3b8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        _autoRandomPassword
                            ? "Copy & Change buttons shown in Home"
                            : "Manual password entry — no auto buttons",
                        style: const TextStyle(
                            color: Color(0xff475569), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _autoRandomPassword,
                  onChanged: (value) {
                    setState(() {
                      _autoRandomPassword = value;
                    });
                    _saveData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? "Auto password enabled"
                              : "Auto password disabled — enter manually",
                        ),
                        backgroundColor:
                            value ? Colors.green : Colors.orange,
                      ),
                    );
                  },
                  activeColor: const Color(0xff22c55e),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Webhook Enabled Toggle ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff111827),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff1f2937)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Webhook Enabled",
                          style: TextStyle(
                              color: Color(0xff94a3b8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        _webhookEnabled
                            ? "Logs will show in Home tab"
                            : "Logs hidden in Home tab",
                        style: const TextStyle(
                            color: Color(0xff475569), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _webhookEnabled,
                  onChanged: (value) {
                    setState(() {
                      _webhookEnabled = value;
                    });
                    _saveData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _webhookEnabled
                              ? "Webhook enabled - Logs visible"
                              : "Webhook disabled - Logs hidden",
                        ),
                        backgroundColor:
                            _webhookEnabled ? Colors.green : Colors.orange,
                      ),
                    );
                  },
                  activeColor: const Color(0xff22c55e),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Active Webhook Selector (only show if webhook is enabled)
          if (_webhookEnabled) ...[
            const Text("Active Webhook",
                style: TextStyle(
                    color: Color(0xff94a3b8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xff111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xff1f2937)),
              ),
              child: Column(
                children: [
                  _buildWebhookRadio(
                    value: 1,
                    label: "Webhook 1 \u2013 Direct System",
                    subtitle: "Parses success/failed counts instantly",
                    color: const Color(0xff22c55e),
                  ),
                  Divider(height: 1, color: const Color(0xff1f2937)),
                  _buildWebhookRadio(
                    value: 2,
                    label: "Webhook 2 \u2013 Job ID System",
                    subtitle: "submitwork.org async job_id API",
                    color: const Color(0xff3b82f6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Webhook 1 URL
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xff22c55e),
                    shape: BoxShape.circle,
                  ),
                ),
                const Text("Webhook 1 URL (Direct)",
                    style: TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _webhook1Controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: _activeWebhook == 1
                    ? const Icon(Icons.check_circle,
                        color: Color(0xff22c55e), size: 18)
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            // Webhook 2 URL
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xff3b82f6),
                    shape: BoxShape.circle,
                  ),
                ),
                const Text("Webhook 2 URL (Job ID)",
                    style: TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _webhook2Controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: _activeWebhook == 2
                    ? const Icon(Icons.check_circle,
                        color: Color(0xff3b82f6), size: 18)
                    : null,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // JSON Filename
          TextField(
            controller: _filenameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: "JSON Filename",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            child: _buildHoverButton(
              label: "Save Settings",
              isOutlined: true,
              onPressed: () {
                setState(() {
                  _webhook1Url = _webhook1Controller.text.trim();
                  _webhook2Url = _webhook2Controller.text.trim();
                  _jsonFilename = _filenameController.text.trim();
                });
                _saveData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Settings Saved"),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildWebhookRadio({
    required int value,
    required String label,
    required String subtitle,
    required Color color,
  }) {
    final bool isSelected = _activeWebhook == value;
    return _HoverContainer(
      onTap: () => setState(() => _activeWebhook = value),
      defaultColor: Colors.transparent,
      hoverColor: color.withOpacity(0.1),
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Radio<int>(
            value: value,
            groupValue: _activeWebhook,
            onChanged: (v) => setState(() => _activeWebhook = v!),
            activeColor: color,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xff94a3b8),
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: Color(0xff475569), fontSize: 11),
                ),
              ],
            ),
          ),
          if (isSelected)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "ACTIVE",
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable hover-aware container widget
// ─────────────────────────────────────────────────────────────────────────────
class _HoverContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color defaultColor;
  final Color hoverColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;

  const _HoverContainer({
    required this.child,
    required this.onTap,
    required this.defaultColor,
    required this.hoverColor,
    required this.borderRadius,
    required this.padding,
    this.border,
  });

  @override
  State<_HoverContainer> createState() => _HoverContainerState();
}

class _HoverContainerState extends State<_HoverContainer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : widget.defaultColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: widget.border,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
