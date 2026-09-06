import 'package:bicimad_social/features/rankings/domain/community_route_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'conserva solo el mejor viaje de cada usuario y ordena por duración',
    () {
      final ranking = CommunityRouteRanking.fromCandidates([
        _candidate('current', 420000, isCurrentUser: true),
        _candidate('current', 390000, isCurrentUser: true),
        _candidate('followed', 405000),
      ]);

      expect(ranking.entries.map((entry) => entry.userId), [
        'current',
        'followed',
      ]);
      expect(ranking.entries.map((entry) => entry.durationMilliseconds), [
        390000,
        405000,
      ]);
      expect(ranking.currentUserEntry?.position, 1);
    },
  );

  test('usa milisegundos para desempatar tiempos del mismo segundo', () {
    final ranking = CommunityRouteRanking.fromCandidates([
      _candidate('first', 411231),
      _candidate('second', 411842),
    ]);

    expect(ranking.entries.map((entry) => entry.position), [1, 2]);
  });

  test('los empates reales comparten posición competitiva', () {
    final ranking = CommunityRouteRanking.fromCandidates([
      _candidate('first', 411000),
      _candidate('second', 411000),
      _candidate('third', 415000),
      _candidate('fourth', 420000),
    ]);

    expect(ranking.entries.map((entry) => entry.position), [1, 1, 3, 4]);
    expect(ranking.entries[0].tier, CommunityPlacementTier.gold);
    expect(ranking.entries[1].tier, CommunityPlacementTier.gold);
    expect(ranking.entries[2].tier, CommunityPlacementTier.bronze);
    expect(ranking.entries[3].tier, CommunityPlacementTier.graphite);
  });

  test('asigna oro, plata, bronce y grafito por posición comunitaria', () {
    final ranking = CommunityRouteRanking.fromCandidates([
      _candidate('gold', 300000),
      _candidate('silver', 310000),
      _candidate('bronze', 320000),
      _candidate('graphite', 330000),
    ]);

    expect(ranking.entries.map((entry) => entry.position), [1, 2, 3, 4]);
    expect(ranking.entries.map((entry) => entry.tier), [
      CommunityPlacementTier.gold,
      CommunityPlacementTier.silver,
      CommunityPlacementTier.bronze,
      CommunityPlacementTier.graphite,
    ]);
  });

  test('funciona con solo el viaje del usuario actual y avatar fallback', () {
    final ranking = CommunityRouteRanking.fromCandidates([
      const CommunityRouteCandidate(
        userId: 'current',
        displayName: 'Usuario',
        username: 'usuario',
        avatarKey: '',
        durationMilliseconds: 300000,
        isCurrentUser: true,
      ),
    ]);

    expect(ranking.entries, hasLength(1));
    expect(ranking.currentUserEntry?.position, 1);
    expect(ranking.currentUserEntry?.avatarAsset, 'assets/avatar/1.png');
  });

  test('descarta duraciones inválidas', () {
    final ranking = CommunityRouteRanking.fromCandidates([
      _candidate('zero', 0),
      _candidate('negative', -1),
      _candidate('valid', 300000),
    ]);

    expect(ranking.entries.single.userId, 'valid');
  });
}

CommunityRouteCandidate _candidate(
  String userId,
  int durationMilliseconds, {
  bool isCurrentUser = false,
}) {
  return CommunityRouteCandidate(
    userId: userId,
    displayName: 'Usuario $userId',
    username: 'user_$userId',
    avatarKey: '1.png',
    durationMilliseconds: durationMilliseconds,
    directDistanceMeters: 1200,
    isCurrentUser: isCurrentUser,
  );
}
