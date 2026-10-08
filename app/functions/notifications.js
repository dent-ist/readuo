'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { notificationId, enabled, sameGeneration, acceptanceActors } = require('./notification_policy');
const { deliverPush } = require('./notification_delivery');

const options = { region: 'us-central1', maxInstances: 3, retry: true };

async function sourceAvailable(transaction, database, notice) {
  const { actorId, recipientId } = notice;
  if (actorId === recipientId) return false;
  const paths = [
    `blocks/${actorId}/blocked/${recipientId}`,
    `blocks/${recipientId}/blocked/${actorId}`,
    `readerProfiles/${actorId}`,
    `readerProfiles/${recipientId}`,
    `accountDeletions/${actorId}`,
    `accountDeletions/${recipientId}`,
    notice.sourcePath,
  ];
  const [outgoingBlock, incomingBlock, actor, recipient, actorDeletion, recipientDeletion, source] = await transaction.getAll(...paths.map(path => database.doc(path)));
  if (outgoingBlock.exists || incomingBlock.exists || !actor.exists || !recipient.exists || actorDeletion.exists || recipientDeletion.exists || !source.exists || !sameGeneration(source.data().createdAt, notice.sourceCreatedAt)) return false;
  if (notice.type === 'friendRequest') {
    return source.data().requesterId === actorId && source.data().recipientId === recipientId;
  }
  const friendships = await transaction.getAll(
    database.doc(`friendships/${actorId}--${recipientId}`),
    database.doc(`friendships/${recipientId}--${actorId}`),
  );
  if (!friendships.some(friendship => friendship.exists)) return false;
  if (notice.type === 'requestAccepted') return source.data().memberIds?.[0] === recipientId && source.data().memberIds?.[1] === actorId;
  const parent = await transaction.get(database.doc(`${notice.isReview ? 'circleReviews' : 'circlePosts'}/${notice.targetId}`));
  if (!parent.exists || parent.data().authorId !== recipientId || parent.data().moderationState === 'removed') return false;
  if (notice.type === 'like' && source.data().userId !== actorId) return false;
  if (notice.type === 'comment' && source.data().authorId !== actorId) return false;
  if (notice.isReview) {
    const review = parent.data();
    const [shelf, book] = await transaction.getAll(database.doc(`shelves/${review.shelfId}`), database.doc(`shelves/${review.shelfId}/books/${review.bookId}`));
    if (!shelf.exists || !book.exists || !['friends', 'public'].includes(shelf.data().visibility) || shelf.data().ownerId !== recipientId || book.data().ownerId !== recipientId || !sameGeneration(book.data().createdAt, review.bookCreatedAt)) return false;
  }
  return true;
}

async function recordNotification(source, notice) {
  const database = getFirestore();
  const sourceCreatedAt = source.data().createdAt;
  if (!sourceCreatedAt) return;
  const id = notificationId(source.ref.path, sourceCreatedAt);
  const reference = database.doc(`users/${notice.recipientId}/notifications/${id}`);
  const eventReference = database.doc(`notificationEvents/${id}`);
  const candidate = { ...notice, sourcePath: source.ref.path, sourceCreatedAt };
  await database.runTransaction(async transaction => {
    const [event, preferences, actor, recipient, actorDeletion, recipientDeletion] = await transaction.getAll(
      eventReference,
      database.doc(`users/${notice.recipientId}/preferences/notifications`),
      database.doc(`readerProfiles/${notice.actorId}`),
      database.doc(`readerProfiles/${notice.recipientId}`),
      database.doc(`accountDeletions/${notice.actorId}`),
      database.doc(`accountDeletions/${notice.recipientId}`),
    );
    if (event.exists || !actor.exists || !recipient.exists || actorDeletion.exists || recipientDeletion.exists) return;
    const allowed = enabled(preferences.data() || {}, notice.type) && await sourceAvailable(transaction, database, candidate);
    transaction.create(eventReference, { recipientId: notice.recipientId, actorId: notice.actorId, createdAt: FieldValue.serverTimestamp() });
    if (!allowed) return;
    transaction.create(reference, {
      ...candidate,
      actorName: actor.data()?.displayName || 'Reader',
      preview: '',
      readAt: null,
      createdAt: FieldValue.serverTimestamp(),
      pushState: 'pending',
    });
  });
}

exports.notifyFriendRequest = onDocumentCreated({ ...options, document: 'friendRequests/{pairId}' }, event => {
  if (!event.data) return;
  const data = event.data.data();
  return recordNotification(event.data, { type: 'friendRequest', recipientId: data.recipientId, actorId: data.requesterId, targetId: event.params.pairId, isReview: false, commentId: null });
});

exports.notifyRequestAccepted = onDocumentCreated({ ...options, document: 'friendships/{pairId}' }, event => {
  if (!event.data) return;
  const actors = acceptanceActors(event.data.data().memberIds);
  return recordNotification(event.data, { ...actors, type: 'requestAccepted', targetId: actors.actorId, isReview: false, commentId: null });
});

for (const [collection, isReview] of [['circlePosts', false], ['circleReviews', true]]) {
  for (const [subcollection, type] of [['likes', 'like'], ['comments', 'comment']]) {
    exports[`notify${isReview ? 'Review' : 'Post'}${type === 'like' ? 'Like' : 'Comment'}`] = onDocumentCreated({ ...options, document: `${collection}/{contentId}/${subcollection}/{interactionId}` }, async event => {
      if (!event.data) return;
      const parent = await getFirestore().doc(`${collection}/${event.params.contentId}`).get();
      if (!parent.exists) return;
      const actorId = event.data.data()[type === 'like' ? 'userId' : 'authorId'];
      return recordNotification(event.data, { type, actorId, recipientId: parent.data().authorId, targetId: event.params.contentId, isReview, commentId: type === 'comment' ? event.params.interactionId : null });
    });
  }
}

exports.deliverNotificationPush = onDocumentCreated({ ...options, timeoutSeconds: 120, document: 'users/{userId}/notifications/{notificationId}' }, async event => {
  if (!event.data) return;
  return deliverPush({
    database: getFirestore(), messaging: getMessaging(), reference: event.data.ref,
    userId: event.params.userId, notificationId: event.params.notificationId, sourceAvailable,
  });
});

exports._sourceAvailable = sourceAvailable;
