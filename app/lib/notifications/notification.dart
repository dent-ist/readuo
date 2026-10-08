enum NotificationType {
  friendRequest,
  requestAccepted,
  like,
  comment,
  booksAdded,
}

enum NotificationDestinationKind { request, reader, post, bookAddition }

class NotificationDestination {
  const NotificationDestination(
    this.kind,
    this.id, {
    this.commentId,
    this.isReview = false,
  });

  final NotificationDestinationKind kind;
  final String id;
  final String? commentId;
  final bool isReview;
}

class ReaduoNotification {
  const ReaduoNotification({
    required this.id,
    required this.recipientId,
    required this.actorId,
    required this.actorName,
    required this.type,
    required this.targetId,
    required this.createdAt,
    this.commentId,
    this.preview = '',
    this.isReview = false,
    this.readAt,
  });

  final String id;
  final String recipientId;
  final String actorId;
  final String actorName;
  final NotificationType type;
  final String targetId;
  final String? commentId;
  final String preview;
  final bool isReview;
  final DateTime createdAt;
  final DateTime? readAt;

  NotificationDestination get destination => NotificationDestination(
    switch (type) {
      NotificationType.friendRequest => NotificationDestinationKind.request,
      NotificationType.requestAccepted => NotificationDestinationKind.reader,
      NotificationType.like ||
      NotificationType.comment => NotificationDestinationKind.post,
      NotificationType.booksAdded => NotificationDestinationKind.bookAddition,
    },
    targetId,
    commentId: type == NotificationType.comment ? commentId : null,
    isReview: isReview,
  );

  String get title => switch (type) {
    NotificationType.friendRequest => '$actorName sent you a friend request',
    NotificationType.requestAccepted => '$actorName accepted your request',
    NotificationType.like =>
      '$actorName liked your ${isReview ? 'review' : 'post'}',
    NotificationType.comment =>
      '$actorName commented on your ${isReview ? 'review' : 'post'}',
    NotificationType.booksAdded => 'New books in your circle',
  };
}

class NotificationPreferences {
  const NotificationPreferences({
    this.friendRequest = true,
    this.requestAccepted = true,
    this.like = true,
    this.comment = true,
    this.booksAdded = true,
  });

  factory NotificationPreferences.fromMap(Map<String, dynamic> data) =>
      NotificationPreferences(
        friendRequest: data['friendRequest'] as bool? ?? true,
        requestAccepted: data['requestAccepted'] as bool? ?? true,
        like: data['like'] as bool? ?? true,
        comment: data['comment'] as bool? ?? true,
        booksAdded: data['booksAdded'] as bool? ?? true,
      );

  final bool friendRequest;
  final bool requestAccepted;
  final bool like;
  final bool comment;
  final bool booksAdded;

  bool enabled(NotificationType type) => switch (type) {
    NotificationType.friendRequest => friendRequest,
    NotificationType.requestAccepted => requestAccepted,
    NotificationType.like => like,
    NotificationType.comment => comment,
    NotificationType.booksAdded => booksAdded,
  };
}
