'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { notificationId, enabled, sameGeneration, acceptanceActors } = require('../notification_policy');

test('delivery retries reuse one identity but a recreated interaction is distinct', () => {
  const generation = { seconds: 20, nanoseconds: 1 };
  assert.equal(notificationId('circlePosts/a/likes/b', generation), notificationId('circlePosts/a/likes/b', generation));
  assert.notEqual(notificationId('circlePosts/a/likes/b', generation), notificationId('circlePosts/a/likes/b', { seconds: 20, nanoseconds: 2 }));
  assert.throws(() => notificationId('circlePosts/a/likes/b', null));
});

test('each supported preference gates its own event and activities never notify', () => {
  assert.equal(enabled({ like: false }, 'like'), false);
  assert.equal(enabled({ like: false }, 'comment'), true);
  assert.equal(enabled({}, 'friendRequest'), true);
  assert.equal(enabled({}, 'requestAccepted'), true);
  assert.equal(enabled({}, 'bookAdded'), false);
  assert.equal(enabled({}, 'reading'), false);
});

test('acceptance notifies original sender using Rules-enforced member order', () => {
  assert.deepEqual(acceptanceActors(['sender', 'recipient']), { recipientId: 'sender', actorId: 'recipient' });
  assert.throws(() => acceptanceActors(['same', 'same']));
  assert.throws(() => acceptanceActors(['one']));
});

test('source generation comparisons reject removed/recreated content', () => {
  assert.equal(sameGeneration({ seconds: 1, nanoseconds: 0 }, { seconds: 1, nanoseconds: 0 }), true);
  assert.equal(sameGeneration(null, { seconds: 1, nanoseconds: 0 }), false);
  assert.equal(sameGeneration({ seconds: 1, nanoseconds: 1 }, { seconds: 1, nanoseconds: 0 }), false);
});
