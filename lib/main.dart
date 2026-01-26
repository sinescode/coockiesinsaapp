class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  // Data Models
  List<Map<String, String>> _accounts = [];
  List<Map<String, dynamic>> _logs = [];
  
  // Settings Variables
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
  }

  // --- Data Persistence Logic ---

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Load Settings
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

      // Load Accounts
      String? accountsStr = prefs.getString('accounts_list');
      if (accountsStr != null && accountsStr.isNotEmpty) {
        try {
          final List<dynamic> decoded = json.decode(accountsStr);
          var loadedList = decoded.map((e) => Map<String, String>.from(e)).toList();
          
          // --- FIXED: Removed .reversed.toList() ---
          // Since we insert(0) in submitData, the list is already Newest -> Oldest.
          // We just load it as is to maintain that order.
          _accounts = loadedList; 
        } catch (e) {
          _addLog("System", "Error loading saved accounts: $e");
        }
      }

      // Load Logs
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

  Future<void> _submitData() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim(); 
    final cookies = _cookiesController.text.trim();
    
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
      _accounts.insert(0, newEntry); // Keeps Newest at Index 0 (Top)
    });

    String convertedStr = "$username:$password|||$cookies||";
    String payload = "accounts=${base64.encode(utf8.encode(convertedStr))}";

    try {
      final response = await http.post(
        Uri.parse(_webhookUrl),
        headers: {'Content-Type': 'text/plain'},
        body: payload,
      );

      // Parse Webhook Response for Eye-Catching Logs
      String logMessage = "Empty response";
      String logStatus = (response.statusCode >= 200 && response.statusCode < 300) ? "Webhook" : "Error";
      
      if (response.body.isNotEmpty) {
        try {
          dynamic decoded = jsonDecode(response.body);
          
          // Handle if it's wrapped in a list
          if (decoded is List && decoded.isNotEmpty) {
            decoded = decoded[0];
          }

          if (decoded is Map) {
            // Try to find data in 'data' object or root
            dynamic dataNode = decoded['data'] is Map ? decoded['data'] : decoded;
            
            int successCount = dataNode['success_count'] ?? 0;
            int failedCount = dataNode['failed_count'] ?? 0;
            
            // Eye-catching format
            logMessage = " Success: $successCount  | Failed: $failedCount";

            // --- UPDATED LOGIC: Color and Boldness based on counts ---
            String logStyle = "normal";
            if (successCount == 0) {
               logStatus = "Error"; // Triggers Red color
            } else if (failedCount == 0) {
               logStyle = "bold";   // Triggers Bold text
            }
            // ---------------------------------------------------------

            _addLog(logStatus, "(${response.statusCode}) $logMessage", style: logStyle);
          } else {
            logMessage = response.body.trim(); // Fallback
            _addLog(logStatus, "(${response.statusCode}) $logMessage");
          }
        } catch (e) {
          // If parsing fails, just show trimmed body or error
          logMessage = "Invalid JSON response";
          _addLog(logStatus, "(${response.statusCode}) $logMessage");
        }
      } else {
          _addLog(logStatus, "(${response.statusCode}) $logMessage");
      }
      
    } catch (e) {
      _addLog("Error", "Connection error: $e");
    }

    await _saveData();
    
    _usernameController.clear();
    _cookiesController.clear();
    _generatePassword(); 
    
  }

  // --- UPDATED: Added style parameter ---
  void _addLog(String status, String message, {String style = "normal"}) {
    setState(() {
      _logs.insert(0, {
        "status": status,
        "message": message,
        "time": DateFormat.Hms().format(DateTime.now()),
        "style": style, // Store style preference
      });
    });
    _saveData();
  }

  Future<void> _exportToFile() async {
    if (!Platform.isAndroid) {
      _addLog("Error", "Public Downloads export only supported on Android");
      return;
    }

    try {
      var permission = await Permission.manageExternalStorage.status;
      if (!permission.isGranted) {
        permission = await Permission.manageExternalStorage.request();
      }

      Directory saveDir;
      String displayPath;

      if (permission.isGranted) {
        saveDir = Directory('/storage/emulated/0/Download/insta_saver');
        displayPath = '/storage/emulated/0/Download/insta_saver/$_jsonFilename';
      } else {
        final Directory? privateDir = await getDownloadsDirectory();
        if (privateDir == null) {
          _addLog("Error", "Could not access any storage directory");
          return;
        }
        saveDir = Directory('${privateDir.path}/insta_saver');
        displayPath = 'App-private folder: ${saveDir.path}/$_jsonFilename';

        _addLog("Warning", "Permission denied – saved to private folder");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("To save in public Downloads, go to App Settings → Permissions → All files access → Allow"),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 8),
          ),
        );
      }

      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final String filePath = '${saveDir.path}/$_jsonFilename';
      final File file = File(filePath);

      final encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_accounts));

      _addLog("Success", "Exported successfully!");
      _addLog("Info", "Path: $displayPath");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Exported! Check Logs for path"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _addLog("Error", "Export failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Export failed – opening App Settings"),
          backgroundColor: Colors.red,
        ),
      );
      await openAppSettings();
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
                      
                      // Determine Color
                      Color logColor;
                      if (isError) {
                          logColor = Colors.redAccent;
                      } else if (isWebhook) {
                          logColor = Colors.cyanAccent;
                      } else {
                          logColor = Colors.greenAccent;
                      }

                      // Determine Font Weight
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

  // --- TAB 2: SAVED (Includes Duplicate Logic) ---

  Widget _buildSavedTab() {
    // 1. Calculate frequency of each username
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
                    icon: const Icon(Icons.download, color: Color(0xff22c55e)),
                    onPressed: _exportToFile,
                    tooltip: "Export to public Downloads (requires 'All files access')",
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xff1f2937),
                          title: const Text("Delete All Accounts", style: TextStyle(color: Colors.white)),
                          content: const Text("Are you sure you want to delete ALL saved accounts? This cannot be undone.", style: TextStyle(color: Color(0xffe5e7eb))),
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

                    // 2. Check if this username is a duplicate
                    final bool isDuplicate = (usernameCounts[currentUsername] ?? 0) > 1;

                    // 3. Set color based on duplicate status
                    final Color cardColor = isDuplicate 
                        ? const Color(0xff7f1d1d) // Dark Red for duplicates
                        : const Color(0xff1f2937); // Slate for normal

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
                                      // Warning icon if duplicate
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
                                        content: const Text("Are you sure you want to delete this account?", style: TextStyle(color: Color(0xffe5e7eb))),
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