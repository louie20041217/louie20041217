import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'dart:developer' as devtools;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

// Detection History Item Model
class DetectionItem {
  final String imagePath;
  final String label;
  final double confidence;
  final DateTime timestamp;
  final bool isUnknown;

  DetectionItem({
    required this.imagePath,
    required this.label,
    required this.confidence,
    required this.timestamp,
    this.isUnknown = false,
  });
}

// Global list para sa history
List<DetectionItem> detectionHistory = [];

// All available flag classes - matching labels.txt format (10 flags)
final List<String> allFlagClasses = [
  'philippines flag',
  'thailand flag',
  'vietnam flag',
  'singapore flag',
  'malaysia flag',
  'myanmar flag',
  'laos flag',
  'indonesia flag',
  'cambodia flag',
  // Note: model label is spelled "brunie flag", but we display "Brunei"
  'brunie flag',
];

// Display names for flags
final Map<String, String> flagDisplayNames = {
  'philippines flag': 'Philippines',
  'thailand flag': 'Thailand',
  'vietnam flag': 'Vietnam',
  'singapore flag': 'Singapore',
  'malaysia flag': 'Malaysia',
  'myanmar flag': 'Myanmar',
  'laos flag': 'Laos',
  'indonesia flag': 'Indonesia',
  'cambodia flag': 'Cambodia',
  'brunie flag': 'Brunei',
};

// Reverse map from nice display name -> canonical flag key
// e.g. "brunei" -> "brunie flag"
final Map<String, String> displayNameToFlagKey = {
  for (final entry in flagDisplayNames.entries)
    entry.value.toLowerCase(): entry.key.toLowerCase(),
};

/// Normalize raw model label like "4 malaysia flag" into a clean display name
/// like "Malaysia" (no numeric prefix, nice casing).
String _normalizeFlagLabel(String rawLabel) {
  String label = rawLabel.trim().toLowerCase();

  // Try to remove leading index such as "4 malaysia flag"
  label = label.replaceFirst(RegExp(r'^\d+[\s\.\-]*'), '');

  // If it directly matches any known key, map to display value
  if (flagDisplayNames.containsKey(label)) {
    return flagDisplayNames[label]!;
  }

  // Remove generic "flag" word at the end
  label = label.replaceAll(RegExp(r'\s*flag$'), '').trim();

  if (label.isEmpty) return rawLabel;

  // Title case words
  final words = label.split(RegExp(r'\s+'));
  final titleCased = words
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  return titleCased;
}

// Flag Statistics Model
class FlagStats {
  final String name;
  final int totalScans;
  final double totalAccuracy;

  FlagStats({
    required this.name,
    required this.totalScans,
    required this.totalAccuracy,
  });

  double get averageAccuracy => totalScans > 0 ? totalAccuracy / totalScans : 0.0;
  
  String get shortName {
    if (name.length > 12) {
      return name.substring(0, 12) + '...';
    }
    return name;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flag Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFEF4444), // accent red
          secondary: Color(0xFFF97316), // warm orange
          surface: Color(0xFF020617),
          background: Color(0xFF020617),
        ),
        scaffoldBackgroundColor: const Color(0xFF020617),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
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

  void _onHistoryUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      MyHomePage(
        onHistoryUpdate: _onHistoryUpdate,
        onOpenHistoryTab: () {
          setState(() {
            _currentIndex = 1;
          });
        },
      ),
      HistoryPage(key: ValueKey(detectionHistory.length)),
      const AboutPage(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFFF97373), // light red for active item
          unselectedItemColor: Colors.grey[400],
          elevation: 0,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Archive',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.info_outline),
              activeIcon: Icon(Icons.info),
              label: 'Info',
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final VoidCallback onHistoryUpdate;
  final VoidCallback onOpenHistoryTab;

  const MyHomePage({
    super.key,
    required this.onHistoryUpdate,
    required this.onOpenHistoryTab,
  });

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {
  File? filePath;
  String label = '';
  double confidence = 0.0;
  bool isLoading = false;
  bool isUnknown = false;
  List<Map<String, dynamic>> allPredictions = []; // Store all predictions
  late AnimationController _animationController;
  late final PageController _flagPageController;
  Timer? _flagTimer;
  int _flagPageCount = 0;

  @override
  void initState() {
    super.initState();
    _tfLteInit();
    _flagPageController = PageController(viewportFraction: 0.7);
    _flagPageCount = _listFlagAssets().length;
    if (_flagPageCount > 1) {
      _startFlagAutoScroll();
    }
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _flagTimer?.cancel();
    _flagPageController.dispose();
    _animationController.dispose();
    Tflite.close();
    super.dispose();
  }

  Future<void> _tfLteInit() async {
    try {
      String? res = await Tflite.loadModel(
          model: "assets/model_unquant.tflite",
          labels: "assets/labels.txt",
          numThreads: 1,
          isAsset: true,
          useGpuDelegate: false);
      devtools.log("Model loaded: $res");
    } catch (e) {
      devtools.log("Error loading model: $e");
    }
  }

  Future<void> _addToHistory(
      String imagePath, String detectedLabel, double conf, bool unknown) async {
    // Clean up label so it doesn't include the numeric prefix from the model
    final String normalizedLabel = _normalizeFlagLabel(detectedLabel);

    // Add to local history first
    final item = DetectionItem(
      imagePath: imagePath,
      label: normalizedLabel,
      confidence: conf,
      timestamp: DateTime.now(),
      isUnknown: unknown,
    );

    detectionHistory.insert(0, item);
    widget.onHistoryUpdate();

    // Persist to Firestore using the collection and field names shown in your screenshot
    try {
      devtools.log('Attempting to save to Firestore...');
      devtools.log('Raw label: $detectedLabel, Normalized: $normalizedLabel, Confidence: $conf');
      
      final col = FirebaseFirestore.instance.collection('Sanrojo_SoutheastFlag');
      final docRef = await col.add({
        // Store nice display label without the numeric prefix
        'Class_type': normalizedLabel.isEmpty ? 'Unknown' : normalizedLabel,
        'Accuracy_rate': conf.round(), // Convert to int to match screenshot format
        'time': FieldValue.serverTimestamp(),
        'imagePath': imagePath,
      });
      
      devtools.log('Successfully saved to Firestore! Document ID: ${docRef.id}');
      
      // Show success message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.white),
                SizedBox(width: 8),
                Text('Data saved to Firebase successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, stackTrace) {
      devtools.log('Failed to write detection to Firestore: $e');
      devtools.log('Stack trace: $stackTrace');
      
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Failed to save to Firebase: ${e.toString()}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _processImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);

      if (image == null) return;

      var imageMap = File(image.path);

      setState(() {
        filePath = imageMap;
        isLoading = true;
        label = '';
        confidence = 0.0;
        isUnknown = false;
        allPredictions = []; // Clear previous predictions
      });

      var recognitions = await Tflite.runModelOnImage(
          path: image.path,
          imageMean: 0.0,
          imageStd: 255.0,
          numResults: 10, // Get all 10 flag predictions
          threshold: 0.0, // Lower threshold to get all predictions
          asynch: true);

      if (recognitions == null || recognitions.isEmpty) {
        devtools.log("recognitions is Null or Empty");
        setState(() {
          isLoading = false;
          label = 'UNIDENTIFIED OBJECT';
          isUnknown = true;
          confidence = 0.0;
        });
        _addToHistory(image.path, 'Unknown - Not in Database', 0.0, true);
        return;
      }

      devtools.log(recognitions.toString());

      // Store all predictions
      List<Map<String, dynamic>> predictions = [];
      for (var recognition in recognitions) {
        predictions.add({
          'label': recognition['label'].toString(),
          'confidence': (recognition['confidence'] * 100),
        });
      }
      // Sort by confidence (highest first)
      predictions.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));

      double detectedConfidence = predictions[0]['confidence'] as double;
      if (detectedConfidence < 30) {
        setState(() {
          confidence = detectedConfidence;
          label = 'LOW CONFIDENCE DETECTION';
          isUnknown = true;
          isLoading = false;
          allPredictions = predictions;
        });
        _addToHistory(
            image.path, 'Unknown - Low Confidence', detectedConfidence, true);
        // Show prediction distribution modal automatically
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted) {
            _showPredictionDistributionModal(context);
          }
        });
      } else {
        String detectedLabel = predictions[0]['label'].toString();
        final String normalizedLabel = _normalizeFlagLabel(detectedLabel);
        setState(() {
          confidence = detectedConfidence;
          // Show cleaned label (without leading number) in the UI
          label = normalizedLabel.toUpperCase();
          isUnknown = false;
          isLoading = false;
          allPredictions = predictions;
        });
        _addToHistory(image.path, normalizedLabel, detectedConfidence, false);
        // Show prediction distribution modal automatically
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.mounted) {
            _showPredictionDistributionModal(context);
          }
        });
      }
    } catch (e) {
      devtools.log("Error processing image: $e");
      setState(() {
        isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFFDC2626); // deep red
    const Color secondaryColor = Color(0xFFF97316); // warm orange-red
    const Color accentColor = Color(0xFFF97373); // light red accent
    const Color darkText = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage('assets/flag/bg.jpg'),
            fit: BoxFit.cover,
          ),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF0F172A).withOpacity(0.92),
              const Color(0xFF020617).withOpacity(0.98),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.flag_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Flag Detector',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Scan ASEAN flags in seconds with AI recognition.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Main content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    children: [
                      _buildScanCard(primaryColor, secondaryColor, accentColor),
                      const SizedBox(height: 24),
                      // Elevated glass panel for main actions
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.14),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 30,
                              offset: const Offset(0, 22),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        child: Column(
                          children: [
                            _buildLargeActionCard(
                              color: primaryColor,
                              icon: Icons.camera_alt_rounded,
                              title: 'Camera',
                              subtitle: 'Take a photo to detect flags',
                              onTap: () => _processImage(ImageSource.camera),
                            ),
                            const SizedBox(height: 14),
                            _buildLargeActionCard(
                              color: const Color(0xFF4B5563),
                              icon: Icons.photo_library_rounded,
                              title: 'Gallery',
                              subtitle: 'Pick an image from your gallery',
                              onTap: () => _processImage(ImageSource.gallery),
                            ),
                            const SizedBox(height: 14),
                            _buildLargeActionCard(
                              color: secondaryColor,
                              icon: Icons.history_rounded,
                              title: 'Records',
                              subtitle: 'View your detection history',
                              onTap: widget.onOpenHistoryTab,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildFlagClassesCarousel(),
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

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return SizedBox(
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color,
              Color.alphaBlend(Colors.white.withOpacity(0.15), color),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.40),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanCard(
    Color primaryColor,
    Color secondaryColor,
    Color accentColor,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.38), // semi-transparent, no blur
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.white.withOpacity(0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 30,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(26.0),
          child: Column(
            children: [
              // Image / scan preview
              Container(
                height: 360,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06), // a bit more transparent
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.35),
                    width: 1.6,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(21),
                  child: filePath == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [primaryColor, secondaryColor],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.flag_rounded,
                                  size: 70,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Ready to Scan',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Choose an image to detect flags',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.white.withOpacity(0.75),
                                ),
                              ),
                            ],
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                filePath!,
                                fit: BoxFit.cover,
                              ),
                              if (isLoading)
                                Container(
                                  color: Colors.white.withOpacity(0.94),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 62,
                                        height: 62,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(primaryColor),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      const Text(
                                        'Analyzing...',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                ),
              ),
              const SizedBox(height: 28),
              // Results display
              if (label.isNotEmpty && !isLoading) ...[
                  const SizedBox(height: 20),
                  Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
                  decoration: BoxDecoration(
                    color: (isUnknown ? Colors.red : Colors.green).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: isUnknown ? const Color(0xFFF97373) : const Color(0xFF6EE7B7),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isUnknown ? const Color(0xFFE11D48) : secondaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isUnknown ? Icons.warning_rounded : Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isUnknown ? 'Unknown Flag' : 'Flag Detected',
                        style: TextStyle(
                          fontSize: 15,
                          color:
                              isUnknown ? const Color(0xFFFCA5A5) : const Color(0xFFA7F3D0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.6,
                        ),
                      ),
                      if (confidence > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.analytics_outlined,
                                color: accentColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${confidence.toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    // Remaining percentage shown with flag label, e.g. "0.1% Philippines"
                                    '${(100 - confidence).clamp(0, 100).toStringAsFixed(1)}% $label',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.75),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Button to view prediction distribution
                if (allPredictions.isNotEmpty && !isLoading) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => _showPredictionDistributionModal(context),
                    icon: Icon(
                      Icons.bar_chart_rounded,
                      color: accentColor,
                      size: 20,
                    ),
                    label: Text(
                      'View Prediction Distribution',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: accentColor.withOpacity(0.5), width: 1.5),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showPredictionDistributionModal(BuildContext context) {
    const Color accentColor = Color(0xFFF97373);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E293B),
                  const Color(0xFF334155),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Prediction Distribution',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white.withOpacity(0.7)),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: allPredictions.length,
                      itemBuilder: (context, index) {
                        final pred = allPredictions[index];
                        final String rawLabel = pred['label'].toString();
                        final String normalizedLabel = _normalizeFlagLabel(rawLabel);
                        final double predConfidence = pred['confidence'] as double;
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  normalizedLabel,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 8,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          color: Colors.white.withOpacity(0.15),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: predConfidence / 100,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(4),
                                              color: accentColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 60,
                                      child: Text(
                                        '${predConfidence.toStringAsFixed(2)}%',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white.withOpacity(0.8),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Close button
                Container(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: accentColor.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: accentColor, width: 1.5),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
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

  void _startFlagAutoScroll() {
    _flagTimer?.cancel();
    _flagTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_flagPageController.hasClients || _flagPageCount <= 1) return;
      final currentPage = _flagPageController.page?.round() ?? 0;
      int nextPage = currentPage + 1;
      if (nextPage >= _flagPageCount) {
        nextPage = 0;
      }
      _flagPageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Widget _buildLargeActionCard({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color,
              Color.alphaBlend(Colors.white.withOpacity(0.1), color),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.45),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
          border: Border.all(
            color: Colors.white.withOpacity(0.16),
            width: 1.2,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.88),
                            fontSize: 13.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlagClassesCarousel() {
    final List<String> assetPaths = _listFlagAssets();

    if (assetPaths.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Flag Classes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 210,
          child: PageView.builder(
            controller: _flagPageController,
            itemCount: assetPaths.length,
            itemBuilder: (context, index) {
              final String assetPath = assetPaths[index];
            final String flagName = _formatFlagName(assetPath);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Image.asset(
                          assetPath,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              flagName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to learn more',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
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

  List<String> _listFlagAssets() {
    // Enumerate actual images in assets/flag (excluding the background)
    const List<String> assets = [
      'assets/flag/philippines.webp',
      'assets/flag/thailand.jpg',
      'assets/flag/vietnam.webp',
      'assets/flag/singapore.jpg',
      'assets/flag/malaysia.jpg',
      'assets/flag/myanmar.webp',
      'assets/flag/laos.jpg',
      'assets/flag/indonesia.jpg',
      'assets/flag/cambodia.jpeg',
      'assets/flag/brunie.png',
    ];

    return assets;
  }

  String _formatFlagName(String assetPath) {
    final String fileName = assetPath.split('/').last.split('.').first;
    final List<String> words = fileName.replaceAll('_', ' ').split(' ');

    return words
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.history_rounded, size: 22, color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(width: 12),
            const Text(
              'Detection History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (detectionHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever_rounded),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text(
                      'Clear History',
                      style: TextStyle(
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: const Text(
                      'Delete all detection records?',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('CANCEL'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            detectionHistory.clear();
                          });
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'DELETE',
                          style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E293B), // slate blue top
              const Color(0xFF334155), // slightly lighter bottom
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: detectionHistory.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 80,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No History Yet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                        color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your detection history will appear here',
                    style: TextStyle(
                      fontSize: 14,
                        color: Colors.white70,
                    ),
                  ),
                ],
              ),
            )
          : CustomScrollView(
              slivers: [
                // Accuracy Graph Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.18),
                          ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF06B6D4).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.show_chart_rounded,
                                        color: Color(0xFF38BDF8),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Flag Detection Statistics',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.35),
                                    borderRadius: BorderRadius.circular(18),
                            ),
                            child: _buildFlagBarChart(),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Overall Accuracy',
                                  _getOverallAccuracy().toStringAsFixed(1) + '%',
                                  Icons.trending_up_rounded,
                                        const Color(0xFF22C55E),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Highest Accuracy',
                                  _getHighestFlagAccuracy().toStringAsFixed(1) + '%',
                                  Icons.arrow_upward_rounded,
                                        const Color(0xFF6366F1),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Total Flags',
                                  _getUniqueFlagsCount().toString(),
                                  Icons.flag_rounded,
                                        const Color(0xFFFACC15),
                                ),
                              ),
                            ],
                          ),
                        ],
                            ),
                          ),
                      ),
                    ),
                  ),
                ),
                // History List
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = detectionHistory[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.14),
                                width: 1.2,
                              ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(13),
                                ),
                                child: Stack(
                                  children: [
                                    Image.file(
                                      File(item.imagePath),
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          height: 200,
                                          color: const Color(0xFF0A0E1A),
                                          child: const Icon(
                                            Icons.broken_image,
                                            size: 50,
                                            color: Colors.white24,
                                          ),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: item.isUnknown
                                              ? const Color(0xFFEF4444)
                                              : const Color(0xFF06B6D4),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            item.isUnknown ? 'Unknown' : 'Detected',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: item.isUnknown
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFF1F2937),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF5F7FA),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.analytics_outlined,
                                                  size: 16,
                                                  color: const Color(0xFF06B6D4),
                                                ),
                                                const SizedBox(width: 6),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                  '${item.confidence.toStringAsFixed(1)}%',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF1F2937),
                                                  ),
                                                    ),
                                                    const SizedBox(height: 1),
                                                    Text(
                                                      '${(100 - item.confidence).clamp(0, 100).toStringAsFixed(1)}% ${item.label}',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey[600],
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          Icons.access_time_rounded,
                                          size: 14,
                                          color: Colors.grey[500],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDateTime(item.timestamp),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: detectionHistory.length,
                  ),
                ),
              ],
              ),
            ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  // Data class for flag statistics - includes all flags by default
  Map<String, FlagStats> _getFlagStatistics() {
    final Map<String, FlagStats> flagStats = {};
    
    // Initialize all flags with zero scans
    for (var flagKey in allFlagClasses) {
      final displayName = flagDisplayNames[flagKey] ?? flagKey;
      flagStats[flagKey.toLowerCase()] = FlagStats(
        name: displayName,
        totalScans: 0,
        totalAccuracy: 0.0,
      );
    }
    
    // Update with actual detection data
    for (var item in detectionHistory) {
      if (!item.isUnknown) {
        final detectedLabel = item.label.toLowerCase().trim();
        
        // 1) Try exact display-name match first (e.g. "brunei" -> "brunie flag")
        String? matchedKey = displayNameToFlagKey[detectedLabel];
        
        // 2) If still not found, fall back to old heuristics
        if (matchedKey == null) {
          // Try to match with existing flag classes
          for (var flagKey in allFlagClasses) {
            final flagLower = flagKey.toLowerCase();
            // Check if the detected label matches any part of the flag key
            if (detectedLabel.contains(flagLower.split(' ')[1]) || 
                flagLower.contains(detectedLabel.split(' ')[0]) ||
                detectedLabel.startsWith(flagLower.split(' ')[0])) {
              matchedKey = flagKey.toLowerCase();
              break;
            }
          }
        }
        
        // 3) If no match found, try to extract number prefix
        if (matchedKey == null) {
          final match = RegExp(r'^(\d+)\s+').firstMatch(detectedLabel);
          if (match != null) {
            final numStr = match.group(1);
            for (var flagKey in allFlagClasses) {
              if (flagKey.toLowerCase().startsWith('$numStr ')) {
                matchedKey = flagKey.toLowerCase();
                break;
              }
            }
          }
        }
        
        // Use matched key or create new entry
        final key = matchedKey ?? detectedLabel;
        
        if (flagStats.containsKey(key)) {
          flagStats[key] = FlagStats(
            name: flagStats[key]!.name,
            totalScans: flagStats[key]!.totalScans + 1,
            totalAccuracy: flagStats[key]!.totalAccuracy + item.confidence,
          );
        } else {
          // Add new flag if not in the default list
          flagStats[key] = FlagStats(
            name: item.label,
            totalScans: 1,
            totalAccuracy: item.confidence,
          );
        }
      }
    }
    
    return flagStats;
  }

  Widget _buildFlagBarChart() {
    final flagStats = _getFlagStatistics();
    
    // Get all flags, sorted by the original order in allFlagClasses to show all 10
    final sortedFlags = allFlagClasses.map((flagKey) {
      final key = flagKey.toLowerCase();
      return flagStats[key] ?? FlagStats(
        name: flagDisplayNames[flagKey] ?? flagKey,
        totalScans: 0,
        totalAccuracy: 0.0,
      );
    }).toList();
    
    // Create spots for line chart
    final spots = sortedFlags.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.averageAccuracy);
    }).toList();

    final maxAccuracy = sortedFlags.isNotEmpty 
        ? sortedFlags.map((f) => f.averageAccuracy).reduce((a, b) => a > b ? a : b)
        : 100.0;
    final maxY = (maxAccuracy > 0 ? (maxAccuracy * 1.2).clamp(0.0, 120.0) : 100.0).toDouble();

    return Column(
      children: [
        SizedBox(
          height: 250,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY > 0 ? maxY / 5 : 20,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey.withOpacity(0.15),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 90,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < sortedFlags.length) {
                        final flag = sortedFlags[index];
                        // Extract country name (remove "Flag" suffix)
                        String displayName = flag.name
                            .replaceAll(' Flag', '')
                            .replaceAll('flag', '')
                            .trim();
                        
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Transform.rotate(
                            angle: -0.5, // Rotate diagonally like reference image
                            child: SizedBox(
                              width: 75,
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}%',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              minX: 0,
              maxX: sortedFlags.isEmpty ? 0 : (sortedFlags.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: const Color(0xFF06B6D4),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: _getFlagColor(index),
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF06B6D4).withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Flag list with icons and details - show all flags
        ...sortedFlags.map((flag) {
          final index = sortedFlags.indexOf(flag);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getFlagColor(index).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.flag_rounded,
                    color: _getFlagColor(index),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        flag.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.95),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${flag.totalScans} scan${flag.totalScans > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getFlagColor(index).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${flag.averageAccuracy.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _getFlagColor(index),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Color _getFlagColor(int index) {
    final colors = [
      const Color(0xFF06B6D4),
      const Color(0xFF8B5CF6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFFEC4899),
      const Color(0xFF6366F1),
      const Color(0xFF14B8A6),
    ];
    return colors[index % colors.length];
  }

  double _getOverallAccuracy() {
    if (detectionHistory.isEmpty) return 0.0;
    final sum = detectionHistory
        .where((item) => !item.isUnknown)
        .fold<double>(0.0, (sum, item) => sum + item.confidence);
    final count = detectionHistory.where((item) => !item.isUnknown).length;
    return count > 0 ? sum / count : 0.0;
  }

  double _getHighestFlagAccuracy() {
    final flagStats = _getFlagStatistics();
    if (flagStats.isEmpty) return 0.0;
    return flagStats.values
        .map((flag) => flag.averageAccuracy)
        .fold<double>(0.0, (max, acc) => acc > max ? acc : max);
  }

  int _getUniqueFlagsCount() {
    return _getFlagStatistics().length;
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.info_rounded, size: 22, color: Color(0xFF06B6D4)),
            ),
            const SizedBox(width: 12),
            const Text(
              'About',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E293B),
              const Color(0xFF334155),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
      ),
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                  ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                            color: const Color(0xFF06B6D4).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.flag_rounded,
                      size: 64,
                      color: Color(0xFF06B6D4),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Flag Detector',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                            color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'v1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                              color: Color(0xFFDDD6FE),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'AI-powered flag detection system using advanced neural networks for accurate identification of country flags.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                            color: Colors.white.withOpacity(0.85),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    height: 1,
                          color: Colors.white.withOpacity(0.12),
                  ),
                  const SizedBox(height: 24),
                  _buildFeature(Icons.psychology_rounded, 'AI Neural Network', const Color(0xFF06B6D4)),
                  _buildFeature(Icons.speed_rounded, 'Real-time Processing', const Color(0xFF8B5CF6)),
                  _buildFeature(Icons.cloud_off_rounded, 'Offline Capable', const Color(0xFF10B981)),
                  _buildFeature(Icons.security_rounded, 'Secure Detection', const Color(0xFFF59E0B)),
                  _buildFeature(Icons.analytics_rounded, 'Smart Analysis', const Color(0xFFEF4444)),
                ],
                    ),
                  ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}