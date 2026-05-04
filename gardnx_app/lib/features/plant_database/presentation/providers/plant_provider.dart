import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/config/constants/api_constants.dart';
import 'package:gardnx_app/core/network/api_interceptors.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';
import 'package:gardnx_app/features/plant_database/domain/models/companion_rule.dart';
import 'package:gardnx_app/features/plant_database/data/repositories/plant_repository.dart';
import 'package:gardnx_app/shared/providers/firebase_providers.dart';

// autoDispose ensures the in-memory plant cache is cleared whenever the
// provider is no longer watched (e.g., after sign-out), preventing
// user A's custom plants from showing for user B.
final plantRepositoryProvider =
    Provider.autoDispose<PlantRepository>((ref) => PlantRepository());

/// All plants (Firestore + local fallback), with Perenual image enrichment
/// applied when the backend is reachable.
///
/// The repository fetches curated + user-owned plants from Firestore. Then we
/// request the backend catalog (which runs Perenual enrichment server-side)
/// and merge in any image URLs that are missing locally.
final allPlantsProvider = FutureProvider<List<Plant>>((ref) async {
  final repo = ref.read(plantRepositoryProvider);
  final uid = ref.watch(currentFirebaseUserProvider)?.uid;

  // 1. Fetch from Firestore (curated + user-owned plants).
  final plants = await repo.getAllPlants(uid: uid);

  // 2. Attempt to enrich with backend image URLs (best-effort; never blocks).
  try {
    final dio = ref.read(_enrichDioProvider);
    final response = await dio.get<List<dynamic>>(
      '/plants/catalog',
      queryParameters: {'enrich': 'true'},
    );
    if (response.statusCode == 200 && response.data != null) {
      final backendPlants = response.data!
          .map((e) => Plant.fromJson(e as Map<String, dynamic>))
          .toList();
      // Build a lookup by plant ID and name (both keys used for matching).
      final byId = <String, Plant>{};
      final byName = <String, Plant>{};
      for (final bp in backendPlants) {
        byId[bp.id] = bp;
        byName[bp.name.toLowerCase()] = bp;
      }
      // Merge: if a local plant has no image, use backend's image URL.
      return plants.map((p) {
        if (p.imageUrl != null) return p;
        final match = byId[p.id] ?? byName[p.name.toLowerCase()];
        if (match?.imageUrl != null) {
          return p.copyWith(imageUrl: match!.imageUrl);
        }
        return p;
      }).toList();
    }
  } catch (_) {
    // Backend unreachable — just return unenriched plants.
  }

  return plants;
});

/// Dio instance used only for plant image enrichment (no auth required for catalog).
final _enrichDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
  dio.interceptors.add(AuthInterceptor());
  return dio;
});

/// Single plant by id
final plantByIdProvider =
    FutureProvider.family<Plant?, String>((ref, id) async {
  final repo = ref.read(plantRepositoryProvider);
  return repo.getPlantById(id);
});

/// Companion plants for a given plant id
final companionPlantsProvider =
    FutureProvider.family<List<Plant>, String>((ref, plantId) async {
  final repo = ref.read(plantRepositoryProvider);
  return repo.getCompanionPlants(plantId);
});

/// Companion rules for a given plant id
final companionRulesForPlantProvider =
    FutureProvider.family<List<CompanionRule>, String>((ref, plantId) async {
  final repo = ref.read(plantRepositoryProvider);
  final companions = await repo.getCompanionsForPlant(plantId);
  final incompatibles = await repo.getIncompatiblesForPlant(plantId);
  return [...companions, ...incompatibles];
});

/// Plants suitable for current month
final plantsForCurrentMonthProvider = FutureProvider<List<Plant>>((ref) async {
  final repo = ref.read(plantRepositoryProvider);
  return repo.getPlantsForMonth(DateTime.now().month);
});

// ---------------------------------------------------------------------------
// Global plant search — queries the Perenual database via the backend.
// Returns [] when query is too short or the backend is unreachable.
// Keyed on query string; auto-disposed when the widget leaves the tree.
// ---------------------------------------------------------------------------

final _globalSearchDio = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
  ));
  dio.interceptors.add(AuthInterceptor());
  return dio;
});

/// Saves a Perenual plant to the local Firestore collection.
/// Returns the new document ID on success.
final addPlantProvider =
    Provider<Future<String> Function(Plant)>((ref) {
  final repo = ref.read(plantRepositoryProvider);
  return (Plant plant) async {
    final uid = ref.read(currentFirebaseUserProvider)?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('Sign in required to save a plant.');
    }
    final id = await repo.addPlant(plant, uid: uid);
    ref.invalidate(allPlantsProvider);
    return id;
  };
});

/// Searches the Perenual global plant database through the backend.
/// Only fires for queries of 2+ characters.
final globalPlantSearchProvider =
    FutureProvider.family.autoDispose<List<Plant>, String>((ref, query) async {
  if (query.trim().length < 2) return [];

  try {
    final dio = ref.read(_globalSearchDio);
    final response = await dio.get<List<dynamic>>(
      '/plants/search',
      queryParameters: {'q': query.trim()},
    );
    final data = response.data ?? [];
    return data
        .map((e) => Plant.fromJson(e as Map<String, dynamic>))
        .toList();
  } on DioException {
    return []; // backend offline — silent fallback
  } catch (_) {
    return [];
  }
});
