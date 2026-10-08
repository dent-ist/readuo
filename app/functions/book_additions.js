'use strict';

const { createHash, randomUUID } = require('node:crypto');
const { Timestamp, FieldPath, FieldValue } = require('firebase-admin/firestore');
const { sameGeneration } = require('./notification_policy');
const { deliverPush } = require('./notification_delivery');

const quietWindow = 120000;
const eventLifetime = 3600000;
const sourceLimit = 1000;
const hash = value => createHash('sha256').update(value).digest('hex');
const millis = value => value?.toMillis?.() ?? (value?.seconds == null ? 0 : value.seconds * 1000);
const capable = token => token.bookAdditionV1 === true;
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);

function sourceIdentity(source) {
  return hash(`${source.actorId}/${source.bookId}/${source.addedAt.seconds}/${source.addedAt.nanoseconds}`);
}

function decodeAddition(path, data) {
  const match = /^shelves\/([^/]+)\/books\/([^/]+)\/activities\/([^/]+)$/.exec(path);
  if (!match || data?.type !== 'added' || data.audience !== 'friends' ||
      !validId(data.authorId) || data.shelfId !== match[1] || data.bookId !== match[2] ||
      !validId(data.activityGeneration) || !Number.isInteger(data.createdAt?.seconds) || !Number.isInteger(data.createdAt?.nanoseconds)) return null;
  return {
    actorId: data.authorId, shelfId: match[1], bookId: match[2], sourcePath: path,
    activityGeneration: data.activityGeneration, addedAt: data.createdAt,
    batchId: typeof data.batchId === 'string' ? data.batchId : null,
  };
}

function createBookAdditions({ database, messaging, now = Date.now, diagnostic = () => {} }) {
  const configRef = database.doc('notificationConfiguration/bookAdditions');
  const groups = database.collection('bookAdditionGroups');
  const noticeRef = (recipientId, groupId) => database.doc(`users/${recipientId}/bookAdditionNotifications/books_${groupId}`);

  async function audience(transaction, actorId, recipientId, addedAt) {
    if (!validId(actorId) || !validId(recipientId) || actorId === recipientId) return null;
    const paths = [
      configRef.path, `readerProfiles/${actorId}`, `activeAccounts/${actorId}`,
      `activeAccounts/${recipientId}`, `accountDeletions/${actorId}`, `accountDeletions/${recipientId}`,
      `blocks/${actorId}/blocked/${recipientId}`, `blocks/${recipientId}/blocked/${actorId}`,
      `friendships/${actorId}--${recipientId}`, `friendships/${recipientId}--${actorId}`,
      `users/${recipientId}/preferences/notifications`,
    ];
    const [config, actor, activeActor, activeRecipient, actorDeletion, recipientDeletion,
      outgoingBlock, incomingBlock, forward, reverse, preferences] = await transaction.getAll(...paths.map(path => database.doc(path)));
    if (config.data()?.enabled !== true || !millis(config.data()?.enabledSince) ||
        (addedAt != null && millis(addedAt) < millis(config.data().enabledSince)) ||
        !actor.exists || !activeActor.exists || !activeRecipient.exists || actorDeletion.exists || recipientDeletion.exists ||
        outgoingBlock.exists || incomingBlock.exists || preferences.data()?.booksAdded === false) return null;
    const friendship = [forward, reverse].find(snapshot => snapshot.exists &&
      Array.isArray(snapshot.data().memberIds) && snapshot.data().memberIds.includes(actorId) &&
      snapshot.data().memberIds.includes(recipientId) &&
      millis(snapshot.data().createdAt) > 0 &&
      (addedAt == null || millis(snapshot.data().createdAt) <= millis(addedAt)));
    if (addedAt != null && millis(preferences.data()?.booksAddedSince) > millis(addedAt)) return null;
    return friendship ? { actorName: String(actor.data().displayName || 'Reader').replace(/[\r\n\t]/g, ' ').slice(0, 120), enabledSince: config.data().enabledSince, preferenceSince: millis(preferences.data()?.booksAddedSince) } : null;
  }

  async function validSources(transaction, sources, enabledSince) {
    const result = [];
    const seen = new Set();
    for (let offset = 0; offset < sources.length; offset += 100) {
      const chunk = sources.slice(offset, offset + 100);
      const snapshots = await transaction.getAll(...chunk.flatMap(source => [
        database.doc(source.sourcePath), database.doc(`shelves/${source.shelfId}`),
        database.doc(`shelves/${source.shelfId}/books/${source.bookId}`),
      ]));
      chunk.forEach((source, index) => {
        const [activity, shelf, book] = snapshots.slice(index * 3, index * 3 + 3);
        const decoded = activity.exists ? decodeAddition(activity.ref.path, activity.data()) : null;
        const identity = sourceIdentity(source);
        if (seen.has(identity) || !decoded || decoded.actorId !== source.actorId ||
            !sameGeneration(decoded.addedAt, source.addedAt) || millis(source.addedAt) < millis(enabledSince) ||
            !shelf.exists || shelf.data().ownerId !== source.actorId ||
            !['friends', 'public'].includes(shelf.data().visibility) || shelf.data().autoShareActivity !== true ||
            !book.exists || book.data().ownerId !== source.actorId || book.data().shelfId !== source.shelfId ||
            book.data().isOwned !== true || book.data().activityGeneration !== source.activityGeneration ||
            decoded.activityGeneration !== source.activityGeneration || !sameGeneration(book.data().createdAt, source.addedAt)) return;
        seen.add(identity);
        result.push(source);
      });
    }
    return result;
  }

  async function addForRecipient(source, recipientId) {
    const identity = sourceIdentity(source);
    const pairRef = database.doc(`bookAdditionPairs/${hash(`${source.actorId}/${recipientId}`)}`);
    const receiptRef = database.doc(`bookAdditionReceipts/${hash(`${recipientId}/${identity}`)}`);
    const proposedGroup = groups.doc(randomUUID());
    return database.runTransaction(async transaction => {
      const [pair, receipt] = await transaction.getAll(pairRef, receiptRef);
      if (receipt.exists || now() - millis(source.addedAt) > eventLifetime || millis(source.addedAt) > now() + 300000) return;
      const allowed = await audience(transaction, source.actorId, recipientId, source.addedAt);
      if (!allowed || !(await validSources(transaction, [source], allowed.enabledSince)).length) return;
      const tokens = await transaction.get(database.collection(`users/${recipientId}/notificationTokens`).where('bookAdditionV1', '==', true).limit(100));
      if (!tokens.docs.some(snapshot => capable(snapshot.data()) && millis(snapshot.data().bookAdditionEnabledAt) > 0 && millis(snapshot.data().bookAdditionEnabledAt) <= millis(source.addedAt) && now() - millis(snapshot.data().updatedAt) <= 30 * 24 * eventLifetime)) return;
      const previousRef = pair.data()?.groupId ? groups.doc(pair.data().groupId) : null;
      const previous = previousRef ? await transaction.get(previousRef) : null;
      const continuing = previous?.data()?.state === 'collecting' && previous.data().dueAt > now() && previous.data().preferenceSince === allowed.preferenceSince;
      const groupRef = continuing ? previousRef : proposedGroup;
      const entry = { ...source, recipientId };
      transaction.create(receiptRef, { actorId: source.actorId, recipientId, sourcePath: source.sourcePath, addedAt: source.addedAt, groupId: groupRef.id });
      const sourceCount = (continuing ? previous.data().sourceCount || 0 : 0) + 1;
      if (sourceCount <= sourceLimit) transaction.create(groupRef.collection('bookAdditionEntries').doc(identity), entry);
      transaction.set(groupRef, {
        actorId: source.actorId, recipientId, state: 'collecting',
        firstAddedAt: continuing && millis(previous.data().firstAddedAt) < millis(source.addedAt) ? previous.data().firstAddedAt : source.addedAt,
        preferenceSince: allowed.preferenceSince, sourceCount, overflow: sourceCount > sourceLimit,
        lastAdditionAt: now(), dueAt: now() + quietWindow,
      }, { merge: true });
      transaction.set(pairRef, { actorId: source.actorId, recipientId, groupId: groupRef.id });
    });
  }

  async function record(path, data) {
    const source = decodeAddition(path, data);
    if (!source || now() - millis(source.addedAt) > eventLifetime) return;
    const config = await configRef.get();
    if (config.data()?.enabled !== true || millis(source.addedAt) < millis(config.data()?.enabledSince)) return;
    const fanoutRef = database.doc(`bookAdditionFanouts/${sourceIdentity(source)}`);
    const progress = await fanoutRef.get();
    if (progress.data()?.complete === true) return;
    let query = database.collection('friendships').where('memberIds', 'array-contains', source.actorId).orderBy(FieldPath.documentId()).limit(100);
    if (progress.data()?.cursor) query = query.startAfter(progress.data().cursor);
    const friendships = await query.get();
    const recipients = new Set(friendships.docs.flatMap(snapshot => snapshot.data().memberIds || []).filter(uid => uid !== source.actorId));
    for (const recipientId of recipients) await addForRecipient(source, recipientId);
    await database.runTransaction(async transaction => {
      const current = await transaction.get(fanoutRef);
      const cursor = friendships.docs.at(-1)?.id || progress.data()?.cursor || '';
      if ((current.data()?.cursor || '') > cursor) return;
      transaction.set(fanoutRef, { actorId: source.actorId, sourcePath: source.sourcePath, addedAt: source.addedAt, cursor, pairId: cursor, complete: friendships.size < 100 });
    });
    if (friendships.size === 100) throw new Error('Book notification fanout will continue.');
  }

  async function readGroup(transaction, groupId, recipientId) {
    const group = await transaction.get(groups.doc(groupId));
    if (!group.exists || group.data().recipientId !== recipientId) return null;
    const data = group.data();
    if (data.overflow === true || data.sourceCount > sourceLimit) return null;
    const allowed = await audience(transaction, data.actorId, recipientId, data.firstAddedAt);
    if (!allowed) return null;
    const entries = [];
    let cursor;
    for (let page = 0; page <= sourceLimit / 100; page++) {
      let query = group.ref.collection('bookAdditionEntries').orderBy(FieldPath.documentId()).limit(100);
      if (cursor) query = query.startAfter(cursor);
      const snapshots = await transaction.get(query);
      entries.push(...snapshots.docs.map(snapshot => snapshot.data()));
      if (entries.length > sourceLimit) return null;
      if (snapshots.size < 100) break;
      cursor = snapshots.docs.at(-1);
    }
    const sources = await validSources(transaction, entries, allowed.enabledSince);
    return sources.length ? { ...allowed, ...data, count: sources.length } : null;
  }

  async function flush(groupId) {
    return database.runTransaction(async transaction => {
      const reference = groups.doc(groupId);
      const group = await transaction.get(reference);
      if (!group.exists || group.data().state !== 'collecting' || group.data().dueAt > now()) return;
      const data = group.data();
      const current = await readGroup(transaction, groupId, data.recipientId);
      const target = noticeRef(data.recipientId, groupId);
      const existing = await transaction.get(target);
      transaction.update(reference, { state: current ? 'frozen' : 'cancelled', dueAt: FieldValue.delete(), terminalReason: data.overflow === true ? 'source_limit' : current ? null : 'unavailable' });
      if (data.overflow === true) diagnostic('book_addition_source_limit');
      if (!current || existing.exists || now() - data.lastAdditionAt > eventLifetime) return;
      transaction.create(target, {
        type: 'booksAdded', actorId: data.actorId, actorName: current.actorName,
        recipientId: data.recipientId, targetId: groupId, count: current.count,
        createdAt: Timestamp.fromMillis(now()), readAt: null, pushState: 'pending',
      });
    });
  }

  async function sweep() {
    const due = await groups.where('dueAt', '<=', now()).orderBy('dueAt').limit(10).get();
    for (const group of due.docs) {
      try { await flush(group.id); } catch (_) { diagnostic('book_addition_flush_retry'); }
    }
  }

  async function deliver(reference, recipientId, notificationId) {
    let payload;
    let firstAddedAt;
    await deliverPush({
      database, messaging, reference, userId: recipientId, notificationId, now,
      tokenAllowed: token => capable(token) && millis(token.bookAdditionEnabledAt) > 0 && millis(token.bookAdditionEnabledAt) <= firstAddedAt,
      sourceAvailable: async (transaction, _, notice) => {
        const current = await readGroup(transaction, notice.targetId, recipientId);
        if (!current || current.state !== 'frozen' || current.actorId !== notice.actorId) return false;
        firstAddedAt = millis(current.firstAddedAt);
        payload = { title: 'Readuo', body: `${current.actorName} added ${current.count} ${current.count === 1 ? 'book' : 'books'}` };
        return true;
      },
      notificationPayload: () => payload,
    });
  }

  return { record, addForRecipient, flush, sweep, deliver };
}

module.exports = { createBookAdditions, decodeAddition, sourceIdentity, quietWindow };
