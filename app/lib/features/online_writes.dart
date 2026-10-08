import 'package:cloud_firestore/cloud_firestore.dart';

extension OnlineDocumentWrites on DocumentReference<Map<String, dynamic>> {
  Future<void> setOnline(Map<String, dynamic> data, [SetOptions? options]) =>
      firestore.runTransaction((transaction) async {
        await transaction.get(this);
        transaction.set(this, data, options);
      }, maxAttempts: 1);

  Future<void> updateOnline(Map<String, dynamic> data) =>
      firestore.runTransaction((transaction) async {
        await transaction.get(this);
        transaction.update(this, data);
      }, maxAttempts: 1);

  Future<void> deleteOnline() => firestore.runTransaction((transaction) async {
    await transaction.get(this);
    transaction.delete(this);
  }, maxAttempts: 1);
}
