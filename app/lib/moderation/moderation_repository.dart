import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const reportReasons = [
  'Harassment or bullying',
  'Inappropriate content',
  'Spam or misleading content',
  'Privacy concern',
  'Something else',
];

class ReportTarget {
  const ReportTarget({
    required this.kind,
    this.id,
    this.parentKind,
    this.parentId,
  });
  const ReportTarget.support()
    : kind = 'support',
      id = null,
      parentKind = null,
      parentId = null;

  final String kind;
  final String? id;
  final String? parentKind;
  final String? parentId;

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (id != null) 'id': id,
    if (parentKind != null) 'parentKind': parentKind,
    if (parentId != null) 'parentId': parentId,
  };
}

class ReportReceipt {
  const ReportReceipt(this.id, this.readerId);
  final String id;
  final String? readerId;
}

class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.kind,
    required this.reason,
    required this.note,
    required this.content,
    this.status = 'pending',
    this.reviewNote = '',
    this.decision,
    this.photoPath,
    this.photoUrl,
  });

  factory ModerationReport.fromJson(Map<String, dynamic> data) =>
      ModerationReport(
        id: data['id'] as String,
        kind: (data['target'] as Map)['kind'] as String,
        reason: data['reason'] as String,
        note: data['note'] as String? ?? '',
        content: data['contentSnapshot'] as String? ?? 'Support concern',
        status: data['status'] as String,
        reviewNote: data['reviewNote'] as String? ?? '',
        decision: data['decision'] as String?,
        photoPath: data['photoPath'] as String?,
        photoUrl: data['photoUrl'] as String?,
      );

  final String id;
  final String kind;
  final String reason;
  final String note;
  final String content;
  final String status;
  final String reviewNote;
  final String? decision;
  final String? photoPath;
  final String? photoUrl;
}

class ReportPage {
  const ReportPage(this.reports, this.nextCursor);
  final List<ModerationReport> reports;
  final String? nextCursor;
}

class ModerationFailure implements Exception {
  const ModerationFailure(this.message, {this.code = 'unknown'});
  final String message;
  final String code;
  @override
  String toString() => message;
}

abstract interface class ModerationRepository {
  Future<bool> isModerator();
  Future<ReportReceipt> submit({
    required String requestId,
    required ReportTarget target,
    required String reason,
    required String note,
  });
  Future<ReportPage> list({String? afterId});
  Future<void> decide({
    required String reportId,
    required String decision,
    required String note,
  });
}

typedef ModerationCallable =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, Object?> data,
    );

class CallableModerationRepository implements ModerationRepository {
  const CallableModerationRepository({
    required this.call,
    required this.checkModerator,
  });
  final ModerationCallable call;
  final Future<bool> Function() checkModerator;

  @override
  Future<bool> isModerator() => checkModerator();

  @override
  Future<ReportReceipt> submit({
    required String requestId,
    required ReportTarget target,
    required String reason,
    required String note,
  }) async {
    final result = await call('submitReport', {
      'requestId': requestId,
      'target': target.toJson(),
      'reason': reason,
      'note': note,
    });
    return ReportReceipt(
      result['reportId'] as String,
      result['readerId'] as String?,
    );
  }

  @override
  Future<ReportPage> list({String? afterId}) async {
    final result = await call('listReports', {
      if (afterId != null) 'afterId': afterId,
    });
    return ReportPage(
      (result['reports'] as List)
          .map(
            (value) => ModerationReport.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
      result['nextCursor'] as String?,
    );
  }

  @override
  Future<void> decide({
    required String reportId,
    required String decision,
    required String note,
  }) async {
    await call('moderationAction', {
      'reportId': reportId,
      'decision': decision,
      'note': note,
    });
  }
}

class FirebaseModerationTransport {
  FirebaseModerationTransport({
    required this.auth,
    required this.baseUri,
    required this.client,
  });
  final FirebaseAuth auth;
  final Uri baseUri;
  final http.Client client;

  Future<bool> isModerator() async =>
      (await auth.currentUser?.getIdTokenResult(true))?.claims?['moderator'] ==
      true;

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, Object?> data,
  ) async {
    final user = auth.currentUser;
    if (user == null)
      throw const ModerationFailure(
        'Sign in to continue.',
        code: 'unauthenticated',
      );
    final token = await user.getIdToken();
    if (token == null || auth.currentUser?.uid != user.uid)
      throw const ModerationFailure('Sign in again.');
    try {
      final response = await client
          .post(
            baseUri.resolve(name),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(const Duration(seconds: 40));
      if (auth.currentUser?.uid != user.uid)
        throw const ModerationFailure(
          'Your account changed. Reopen this screen.',
        );
      final envelope = jsonDecode(response.body) as Map<String, dynamic>;
      if (envelope['error'] case final Map error) {
        throw ModerationFailure(
          error['message'] as String? ?? 'Please retry.',
          code: error['status'] as String? ?? 'unknown',
        );
      }
      if (response.statusCode != 200 || envelope['result'] is! Map)
        throw const ModerationFailure(
          'The service is unavailable. Please retry.',
        );
      return Map<String, dynamic>.from(envelope['result'] as Map);
    } on ModerationFailure {
      rethrow;
    } catch (_) {
      throw const ModerationFailure(
        'Could not connect. Your details are still here. Please retry.',
      );
    }
  }
}

String newReportRequestId() => List.generate(
  24,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
