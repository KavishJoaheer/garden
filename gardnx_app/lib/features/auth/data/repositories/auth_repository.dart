import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/user_model.dart';
import '../../../../shared/services/session_service.dart';

/// Repository that handles all Firebase Authentication and user document
/// operations for the GardNx application.
class AuthRepository {
  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final SessionService _sessionService;

  AuthRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _sessionService = SessionService(
          firebaseAuth: firebaseAuth ?? FirebaseAuth.instance,
        );

  /// Reference to the users collection in Firestore.
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// Returns the currently signed-in [User], or null if not signed in.
  User? get currentUser => _firebaseAuth.currentUser;

  /// A stream that emits the current [User] whenever the auth state changes
  /// (sign in, sign out, token refresh).
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  /// Signs in an existing user with [email] and [password].
  ///
  /// Returns the [UserCredential] on success.
  /// Throws a [FirebaseAuthException] on failure.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    // Create Firestore document if it was never created (e.g. signed up before
    // rules were deployed).
    if (credential.user != null) {
      final doc = await _usersCollection.doc(credential.user!.uid).get();
      if (!doc.exists) {
        await createUserDocument(credential.user!);
      }
      await _sessionService.startSession();
    }
    return credential;
  }

  /// Registers a new user with [email], [password], and [displayName].
  ///
  /// After creating the Firebase Auth account, this also:
  /// 1. Sets the user's display name on the auth profile.
  /// 2. Creates a corresponding document in the Firestore `users` collection.
  ///
  /// Returns the [UserCredential] on success.
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // Update the display name on the Firebase Auth profile.
    await credential.user?.updateDisplayName(displayName.trim());

    // Create the user document in Firestore.
    if (credential.user != null) {
      await createUserDocument(credential.user!, displayName: displayName);
      await _sessionService.startSession();
    }

    return credential;
  }

  /// Signs the current user out.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await _sessionService.clearSession();
  }

  /// Deletes the current user's account, cascading through all owned data.
  ///
  /// Order: gardens (+ their beds/layouts/events/tasks subcollections) →
  /// user-owned plants in the shared catalog → users/{uid} → Firebase Auth
  /// account → local sign-out. Each step runs while auth privileges are
  /// still valid so Firestore rules accept the writes.
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;
    final uid = user.uid;

    await _deleteOwnedGardens(uid);
    await _deleteOwnedPlants(uid);
    await _usersCollection.doc(uid).delete();
    await user.delete();
    await signOut();
  }

  Future<void> _deleteOwnedGardens(String uid) async {
    final gardens = await _firestore
        .collection('gardens')
        .where('userId', isEqualTo: uid)
        .get();
    for (final garden in gardens.docs) {
      for (final sub in const ['beds', 'layouts', 'events', 'tasks']) {
        await _deleteSubcollection(garden.reference.collection(sub));
      }
      await garden.reference.delete();
    }
  }

  Future<void> _deleteOwnedPlants(String uid) async {
    final snapshot = await _firestore
        .collection('plants')
        .where('userId', isEqualTo: uid)
        .get();
    await _deleteDocs(snapshot.docs.map((d) => d.reference));
  }

  /// Deletes every doc in [col] in 400-doc batches.
  Future<void> _deleteSubcollection(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final snapshot = await col.get();
    await _deleteDocs(snapshot.docs.map((d) => d.reference));
  }

  Future<void> _deleteDocs(Iterable<DocumentReference> refs) async {
    const chunkSize = 400;
    final list = refs.toList();
    for (var i = 0; i < list.length; i += chunkSize) {
      final batch = _firestore.batch();
      for (final ref in list.skip(i).take(chunkSize)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  /// Sends a password-reset email to the given [email] address.
  Future<void> resetPassword({required String email}) async {
    await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
  }

  /// Creates (or overwrites) a Firestore document in the `users` collection
  /// for the given [user].
  ///
  /// Optionally pass a [displayName] that differs from `user.displayName`.
  Future<void> createUserDocument(
    User user, {
    String? displayName,
  }) async {
    final userModel = UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: displayName?.trim() ?? user.displayName,
      photoUrl: user.photoURL,
      createdAt: DateTime.now(),
    );

    await _usersCollection.doc(user.uid).set(
          userModel.toFirestore(),
          SetOptions(merge: true),
        );
  }

  /// Fetches the [UserModel] for the given [userId] from Firestore.
  ///
  /// Returns null if no document exists for that user.
  Future<UserModel?> getUserModel(String userId) async {
    final doc = await _usersCollection.doc(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromFirestore(doc);
  }

  /// Returns a real-time stream of the [UserModel] for the given [userId].
  Stream<UserModel?> watchUserModel(String userId) {
    return _usersCollection.doc(userId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromFirestore(doc);
    });
  }
}
