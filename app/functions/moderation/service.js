'use strict';

const { createHash } = require('node:crypto');
const { ModerationError, requireUser, requireModerator, object, bounded, identifier, targetPath, reasons, filterContent } = require('./policy');

function denied() {
  throw new ModerationError('permission-denied', 'This content is unavailable.');
}

function sameTime(first, second) {
  return first?.isEqual instanceof Function ? first.isEqual(second) : first === second;
}

function createModerationService(db, timestamp, profileServices = {}) {
  async function read(transaction, path) {
    const snapshot = await transaction.get(db.doc(path));
    return snapshot.exists ? snapshot.data() : null;
  }

  async function blocked(transaction, viewer, author) {
    if (viewer === author) return false;
    return !!(await read(transaction, `blocks/${viewer}/blocked/${author}`) ||
      await read(transaction, `blocks/${author}/blocked/${viewer}`));
  }

  async function authorize(transaction, viewer, kind, data) {
    if (!data || data.moderationState === 'removed') denied();
    const author = identifier(kind === 'profile' ? data.ownerId : data.authorId);
    if (await blocked(transaction, viewer, author)) denied();
    if (kind === 'profile' || viewer === author) return;
    if (!(await read(transaction, `friendships/${viewer}--${author}`) ||
        await read(transaction, `friendships/${author}--${viewer}`))) denied();
    if (kind === 'review') {
      const shelf = await read(transaction, `shelves/${identifier(data.shelfId)}`);
      const book = await read(transaction, `shelves/${identifier(data.shelfId)}/books/${identifier(data.bookId)}`);
      if (!shelf || !book || shelf.ownerId !== author || !['friends', 'public'].includes(shelf.visibility) ||
          book.ownerId !== author || book.shelfId !== data.shelfId ||
          !sameTime(book.createdAt, data.bookCreatedAt) || book.title !== data.title ||
          book.author !== data.bookAuthor || book.coverUrl !== data.coverUrl) denied();
    }
  }

  async function resolve(transaction, viewer, target) {
    const path = targetPath(target);
    if (!path) return { path: null, authorId: null, text: null, createdAt: null };
    const data = await read(transaction, path);
    if (!data || data.moderationState === 'removed') denied();
    if (target.kind === 'comment') {
      const parentPath = path.split('/comments/')[0];
      await authorize(transaction, viewer, target.parentKind, await read(transaction, parentPath));
      if (await blocked(transaction, viewer, identifier(data.authorId))) denied();
    } else {
      await authorize(transaction, viewer, target.kind, data);
    }
    const authorId = identifier(target.kind === 'profile' ? data.ownerId : data.authorId);
    if (await read(transaction, `accountDeletions/${authorId}`)) denied();
    if (target.kind === 'profile' && authorId !== target.id) denied();
    return { path, authorId, text: String(data.text ?? data.displayName ?? '').slice(0, 5000),
      photoPath: typeof data.photoPath === 'string' ? data.photoPath : target.kind === 'profile' && typeof data.photoStoragePath === 'string' ? data.photoStoragePath : null,
      photoUrl: target.kind === 'profile' && typeof data.photoUrl === 'string' && data.photoUrl.startsWith('https://') ? data.photoUrl : null,
      createdAt: data.createdAt ?? null };
  }

  async function submitReport(request) {
    const uid = requireUser(request);
    const data = object(request.data, ['requestId', 'target', 'reason', 'note']);
    identifier(data.requestId);
    targetPath(data.target);
    if (!reasons.includes(data.reason)) throw new ModerationError('invalid-argument', 'Choose a report reason.');
    const note = bounded(data.note ?? '', 2000, true);
    const reportId = createHash('sha256').update(`${uid}:${data.requestId}`).digest('hex');
    const fingerprint = createHash('sha256').update(JSON.stringify([targetPath(data.target), data.reason, note])).digest('hex');
    return db.runTransaction(async transaction => {
      if (!await read(transaction, `activeAccounts/${uid}`) || await read(transaction, `accountDeletions/${uid}`)) denied();
      const existing = await read(transaction, `reports/${reportId}`);
      if (existing) {
        if (existing.fingerprint !== fingerprint) throw new ModerationError('already-exists', 'This request was already used.');
        return { reportId, readerId: existing.targetAuthorId };
      }
      const resolved = await resolve(transaction, uid, data.target);
      const rate = await read(transaction, `reportLimits/${uid}`);
      const now = timestamp();
      const recent = rate && now.toMillis() - rate.windowStart.toMillis() < 3600000;
      if (recent && rate.count >= 20) throw new ModerationError('resource-exhausted', 'Too many reports. Try again later.');
      transaction.set(db.doc(`reportLimits/${uid}`), { windowStart: recent ? rate.windowStart : now, count: recent ? rate.count + 1 : 1 });
      transaction.create(db.doc(`reports/${reportId}`), {
        reporterId: uid, target: data.target, targetPath: resolved.path, targetAuthorId: resolved.authorId,
        targetCreatedAt: resolved.createdAt, contentSnapshot: resolved.text, photoPath: resolved.photoPath ?? null, photoUrl: resolved.photoUrl ?? null,
        reason: data.reason, note, fingerprint, status: 'pending', createdAt: now,
      });
      return { reportId, readerId: resolved.authorId };
    });
  }

  async function moderationAction(request) {
    const actorId = requireModerator(request);
    const data = object(request.data, ['reportId', 'decision', 'note']);
    const reportId = identifier(data.reportId);
    if (!['remove', 'dismiss', 'resolve'].includes(data.decision)) throw new ModerationError('invalid-argument', 'Invalid action.');
    const note = bounded(data.note ?? '', 2000);
    const result = await db.runTransaction(async transaction => {
      if (!await read(transaction, `activeAccounts/${actorId}`) || await read(transaction, `accountDeletions/${actorId}`)) denied();
      const report = await read(transaction, `reports/${reportId}`);
      if (!report) throw new ModerationError('not-found', 'Report not found.');
      if (await read(transaction, `accountDeletions/${identifier(report.reporterId)}`) ||
          (report.targetAuthorId && await read(transaction, `accountDeletions/${identifier(report.targetAuthorId)}`))) denied();
      if (report.status !== 'pending') {
        const previous = await read(transaction, `moderationActions/${reportId}`);
        if (previous?.actorId === actorId && previous.decision === data.decision && previous.note === note) return { reportId, status: report.status, deletePath: previous.deletePath ?? null, profileId: previous.profileId ?? null, photoPrefix: previous.photoPrefix ?? null };
        throw new ModerationError('failed-precondition', 'This report has already been handled.');
      }
      const path = targetPath(report.target);
      if (path !== report.targetPath) throw new ModerationError('failed-precondition', 'Invalid stored target.');
      if (data.decision === 'remove' && !path) throw new ModerationError('invalid-argument', 'Support concerns have no content to remove.');
      if (data.decision === 'resolve' && path) throw new ModerationError('invalid-argument', 'Choose remove or dismiss for reported content.');
      const current = path ? await read(transaction, path) : null;
      if (current && (current.authorId ?? current.ownerId) !== report.targetAuthorId) throw new ModerationError('failed-precondition', 'Target identity changed.');
      if (current && !sameTime(current.createdAt ?? null, report.targetCreatedAt)) throw new ModerationError('failed-precondition', 'Target was replaced.');
      const now = timestamp();
      const deletePath = data.decision === 'remove' && path && report.target.kind !== 'profile' ? path : null;
      const profileId = data.decision === 'remove' && report.target.kind === 'profile' ? report.target.id : null;
      const photoPrefix = data.decision === 'remove' && report.target.kind === 'post' ? `circlePosts/${report.targetAuthorId}/${report.target.id}/` : null;
      const status = deletePath || profileId ? 'processing' : data.decision === 'dismiss' ? 'dismissed' : 'resolved';
      if (data.decision === 'remove' && current && !profileId) transaction.delete(db.doc(path));
      if (profileId) {
        transaction.set(db.doc(`moderatedProfiles/${profileId}`), { ownerId: profileId, reportId, reporterId: report.reporterId, targetAuthorId: report.targetAuthorId, createdAt: now });
        if (current) transaction.update(db.doc(path), { displayName: 'Reader', photoUrl: null, photoStoragePath: null, updatedAt: now });
      }
      if (deletePath) transaction.set(db.doc(lockPath(report.target)), { targetPath: path, reportId, reporterId: report.reporterId, targetAuthorId: report.targetAuthorId, createdAt: now });
      transaction.create(db.doc(`moderationActions/${reportId}`), {
        reportId, actorId, reporterId: report.reporterId, targetAuthorId: report.targetAuthorId,
        decision: data.decision, note, targetPath: path, deletePath, profileId, photoPrefix,
        targetExisted: current !== null, previousModerationState: current?.moderationState ?? null,
        contentAtAction: current ? String(current.text ?? current.displayName ?? '').slice(0, 5000) : null,
        photoPathAtAction: current?.photoPath ?? current?.photoStoragePath ?? null,
        photoUrlAtAction: report.target.kind === 'profile' ? current?.photoUrl ?? null : null,
        createdAt: now,
      });
      transaction.update(db.doc(`reports/${reportId}`), { status, actionId: reportId, reviewNote: note, decision: data.decision, actorId });
      return { reportId, status, deletePath, profileId, photoPrefix };
    });
    if (result.status === 'processing') {
      if (result.deletePath) await db.recursiveDelete(db.doc(result.deletePath));
      if (result.photoPrefix) {
        if (!profileServices.deletePhotos) throw new ModerationError('failed-precondition', 'Photo moderation is unavailable.');
        await profileServices.deletePhotos(result.photoPrefix);
      }
      if (result.profileId) {
        if (!profileServices.redact) throw new ModerationError('failed-precondition', 'Profile moderation is unavailable.');
        await profileServices.redact(result.profileId);
      }
      await db.runTransaction(async transaction => {
        const report = await read(transaction, `reports/${reportId}`);
        if (report?.status === 'processing') {
          transaction.update(db.doc(`reports/${reportId}`), { status: 'resolved', resolvedAt: timestamp() });
          transaction.update(db.doc(`moderationActions/${reportId}`), { completedAt: timestamp() });
        }
      });
      result.status = 'resolved';
    }
    return { reportId, status: result.status };
  }

  async function listReports(request) {
    requireModerator(request);
    const data = object(request.data ?? {}, ['afterId']);
    let query = db.collection('reports').where('status', 'in', ['pending', 'processing']).orderBy('__name__').limit(50);
    if (data.afterId) query = query.startAfter(identifier(data.afterId));
    const snapshot = await query.get();
    return { reports: snapshot.docs.map(doc => ({ id: doc.id, ...doc.data(), createdAt: doc.data().createdAt.toDate().toISOString() })),
      nextCursor: snapshot.docs.length === 50 ? snapshot.docs.at(-1).id : null };
  }

  async function checkContent(request) {
    requireUser(request);
    const data = object(request.data, ['text']);
    return filterContent(data.text);
  }

  return { submitReport, moderationAction, listReports, checkContent };
}

function lockPath(target) {
  targetPath(target);
  return `moderationLocks/${target.kind === 'comment' ? `${target.parentKind}--${target.parentId}--comment--${target.id}` : `${target.kind}--${target.id}`}`;
}

module.exports = { createModerationService, lockPath };
