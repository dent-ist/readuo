'use strict';
const { randomUUID } = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');

const leaseMillis = 660000;
const graceMillis = 24 * 60 * 60 * 1000;
function ownerPath(path, uid) {
  return typeof path === 'string' && new RegExp(`^profilePhotos/${uid}/[A-Za-z0-9]{20,64}$`).test(path);
}
function urlPath(url, bucket) {
  try {
    const parsed = new URL(url);
    const match = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(parsed.pathname);
    return parsed.protocol === 'https:' && parsed.hostname === 'firebasestorage.googleapis.com' &&
      match && decodeURIComponent(match[1]) === bucket ? decodeURIComponent(match[2]) : null;
  } catch (_) { return null; }
}
function requireUid(request) {
  const uid = request.auth?.uid;
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw new HttpsError('unauthenticated', 'Sign in again.');
  return uid;
}

async function withProfileLease(uid, db, action, now = Date.now) {
  const token = randomUUID();
  const reference = db.doc(`profileWriteLeases/${uid}`);
  await db.runTransaction(async transaction => {
    const active = await transaction.get(db.doc(`activeAccounts/${uid}`));
    const deleting = await transaction.get(db.doc(`accountDeletions/${uid}`));
    const lease = await transaction.get(reference);
    if (!active.exists || deleting.exists) throw new HttpsError('permission-denied', 'This account is unavailable.');
    if (lease.exists && lease.data().until > now()) throw new HttpsError('aborted', 'Another profile update is finishing. Retry shortly.');
    transaction.set(reference, { ownerId: uid, token, until: now() + leaseMillis });
  });
  const assertHeld = async transaction => {
    const lease = await transaction.get(reference);
    if (!lease.exists || lease.data().token !== token || lease.data().until <= now()) {
      throw new HttpsError('aborted', 'This profile operation expired. Please retry.');
    }
  };
  const check = () => db.runTransaction(assertHeld);
  try { return await action({ assertHeld, check }); }
  finally {
    await db.runTransaction(async transaction => {
      const lease = await transaction.get(reference);
      if (lease.exists && lease.data().token === token) transaction.delete(reference);
    });
  }
}

function createProfileMedia({ db, auth, bucket, now = Date.now }) {
  async function reserve(request) {
    const uid = requireUid(request);
    if (request.data && Object.keys(request.data).length) throw new HttpsError('invalid-argument', 'No fields expected.');
    return withProfileLease(uid, db, async lease => {
      const photoId = db.collection('profilePhotoUploads').doc().id;
      const path = `profilePhotos/${uid}/${photoId}`;
      await db.runTransaction(async transaction => {
        await lease.assertHeld(transaction);
        transaction.set(db.doc(`profilePhotoUploads/${photoId}`), { ownerId: uid, path, createdAt: now(), state: 'reserved' });
      });
      return { path };
    }, now);
  }

  async function save(request) {
    const uid = requireUid(request);
    const data = request.data;
    if (!data || typeof data !== 'object' || Array.isArray(data) ||
        Object.keys(data).some(key => !['displayName', 'path'].includes(key)) ||
        typeof data.displayName !== 'string' || !data.displayName.trim() || data.displayName.trim().length > 80 ||
        (data.path != null && !ownerPath(data.path, uid))) throw new HttpsError('invalid-argument', 'Check your name and photo.');
    return withProfileLease(uid, db, async lease => {
      const reference = db.doc(`readerProfiles/${uid}`);
      const profile = await reference.get();
      if (!profile.exists) throw new HttpsError('failed-precondition', 'Your reader profile is not ready. Reopen it and retry.');
      const previous = profile.data();
      const user = await auth.getUser(uid);
      let photoURL = user.photoURL || null;
      let path = urlPath(photoURL, bucket.name);
      if (data.path != null) {
        path = data.path;
        const operation = await db.doc(`profilePhotoUploads/${path.split('/').at(-1)}`).get();
        if (!operation.exists || operation.data().ownerId !== uid || operation.data().path !== path || operation.data().state === 'removed') {
          throw new HttpsError('failed-precondition', 'Choose this photo again.');
        }
        const file = bucket.file(path);
        const [metadata] = await file.getMetadata();
        if (Number(metadata.size) <= 0 || Number(metadata.size) > 5 * 1024 * 1024 || !['image/jpeg', 'image/png'].includes(metadata.contentType)) {
          throw new HttpsError('invalid-argument', 'Choose a JPEG or PNG photo smaller than 5 MB.');
        }
        let downloadToken = metadata.metadata?.firebaseStorageDownloadTokens?.split(',')[0];
        if (!downloadToken) {
          downloadToken = randomUUID();
          await file.setMetadata({ metadata: { ...metadata.metadata, firebaseStorageDownloadTokens: downloadToken } });
        }
        photoURL = `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}/o/${encodeURIComponent(path)}?alt=media&token=${downloadToken}`;
      }
      const name = data.displayName.trim();
      await db.runTransaction(async transaction => {
        await lease.assertHeld(transaction);
        if (data.path != null) {
          const operation = db.doc(`profilePhotoUploads/${path.split('/').at(-1)}`);
          const current = await transaction.get(operation);
          if (!current.exists || current.data().state === 'removed') throw new HttpsError('aborted', 'Choose this photo again.');
          transaction.update(operation, { state: 'committing' });
        }
      });
      await auth.updateUser(uid, { displayName: name, photoURL });
      await db.runTransaction(async transaction => {
        await lease.assertHeld(transaction);
        const active = await transaction.get(db.doc(`activeAccounts/${uid}`));
        const deleting = await transaction.get(db.doc(`accountDeletions/${uid}`));
        const current = await transaction.get(reference);
        if (!active.exists || deleting.exists || !current.exists) throw new HttpsError('permission-denied', 'The account is being removed.');
        const currentData = current.data();
        if (currentData.photoUrl !== previous.photoUrl && currentData.photoUrl !== photoURL) throw new HttpsError('aborted', 'Another device updated this profile. Reopen and retry.');
        transaction.update(reference, { displayName: name, photoUrl: photoURL,
          photoStoragePath: ownerPath(path, uid) ? path : require('firebase-admin/firestore').FieldValue.delete(),
          updatedAt: require('firebase-admin/firestore').FieldValue.serverTimestamp() });
        if (data.path != null) transaction.update(db.doc(`profilePhotoUploads/${path.split('/').at(-1)}`), { state: 'committed' });
      });
      return { displayName: name, photoUrl: photoURL };
    }, now);
  }

  async function reconcile() {
    let pageToken;
    do {
      const [files, next] = await bucket.getFiles({ prefix: 'profilePhotos/', maxResults: 100, autoPaginate: false, pageToken });
      for (const file of files) {
        const [metadata] = await file.getMetadata();
        if (metadata.metadata?.readuoManaged !== 'v2' || now() - Date.parse(metadata.timeCreated) < graceMillis) continue;
        const uid = file.name.split('/')[1];
        if (!ownerPath(file.name, uid)) continue;
        try {
          await withProfileLease(uid, db, async lease => {
            const user = await auth.getUser(uid);
            const profile = await db.doc(`readerProfiles/${uid}`).get();
            const data = profile.data() || {};
            if (urlPath(user.photoURL, bucket.name) === file.name || data.photoStoragePath === file.name || urlPath(data.photoUrl, bucket.name) === file.name) return;
            const operation = db.doc(`profilePhotoUploads/${file.name.split('/').at(-1)}`);
            await db.runTransaction(async transaction => {
              await lease.assertHeld(transaction);
              const current = await transaction.get(operation);
              if (current.exists && current.data().state === 'committing') throw new HttpsError('aborted', 'An ambiguous profile save must be retained.');
              transaction.set(operation, { ownerId: uid, path: file.name, state: 'removed', updatedAt: now() });
            });
            await lease.check();
            await file.delete({ ignoreNotFound: true, ifGenerationMatch: metadata.generation });
            await operation.delete();
          }, now);
        } catch (error) {
          if (!['aborted', 'permission-denied', 'auth/user-not-found', 404].includes(error.code)) throw error;
        }
      }
      pageToken = next?.pageToken;
    } while (pageToken);
    let cursor;
    while (true) {
    let query = db.collection('profilePhotoUploads').where('createdAt', '<', now() - graceMillis).orderBy('createdAt').limit(100);
    if (cursor) query = query.startAfter(cursor);
    const abandoned = await query.get();
    for (const operation of abandoned.docs) {
      const data = operation.data();
      if (!ownerPath(data.path, data.ownerId)) continue;
      try {
        await withProfileLease(data.ownerId, db, async lease => {
          const [exists] = await bucket.file(data.path).exists();
          if (!exists) await db.runTransaction(async transaction => {
            await lease.assertHeld(transaction);
            transaction.delete(operation.ref);
          });
        }, now);
      } catch (error) {
        if (!['aborted', 'permission-denied'].includes(error.code)) throw error;
      }
    }
    if (abandoned.docs.length < 100) break;
    cursor = abandoned.docs.at(-1);
    }
  }
  return { reserve, save, reconcile };
}

async function removeInactiveUpload(object, db, bucket) {
  const match = /^(?:profilePhotos|circlePosts|bookCovers)\/([A-Za-z0-9_-]{1,128})\//.exec(object.name || '');
  if (!match) return;
  const uid = match[1];
  const [active, deleting] = await db.getAll(db.doc(`activeAccounts/${uid}`), db.doc(`accountDeletions/${uid}`));
  let discard = !active.exists || deleting.exists;
  if (!discard && object.metadata?.readuoManaged === 'v2' && ownerPath(object.name, uid)) {
    const operation = await db.doc(`profilePhotoUploads/${object.name.split('/').at(-1)}`).get();
    discard = !operation.exists || operation.data().path !== object.name || operation.data().ownerId !== uid || operation.data().state === 'removed';
  }
  if (discard) await bucket.file(object.name).delete({ ignoreNotFound: true, ifGenerationMatch: object.generation });
}
module.exports = { createProfileMedia, withProfileLease, removeInactiveUpload, urlPath, ownerPath, leaseMillis };
