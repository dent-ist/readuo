'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { createModerationService } = require('./moderation/service');
const { ModerationError } = require('./moderation/policy');
const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onObjectFinalized } = require('firebase-functions/v2/storage');
const functionsV1 = require('firebase-functions/v1');
const { activateAccount } = require('./accounts');
const { createDeletionService } = require('./deletion/service');
const { createDeletionStore, createDeletionMedia } = require('./deletion/firebase_store');
const { DeletionError } = require('./deletion/policy');
const { loadCover, cleanOrphanCovers, removeDeletedCover } = require('./covers');
const { createProfileMedia, removeInactiveUpload } = require('./profile_media');

initializeApp();
const profileMedia = createProfileMedia({ db: getFirestore(), auth: getAuth(), bucket: getStorage().bucket() });
exports.reserveProfilePhoto = onCall({ maxInstances: 3, timeoutSeconds: 60 }, request => profileMedia.reserve(request));
exports.saveReaderProfile = onCall({ maxInstances: 3, timeoutSeconds: 60 }, request => profileMedia.save(request));
exports.reconcileProfilePhotos = onSchedule({ schedule: 'every 24 hours', maxInstances: 1, timeoutSeconds: 540 }, () => profileMedia.reconcile());
exports.removeInactiveAccountUpload = onObjectFinalized({ region: 'us-east1', bucket: 'readuo-b2f24.firebasestorage.app', maxInstances: 3, timeoutSeconds: 60, retry: true }, event => removeInactiveUpload(event.data, getFirestore(), getStorage().bucket()));
exports.loadBookCover = onCall({ maxInstances: 3, timeoutSeconds: 30 }, request => loadCover(request, getFirestore(), getStorage().bucket()));
exports.cleanOrphanBookCovers = onSchedule({ schedule: 'every 24 hours', maxInstances: 1, timeoutSeconds: 540 }, () => cleanOrphanCovers(getFirestore(), getStorage().bucket()));
exports.removeDeletedBookCover = onDocumentDeleted({ document: 'shelves/{shelfId}/books/{bookId}', maxInstances: 3 }, event => removeDeletedCover(event.data?.data(), getFirestore(), getStorage().bucket()));
const deletion = createDeletionService({
  store: createDeletionStore(getFirestore()),
  auth: getAuth(),
  media: createDeletionMedia(getStorage().bucket()),
});
exports.ensureActiveAccount = onCall({ maxInstances: 3 }, request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  return activateAccount(request.auth.uid);
});
exports.registerReaduoAccount = functionsV1.auth.user().onCreate(async user => {
  try { await activateAccount(user.uid); } catch (error) {
    if (!['unauthenticated', 'failed-precondition'].includes(error.code)) throw error;
  }
});
for (const [name, method] of [['startAccountDeletion', 'start'], ['getAccountDeletionStatus', 'status']]) {
  exports[name] = onCall({ maxInstances: 3 }, async request => {
    try { return await deletion[method](request); } catch (error) {
      if (error instanceof DeletionError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Deletion could not be confirmed. Please retry.');
    }
  });
}
exports.processAccountDeletion = onDocumentCreated({ document: 'accountDeletions/{uid}', retry: true, maxInstances: 3, timeoutSeconds: 120 }, event => deletion.work(event.params.uid));
exports.resumeAccountDeletions = onSchedule({ schedule: 'every 5 minutes', maxInstances: 1, timeoutSeconds: 540 }, async () => {
  const jobs = await getFirestore().collection('accountDeletions').orderBy('updatedAt').limit(10).get();
  for (const job of jobs.docs) {
    try { await deletion.work(job.id); } catch (_) {}
  }
});
const service = createModerationService(getFirestore(), () => Timestamp.now(), {
  async deletePhotos(prefix) {
    await getStorage().bucket().deleteFiles({ prefix });
  },
  async redact(uid) {
    try {
      await getAuth().updateUser(uid, { displayName: 'Reader', photoURL: null });
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
    }
    await getStorage().bucket().deleteFiles({ prefix: `profilePhotos/${uid}/` });
  },
});
for (const name of ['submitReport', 'moderationAction', 'listReports', 'checkContent']) {
  exports[name] = onCall({ enforceAppCheck: false, maxInstances: 10 }, async request => {
    try {
      if (!request.auth || !(await getFirestore().doc(`activeAccounts/${request.auth.uid}`).get()).exists) {
        throw new ModerationError('unauthenticated', 'Sign in with an active account.');
      }
      return await service[name](request);
    } catch (error) {
      if (error instanceof ModerationError) throw new HttpsError(error.code, error.message, error.details);
      throw new HttpsError('internal', 'The request could not be completed. Please retry.');
    }
  });
}

for (const [name, handler] of Object.entries(require('./notifications'))) {
  if (!name.startsWith('_')) exports[name] = handler;
}

Object.assign(exports, require('./book_addition_handlers'));
