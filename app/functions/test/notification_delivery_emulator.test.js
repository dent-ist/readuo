'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { deliverPush } = require('../notification_delivery');

test('Firestore emulator checkpoints mixed outcomes and retries unfinished token only', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST, /^(127\.0\.0\.1|localhost):/);
  const { Firestore, Timestamp } = require('firebase-admin/firestore');
  const database = new Firestore({ projectId: 'demo-readuo-notification-delivery' });
  const userId = `fixture-${Date.now()}`;
  const reference = database.doc(`users/${userId}/notifications/notice`);
  let time = Date.now();
  await reference.set({ recipientId: userId, type: 'comment', pushState: 'pending', createdAt: Timestamp.fromMillis(time) });
  for (const token of ['one', 'two']) await database.doc(`users/${userId}/notificationTokens/${token}`).set({ token, updatedAt: Timestamp.fromMillis(time) });
  const sent = [];
  const messaging = { async sendEachForMulticast(message) {
    sent.push(message.tokens);
    return { responses: message.tokens.map(token => ({ success: sent.length > 1 || token === 'one', error: token === 'two' ? { code: 'messaging/internal-error' } : undefined })) };
  } };
  const run = () => deliverPush({ database, messaging, reference, userId, notificationId: 'notice', sourceAvailable: async () => true, now: () => time, random: () => 0 });
  try {
    await assert.rejects(run());
    time += 60000;
    await run();
    assert.deepEqual(sent, [['one', 'two'], ['two']]);
    assert.equal((await reference.get()).data().pushState, 'sent');
  } finally {
    await database.recursiveDelete(database.doc(`users/${userId}`));
    await database.terminate();
  }
});
