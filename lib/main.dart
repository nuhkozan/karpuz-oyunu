import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── AdMob ID'leri ──────────────────────────────────────────────
// TODO: Bunları AdMob konsolundan alıp buraya yaz
const String kAdAppId     = 'ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX';
const String kInterstitialId = 'ca-app-pub-3940256099942544/1033173712'; // TEST ID
// Yayına çıkarınca üstteki test ID'yi gerçek ID ile değiştir

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tam ekran - durum çubuğunu gizle
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // AdMob başlat
  await MobileAds.instance.initialize();

  runApp(const KarpuzApp());
}

class KarpuzApp extends StatelessWidget {
  const KarpuzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karpuz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  InAppWebViewController? _webViewController;
  InterstitialAd? _interstitialAd;
  bool _adLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadInterstitialAd();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: kInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _adLoaded = true;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _adLoaded = false;
              _loadInterstitialAd(); // Bir sonraki için hazırla
              // Oyuna devam et
              _webViewController?.evaluateJavascript(
                  source: 'if(typeof adDismissed==="function")adDismissed();');
            },
          );
        },
        onAdFailedToLoad: (err) {
          _adLoaded = false;
        },
      ),
    );
  }

  void _showInterstitialAd() {
    if (_adLoaded && _interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      // Reklam yüklenmediyse direkt devam et
      _webViewController?.evaluateJavascript(
          source: 'if(typeof adDismissed==="function")adDismissed();');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: InAppWebView(
          initialFile: 'assets/game.html',
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            transparentBackground: false,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            disableVerticalScroll: true,
            disableHorizontalScroll: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;

            // JS köprüsü: oyun reklam göstermek isteyince burası çağrılır
            controller.addJavaScriptHandler(
              handlerName: 'showAd',
              callback: (args) {
                _showInterstitialAd();
              },
            );

            // Reklamsız satın alma köprüsü
            controller.addJavaScriptHandler(
              handlerName: 'buyAdFree',
              callback: (args) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('ad_free', true);
                controller.evaluateJavascript(
                    source: 'localStorage.setItem("suika_adfree","1");');
              },
            );
          },
          onLoadStop: (controller, url) {
            // Reklamsız durumu JS'e aktar
            SharedPreferences.getInstance().then((prefs) {
              final adFree = prefs.getBool('ad_free') ?? false;
              if (adFree) {
                controller.evaluateJavascript(
                    source: 'localStorage.setItem("suika_adfree","1");');
              }
            });
          },
          onConsoleMessage: (controller, msg) {
            debugPrint('WebView: ${msg.message}');
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }
}
