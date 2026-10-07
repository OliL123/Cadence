// Meld scoring happens once per meld (so moving other tiles, or reopening the
// wall, doesn't replay a 碰), and draws are steered toward tiles that can meld.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cadence/models.dart';
import 'package:cadence/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  CadenceStore withTasks(int n) {
    final s = CadenceStore();
    s.applyState({'tasks': <dynamic>[], 'uid': 0, 'updatedAt': 1});
    for (var i = 0; i < n; i++) {
      s.addTask('T$i', 'uni');
    }
    return s;
  }

  test('a meld scores once, whatever order its ids arrive in', () {
    final s = withTasks(4);
    final ids = s.tasks.map((t) => t.id).toList();
    expect(s.awardMeld('peng', [ids[0], ids[1], ids[2]]), isTrue);
    expect(s.score, 2);
    // Same meld seen again after another tile moved (ids reordered): no repeat.
    expect(s.awardMeld('peng', [ids[2], ids[0], ids[1]]), isFalse);
    expect(s.score, 2);
    // A different meld still scores.
    expect(s.awardMeld('shang', [ids[1], ids[2], ids[3]]), isTrue);
    expect(s.score, 3);
  });

  test('the scored record survives a reload and syncs', () {
    final s = withTasks(3);
    final ids = s.tasks.map((t) => t.id).toList();
    s.awardMeld('peng', ids);
    final again = CadenceStore()..applyState(s.exportState());
    expect(again.score, 2);
    expect(again.awardMeld('peng', ids), isFalse,
        reason: 'reopening the app must not re-celebrate the same meld');
  });

  test('a newer blob from a device with an older score does not rewind it', () {
    final s = withTasks(3);
    final ids = s.tasks.map((t) => t.id).toList();
    // The other device: same tasks, never saw the meld, but edited later.
    final other = s.exportState()..['updatedAt'] = 9999999999999;
    s.awardMeld('peng', ids);
    s.applyRemoteState(Map<String, dynamic>.from(other));
    expect(s.score, 2);
    expect(s.awardMeld('peng', ids), isFalse,
        reason: 'the merged record still knows this meld was scored');
    expect(s.pendingMergePush, isTrue,
        reason: 'the kept score must be pushed back so the cloud converges');
  });

  test('melds scored on two devices between syncs both count', () {
    final s = withTasks(6);
    final ids = s.tasks.map((t) => t.id).toList();
    s.markScoreSynced(0); // both devices last synced at 0
    // The other device scored a peng (+2) on tasks 0-2 and pushed first.
    final other = s.exportState()
      ..['score'] = 2
      ..['scoredMelds'] = ['peng:${ids[0]},${ids[1]},${ids[2]}']
      ..['updatedAt'] = 9999999999999;
    // Meanwhile this device scored a daai (+4) on tasks 3-5.
    s.awardMeld('daai', [ids[3], ids[4], ids[5]]);
    s.applyRemoteState(Map<String, dynamic>.from(other));
    expect(s.score, 6);
    expect(s.pendingMergePush, isTrue);
    // Once pushed, the same blob coming back adds nothing more.
    s.markScoreSynced(s.score);
    s.pendingMergePush = false;
    s.applyRemoteState(Map<String, dynamic>.from(s.exportState()));
    expect(s.score, 6);
  });

  test('a cloud copy already holding our points does not double them', () {
    final s = withTasks(3);
    final ids = s.tasks.map((t) => t.id).toList();
    s.awardMeld('peng', ids);
    s.markScoreSynced(2); // pushed
    final cloud = s.exportState()..['updatedAt'] = 9999999999999;
    s.applyRemoteState(Map<String, dynamic>.from(cloud));
    expect(s.score, 2);
    expect(s.pendingMergePush, isFalse);
  });

  test('a meld record the cloud lacks is pushed back even on a tied score', () {
    final s = withTasks(6);
    final ids = s.tasks.map((t) => t.id).toList();
    s.awardMeld('peng', [ids[0], ids[1], ids[2]]);
    s.markScoreSynced(2);
    final other = s.exportState()
      ..['scoredMelds'] = ['peng:${ids[3]},${ids[4]},${ids[5]}']
      ..['updatedAt'] = 9999999999999;
    s.applyRemoteState(Map<String, dynamic>.from(other));
    expect(s.score, 2);
    expect(s.scoredMelds, hasLength(2));
    expect(s.pendingMergePush, isTrue);
  });

  test('a manual "use the cloud copy" still takes the cloud score', () {
    final s = withTasks(3);
    final ids = s.tasks.map((t) => t.id).toList();
    final cloud = s.exportState();
    s.awardMeld('peng', ids);
    s.applyRemoteState(Map<String, dynamic>.from(cloud), merge: false);
    expect(s.score, 0);
  });

  test('melds of finished tasks are forgotten', () {
    final s = withTasks(4);
    final ids = s.tasks.map((t) => t.id).toList();
    s.awardMeld('peng', [ids[0], ids[1], ids[2]]);
    s.toggleDone(s.byId(ids[0])!);
    s.awardMeld('shang', [ids[1], ids[2], ids[3]]); // triggers the prune
    expect(s.scoredMelds.any((k) => k.startsWith('peng:')), isFalse);
    expect(s.score, 3, reason: 'points already earned are kept');
  });

  test('draws favour tiles that can meld with the wall', () {
    final s = withTasks(1);
    final t = s.tasks.first;
    t.tile = Tile('m', 5);
    t.star = true;
    s.wall = [t.id];
    var fits = 0;
    const n = 600;
    for (var i = 0; i < n; i++) {
      final d = s.drawTile()!;
      if (d.suit == 'm' && (d.val - 5).abs() <= 2) fits++;
      s.deck.add(d); // put it back so the odds stay comparable
    }
    // Random alone fits ~18% of the time (19 of 108 tiles); steered ~67%.
    expect(fits / n, greaterThan(0.5));
  });
}
