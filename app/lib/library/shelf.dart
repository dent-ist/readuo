import 'package:cloud_firestore/cloud_firestore.dart';

enum ShelfVisibility { friends, private, public }

extension ShelfVisibilityDetails on ShelfVisibility {
  String get storageValue => name;

  String get label => switch (this) {
    ShelfVisibility.friends => 'Friends',
    ShelfVisibility.private => 'Private',
    ShelfVisibility.public => 'Public',
  };

  String get description => switch (this) {
    ShelfVisibility.friends => 'Visible to your accepted friends.',
    ShelfVisibility.private => 'Visible only to you.',
    ShelfVisibility.public => 'Visible to signed-in Readuo readers.',
  };
}

class Shelf {
  const Shelf({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    required this.visibility,
    required this.autoShareActivity,
    required this.bookCount,
    this.mutationOperationId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Shelf.fromFirestore(String id, Map<String, dynamic> data) {
    final storedVisibility = data['visibility'];
    final visibility = ShelfVisibility.values.firstWhere(
      (value) => value.storageValue == storedVisibility,
      orElse: () => data['isPublic'] == true
          ? ShelfVisibility.public
          : ShelfVisibility.private,
    );
    return Shelf(
      id: id,
      ownerId: data['ownerId'] as String? ?? '',
      name: (data['name'] as String? ?? 'Untitled shelf').trim(),
      description: (data['description'] as String?)?.trim(),
      visibility: visibility,
      autoShareActivity: data['autoShareActivity'] as bool? ?? false,
      bookCount: (data['bookCount'] as num?)?.toInt() ?? 0,
      mutationOperationId: data['mutationOperationId'] as String?,
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final ShelfVisibility visibility;
  final bool autoShareActivity;
  final int bookCount;
  final String? mutationOperationId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Shelf copyWith({
    String? name,
    String? description,
    ShelfVisibility? visibility,
    bool? autoShareActivity,
  }) {
    return Shelf(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      autoShareActivity: autoShareActivity ?? this.autoShareActivity,
      bookCount: bookCount,
      mutationOperationId: mutationOperationId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _readDate(Object? value) {
    return switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime date => date,
      _ => null,
    };
  }
}

enum ShelfMutationMode { move, remove }

class ShelfMutationOperation {
  const ShelfMutationOperation({
    required this.id,
    required this.ownerId,
    required this.sourceShelfId,
    required this.destinationShelfId,
    required this.mode,
    required this.totalCount,
    required this.processedCount,
  });

  factory ShelfMutationOperation.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ShelfMutationOperation(
      id: id,
      ownerId: data['ownerId'] as String? ?? '',
      sourceShelfId: data['sourceShelfId'] as String? ?? '',
      destinationShelfId: data['destinationShelfId'] as String?,
      mode: data['mode'] == 'move'
          ? ShelfMutationMode.move
          : ShelfMutationMode.remove,
      totalCount: (data['totalCount'] as num?)?.toInt() ?? 0,
      processedCount: (data['processedCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String ownerId;
  final String sourceShelfId;
  final String? destinationShelfId;
  final ShelfMutationMode mode;
  final int totalCount;
  final int processedCount;
}

class CreateShelfInput {
  const CreateShelfInput({
    required this.name,
    this.description = '',
    required this.visibility,
    required this.autoShareActivity,
  });

  final String name;
  final String description;
  final ShelfVisibility visibility;
  final bool autoShareActivity;

  String? get validationMessage {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return 'Enter a shelf name.';
    if (normalizedName.length > 60) {
      return 'Shelf names must be 60 characters or fewer.';
    }
    if (description.trim().length > 500) {
      return 'Shelf descriptions must be 500 characters or fewer.';
    }
    if (visibility == ShelfVisibility.private && autoShareActivity) {
      return 'Private shelves cannot automatically share activity.';
    }
    return null;
  }
}

class UpdateShelfInput {
  const UpdateShelfInput({
    required this.name,
    this.description = '',
    required this.visibility,
    required this.autoShareActivity,
  });

  final String name;
  final String description;
  final ShelfVisibility visibility;
  final bool autoShareActivity;

  String? get validationMessage => CreateShelfInput(
    name: name,
    description: description,
    visibility: visibility,
    autoShareActivity: autoShareActivity,
  ).validationMessage;
}
