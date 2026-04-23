import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/constants/api_constants.dart';
import '../../../../config/constants/firebase_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/models/garden_photo.dart';
import '../../domain/models/segmentation_result.dart';

/// Repository responsible for garden photo analysis operations including
/// upload, segmentation, result retrieval, and garden creation.
class AnalysisRepository {
  final ApiClient _apiClient;
  final FirebaseFirestore _firestore;

  AnalysisRepository({
    required ApiClient apiClient,
    FirebaseFirestore? firestore,
  })  : _apiClient = apiClient,
        _firestore = firestore ?? FirebaseFirestore.instance;

  String? _resolvePhotoUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    return '${ApiConstants.baseUrl}$imageUrl';
  }

  /// Uploads a garden photo to the backend for analysis.
  ///
  /// Returns a [GardenPhoto] with the server-assigned id and imageUrl.
  Future<GardenPhoto> uploadPhoto({
    required File imageFile,
    required String userId,
    Rect? cropRect,
    void Function(int, int)? onProgress,
  }) async {
    try {
      final additionalFields = <String, dynamic>{'userId': userId};
      if (cropRect != null) {
        additionalFields['crop_x'] = cropRect.left.toString();
        additionalFields['crop_y'] = cropRect.top.toString();
        additionalFields['crop_width'] = cropRect.width.toString();
        additionalFields['crop_height'] = cropRect.height.toString();
      }

      final response = await _apiClient.uploadFile<Map<String, dynamic>>(
        ApiConstants.analysisUpload,
        file: imageFile,
        fieldName: 'file',
        additionalFields: additionalFields,
        onSendProgress: onProgress,
      );

      final data = response.data;
      if (data == null) {
        throw const UploadException(
          message: 'Upload succeeded but returned no data.',
        );
      }

      final photo = GardenPhoto.fromJson(data);
      return photo.copyWith(
        localPath: imageFile.path,
        imageUrl: _resolvePhotoUrl(photo.imageUrl),
      );
    } on DioException catch (e) {
      throw UploadException(
        message: e.response?.data?['message'] as String? ??
            'Failed to upload photo. Please try again.',
        code: e.response?.statusCode?.toString(),
        originalError: e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw UploadException(
        message: 'An unexpected error occurred during upload.',
        originalError: e,
      );
    }
  }

  /// Triggers segmentation analysis on a previously uploaded photo.
  ///
  /// Returns a [SegmentationResult] with detected zones.
  Future<SegmentationResult> segmentPhoto({
    required String photoId,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '${ApiConstants.analysisSegment}/$photoId',
      );

      final data = response.data;
      if (data == null) {
        throw const AnalysisException(
          message: 'Segmentation returned no data.',
        );
      }

      return SegmentationResult.fromJson(data);
    } on DioException catch (e) {
      throw AnalysisException(
        message: e.response?.data?['message'] as String? ??
            'Segmentation analysis failed. Try manual mode.',
        code: e.response?.statusCode?.toString(),
        originalError: e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AnalysisException(
        message: 'An unexpected error occurred during analysis.',
        originalError: e,
      );
    }
  }

  /// Retrieves the segmentation result for a given [segmentationId].
  Future<SegmentationResult> getResult({
    required String segmentationId,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '${ApiConstants.analysisResult}/$segmentationId',
      );

      final data = response.data;
      if (data == null) {
        throw const AnalysisException(
          message: 'Could not retrieve analysis result.',
        );
      }

      return SegmentationResult.fromJson(data);
    } on DioException catch (e) {
      throw AnalysisException(
        message: e.response?.data?['message'] as String? ??
            'Failed to retrieve analysis result.',
        code: e.response?.statusCode?.toString(),
        originalError: e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AnalysisException(
        message: 'An unexpected error occurred retrieving the result.',
        originalError: e,
      );
    }
  }

  /// Saves a garden definition to Firestore from the analysis results.
  ///
  /// Returns the Firestore document ID of the created garden.
  Future<String> saveGarden({
    required String userId,
    required String name,
    required GardenPhoto photo,
    required SegmentationResult segmentation,
    required List<String> selectedZoneIds,
  }) async {
    try {
      final gardenRef =
          _firestore.collection(FirebaseConstants.gardensCollection).doc();

      final selectedZones = segmentation.zones
          .where((z) => selectedZoneIds.contains(z.zoneId))
          .toList();

      final gardenData = {
        FirebaseConstants.fieldUserId: userId,
        'name': name,
        'photo': photo.toFirestore(),
        'segmentationId': segmentation.segmentationId,
        'zones': selectedZones.map((z) => z.toJson()).toList(),
        'totalAreaSqM': selectedZones.fold<double>(
          0.0,
          (acc, z) => acc + z.areaSqMeters,
        ),
        'isAiAnalyzed': true,
        FirebaseConstants.fieldCreatedAt: FieldValue.serverTimestamp(),
        FirebaseConstants.fieldUpdatedAt: FieldValue.serverTimestamp(),
      };

      await gardenRef.set(gardenData);

      debugPrint('Garden saved with ID: ${gardenRef.id}');
      return gardenRef.id;
    } on FirebaseException catch (e) {
      throw FirestoreException(
        message: 'Failed to save garden: ${e.message}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw FirestoreException(
        message: 'An unexpected error occurred while saving the garden.',
        originalError: e,
      );
    }
  }
}

/// Provider for the singleton [AnalysisRepository] instance.
final analysisRepositoryProvider = Provider<AnalysisRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AnalysisRepository(apiClient: apiClient);
});
