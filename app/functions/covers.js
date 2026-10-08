'use strict';

const { HttpsError } = require('firebase-functions/v2/https');

function parseCoverPath(path) {
  const match = typeof path === 'string' && /^bookCovers\/([A-Za-z0-9_-]{1,128})\/([A-Za-z0-9_-]{1,128})\/([A-Za-z0-9]{20,64})$/.exec(path);
  if (!match) throw new HttpsError('invalid-argument', 'Invalid book cover.');
  return { ownerId: match[1], bookId: match[2] };
}

async function loadCover(request, db, bucket) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to view this cover.');
  const path = request.data?.path;
  const { ownerId } = parseCoverPath(path);
  const [active, ownerActive, leftBlock, rightBlock] = await db.getAll(
    db.doc(`activeAccounts/${uid}`), db.doc(`activeAccounts/${ownerId}`),
    db.doc(`blocks/${uid}/blocked/${ownerId}`), db.doc(`blocks/${ownerId}/blocked/${uid}`));
  if (!active.exists || !ownerActive.exists || leftBlock.exists || rightBlock.exists) throw new HttpsError('permission-denied', 'This cover is unavailable.');
  const books = await db.collectionGroup('books').where('coverStoragePath', '==', path).limit(2).get();
  let allowed = false;
  for (const book of books.docs) {
    const data = book.data();
    if (data.ownerId !== ownerId || data.coverUrl !== path || book.ref.parent.parent?.parent.id !== 'shelves') continue;
    const shelf = await book.ref.parent.parent.get();
    if (!shelf.exists || shelf.data().ownerId !== ownerId || shelf.data().mutationOperationId) continue;
    if (uid === ownerId) { allowed = true; break; }
    if (data.isOwned !== true) continue;
    if (shelf.data().visibility === 'public') { allowed = true; break; }
    if (shelf.data().visibility === 'friends') {
      const relationships = await db.getAll(db.doc(`friendships/${uid}--${ownerId}`), db.doc(`friendships/${ownerId}--${uid}`));
      if (relationships.some(document => document.exists)) { allowed = true; break; }
    }
  }
  if (!allowed) throw new HttpsError('permission-denied', 'This cover is unavailable.');
  const file = bucket.file(path);
  const [metadata] = await file.getMetadata();
  if (Number(metadata.size) > 5 * 1024 * 1024 || !['image/jpeg', 'image/png'].includes(metadata.contentType)) throw new HttpsError('failed-precondition', 'Invalid cover image.');
  const [bytes] = await file.download();
  return { bytes: bytes.toString('base64') };
}

async function cleanOrphanCovers(db, bucket, now = Date.now()) {
  let cursor;
  do {
    const [files, next] = await bucket.getFiles({ prefix: 'bookCovers/', maxResults: 100, autoPaginate: false, pageToken: cursor });
    for (const file of files) {
      const [metadata] = await file.getMetadata();
      if (now - Date.parse(metadata.timeCreated) < 24 * 60 * 60 * 1000) continue;
      const books = await db.collectionGroup('books').where('coverStoragePath', '==', file.name).limit(1).get();
      if (books.empty) await file.delete({ ignoreNotFound: true, ifGenerationMatch: metadata.generation });
    }
    cursor = next?.pageToken;
  } while (cursor);
}

async function removeDeletedCover(data, db, bucket) {
  if (!data?.coverStoragePath) return;
  const { ownerId } = parseCoverPath(data.coverStoragePath);
  if (data.ownerId !== ownerId) return;
  const remaining = await db.collectionGroup('books').where('coverStoragePath', '==', data.coverStoragePath).limit(1).get();
  if (remaining.empty) await bucket.file(data.coverStoragePath).delete({ ignoreNotFound: true });
}

module.exports = { parseCoverPath, loadCover, cleanOrphanCovers, removeDeletedCover };
