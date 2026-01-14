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

void main() {
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
        primaryColor: const Color(0xff0f172a), // Slate 900
        scaffoldBackgroundColor: const Color(0xff0f172a),
        cardColor: const Color(0xff111827), // Slate 950
        dividerColor: const Color(0xff1f2937),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xffe5e7eb)), // Slate 200
          bodySmall: TextStyle(color: Color(0xff94a3b8)),  // Slate 400
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
          labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff22c55e), // Green 500
            foregroundColor: const Color(0xff0b1220),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xfff97316), // Orange 500
            side: const BorderSide(color: Color(0xfff97316)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
  
  // Settings
  String _webhookUrl = "https://ins.skysysx.com/api/api/v1/webhook/...";
  String _jsonFilename = "accounts.json";
  String _currentPassword = "";
  
  // Input Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _cookiesController = TextEditingController();
  final TextEditingController _webhookController = TextEditingController();
  final TextEditingController _filenameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    if (_currentPassword.isEmpty) {
      _generatePassword();
    } else {
      _passwordController.text = _currentPassword;
    }
  }

  // --- Data Persistence Logic ---

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      _webhookUrl = prefs.getString('webhook_url') ?? _webhookUrl;
      _jsonFilename = prefs.getString('json_filename') ?? _jsonFilename;
      _currentPassword = prefs.getString('current_password') ?? "";
      
      // Load Accounts
      String? accountsStr = prefs.getString('accounts_list');
      if (accountsStr != null) {
        _accounts = List<Map<String, String>>.from(json.decode(accountsStr));
      }

      // Load Logs
      String? logsStr = prefs.getString('logs_list');
      if (logsStr != null) {
        _logs = List<Map<String, dynamic>>.from(json.decode(logsStr));
      }
      
      // Set settings controllers
      _webhookController.text = _webhookUrl;
      _filenameController.text = _jsonFilename;
      _passwordController.text = _currentPassword;
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webhook_url', _webhookUrl);
    await prefs.setString('json_filename', _jsonFilename);
    await prefs.setString('current_password', _currentPassword);
    await prefs.setString('accounts_list', json.encode(_accounts));
    await prefs.setString('logs_list', json.encode(_logs));
  }

  // --- Feature Logic ---

  void _generatePassword() {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    final dateStr = DateFormat('dd').format(DateTime.now()); // Today's Day (e.g., 13)
    final random = Random();
    final length = random.nextInt(5) + 8; // 8 to 12
    final letterCount = length - dateStr.length;

    String result = '';
    for (int i = 0; i < letterCount; i++) {
      result += chars[random.nextInt(chars.length)];
    }
    _currentPassword = result + dateStr;
    _passwordController.text = _currentPassword;
    _saveData();
  }

  void _copyPassword() {
    Clipboard.setData(ClipboardData(text: _currentPassword));
    _addLog("System", "Password copied to clipboard");
  }

  Future<void> _submitData() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final cookies = _cookiesController.text.trim();
    final webhook = _webhookController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _addLog("Error", "Username and Password required");
      return;
    }

    // Update Settings
    _webhookUrl = webhook;
    _jsonFilename = _filenameController.text.trim();
    
    // Create new entry
    final newEntry = {
      "email": "",
      "username": username,
      "password": password,
      "auth_code": cookies,
    };

    // Save to Local Storage (Accounts List)
    setState(() {
      _accounts.add(newEntry);
    });

    // Prepare Webhook Payload (Base64)
    String convertedStr = "$username:$password|||$cookies||";
    String payload = "accounts=${base64.encode(utf8.encode(convertedStr))}";

    // Send Request
    try {
      final response = await http.post(
        Uri.parse(webhook),
        headers: {'Content-Type': 'text/plain'},
        body: payload,
      );

      if (response.statusCode == 200) {
        _addLog("Success", "Webhook response: ${response.body}");
      } else {
        _addLog("Error", "Webhook failed: ${response.statusCode}");
      }
    } catch (e) {
      _addLog("Error", "Connection error: $e");
    }

    // Save everything and Reset Inputs
    await _saveData();
    _usernameController.clear();
    _cookiesController.clear();
    _generatePassword(); // Change password for next use
  }

  void _addLog(String status, String message) {
    setState(() {
      _logs.insert(0, {
        "status": status,
        "message": message,
        "time": DateFormat.Hms().format(DateTime.now())
      });
    });
    _saveData();
  }

  Future<void> _exportToFile() async {
    // Request Permission for Android 10+ (Scoped Storage)
    // Note: Writing to /Download directly requires MANAGE_EXTERNAL_STORAGE on newer Androids
    // or using the Storage Access Framework. For this example, we try standard Downloads.
    
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      _addLog("Error", "Storage permission denied");
      return;
    }

    try {
      Directory? directory;
      if (Platform.isAndroid) {
        // Try to get the Downloads directory
        directory = Directory('/storage/emulated/0/Download/insta_saver');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory != null) {
        final path = "${directory.path}/$_jsonFilename";
        final file = File(path);
        await file.writeAsString(json.encode(_accounts, toEncodable: (e) => e.toString()));
        
        _addLog("Success", "Exported to: $path");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved to Download/insta_saver"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      _addLog("Error", "Export failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Account Manager", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xff111827),
        elevation: 0,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildSavedTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xff111827),
        selectedItemColor: const Color(0xff22c55e),
        unselectedItemColor: const Color(0xff94a3b8),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.save_alt), label: "Saved"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
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
          
          // Password Input with Actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Password", style: TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
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
                          borderSide: const BorderSide(color: Color(0xff1f2937)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  _buildSmallBtn("Copy", _copyPassword),
                  const SizedBox(width: 5),
                  _buildSmallBtn("Change", _generatePassword),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          
          _buildInput("Cookies", _cookiesController, false),
          const SizedBox(height: 20),
          
          // Action Buttons Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _usernameController.clear();
                    _cookiesController.clear();
                  },
                  child: const Text("Clear Inputs"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _submitData,
                  child: const Text("Convert & Push"),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 30),
          
          // Logs Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Logs", style: TextStyle(color: Color(0xff94a3b8), fontSize: 14, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () {
                  setState(() => _logs.clear());
                  _saveData();
                }, 
                child: const Text("Clear Logs", style: TextStyle(fontSize: 12, color: Colors.red))
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
                ? const Center(child: Text("No logs yet", style: TextStyle(color: Color(0xff475569), fontSize: 12)))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final isError = log['status'] == "Error";
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        leading: Text(
                          log['time'],
                          style: const TextStyle(fontSize: 10, color: Color(0xff94a3b8)),
                        ),
                        title: Text(
                          "${log['status']}: ${log['message']}",
                          style: TextStyle(fontSize: 12, color: isError ? Colors.redAccent : Colors.greenAccent),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, bool obscure) {
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

  Widget _buildSmallBtn(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xff334155),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  // --- TAB 2: SAVED ---

  Widget _buildSavedTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xff111827),
            border: Border(bottom: BorderSide(color: Color(0xff1f2937)))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Saved Accounts: ${_accounts.length}", style: const TextStyle(color: Colors.white)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.download, color: Color(0xff22c55e)),
                    onPressed: _exportToFile,
                    tooltip: "Download to Download/insta_saver",
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    onPressed: () {
                      setState(() => _accounts.clear());
                      _saveData();
                    },
                    tooltip: "Clear All",
                  ),
                ],
              )
            ],
          ),
        ),
        Expanded(
          child: _accounts.isEmpty
              ? const Center(child: Text("No saved accounts", style: TextStyle(color: Color(0xff475569))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _accounts.length,
                  itemBuilder: (context, index) {
                    final acc = _accounts[index];
                    return Card(
                      color: const Color(0xff1f2937),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(acc['username'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                  onPressed: () {
                                    setState(() => _accounts.removeAt(index));
                                    _saveData();
                                  },
                                )
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text("Pass: ${acc['password']}", style: const TextStyle(color: Color(0xff94a3b8), fontSize: 12)),
                            const SizedBox(height: 2),
                            Text("Cookies: ${acc['auth_code']?.substring(0, 20)}...", style: const TextStyle(color: Color(0xff94a3b8), fontSize: 10)),
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

  // --- TAB 3: SETTINGS ---

  Widget _buildSettingsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            controller: _webhookController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: "Webhook URL",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
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
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _webhookUrl = _webhookController.text;
                  _jsonFilename = _filenameController.text;
                  _currentPassword = _passwordController.text;
                });
                _saveData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Settings Saved"), backgroundColor: Colors.green)
                );
              },
              child: const Text("Save Settings"),
            ),
          )
        ],
      ),
    );
  }
}