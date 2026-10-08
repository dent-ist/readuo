'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createModerationService, lockPath } = require('../moderation/service');
const { filterContent, enforceContent, targetPath, requireModerator } = require('../moderation/policy');

const moment = { toMillis: () => 10000, toDate: () => new Date(10000), isEqual: other => other === moment };
const member = { uid: 'reader', token: {} };
const moderator = { uid: 'operator', token: { moderator: true } };

function fixture(extra = {}) {
  const records = new Map(Object.entries({
    'activeAccounts/reader': {},
    'activeAccounts/operator': {},
    'circlePosts/post': { authorId: 'author', text: 'A book worth reading', createdAt: moment },
    'friendships/reader--author': {},
    'readerProfiles/author': { ownerId: 'author', displayName: 'Author', createdAt: moment },
    ...extra,
  }));
  const deleted = [];
  let failDeletion = false;
  const db = {
    doc: path => ({ path }),
    runTransaction: async callback => {
      const pending = [];
      let writing = false;
      const transaction = {
        get: async ref => {
          assert.equal(writing, false, 'all reads precede writes');
          return { exists: records.has(ref.path), data: () => records.get(ref.path) };
        },
        create: (ref, data) => { writing = true; assert.equal(records.has(ref.path), false); pending.push(() => records.set(ref.path, data)); },
        set: (ref, data) => { writing = true; pending.push(() => records.set(ref.path, data)); },
        update: (ref, data) => { writing = true; assert.equal(records.has(ref.path), true); pending.push(() => records.set(ref.path, { ...records.get(ref.path), ...data })); },
        delete: ref => { writing = true; pending.push(() => records.delete(ref.path)); },
      };
      const result = await callback(transaction);
      pending.forEach(write => write());
      return result;
    },
    recursiveDelete: async ref => {
      assert.ok([...records.keys()].some(path => path.startsWith('moderationActions/')), 'audit before delete');
      if (failDeletion) throw new Error('transient deletion failure');
      deleted.push(ref.path);
      for (const path of records.keys()) if (path === ref.path || path.startsWith(`${ref.path}/`)) records.delete(path);
    },
  };
  const photos = [];
  const profiles = [];
  const service = createModerationService(db, () => moment, {
    deletePhotos: async prefix => photos.push(prefix),
    redact: async uid => profiles.push(uid),
  });
  const submit = (target = { kind: 'post', id: 'post' }, overrides = {}) => service.submitReport({ auth: member, data: { requestId: 'request1', target, reason: 'Harassment or bullying', note: 'Please review', ...overrides } });
  const act = (reportId, decision = 'remove', auth = moderator) => service.moderationAction({ auth, data: { reportId, decision, note: 'Reviewed the reported content.' } });
  return { records, deleted, photos, profiles, service, submit, act, fail: value => { failDeletion = value; } };
}

test('operator claim must be the boolean true; paths and payload cannot forge identity', async () => {
  for (const auth of [undefined, member, { uid: 'operator', token: { moderator: 'true' } }]) assert.throws(() => requireModerator({ auth }));
  assert.equal(requireModerator({ auth: moderator }), 'operator');
  for (const target of [{ kind: 'post', id: '../private' }, { kind: 'comment', id: 'a', parentKind: 'profile', parentId: 'b' }, { kind: 'support', id: 'author' }]) assert.throws(() => targetPath(target));
  const context = fixture();
  await assert.rejects(context.submit(undefined, { reporterId: 'victim' }), { code: 'invalid-argument' });
  await assert.rejects(context.service.submitReport({ data: {} }), { code: 'unauthenticated' });
});

test('report target is resolved from authorized server data; retries deduplicate', async () => {
  const context = fixture();
  const receipt = await context.submit();
  assert.equal(receipt.readerId, 'author');
  assert.deepEqual(await context.submit(), receipt);
  assert.equal(context.records.get('reportLimits/reader').count, 1);
  assert.equal(context.records.get(`reports/${receipt.reportId}`).contentSnapshot, 'A book worth reading');
  await assert.rejects(context.submit(undefined, { note: 'changed payload' }), { code: 'already-exists' });
});

test('strangers, blocks in either direction, removed and missing targets are denied', async () => {
  for (const block of ['blocks/reader/blocked/author', 'blocks/author/blocked/reader']) {
    await assert.rejects(fixture({ [block]: {} }).submit(), { code: 'permission-denied' });
  }
  const stranger = fixture();
  stranger.records.delete('friendships/reader--author');
  await assert.rejects(stranger.submit(), { code: 'permission-denied' });
  await assert.rejects(fixture({ 'circlePosts/post': { authorId: 'author', moderationState: 'removed' } }).submit(), { code: 'permission-denied' });
  await assert.rejects(fixture().submit({ kind: 'post', id: 'missing' }), { code: 'permission-denied' });
});

test('reviews require live source shelf visibility, friendship and exact book generation', async () => {
  const seed = {
    'circleReviews/review': { authorId: 'author', shelfId: 'shelf', bookId: 'book', bookCreatedAt: moment, title: 'Title', bookAuthor: 'Writer', coverUrl: null, text: 'Review', createdAt: moment },
    'shelves/shelf': { ownerId: 'author', visibility: 'friends' },
    'shelves/shelf/books/book': { ownerId: 'author', shelfId: 'shelf', createdAt: moment, title: 'Title', author: 'Writer', coverUrl: null },
  };
  await fixture(seed).submit({ kind: 'review', id: 'review' });
  for (const change of [
    { 'shelves/shelf': { ownerId: 'author', visibility: 'private' } },
    { 'shelves/shelf/books/book': { ...seed['shelves/shelf/books/book'], createdAt: 'replaced' } },
    { 'shelves/shelf/books/book': { ...seed['shelves/shelf/books/book'], title: 'Stale title' } },
  ]) await assert.rejects(fixture({ ...seed, ...change }).submit({ kind: 'review', id: 'review' }), { code: 'permission-denied' });
});

test('comments require parent access and no block with comment author', async () => {
  const target = { kind: 'comment', id: 'comment', parentKind: 'post', parentId: 'post' };
  const seed = { 'circlePosts/post/comments/comment': { authorId: 'third', text: 'Comment', createdAt: moment } };
  assert.equal((await fixture(seed).submit(target)).readerId, 'third');
  assert.equal(lockPath(target), 'moderationLocks/post--post--comment--comment');
  await assert.rejects(fixture({ ...seed, 'blocks/third/blocked/reader': {} }).submit(target), { code: 'permission-denied' });
  const missingParent = fixture(seed);
  missingParent.records.delete('circlePosts/post');
  await assert.rejects(missingParent.submit(target), { code: 'permission-denied' });
});

test('support concerns have no reader target and cannot remove content', async () => {
  const context = fixture();
  const receipt = await context.submit({ kind: 'support' });
  assert.equal(receipt.readerId, null);
  await assert.rejects(context.act(receipt.reportId), { code: 'invalid-argument' });
  assert.equal((await context.act(receipt.reportId, 'resolve')).status, 'resolved');
});

test('removal snapshots audit, locks source, recursively deletes descendants and photos, and retries safely', async () => {
  const context = fixture({ 'circlePosts/post/comments/comment': { text: 'Nested comment' } });
  const { reportId } = await context.submit();
  await assert.rejects(context.act(reportId, 'remove', member), { code: 'permission-denied' });
  context.fail(true);
  await assert.rejects(context.act(reportId), /transient/);
  assert.equal(context.records.get(`reports/${reportId}`).status, 'processing');
  assert.equal(context.records.has('circlePosts/post'), false);
  assert.ok(context.records.has('moderationLocks/post--post'));
  context.fail(false);
  assert.equal((await context.act(reportId)).status, 'resolved');
  assert.equal(context.records.has('circlePosts/post/comments/comment'), false);
  assert.deepEqual(context.photos, ['circlePosts/author/post/']);
  await context.act(reportId);
  assert.equal(context.deleted.length, 1);
  const audit = context.records.get(`moderationActions/${reportId}`);
  assert.equal(audit.contentAtAction, 'A book worth reading');
  assert.equal(audit.reporterId, 'reader');
  assert.equal(audit.targetAuthorId, 'author');
  await assert.rejects(context.act(reportId, 'dismiss'), { code: 'failed-precondition' });
});

test('replacement target is never deleted and dismissed reports retain content', async () => {
  const context = fixture();
  const { reportId } = await context.submit();
  context.records.set('circlePosts/post', { authorId: 'author', createdAt: 'replacement' });
  await assert.rejects(context.act(reportId), { code: 'failed-precondition' });
  const dismissed = fixture();
  const receipt = await dismissed.submit();
  await dismissed.act(receipt.reportId, 'dismiss');
  assert.ok(dismissed.records.has('circlePosts/post'));
  assert.equal(dismissed.deleted.length, 0);
});

test('profile removal redacts fields and coordinates Auth/avatar cleanup without suspension', async () => {
  const context = fixture({ 'readerProfiles/author': { ownerId: 'author', displayName: 'Author', createdAt: moment, photoUrl: 'https://example.com/photo.png', photoStoragePath: 'profilePhotos/author/photo-1' } });
  const { reportId } = await context.submit({ kind: 'profile', id: 'author' });
  assert.equal(context.records.get(`reports/${reportId}`).photoPath, 'profilePhotos/author/photo-1');
  assert.equal(context.records.get(`reports/${reportId}`).photoUrl, 'https://example.com/photo.png');
  await context.act(reportId);
  const profile = context.records.get('readerProfiles/author');
  assert.equal(profile.displayName, 'Reader');
  assert.equal(profile.photoUrl, null);
  assert.equal(profile.photoStoragePath, null);
  assert.equal(profile.moderationState, undefined);
  assert.ok(context.records.has('moderatedProfiles/author'));
  assert.deepEqual(context.profiles, ['author']);
});

test('rate limit does not consume duplicate requests and allows bounded reports', async () => {
  const context = fixture();
  for (let index = 0; index < 20; index++) await context.submit(undefined, { requestId: `report${index}` });
  await context.submit(undefined, { requestId: 'report0' });
  await assert.rejects(context.submit(undefined, { requestId: 'overflow' }), { code: 'resource-exhausted' });
});

test('account deletion markers prevent new reports and moderation evidence during cleanup', async () => {
  await assert.rejects(fixture({ 'accountDeletions/reader': {} }).submit({ kind: 'support' }), { code: 'permission-denied' });
  await assert.rejects(fixture({ 'accountDeletions/author': {} }).submit(), { code: 'permission-denied' });
  for (const uid of ['reader', 'author', 'operator']) {
    const context = fixture();
    const { reportId } = await context.submit();
    context.records.set(`accountDeletions/${uid}`, {});
    await assert.rejects(context.act(reportId), { code: 'permission-denied' });
    assert.equal(context.records.has(`moderationActions/${reportId}`), false);
  }
});

test('filter handles case, punctuation and multiline with explicit documented limits', () => {
  for (const text of ['I WILL KILL YOU', 'Please, kill yourself.', 'line\nI\twill\r\nkill you!']) {
    assert.equal(filterContent(text).allowed, false);
    assert.throws(() => enforceContent(text), { code: 'failed-precondition' });
  }
  for (const text of ['A thoughtful review', 'skill yourself', 'I will kill your weeds', 'kill yourselfish', 'I will kill you_', 'i will kіll you']) assert.equal(filterContent(text).allowed, true);
  assert.throws(() => filterContent('a'.repeat(5001)), { code: 'invalid-argument' });
});
