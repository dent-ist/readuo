'use strict';

const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { HttpsError } = require('firebase-functions/v2/https');

async function activateAccount(uid, database = getFirestore(), auth = getAuth()) {
  return database.runTransaction(async transaction => {
    const active = database.doc(`activeAccounts/${uid}`);
    const marker = database.doc(`accountDeletions/${uid}`);
    const [registration, deletion] = await transaction.getAll(active, marker);
    if (deletion.exists) throw new HttpsError('failed-precondition', 'Account deletion is processing.');
    let user;
    try { user = await auth.getUser(uid); } catch (error) {
      if (error.code === 'auth/user-not-found') throw new HttpsError('unauthenticated', 'This account no longer exists.');
      throw error;
    }
    if (user.disabled) throw new HttpsError('permission-denied', 'This account is unavailable.');
    if (!registration.exists) transaction.create(active, { createdAt: FieldValue.serverTimestamp() });
    return { active: true };
  });
}

module.exports = { activateAccount };
