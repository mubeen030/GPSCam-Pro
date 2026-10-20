import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService instance = AdService._internal();
  AdService._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;
  int _photoCaptureCount = 0;

  // Official Google AdMob Test Ad Unit IDs
  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    return '';
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/1033173712';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    return '';
  }

  static Future<void> initialize() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await MobileAds.instance.initialize();
      }
    } catch (e) {
      debugPrint("AdMob initialize error: $e");
    }
  }

  // --- Banner Ad Factory ---
  static BannerAd createBannerAd({
    required Function(Ad) onAdLoaded,
    Function(Ad, LoadAdError)? onAdFailedToLoad,
  }) {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: (ad, error) {
          debugPrint("Banner Ad failed to load: $error");
          ad.dispose();
          if (onAdFailedToLoad != null) onAdFailedToLoad(ad, error);
        },
      ),
    );
  }

  // --- Interstitial Ad Management ---
  void loadInterstitialAd() {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (_interstitialAd != null || _isInterstitialLoading) return;

    _isInterstitialLoading = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              loadInterstitialAd(); // Preload next interstitial
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint("Interstitial Ad failed to load: $error");
          _interstitialAd = null;
          _isInterstitialLoading = false;
        },
      ),
    );
  }

  /// Trigger after photo saves. Displays an interstitial ad every 3 photos to avoid spamming the user.
  void onPhotoSaved({int interval = 3}) {
    _photoCaptureCount++;
    if (_photoCaptureCount % interval == 0) {
      showInterstitialAd();
    }
  }

  void showInterstitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      loadInterstitialAd();
    }
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
