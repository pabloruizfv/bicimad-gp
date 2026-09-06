import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/bike_id.dart';
import '../../../core/utils/decimal_amount.dart';
import '../../achievements/domain/achievement.dart';
import '../../achievements/domain/achievement_ranking.dart';
import '../../rankings/domain/community_route_ranking.dart';
import '../../rankings/domain/head_to_head.dart';
import '../../rankings/domain/route_key.dart';
import '../../trips/domain/trip.dart';
import '../domain/follow_connection.dart';
import '../domain/profile_statistics.dart';
import '../domain/social_profile.dart';
import '../domain/social_repository.dart';

class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this.client);

  final SupabaseClient client;

  @override
  bool get isConfigured => true;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  String? get currentEmail => client.auth.currentUser?.email;

  @override
  bool get hasSession => client.auth.currentSession != null;

  @override
  Future<bool> restoreSession() async {
    if (kDebugMode) {
      debugPrint(
        '[BICIMAD_DIAG] stage=supabase_auth '
        'event=session_restore_started',
      );
    }
    try {
      // Supabase Auth uses a replaying stream, so this also waits for the
      // initial persisted-session decision when restoration is still running.
      await client.auth.onAuthStateChange.first;
      final session = await client.auth.getSession();
      if (kDebugMode) {
        debugPrint(
          '[BICIMAD_DIAG] stage=supabase_auth '
          'event=session_restore_completed authenticated=${session != null}',
        );
      }
      return session != null;
    } on AuthException catch (error) {
      if (client.auth.currentSession == null) {
        if (kDebugMode) {
          debugPrint(
            '[BICIMAD_DIAG] stage=supabase_auth '
            'event=session_restore_completed authenticated=false',
          );
        }
        return false;
      }
      if (kDebugMode) {
        debugPrint(
          '[BICIMAD_DIAG] stage=supabase_auth '
          'event=session_restore_error type=AuthException',
        );
      }
      throw SocialAuthFailure(classifySupabaseAuthFailure(error));
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BICIMAD_DIAG] stage=supabase_auth '
          'event=session_restore_error type=${error.runtimeType}',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> sendOtp(String normalizedEmail) async {
    try {
      await client.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: true,
      );
    } on AuthException catch (error) {
      if (kDebugMode) {
        debugPrint(buildSafeSupabaseAuthDiagnostic('send_otp', error));
      }
      throw SocialAuthFailure(classifySupabaseAuthFailure(error));
    }
  }

  @override
  Future<void> verifyOtp({
    required String normalizedEmail,
    required String token,
  }) async {
    final response = await client.auth.verifyOTP(
      email: normalizedEmail,
      token: token,
      type: OtpType.email,
    );
    if (response.session == null || response.user == null) {
      throw const SocialRepositoryException(
        'No se ha podido verificar el código.',
      );
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();

  @override
  Future<void> deleteOwnAccount() async {
    _requireUserId();
    await client.rpc('delete_own_account');
    await client.auth.signOut(scope: SignOutScope.local);
  }

  @override
  Future<SocialProfile?> getMyProfile() async {
    final userId = _requireUserId();
    final result = await client
        .from('profiles')
        .select('user_id, username, display_name, avatar_key, is_public')
        .eq('user_id', userId)
        .maybeSingle();
    return result == null ? null : _profileFromMap(result);
  }

  @override
  Future<SocialProfile> createProfile({
    required String username,
    required String displayName,
    required String avatarKey,
    required bool isPublic,
    required String? mpassUserId,
  }) async {
    final result = await client.rpc(
      'create_own_profile',
      params: {
        'p_username': username,
        'p_display_name': displayName,
        'p_avatar_key': avatarKey,
        'p_is_public': isPublic,
        'p_mpass_user_id': mpassUserId,
      },
    );
    return _profileFromResult(result);
  }

  @override
  Future<SocialProfile> updateProfile({
    required String displayName,
    required String avatarKey,
    required bool isPublic,
  }) async {
    final result = await client.rpc(
      'update_own_profile',
      params: {
        'p_display_name': displayName,
        'p_avatar_key': avatarKey,
        'p_is_public': isPublic,
      },
    );
    return _profileFromResult(result);
  }

  @override
  Future<List<SocialProfile>> searchProfiles(String query) async {
    final result = await client.rpc(
      'search_social_profiles',
      params: {'p_query': query.trim()},
    );
    return _mapsFromResult(result).map(_profileFromMap).toList();
  }

  @override
  Future<SocialProfileDetails?> getProfileDetails(String userId) async {
    final result = await client.rpc(
      'get_social_profile',
      params: {'p_user_id': userId},
    );
    final rows = _mapsFromResult(result);
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final canViewStats = row['can_view_stats'] == true;
    return SocialProfileDetails(
      profile: _profileFromMap(row),
      statistics: canViewStats ? _statisticsFromMap(row) : null,
      followersCount: _optionalIntValue(row['followers_count']),
      followingCount: _optionalIntValue(row['following_count']),
    );
  }

  @override
  Future<List<FollowConnection>> getConnections(ConnectionListType type) async {
    final result = await client.rpc(
      'list_social_connections',
      params: {'p_kind': _connectionKind(type)},
    );
    return [for (final row in _mapsFromResult(result)) _connectionFromMap(row)];
  }

  @override
  Future<void> follow(String userId) =>
      _callFollowRpc('request_follow', userId);

  @override
  Future<void> acceptFollow(String userId) =>
      _callFollowRpc('accept_follow_request', userId);

  @override
  Future<void> rejectFollow(String userId) =>
      _callFollowRpc('reject_follow_request', userId);

  @override
  Future<void> cancelFollow(String userId) =>
      _callFollowRpc('cancel_follow_request', userId);

  @override
  Future<void> unfollow(String userId) =>
      _callFollowRpc('unfollow_profile', userId);

  @override
  Future<void> removeFollower(String userId) =>
      _callFollowRpc('remove_follower', userId);

  @override
  Future<List<Trip>> getOwnTrips({required String localUserId}) async {
    const pageSize = 500;
    final trips = <Trip>[];
    var offset = 0;
    while (true) {
      final result = await client
          .from('trips')
          .select(
            'provider, source_trip_id, origin_station_id, origin_station_name, '
            'destination_station_id, destination_station_name, started_at, '
            'duration_seconds, origin_latitude, origin_longitude, '
            'destination_latitude, destination_longitude, '
            'direct_distance_meters, bike_id, trip_cost',
          )
          .order('started_at')
          .range(offset, offset + pageSize - 1);
      final rows = _mapsFromResult(result);
      trips.addAll(
        rows.map((row) => _tripFromMap(row, localUserId: localUserId)),
      );
      if (rows.length < pageSize) {
        break;
      }
      offset += pageSize;
    }
    return trips;
  }

  @override
  Future<void> upsertOwnTrips(List<Trip> trips) async {
    const batchSize = 200;
    for (var offset = 0; offset < trips.length; offset += batchSize) {
      final end = (offset + batchSize).clamp(0, trips.length);
      final batch = trips.sublist(offset, end);
      await client.rpc(
        'upsert_own_trips',
        params: {
          'p_trips': [for (final trip in batch) _tripToMap(trip)],
        },
      );
    }
  }

  @override
  Future<List<UserAchievement>> getUserAchievements(String userId) async {
    final result = await client
        .from('user_achievements')
        .select('category_id, level_id, threshold, progress, unlocked_at')
        .eq('user_id', userId)
        .order('threshold');
    return _mapsFromResult(
      result,
    ).map(_achievementFromMap).whereType<UserAchievement>().toList();
  }

  @override
  Future<AchievementCommunityRanking> getAchievementRanking(
    String categoryId,
  ) async {
    final result = await client.rpc(
      'get_achievement_ranking',
      params: {'p_category_id': categoryId},
    );
    final rows = _mapsFromResult(result);
    final entries = [
      for (final row in rows)
        AchievementRankingEntry(
          rank: _intValue(row['rank_position']),
          userId: _requiredString(row['user_id']),
          displayName: _requiredString(row['display_name']),
          avatarKey: _requiredString(row['avatar_key']),
          value: _intValue(row['metric_value']),
          isCurrentUser: row['is_current_user'] == true,
        ),
    ];
    return AchievementCommunityRanking(
      categoryId: categoryId,
      entries: List.unmodifiable(entries),
      totalUsers: rows.isEmpty ? 0 : _intValue(rows.first['total_users']),
    );
  }

  @override
  Future<CommunityRouteRanking> getCommunityRouteRanking({
    required String originStationId,
    required String destinationStationId,
  }) async {
    final result = await client.rpc(
      'get_community_route_ranking',
      params: {
        'p_origin_station_id': originStationId,
        'p_destination_station_id': destinationStationId,
      },
    );
    final candidates = [
      for (final row in _mapsFromResult(result))
        CommunityRouteCandidate(
          userId: _requiredString(row['user_id']),
          displayName: _requiredString(row['display_name']),
          username: _requiredString(row['username']),
          avatarKey: _optionalString(row['avatar_key']) ?? '1.png',
          durationMilliseconds: _intValue(row['duration_milliseconds']),
          directDistanceMeters: _doubleValue(row['direct_distance_meters']),
          startedAt: DateTime.tryParse(row['started_at']?.toString() ?? ''),
          isCurrentUser: row['is_current_user'] == true,
        ),
    ];
    return CommunityRouteRanking.fromCandidates(candidates);
  }

  @override
  Future<HeadToHeadSummary> getHeadToHead(String otherUserId) async {
    final result = await client.rpc(
      'get_head_to_head',
      params: {'p_other_user_id': otherUserId},
    );
    final entries = [
      for (final row in _mapsFromResult(result))
        HeadToHeadEntry(
          routeKey: RouteKey(
            originStationId: _requiredString(row['origin_station_id']),
            destinationStationId: _requiredString(
              row['destination_station_id'],
            ),
          ),
          originStationName: _requiredString(row['origin_station_name']),
          destinationStationName: _requiredString(
            row['destination_station_name'],
          ),
          currentDurationMilliseconds: _intValue(
            row['current_duration_milliseconds'],
          ),
          otherDurationMilliseconds: _intValue(
            row['other_duration_milliseconds'],
          ),
        ),
    ];
    return HeadToHeadSummary(entries: orderHeadToHeadEntries(entries));
  }

  @override
  Future<void> refreshOwnAchievements() async {
    _requireUserId();
    await client.rpc('refresh_own_achievements');
  }

  Future<void> _callFollowRpc(String function, String userId) async {
    await client.rpc(function, params: {'p_user_id': userId});
  }

  String _requireUserId() {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      throw const SocialRepositoryException('No hay una sesión social activa.');
    }
    return userId;
  }

  SocialProfile _profileFromResult(Object? result) {
    final rows = _mapsFromResult(result);
    if (rows.isEmpty) {
      throw const SocialRepositoryException(
        'No se ha podido guardar el perfil.',
      );
    }
    return _profileFromMap(rows.first);
  }

  SocialProfile _profileFromMap(Map<String, Object?> row) {
    return SocialProfile(
      userId: _requiredString(row['user_id']),
      username: _requiredString(row['username']),
      displayName: _requiredString(row['display_name']),
      avatarKey: _requiredString(row['avatar_key']),
      isPublic: row['is_public'] == true,
      mostUsedStationName: _optionalString(row['most_used_station_name']),
      outgoingFollowStatus: parseFollowStatus(row['outgoing_status']),
      followsCurrentUser: row['follows_current_user'] == true,
    );
  }

  FollowConnection _connectionFromMap(Map<String, Object?> row) {
    final status = parseFollowStatus(row['status']);
    final direction = switch (row['direction']?.toString()) {
      'incoming' => FollowDirection.incoming,
      _ => FollowDirection.outgoing,
    };
    return FollowConnection(
      profile: _profileFromMap(row),
      status: status ?? FollowStatus.pending,
      direction: direction,
      createdAt: DateTime.parse(_requiredString(row['created_at'])),
    );
  }

  ProfileStatistics _statisticsFromMap(Map<String, Object?> row) {
    return ProfileStatistics(
      totalTrips: _intValue(row['total_trips']),
      historySpanDays: _intValue(row['history_span_days']),
      distinctTripDays: _intValue(row['distinct_trip_days']),
      totalDurationSeconds: _intValue(row['total_duration_seconds']),
      totalDistanceMeters: _doubleValue(row['total_distance_meters']) ?? 0,
      equivalentAverageSpeedKmh: _doubleValue(
        row['equivalent_average_speed_kmh'],
      ),
      tripsWithDistance: _intValue(row['trips_with_distance']),
    );
  }

  UserAchievement? _achievementFromMap(Map<String, Object?> row) {
    final categoryId = _optionalString(row['category_id']);
    final levelId = AchievementLevelIdValues.parse(row['level_id']);
    final threshold = _optionalIntValue(row['threshold']);
    final unlockedAt = DateTime.tryParse(row['unlocked_at']?.toString() ?? '');
    if (categoryId == null ||
        levelId == null ||
        threshold == null ||
        unlockedAt == null) {
      return null;
    }
    return UserAchievement(
      categoryId: categoryId,
      levelId: levelId,
      threshold: threshold,
      unlockedAt: unlockedAt,
      progress: _optionalIntValue(row['progress']) ?? threshold,
    );
  }

  int? _optionalIntValue(Object? value) {
    if (value == null) {
      return null;
    }
    return value is int ? value : int.tryParse(value.toString());
  }

  String? _optionalString(Object? value) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }

  Trip _tripFromMap(Map<String, Object?> row, {required String localUserId}) {
    final externalId = _requiredString(row['source_trip_id']);
    return Trip(
      id: 'bicimad-$externalId',
      externalId: externalId,
      userId: localUserId,
      originStationId: _requiredString(row['origin_station_id']),
      originStationName: _requiredString(row['origin_station_name']),
      destinationStationId: _requiredString(row['destination_station_id']),
      destinationStationName: _requiredString(row['destination_station_name']),
      startedAt: DateTime.parse(_requiredString(row['started_at'])),
      durationSeconds: _intValue(row['duration_seconds']),
      isShared: true,
      originLatitude: _doubleValue(row['origin_latitude']),
      originLongitude: _doubleValue(row['origin_longitude']),
      destinationLatitude: _doubleValue(row['destination_latitude']),
      destinationLongitude: _doubleValue(row['destination_longitude']),
      directDistanceMeters: _doubleValue(row['direct_distance_meters']),
      bikeId: normalizeBikeId(row['bike_id']),
      tripCost: normalizeDecimalAmount(row['trip_cost']),
    );
  }

  Map<String, Object?> _tripToMap(Trip trip) => {
    'provider': 'bicimad',
    'source_trip_id': trip.externalId,
    'origin_station_id': trip.originStationId,
    'origin_station_name': trip.originStationName,
    'destination_station_id': trip.destinationStationId,
    'destination_station_name': trip.destinationStationName,
    'started_at': trip.startedAt.toUtc().toIso8601String(),
    'duration_seconds': trip.durationSeconds,
    'origin_latitude': trip.originLatitude,
    'origin_longitude': trip.originLongitude,
    'destination_latitude': trip.destinationLatitude,
    'destination_longitude': trip.destinationLongitude,
    'direct_distance_meters': trip.directDistanceMeters,
    'bike_id': normalizeBikeId(trip.bikeId),
    'trip_cost': trip.tripCost,
  };

  String _connectionKind(ConnectionListType type) => switch (type) {
    ConnectionListType.followers => 'followers',
    ConnectionListType.following => 'following',
    ConnectionListType.receivedRequests => 'received_requests',
    ConnectionListType.sentRequests => 'sent_requests',
  };

  List<Map<String, Object?>> _mapsFromResult(Object? result) {
    if (result is List) {
      return [
        for (final item in result)
          if (item is Map) Map<String, Object?>.from(item),
      ];
    }
    if (result is Map) {
      return [Map<String, Object?>.from(result)];
    }
    return const [];
  }

  String _requiredString(Object? value) {
    final result = value?.toString() ?? '';
    if (result.isEmpty) {
      throw const SocialRepositoryException('Respuesta social inesperada.');
    }
    return result;
  }

  int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _doubleValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}

class UnavailableSocialRepository implements SocialRepository {
  const UnavailableSocialRepository();

  Never _unavailable() => throw const SocialRepositoryException(
    'Falta la configuración local de Supabase.',
  );

  @override
  bool get isConfigured => false;
  @override
  String? get currentEmail => null;
  @override
  String? get currentUserId => null;
  @override
  bool get hasSession => false;
  @override
  Future<void> acceptFollow(String userId) async => _unavailable();
  @override
  Future<void> cancelFollow(String userId) async => _unavailable();
  @override
  Future<void> deleteOwnAccount() async => _unavailable();
  @override
  Future<SocialProfile> createProfile({
    required String username,
    required String displayName,
    required String avatarKey,
    required bool isPublic,
    required String? mpassUserId,
  }) async => _unavailable();
  @override
  Future<void> follow(String userId) async => _unavailable();
  @override
  Future<List<FollowConnection>> getConnections(
    ConnectionListType type,
  ) async => _unavailable();
  @override
  Future<SocialProfile?> getMyProfile() async => _unavailable();
  @override
  Future<List<Trip>> getOwnTrips({required String localUserId}) async =>
      _unavailable();
  @override
  Future<List<UserAchievement>> getUserAchievements(String userId) async =>
      _unavailable();
  @override
  Future<AchievementCommunityRanking> getAchievementRanking(
    String categoryId,
  ) async => _unavailable();
  @override
  Future<CommunityRouteRanking> getCommunityRouteRanking({
    required String originStationId,
    required String destinationStationId,
  }) async => _unavailable();
  @override
  Future<HeadToHeadSummary> getHeadToHead(String otherUserId) async =>
      _unavailable();
  @override
  Future<SocialProfileDetails?> getProfileDetails(String userId) async =>
      _unavailable();
  @override
  Future<void> rejectFollow(String userId) async => _unavailable();
  @override
  Future<bool> restoreSession() async => false;
  @override
  Future<void> removeFollower(String userId) async => _unavailable();
  @override
  Future<List<SocialProfile>> searchProfiles(String query) async =>
      _unavailable();
  @override
  Future<void> sendOtp(String normalizedEmail) async => _unavailable();
  @override
  Future<void> signOut() async {}
  @override
  Future<void> unfollow(String userId) async => _unavailable();
  @override
  Future<SocialProfile> updateProfile({
    required String displayName,
    required String avatarKey,
    required bool isPublic,
  }) async => _unavailable();
  @override
  Future<void> upsertOwnTrips(List<Trip> trips) async => _unavailable();
  @override
  Future<void> refreshOwnAchievements() async => _unavailable();
  @override
  Future<void> verifyOtp({
    required String normalizedEmail,
    required String token,
  }) async => _unavailable();
}

class SocialRepositoryException implements Exception {
  const SocialRepositoryException(this.message);

  final String message;
}

SocialAuthFailureKind classifySupabaseAuthFailure(AuthException error) {
  switch (error.code) {
    case 'email_address_not_authorized':
      return SocialAuthFailureKind.emailNotAuthorized;
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return SocialAuthFailureKind.rateLimited;
    case 'otp_disabled':
    case 'email_provider_disabled':
      return SocialAuthFailureKind.otpDisabled;
    case 'signup_disabled':
      return SocialAuthFailureKind.signupDisabled;
    case 'email_address_invalid':
      return SocialAuthFailureKind.invalidEmail;
    case 'request_timeout':
      return SocialAuthFailureKind.connection;
  }

  if (error.statusCode == '429') {
    return SocialAuthFailureKind.rateLimited;
  }
  final status = int.tryParse(error.statusCode ?? '');
  if (status != null && status >= 500) {
    return SocialAuthFailureKind.serviceUnavailable;
  }
  if (error is AuthRetryableFetchException) {
    return SocialAuthFailureKind.connection;
  }
  if (error is AuthUnknownException) {
    final original = error.originalError;
    if (original is HandshakeException) {
      return SocialAuthFailureKind.secureConnection;
    }
    if (original is SocketException ||
        original is http.ClientException ||
        original is TimeoutException) {
      return SocialAuthFailureKind.connection;
    }
  }
  return SocialAuthFailureKind.unexpectedResponse;
}

String buildSafeSupabaseAuthDiagnostic(String operation, AuthException error) {
  final safeOperation = RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(operation)
      ? operation
      : 'unknown';
  final status = RegExp(r'^\d{3}$').hasMatch(error.statusCode ?? '')
      ? error.statusCode
      : 'none';
  final code = RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(error.code ?? '')
      ? error.code
      : 'none';
  return '[SOCIAL_DIAG] stage=auth event=error operation=$safeOperation '
      'type=${error.runtimeType} status=$status code=$code';
}
