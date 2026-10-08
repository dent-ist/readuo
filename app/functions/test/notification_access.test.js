'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { runInNewContext } = require('node:vm');
const { enabled } = require('../notification_policy');

const loaded = { exports: {} };
runInNewContext(readFileSync(resolve(__dirname, '../notifications.js'), 'utf8'), {
  module: loaded,
  exports: loaded.exports,
  require(name) {
    if (name === './notification_policy') return require('../notification_policy');
    if (name === './notification_delivery') return require('../notification_delivery');
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (...args) => args.at(-1) };
    if (name === 'firebase-admin/firestore') return { getFirestore() { throw new Error('Live database access forbidden in this test.'); } };
    if (name === 'firebase-admin/messaging') return { getMessaging() { throw new Error('Live messaging access forbidden in this test.'); } };
    throw new Error(`Unexpected import: ${name}`);
  },
}, { filename: 'notifications.js' });
const sourceAvailable = loaded.exports._sourceAvailable;
const generation = { seconds: 100, nanoseconds: 7 };

function fixture(isReview = false) {
  const parent = `${isReview ? 'circleReviews' : 'circlePosts'}/parent`;
  const notice = { type: 'comment', actorId: 'actor', recipientId: 'recipient',
    sourcePath: `${parent}/comments/comment`, sourceCreatedAt: generation, targetId: 'parent', isReview };
  const records = new Map(Object.entries({
    'readerProfiles/actor': {},
    'readerProfiles/recipient': {},
    'friendships/actor--recipient': {},
    [parent]: { authorId: 'recipient', shelfId: 'shelf', bookId: 'book', bookCreatedAt: generation },
    [notice.sourcePath]: { authorId: 'actor', createdAt: generation },
    'shelves/shelf': { ownerId: 'recipient', visibility: 'friends' },
    'shelves/shelf/books/book': { ownerId: 'recipient', createdAt: generation },
  }));
  const reads = [];
  const snapshot = ref => {
    reads.push(ref.path);
    return { exists: records.has(ref.path), data: () => records.get(ref.path) };
  };
  const database = { doc: path => ({ path }) };
  const transaction = { get: async ref => snapshot(ref), getAll: async (...refs) => refs.map(snapshot) };
  return { records, notice, parent, reads, check: () => sourceAvailable(transaction, database, notice) };
}

test('notifications reject self interaction before any read', async () => {
  const context = fixture();
  context.notice.recipientId = 'actor';
  assert.equal(await context.check(), false);
  assert.equal(context.reads.length, 0);
});

test('both block directions and either deletion marker revoke notifications', async () => {
  for (const path of ['blocks/actor/blocked/recipient', 'blocks/recipient/blocked/actor', 'accountDeletions/actor', 'accountDeletions/recipient']) {
    const context = fixture();
    context.records.set(path, {});
    assert.equal(await context.check(), false, path);
  }
});

test('deleted profiles, deleted source and changed nanosecond generation revoke notification', async () => {
  for (const path of ['readerProfiles/actor', 'readerProfiles/recipient', 'circlePosts/parent/comments/comment']) {
    const context = fixture();
    context.records.delete(path);
    assert.equal(await context.check(), false, path);
  }
  const replaced = fixture();
  replaced.records.set(replaced.notice.sourcePath, { authorId: 'actor', createdAt: { ...generation, nanoseconds: 8 } });
  assert.equal(await replaced.check(), false);
});

test('current friendship required in either orientation; revoked or missing parent denies', async () => {
  const context = fixture();
  assert.equal(await context.check(), true);
  context.records.delete('friendships/actor--recipient');
  assert.equal(await context.check(), false);
  context.records.set('friendships/recipient--actor', {});
  assert.equal(await context.check(), true);
  context.records.delete(context.parent);
  assert.equal(await context.check(), false);
});

test('moderated or wrong-owner parent and forged source authors are rejected', async () => {
  for (const parentData of [{ authorId: 'recipient', moderationState: 'removed' }, { authorId: 'outsider' }]) {
    const context = fixture();
    context.records.set(context.parent, parentData);
    assert.equal(await context.check(), false);
  }
  const comment = fixture();
  comment.records.set(comment.notice.sourcePath, { authorId: 'outsider', createdAt: generation });
  assert.equal(await comment.check(), false);
  const like = fixture();
  like.notice.type = 'like';
  like.records.set(like.notice.sourcePath, { userId: 'outsider', createdAt: generation });
  assert.equal(await like.check(), false);
  like.records.set(like.notice.sourcePath, { userId: 'actor', createdAt: generation });
  assert.equal(await like.check(), true);
});

test('review notifications require current shared shelf, source book and generation', async () => {
  const shared = fixture(true);
  assert.equal(await shared.check(), true);
  shared.records.set('shelves/shelf', { ownerId: 'recipient', visibility: 'public' });
  assert.equal(await shared.check(), true);
  for (const shelf of [{ ownerId: 'recipient', visibility: 'private' }, { ownerId: 'outsider', visibility: 'friends' }]) {
    const context = fixture(true);
    context.records.set('shelves/shelf', shelf);
    assert.equal(await context.check(), false);
  }
  for (const path of ['shelves/shelf', 'shelves/shelf/books/book']) {
    const context = fixture(true);
    context.records.delete(path);
    assert.equal(await context.check(), false);
  }
  for (const book of [{ ownerId: 'outsider', createdAt: generation }, { ownerId: 'recipient', createdAt: { ...generation, nanoseconds: 8 } }]) {
    const context = fixture(true);
    context.records.set('shelves/shelf/books/book', book);
    assert.equal(await context.check(), false);
  }
});

test('friend requests need correct source participants even before friendship exists', async () => {
  const context = fixture();
  context.notice.type = 'friendRequest';
  context.records.delete('friendships/actor--recipient');
  context.records.set(context.notice.sourcePath, { requesterId: 'actor', recipientId: 'recipient', createdAt: generation });
  assert.equal(await context.check(), true);
  context.records.set(context.notice.sourcePath, { requesterId: 'recipient', recipientId: 'actor', createdAt: generation });
  assert.equal(await context.check(), false);
});

test('request acceptance validates initiator orientation and current friendship', async () => {
  const context = fixture();
  context.notice.type = 'requestAccepted';
  context.records.set(context.notice.sourcePath, { memberIds: ['recipient', 'actor'], createdAt: generation });
  assert.equal(await context.check(), true);
  context.records.set(context.notice.sourcePath, { memberIds: ['actor', 'recipient'], createdAt: generation });
  assert.equal(await context.check(), false);
});

test('preference veto composes with live source authorization for all supported events', async () => {
  const context = fixture();
  const accessible = await context.check();
  assert.equal(accessible, true);
  assert.equal(enabled({ comment: false }, context.notice.type) && accessible, false);
  assert.equal(enabled({ comment: true }, context.notice.type) && accessible, true);
  assert.equal(enabled({}, 'unknown'), false);
});
