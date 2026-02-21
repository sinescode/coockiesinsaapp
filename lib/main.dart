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
import 'security_module.dart'; // Import the security module

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
          labelStyle: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff22c55e),
            foregroundColor: const Color(0xff0b1220),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xfff97316),
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
  
  // Settings Variables
  String _webhookUrl = "http://43.135.182.151/api/api/v1/webhook/nRlmI2-8T7x2DAWe1hWxi97qGA1FcCxrNcyCtLTO_Cw/account-push";
  String _jsonFilename = "accounts.json";
  String _currentPassword = "";
  
  // Server Status Variables
  String _serverStatus = "Check"; 
  bool _isChecking = false;

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
  }

  // --- Data Persistence Logic ---

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final savedWebhook = prefs.getString('webhook_url');
    final savedFilename = prefs.getString('json_filename');
    final savedPassword = prefs.getString('current_password');

    setState(() {
      if (savedWebhook != null) _webhookUrl = savedWebhook;
      if (savedFilename != null) _jsonFilename = savedFilename;
      _currentPassword = savedPassword ?? ""; 

      _webhookController.text = _webhookUrl;
      _filenameController.text = _jsonFilename;
      _passwordController.text = _currentPassword;

      String? accountsStr = prefs.getString('accounts_list');
      if (accountsStr != null && accountsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(accountsStr);
          _accounts = decoded.map((e) => Map<String, String>.from(e)).toList();
        } catch (e) {
          _addLog("System", "Error loading saved accounts: $e");
        }
      }

      String? logsStr = prefs.getString('logs_list');
      if (logsStr != null && logsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(logsStr);
          _logs = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (e) {
          print("Error loading logs: $e");
        }
      }
    });

    if (_currentPassword.isEmpty) {
      _generatePassword();
    }
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
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
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
    _addLog("System", "Password copied successfully");
  }

  Future<void> _checkServerStatus() async {
    if (_webhookUrl.isEmpty || !_webhookUrl.startsWith("http")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please set a valid Webhook URL in Settings first."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isChecking = true;
      _serverStatus = "Checking...";
    });

    const chars = "abcdefghijklmnopqrstuvwxyz1234567890";
    final random = Random();
    
    String randomUser = List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
    String randomPass = List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();
    String randomCookie = List.generate(10, (index) => chars[random.nextInt(chars.length)]).join();

    String convertedStr = "$randomUser:$randomPass|||$randomCookie||";
    String payload = "accounts=${base64.encode(utf8.encode(convertedStr))}";

    try {
      final response = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'text/plain'},
        body: payload,
      ).timeout(const Duration(seconds: 10));

      if (response.body.isNotEmpty) {
        try {
          dynamic decoded = jsonDecode(response.body);
          if (decoded is List && decoded.isNotEmpty) decoded = decoded[0];

          if (decoded is Map) {
            dynamic dataNode = decoded['data'] is Map ? decoded['data'] : decoded;
            int successCount = dataNode['success_count'] ?? 0;
            int failedCount = dataNode['failed_count'] ?? 0;

            setState(() {
              if (failedCount > 0 && successCount == 0) {
                _serverStatus = "ON"; 
              } else if (failedCount == 0 && successCount == 0) {
                _serverStatus = "OFF"; 
              } else {
                _serverStatus = "ON"; 
              }
            });
          } else {
             setState(() => _serverStatus = "OFF");
          }
        } catch (e) {
          setState(() => _serverStatus = "OFF");
        }
      } else {
        setState(() => _serverStatus = "OFF");
      }

    } catch (e) {
      setState(() => _serverStatus = "OFF");
    } finally {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _submitData() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim(); 
    final cookies = _cookiesController.text.trim();
    
    // Sync _currentPassword with what's shown in the field
    _currentPassword = password;
    _webhookUrl = _webhookController.text.trim();
    _jsonFilename = _filenameController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _addLog("Error", "Username and Password required");
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
    });

    await _saveData();

    String convertedStr = "$username:$password|||$cookies||";
    String payload = "accounts=${base64.encode(utf8.encode(convertedStr))}";

    try {
      final response = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'text/plain'},
        body: payload,
      );

      String logMessage = "Empty response";
      String logStatus = (response.statusCode >= 200 && response.statusCode < 300) ? "Webhook" : "Error";
      
      if (response.body.isNotEmpty) {
        try {
          dynamic decoded = jsonDecode(response.body);
          if (decoded is List && decoded.isNotEmpty) decoded = decoded[0];

          if (decoded is Map) {
            dynamic dataNode = decoded['data'] is Map ? decoded['data'] : decoded;
            int successCount = dataNode['success_count'] ?? 0;
            int failedCount = dataNode['failed_count'] ?? 0;
            
            logMessage = " Success: $successCount  | Failed: $failedCount";

            String logStyle = "normal";
            if (successCount == 0) {
               logStatus = "Error"; 
            } else if (failedCount == 0) {
               logStyle = "bold";   
            }

            _addLog(logStatus, "(${response.statusCode}) $logMessage", style: logStyle);
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
    
    _usernameController.clear();
    _cookiesController.clear();
    _generatePassword(); 
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

  // --- DOWNLOAD ENCRYPTED FILE (password on first line, then encrypted JSON) ---
  Future<void> _downloadEncryptedFile() async {
    try {
      // Use the password currently shown in the field (fixes mismatch)
      final String activePassword = _passwordController.text.trim().isNotEmpty
          ? _passwordController.text.trim()
          : _currentPassword;

      // 1. Prepare data: first line = password, then encrypted JSON
      final String rawJson = json.encode(_accounts);
      final String encryptedOutput = SecureVault.pack(rawJson, activePassword);
      final String fileContent = '$activePassword\n$encryptedOutput';

      // 2. Save to Downloads folder
      if (!Platform.isAndroid) {
        _addLog("Error", "Download only supported on Android");
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
          _addLog("Error", "Cannot access Downloads directory");
          return;
        }
        saveDir = Directory('${privateDir.path}/insta_saver');
      }

      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final File saveFile = File('${saveDir.path}/$_jsonFilename');
      await saveFile.writeAsString(fileContent);

      _addLog("System", "File saved to ${saveFile.path}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Downloaded to ${saveFile.path}"),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      _addLog("Error", "Download failed: $e");
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
        _addLog("Error", "No backup file found at ${file.path}");
        return;
      }

      // 1. Read file content - first line is password, rest is encrypted data
      String fileContent = await file.readAsString();
      final int newlineIdx = fileContent.indexOf('\n');
      String encryptedContent;
      String filePassword;
      if (newlineIdx != -1) {
        filePassword = fileContent.substring(0, newlineIdx).trim();
        encryptedContent = fileContent.substring(newlineIdx + 1).trim();
      } else {
        // Legacy format (no password line) - use current password
        filePassword = _passwordController.text.trim().isNotEmpty
            ? _passwordController.text.trim()
            : _currentPassword;
        encryptedContent = fileContent;
      }

      // 2. Decrypt
      String decryptedJson = SecureVault.unpack(encryptedContent, filePassword);

      if (decryptedJson.startsWith("ERROR:")) {
        _addLog("Error", "Decryption Failed: Wrong password or tampered file");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Import Failed: Wrong Password?"), backgroundColor: Colors.red),
        );
        return;
      }

      // 3. Load Data
      final List<dynamic> decoded = json.decode(decryptedJson);
      setState(() {
        _accounts = decoded.map((e) => Map<String, String>.from(e)).toList();
      });

      await _saveData();
      _addLog("Success", "Imported ${_accounts.length} accounts from secure backup");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Imported ${_accounts.length} accounts"), backgroundColor: Colors.green),
      );

    } catch (e) {
      _addLog("Error", "Import failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Account Manager", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xff111827),
        elevation: 0,
        actions: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _serverStatus == "ON" ? Colors.green.withOpacity(0.2) : 
                       _serverStatus == "OFF" ? Colors.red.withOpacity(0.2) : 
                       Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _serverStatus,
                style: TextStyle(
                  color: _serverStatus == "ON" ? Colors.greenAccent : 
                         _serverStatus == "OFF" ? Colors.redAccent : 
                         Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 12
                ),
              ),
            ),
          ),
          _isChecking 
            ? const Padding(
                padding: EdgeInsets.all(16.0), 
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                      final isError = log['status'] == "Error" || log['status'] == "Warning";
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

                      FontWeight fontWeight = isBold ? FontWeight.bold : FontWeight.normal;

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        leading: Text(
                          log['time'],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10, 
                            color: Color(0xff94a3b8)
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
    final Map<String, int> usernameCounts = {};
    for (var acc in _accounts) {
      final user = acc['username'] ?? "";
      if (user.isNotEmpty) {
        usernameCounts[user] = (usernameCounts[user] ?? 0) + 1;
      }
    }

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
                    icon: const Icon(Icons.file_upload, color: Color(0xff3b82f6)),
                    onPressed: _importFromFile,
                    tooltip: "Import Secure File",
                  ),
                  // --- Download Button ---
                  IconButton(
                    icon: const Icon(Icons.download, color: Color(0xff22c55e)),
                    onPressed: _downloadEncryptedFile,
                    tooltip: "Download Backup",
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xff1f2937),
                          title: const Text("Delete All Accounts", style: TextStyle(color: Colors.white)),
                          content: const Text("Are you sure you want to delete ALL saved accounts?", style: TextStyle(color: Color(0xffe5e7eb))),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel", style: TextStyle(color: Color(0xff94a3b8))),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Delete All", style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        setState(() => _accounts.clear());
                        _saveData();
                        _addLog("System", "All accounts cleared");
                      }
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
                    final currentUsername = acc['username'] ?? "";
                    final bool isDuplicate = (usernameCounts[currentUsername] ?? 0) > 1;
                    final Color cardColor = isDuplicate 
                        ? const Color(0xff7f1d1d) 
                        : const Color(0xff1f2937);

                    return Card(
                      color: cardColor,
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
                                Expanded(
                                  child: Row(
                                    children: [
                                      if (isDuplicate) 
                                        const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                                      if (isDuplicate) const SizedBox(width: 5),
                                      
                                      Flexible(
                                        child: Text(
                                          currentUsername,
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        backgroundColor: const Color(0xff1f2937),
                                        title: const Text("Delete Account", style: TextStyle(color: Colors.white)),
                                        content: const Text("Are you sure?", style: TextStyle(color: Color(0xffe5e7eb))),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text("Cancel", style: TextStyle(color: Color(0xff94a3b8))),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text("Delete", style: TextStyle(color: Colors.redAccent)),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      setState(() => _accounts.removeAt(index));
                                      _saveData();
                                      _addLog("System", "Account deleted");
                                    }
                                  },
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text("Password: ${acc['password']}", style: const TextStyle(color: Color(0xff94a3b8), fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              "Cookies: ${acc['auth_code']?.isEmpty == true ? 'None' : '${acc['auth_code']!.substring(0, acc['auth_code']!.length < 30 ? acc['auth_code']!.length : 30)}...'}",
                              style: const TextStyle(color: Color(0xff94a3b8), fontSize: 11),
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
                  _webhookUrl = _webhookController.text.trim();
                  _jsonFilename = _filenameController.text.trim();
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

