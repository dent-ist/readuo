'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { deliverPush, tokenKey } = require('../notification_delivery');

function fixture() {
  const context = { time: 2000000000000, allowed: true, sends: [], checks: 0 };
  const records = new Map();
  const reference = { path: 'users/reader/notifications/notice' };
  const snapshot = (reference, source = records) => ({ ref: reference, exists: source.has(reference.path), data: () => source.get(reference.path) });
  const database = {
    doc: path => ({ path }),
    collection: path => ({ get: async () => ({ docs: [...records.keys()].filter(key => key.startsWith(`${path}/`)).map(key => snapshot({ path: key })) }) }),
    async runTransaction(operation) {
      const staged = new Map([...records].map(([key, value]) => [key, structuredClone(value)]));
      let written = false;
      const transaction = {
        get: async reference => { assert.equal(written, false, 'read after write'); return snapshot(reference, staged); },
        getAll: async (...references) => { assert.equal(written, false, 'read after write'); return references.map(reference => snapshot(reference, staged)); },
        update: (reference, value) => { written = true; staged.set(reference.path, { ...staged.get(reference.path), ...value }); },
        delete: reference => { written = true; staged.delete(reference.path); },
      };
      const result = await operation(transaction);
      records.clear();
      staged.forEach((value, key) => records.set(key, value));
      return result;
    },
  };
  records.set(reference.path, { recipientId: 'reader', type: 'like', createdAt: { seconds: context.time / 1000 }, pushState: 'pending' });
  for (const token of ['one', 'two']) records.set(`users/reader/notificationTokens/${token}`, { token, updatedAt: { seconds: context.time / 1000 } });
  context.response = tokens => tokens.map(() => ({ success: true }));
  const messaging = { async sendEachForMulticast(message) {
    context.sends.push(message);
    return { responses: await context.response(message.tokens) };
  } };
  return Object.assign(context, {
    records, reference,
    notice: () => records.get(reference.path),
    run: () => deliverPush({ database, messaging, reference, userId: 'reader', notificationId: 'notice', now: () => context.time, random: () => 0, sourceAvailable: async () => { context.checks++; return context.allowed; } }),
  });
}

test('successful tokens are checkpointed, generic payload and stable tag, terminal dedupe', async () => {
  const context = fixture();
  await context.run();
  await context.run();
  assert.equal(context.sends.length, 1);
  assert.equal(context.notice().pushState, 'sent');
  assert.equal(context.notice().pushResults[tokenKey('one')], 'sent');
  assert.deepEqual(context.sends[0].data, { notificationId: 'notice', recipientId: 'reader' });
  assert.equal(context.sends[0].android.notification.tag, 'notice');
  assert.equal(context.sends[0].notification.body, 'You have a new notification. Open Readuo to view it.');
});

test('thrown transport error releases claim and bounded backoff retries', async () => {
  const context = fixture();
  context.response = () => { throw new Error('transport'); };
  await assert.rejects(context.run(), /retry/);
  assert.equal(context.notice().pushState, 'pending');
  await assert.rejects(context.run(), /deferred/);
  assert.equal(context.sends.length, 1);
  context.time += 60000;
  context.response = tokens => tokens.map(() => ({ success: true }));
  await context.run();
  assert.equal(context.notice().pushState, 'sent');
});

test('partial transient response retries only unfinished tokens', async () => {
  const context = fixture();
  context.response = () => [{ success: true }, { success: false, error: { code: 'messaging/server-unavailable' } }];
  await assert.rejects(context.run());
  context.time += 60000;
  context.response = tokens => tokens.map(() => ({ success: true }));
  await context.run();
  assert.deepEqual(context.sends[1].tokens, ['two']);
  assert.equal(context.notice().pushState, 'sent');
});

test('live lease defers, expired fenced lease recovers; historical legacy claims never replay', async () => {
  const context = fixture();
  Object.assign(context.notice(), { pushState: 'claimed', pushLease: 'crashed', pushLeaseUntil: context.time + 1000 });
  await assert.rejects(context.run(), /deferred/);
  context.time += 1001;
  await context.run();
  assert.equal(context.notice().pushState, 'sent');
  const legacy = fixture();
  legacy.notice().pushState = 'claimed';
  await legacy.run();
  assert.equal(legacy.notice().pushState, 'expired');
  assert.equal(legacy.sends.length, 0);
});

test('expiry and attempt limit terminate without sending', async () => {
  for (const mode of ['old', 'attempts']) {
    const context = fixture();
    if (mode === 'old') context.time += 3600001;
    else context.notice().pushAttempts = 6;
    await context.run();
    assert.equal(context.sends.length, 0);
    assert.ok(['expired', 'failed'].includes(context.notice().pushState));
  }
});

test('source revocation or preference changes veto retries', async () => {
  for (const mode of ['access', 'preference']) {
    const context = fixture();
    context.response = () => { throw new Error('retry'); };
    await assert.rejects(context.run());
    context.time += 60000;
    if (mode === 'access') context.allowed = false;
    else context.records.set('users/reader/preferences/notifications', { like: false });
    await context.run();
    assert.equal(context.sends.length, 1);
    assert.equal(context.notice().pushState, 'skipped');
  }
});

test('expired and invalid tokens are removed, permanent errors are not retried', async () => {
  const context = fixture();
  context.records.get('users/reader/notificationTokens/one').updatedAt = { seconds: 1 };
  context.response = () => [{ success: false, error: { code: 'messaging/registration-token-not-registered' } }];
  await context.run();
  assert.deepEqual(context.sends[0].tokens, ['two']);
  assert.equal(context.records.has('users/reader/notificationTokens/one'), false);
  assert.equal(context.records.has('users/reader/notificationTokens/two'), false);
  assert.equal(context.notice().pushState, 'failed');
});

test('recipient mismatch never sends', async () => {
  const context = fixture();
  context.notice().recipientId = 'other';
  await context.run();
  assert.equal(context.sends.length, 0);
});

test('duplicate installation token strings are sent only once', async () => {
  const context = fixture();
  context.records.set('users/reader/notificationTokens/duplicate', { token: 'one', updatedAt: { seconds: context.time / 1000 } });
  await context.run();
  assert.deepEqual(context.sends[0].tokens, ['one', 'two']);
});

test('token rotation during send does not delete replacement registration', async () => {
  const context = fixture();
  context.response = () => {
    context.records.set('users/reader/notificationTokens/one', { token: 'replacement', updatedAt: { seconds: context.time / 1000 } });
    return [{ success: false, error: { code: 'messaging/invalid-registration-token' } }, { success: true }];
  };
  await context.run();
  assert.equal(context.records.get('users/reader/notificationTokens/one').token, 'replacement');
});
