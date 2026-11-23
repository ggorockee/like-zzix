import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/ad_flags.dart';
import 'package:likezzix/services/ad_service.dart';
import 'package:likezzix/services/save_ad_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAds extends AdService {
  _FakeAds({required bool on, this.ready = true})
    : super(
        flags: AdFlags(
          showNativeAd: false,
          showInterstitialAd: on,
          showRewardedAd: false,
          interstitialAdInterval: 3,
        ),
      );

  bool ready;
  int preloads = 0;
  int shows = 0;

  @override
  Future<void> preloadInterstitial() async => preloads++;

  @override
  Future<bool> showInterstitial() async {
    if (!ready) return false;
    shows++;
    return true;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> save(SaveAdController c, int n, {bool locked = false}) async {
    for (var i = 0; i < n; i++) {
      await c.onSaved(locked: locked);
    }
  }

  test('3회 저장마다 한 번, 첫 저장부터 미리 로드', () async {
    final ads = _FakeAds(on: true);
    var shown = 0;
    final c = SaveAdController(ads: ads, onShown: () => shown++);
    await save(c, 1);
    expect((ads.preloads, ads.shows), (1, 0));
    await save(c, 2);
    expect(ads.shows, 1);
    await save(c, 3);
    expect((ads.shows, shown), (2, 2));
  });

  test('잠금 중에는 광고를 띄우지 않고, 풀 때 보여 준다', () async {
    final ads = _FakeAds(on: true);
    final c = SaveAdController(ads: ads);
    await save(c, 5, locked: true);
    expect(ads.shows, 0);
    await c.showIfDue();
    expect(ads.shows, 1);
    await c.showIfDue();
    expect(ads.shows, 1);
  });

  test('광고가 준비되지 않았으면 횟수를 유지했다가 다음에 보여 준다', () async {
    final ads = _FakeAds(on: true, ready: false);
    final c = SaveAdController(ads: ads);
    await save(c, 3);
    expect(ads.shows, 0);
    ads.ready = true;
    await save(c, 1);
    expect(ads.shows, 1);
  });

  test('횟수는 앱을 다시 켜도 이어진다', () async {
    final ads = _FakeAds(on: true);
    await save(SaveAdController(ads: ads), 2);
    await save(SaveAdController(ads: ads), 1);
    expect(ads.shows, 1);
  });

  test('플래그가 꺼져 있으면 아무것도 하지 않는다', () async {
    final ads = _FakeAds(on: false);
    await save(SaveAdController(ads: ads), 5);
    expect((ads.preloads, ads.shows), (0, 0));
  });
}
