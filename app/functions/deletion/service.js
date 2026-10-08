'use strict';

const { randomUUID } = require('node:crypto');
const { DeletionError, caller, validateStart, groups, pathsIn, classify } = require('./policy');

function createDeletionService({ store, auth, media, now = Date.now, randomId = randomUUID }) {
  async function start(request) {
    const uid = validateStart(request, now());
    const existing = await store.get(uid);
    if (existing) return { status: 'processing', jobId: existing.jobId };
    let user;
    try { user = await auth.getUser(uid); } catch (error) {
      if (error.code === 'auth/user-not-found') throw new DeletionError('unauthenticated', 'This account no longer exists.');
      throw error;
    }
    if (user.uid !== uid || user.disabled || !user.providerData.some(provider => provider.providerId === 'google.com')) {
      throw new DeletionError('permission-denied', 'Verify the linked Google account to continue.');
    }
    const job = await store.begin(uid, {
      jobId: randomId(), phase: 'firestore', groupIndex: 0, cursor: null, pendingPath: null,
      createdAt: now(), updatedAt: now(), retrying: false, leaseToken: null, leaseUntil: 0,
    });
    return { status: 'processing', jobId: job.jobId };
  }

  async function status(request) {
    const uid = caller(request);
    if (request.data && Object.keys(request.data).length) throw new DeletionError('invalid-argument', 'No account identifier is accepted.');
    const job = await store.get(uid);
    if (job) return { status: 'processing', phase: job.phase, retrying: job.retrying === true, jobId: job.jobId };
    try { await auth.getUser(uid); return { status: 'not-started' }; } catch (error) {
      if (error.code === 'auth/user-not-found') return { status: 'complete' };
      throw error;
    }
  }

  async function work(uid) {
    const leaseToken = randomId();
    let job = await store.acquire(uid, leaseToken, now());
    if (!job) return { status: 'busy-or-complete' };
    if (store.hasActiveProfileWriter && await store.hasActiveProfileWriter(uid, now())) {
      await store.release(uid, leaseToken, false, now());
      return { status: 'processing' };
    }
    const deadline = now() + 40000;
    const save = async changes => {
      job = await store.checkpoint(uid, leaseToken, { ...changes, updatedAt: now(), leaseUntil: now() + 120000 });
      if (!job) throw new DeletionError('aborted', 'Deletion is being continued by another worker.');
    };
    const remove = async path => {
      await save({ pendingPath: path });
      await store.rememberRoot(uid, path);
      await store.removeTree(path);
      await save({ pendingPath: null });
    };
    try {
      if (job.pendingPath) await remove(job.pendingPath);
      while (now() < deadline && job.phase === 'firestore') {
        if (job.groupIndex >= groups.length) {
          await save({ phase: 'owned-roots', rootIndex: 0, cursor: null });
          break;
        }
        const page = await store.page(groups[job.groupIndex], job.cursor, 50);
        for (const document of page) {
          const decision = classify(document.path, document.data, uid);
          const referencesRemovedRoot = decision.type !== 'delete' && await store.referencesRoots(uid, pathsIn(document.data));
          if (decision.type === 'delete' || referencesRemovedRoot) await remove(document.path);
          else if (decision.type === 'redact') await store.redact(document, decision.patch);
          await save({ cursor: document.path });
          if (now() >= deadline) break;
        }
        if (!page.length) await save({ groupIndex: job.groupIndex + 1, cursor: null });
      }
      const ownedRoots = [`users/${uid}`, `blocks/${uid}`, `readerProfiles/${uid}`, `moderatedProfiles/${uid}`, `reportLimits/${uid}`, `activeAccounts/${uid}`];
      while (now() < deadline && job.phase === 'owned-roots') {
        if (job.rootIndex >= ownedRoots.length) { await save({ phase: 'storage', mediaIndex: 0 }); break; }
        await remove(ownedRoots[job.rootIndex]);
        await save({ rootIndex: job.rootIndex + 1 });
      }
      const prefixes = [`circlePosts/${uid}/`, `profilePhotos/${uid}/`, `bookCovers/${uid}/`];
      while (now() < deadline && job.phase === 'storage') {
        if (job.mediaIndex >= prefixes.length) { await save({ phase: 'auth' }); break; }
        const empty = await media.removePage(prefixes[job.mediaIndex]);
        if (empty) await save({ mediaIndex: job.mediaIndex + 1 });
        else await save({});
      }
      if (now() < deadline && job.phase === 'auth') {
        try { await auth.deleteUser(uid); } catch (error) {
          if (error.code !== 'auth/user-not-found') throw error;
        }
        await save({ phase: 'finalizing', authDeletedAt: now() });
      }
      if (job.phase === 'finalizing') {
        await store.finish(uid, leaseToken, job);
        return { status: 'complete' };
      }
      await store.release(uid, leaseToken, false, now());
      return { status: 'processing' };
    } catch (error) {
      await store.release(uid, leaseToken, true, now());
      throw new DeletionError('unavailable', 'Deletion will retry automatically.');
    }
  }

  return { start, status, work };
}

module.exports = { createDeletionService };
