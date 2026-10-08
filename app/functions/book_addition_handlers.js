'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const logger = require('firebase-functions/logger');
const { createBookAdditions } = require('./book_additions');

const service = () => createBookAdditions({ database: getFirestore(), messaging: getMessaging(), diagnostic: code => logger.warn(code) });
const options = { region: 'us-central1', maxInstances: 3, retry: true, timeoutSeconds: 120 };

exports.collectBookAddition = onDocumentCreated({ ...options, document: 'shelves/{shelfId}/books/{bookId}/activities/{activityId}' }, event => {
  if (event.data) return service().record(event.data.ref.path, event.data.data());
});
exports.flushBookAdditions = onSchedule({ region: 'us-central1', schedule: 'every 1 minutes', maxInstances: 1, timeoutSeconds: 540 }, () => service().sweep());
exports.deliverBookAdditionPush = onDocumentCreated({ ...options, document: 'users/{userId}/bookAdditionNotifications/{notificationId}' }, event => {
  if (event.data) return service().deliver(event.data.ref, event.params.userId, event.params.notificationId);
});
