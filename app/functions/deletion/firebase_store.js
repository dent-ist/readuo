'use strict';

const { createHash } = require('node:crypto');
const { FieldPath } = require('firebase-admin/firestore');

function createDeletionStore(db) {
  const marker = uid => db.doc(`accountDeletions/${uid}`);
  const rootRef = (uid, path) => marker(uid).collection('roots').doc(createHash('sha256').update(path).digest('hex'));
  return {
    async hasActiveProfileWriter(uid, now) {
      const lease = await db.doc(`profileWriteLeases/${uid}`).get();
      return lease.exists && lease.data().until > now;
    },
    async get(uid) {
      const snapshot = await marker(uid).get();
      return snapshot.exists ? snapshot.data() : null;
    },
    async begin(uid, job) {
      return db.runTransaction(async transaction => {
        const snapshot = await transaction.get(marker(uid));
        if (snapshot.exists) return snapshot.data();
        transaction.create(marker(uid), job);
        transaction.delete(db.doc(`activeAccounts/${uid}`));
        return job;
      });
    },
    async acquire(uid, leaseToken, now) {
      return db.runTransaction(async transaction => {
        const snapshot = await transaction.get(marker(uid));
        if (!snapshot.exists || snapshot.data().leaseUntil > now) return null;
        const job = { ...snapshot.data(), leaseToken, leaseUntil: now + 120000 };
        transaction.update(marker(uid), { leaseToken, leaseUntil: job.leaseUntil });
        return job;
      });
    },
    async checkpoint(uid, leaseToken, changes) {
      return db.runTransaction(async transaction => {
        const snapshot = await transaction.get(marker(uid));
        if (!snapshot.exists || snapshot.data().leaseToken !== leaseToken) return null;
        transaction.update(marker(uid), changes);
        return { ...snapshot.data(), ...changes };
      });
    },
    async release(uid, leaseToken, retrying, now) {
      await db.runTransaction(async transaction => {
        const snapshot = await transaction.get(marker(uid));
        if (snapshot.exists && snapshot.data().leaseToken === leaseToken) {
          transaction.update(marker(uid), { leaseToken: null, leaseUntil: 0, retrying, updatedAt: now });
        }
      });
    },
    async page(group, cursor, limit) {
      let query = db.collectionGroup(group).orderBy(FieldPath.documentId()).limit(limit);
      if (cursor) query = query.startAfter(db.doc(cursor));
      const snapshot = await query.get();
      return snapshot.docs.map(document => ({ path: document.ref.path, data: document.data(), updateTime: document.updateTime }));
    },
    async rememberRoot(uid, path) {
      await rootRef(uid, path).set({ path });
    },
    async referencesRoots(uid, paths) {
      const ancestors = new Set();
      for (const path of paths) {
        const segments = path.split('/');
        if (segments.length % 2 !== 0) continue;
        for (let length = 2; length <= segments.length; length += 2) ancestors.add(segments.slice(0, length).join('/'));
      }
      if (!ancestors.size) return false;
      const snapshots = await db.getAll(...[...ancestors].map(path => rootRef(uid, path)));
      return snapshots.some(snapshot => snapshot.exists);
    },
    async removeTree(path) { await db.recursiveDelete(db.doc(path)); },
    async redact(document, patch) {
      await db.doc(document.path).update(patch, { lastUpdateTime: document.updateTime });
    },
    async finish(uid, leaseToken) {
      await db.recursiveDelete(marker(uid).collection('roots'));
      await db.runTransaction(async transaction => {
        const snapshot = await transaction.get(marker(uid));
        if (snapshot.data()?.leaseToken !== leaseToken) throw new Error('Deletion lease changed.');
        transaction.delete(marker(uid));
      });
    },
  };
}

function createDeletionMedia(bucket) {
  return {
    async removePage(prefix) {
      const [files] = await bucket.getFiles({ prefix, maxResults: 100, autoPaginate: false });
      for (const file of files) await file.delete({ ignoreNotFound: true });
      return files.length === 0;
    },
  };
}

module.exports = { createDeletionStore, createDeletionMedia };
