'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createBookAdditions, decodeAddition } = require('../book_additions');

test('book additions durable grouping, privacy and compatible delivery', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async context => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST, /^(127\.0\.0\.1|localhost):/);
  const { Firestore, Timestamp } = require('firebase-admin/firestore');
  const database = new Firestore({ projectId: `demo-readuo-books-${Date.now()}` });
  let time = 1790000000000;
  let sequence = 0;
  const sends = [];
  const diagnostics = [];
  let failToken;
  const messaging = { async sendEachForMulticast(payload) {
    sends.push(payload);
    return { responses: payload.tokens.map(token => ({ success: token !== failToken, error: token === failToken ? { code: 'messaging/internal-error' } : undefined })) };
  } };
  const service = createBookAdditions({ database, messaging, now: () => time, diagnostic: code => diagnostics.push(code) });
  const timestamp = offset => Timestamp.fromMillis(time + offset);
  async function setup() {
    sequence++;
    const actorId = `actor${sequence}`;
    const recipientId = `recipient${sequence}`;
    const shelfId = `shelf${sequence}`;
    await Promise.all([
      database.doc('notificationConfiguration/bookAdditions').set({ enabled: true, enabledSince: timestamp(-10000) }),
      database.doc(`readerProfiles/${actorId}`).set({ displayName: 'Kenny Kim' }),
      database.doc(`activeAccounts/${actorId}`).set({}), database.doc(`activeAccounts/${recipientId}`).set({}),
      database.doc(`friendships/${actorId}--${recipientId}`).set({ memberIds: [actorId, recipientId], createdAt: timestamp(-10000) }),
      database.doc(`shelves/${shelfId}`).set({ ownerId: actorId, visibility: 'friends', autoShareActivity: true }),
      database.doc(`users/${recipientId}/notificationTokens/old`).set({ token: 'old', updatedAt: timestamp(0) }),
      database.doc(`users/${recipientId}/notificationTokens/new`).set({ token: 'new', updatedAt: timestamp(0), bookAdditionV1: true, bookAdditionEnabledAt: timestamp(-1000) }),
    ]);
    async function add(bookId, overrides = {}) {
      const path = `shelves/${shelfId}/books/${bookId}/activities/added`;
      const data = { authorId: actorId, shelfId, bookId, audience: 'friends', type: 'added', activityGeneration: 'generation', batchId: null, createdAt: timestamp(0), ...overrides };
      await database.doc(`shelves/${shelfId}/books/${bookId}`).set({ ownerId: actorId, shelfId, isOwned: true, activityGeneration: 'generation', createdAt: data.createdAt });
      await database.doc(path).set(data);
      return { path, data, source: decodeAddition(path, data) };
    }
    async function groups() { return (await database.collection('bookAdditionGroups').where('actorId', '==', actorId).get()).docs; }
    async function notices() { return (await database.collection(`users/${recipientId}/bookAdditionNotifications`).get()).docs; }
    return { actorId, recipientId, shelfId, add, groups, notices };
  }
  try {
    await context.test('ten concurrent additions produce one notice after inactivity; replay does not extend', async () => {
      const fixture = await setup();
      const sources = await Promise.all(Array.from({ length: 10 }, (_, index) => fixture.add(`book${index}`, { batchId: index % 2 ? 'scan' : null })));
      const attempts = await Promise.allSettled(sources.map(source => service.record(source.path, source.data)));
      for (const [index, attempt] of attempts.entries()) {
        if (attempt.status === 'rejected') {
          assert.equal(attempt.reason.code, 10);
          await service.record(sources[index].path, sources[index].data);
        }
      }
      const [group] = await fixture.groups();
      assert.equal((await fixture.groups()).length, 1);
      const deadline = group.data().dueAt;
      time += 60000;
      await service.record(sources[0].path, sources[0].data);
      assert.equal((await group.ref.get()).data().dueAt, deadline);
      await service.flush(group.id);
      assert.equal((await fixture.notices()).length, 0);
      time += 60000;
      await Promise.all([service.flush(group.id), service.flush(group.id)]);
      const notices = await fixture.notices();
      assert.equal(notices.length, 1);
      assert.equal(notices[0].data().count, 10);
      await service.deliver(notices[0].ref, fixture.recipientId, notices[0].id);
      assert.deepEqual(sends.at(-1).tokens, ['new']);
      assert.equal(sends.at(-1).notification.body, 'Kenny Kim added 10 books');
      assert.equal((await database.collection(`users/${fixture.recipientId}/notifications`).get()).size, 0);
      const later = await fixture.add('later');
      await service.record(later.path, later.data);
      assert.equal((await fixture.groups()).length, 2);
    });
    await context.test('out-of-order additions retain the earliest eligibility timestamp', async () => {
      const fixture = await setup();
      const earlier = await fixture.add('earlier');
      time += 500;
      const later = await fixture.add('later');
      await service.record(later.path, later.data);
      await service.record(earlier.path, earlier.data);
      const [group] = await fixture.groups();
      assert.equal(group.data().firstAddedAt.toMillis(), earlier.data.createdAt.toMillis());
      assert.equal(group.data().sourceCount, 2);
    });
    await context.test('a new addition extends quiet window; an expired collecting window rolls over', async () => {
      const fixture = await setup();
      const first = await fixture.add('first');
      await service.record(first.path, first.data);
      time += 90000;
      const second = await fixture.add('second');
      await service.record(second.path, second.data);
      const [group] = await fixture.groups();
      assert.equal(group.data().dueAt, time + 120000);
      time += 120001;
      const third = await fixture.add('third');
      await service.record(third.path, third.data);
      assert.equal((await fixture.groups()).length, 2);
    });
    await context.test('private, no-share, unowned, status and historically enabled events never enqueue', async () => {
      for (const mode of ['private', 'noShare', 'unowned', 'status', 'enabledLater', 'tokenLater', 'newFriend', 'disabled']) {
        const fixture = await setup();
        const event = await fixture.add('book', mode === 'status' ? { type: 'started' } : {});
        if (mode === 'private') await database.doc(`shelves/${fixture.shelfId}`).update({ visibility: 'private' });
        if (mode === 'noShare') await database.doc(`shelves/${fixture.shelfId}`).update({ autoShareActivity: false });
        if (mode === 'unowned') await database.doc(`shelves/${fixture.shelfId}/books/book`).update({ isOwned: false });
        if (mode === 'enabledLater') await database.doc(`users/${fixture.recipientId}/preferences/notifications`).set({ booksAdded: true, booksAddedSince: timestamp(1) });
        if (mode === 'tokenLater') await database.doc(`users/${fixture.recipientId}/notificationTokens/new`).update({ bookAdditionEnabledAt: timestamp(1) });
        if (mode === 'newFriend') await database.doc(`friendships/${fixture.actorId}--${fixture.recipientId}`).update({ createdAt: timestamp(1) });
        if (mode === 'disabled') await database.doc('notificationConfiguration/bookAdditions').update({ enabled: false });
        await service.record(event.path, event.data);
        assert.equal((await fixture.groups()).length, 0, mode);
      }
    });
    await context.test('revoked or moved sources disappear from count; all revoked suppresses notice', async () => {
      const fixture = await setup();
      for (const id of ['valid', 'moved', 'removed']) { const event = await fixture.add(id); await service.record(event.path, event.data); }
      await database.doc(`shelves/${fixture.shelfId}/books/moved`).update({ activityGeneration: 'moved-generation' });
      await database.doc(`shelves/${fixture.shelfId}/books/removed`).delete();
      time += 120000;
      await service.flush((await fixture.groups())[0].id);
      assert.equal((await fixture.notices())[0].data().count, 1);
      await database.doc(`blocks/${fixture.recipientId}/blocked/${fixture.actorId}`).set({});
      const notice = (await fixture.notices())[0];
      const previous = sends.length;
      await service.deliver(notice.ref, fixture.recipientId, notice.id);
      assert.equal(sends.length, previous);
    });
    await context.test('partial retry checkpoints successful devices and rechecks settings', async () => {
      const fixture = await setup();
      await database.doc(`users/${fixture.recipientId}/notificationTokens/other`).set({ token: 'retry', updatedAt: timestamp(0), bookAdditionV1: true, bookAdditionEnabledAt: timestamp(-1000) });
      const event = await fixture.add('book'); await service.record(event.path, event.data);
      time += 120000; await service.flush((await fixture.groups())[0].id);
      const notice = (await fixture.notices())[0];
      failToken = 'retry';
      await assert.rejects(service.deliver(notice.ref, fixture.recipientId, notice.id));
      const before = sends.length;
      await database.doc(`users/${fixture.recipientId}/preferences/notifications`).set({ booksAdded: false });
      time += 80000;
      await service.deliver(notice.ref, fixture.recipientId, notice.id);
      assert.equal(sends.length, before);
      assert.equal((await notice.ref.get()).data().pushState, 'skipped');
      failToken = null;
    });
    await context.test('1001st source suppresses the whole window and terminates without partial count', async () => {
      const fixture = await setup();
      const first = await fixture.add('first'); await service.record(first.path, first.data);
      const [group] = await fixture.groups();
      await group.ref.update({ sourceCount: 1000 });
      const next = await fixture.add('overflow'); await service.record(next.path, next.data);
      assert.equal((await group.ref.get()).data().overflow, true);
      time += 120000;
      await service.flush(group.id);
      assert.equal((await fixture.notices()).length, 0);
      assert.equal((await group.ref.get()).data().terminalReason, 'source_limit');
      assert.equal((await group.ref.get()).data().dueAt, undefined);
      assert.ok(diagnostics.includes('book_addition_source_limit'));
      const after = await fixture.add('after'); await service.record(after.path, after.data);
      assert.equal((await fixture.groups()).length, 2);
    });
    await context.test('validation traverses more than one page and counts unique valid books', async () => {
      const fixture = await setup();
      const first = await fixture.add('first'); await service.record(first.path, first.data);
      const [group] = await fixture.groups();
      const batch = database.batch();
      for (let index = 0; index < 101; index++) {
        const bookId = `paged${index}`;
        const sourcePath = `shelves/${fixture.shelfId}/books/${bookId}/activities/add`;
        const data = { authorId: fixture.actorId, shelfId: fixture.shelfId, bookId, type: 'added', audience: 'friends', activityGeneration: 'generation', createdAt: timestamp(0), batchId: null };
        const source = decodeAddition(sourcePath, data);
        batch.set(database.doc(sourcePath), data);
        batch.set(database.doc(`shelves/${fixture.shelfId}/books/${bookId}`), { ownerId: fixture.actorId, shelfId: fixture.shelfId, isOwned: true, activityGeneration: 'generation', createdAt: timestamp(0) });
        batch.set(group.ref.collection('bookAdditionEntries').doc(`paged${index}`), { ...source, recipientId: fixture.recipientId });
      }
      batch.update(group.ref, { sourceCount: 102 });
      await batch.commit();
      time += 120000; await service.flush(group.id);
      const notice = (await fixture.notices())[0];
      assert.equal(notice.data().count, 102);
      await service.deliver(notice.ref, fixture.recipientId, notice.id);
      assert.equal(sends.at(-1).notification.body, 'Kenny Kim added 102 books');
    });
    await context.test('actor deletion, source deletion and preference revocation cancel before flush', async () => {
      for (const reason of ['actorDeletion', 'recipientDeletion', 'sourceDeletion', 'muted']) {
        const fixture = await setup();
        const event = await fixture.add('book'); await service.record(event.path, event.data);
        if (reason === 'actorDeletion') await database.doc(`accountDeletions/${fixture.actorId}`).set({});
        if (reason === 'recipientDeletion') await database.doc(`accountDeletions/${fixture.recipientId}`).set({});
        if (reason === 'sourceDeletion') await database.doc(event.path).delete();
        if (reason === 'muted') await database.doc(`users/${fixture.recipientId}/preferences/notifications`).set({ booksAdded: false });
        time += 120000; await service.flush((await fixture.groups())[0].id);
        assert.equal((await fixture.notices()).length, 0, reason);
      }
    });
    await context.test('retry recounts surviving sources, does not resend success and excludes rotated capability epochs', async () => {
      const fixture = await setup();
      await database.doc(`users/${fixture.recipientId}/notificationTokens/retry`).set({ token: 'retry', updatedAt: timestamp(0), bookAdditionV1: true, bookAdditionEnabledAt: timestamp(-1000) });
      for (const id of ['first', 'second']) { const event = await fixture.add(id); await service.record(event.path, event.data); }
      time += 120000; await service.flush((await fixture.groups())[0].id);
      const notice = (await fixture.notices())[0];
      failToken = 'retry';
      await assert.rejects(service.deliver(notice.ref, fixture.recipientId, notice.id));
      await database.doc(`shelves/${fixture.shelfId}/books/second`).delete();
      await database.doc(`users/${fixture.recipientId}/notificationTokens/rotated`).set({ token: 'newer', updatedAt: timestamp(0), bookAdditionV1: true, bookAdditionEnabledAt: timestamp(0) });
      time += 80000; failToken = null;
      await service.deliver(notice.ref, fixture.recipientId, notice.id);
      assert.deepEqual(sends.at(-1).tokens, ['retry']);
      assert.equal(sends.at(-1).notification.body, 'Kenny Kim added 1 book');
      const before = sends.length;
      await service.deliver(notice.ref, fixture.recipientId, notice.id);
      assert.equal(sends.length, before);
    });
  } finally {
    for (const collection of await database.listCollections()) await database.recursiveDelete(collection);
    await database.terminate();
  }
});
