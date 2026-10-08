'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { decodeAddition, sourceIdentity, quietWindow } = require('../book_additions');
const { groups, classify } = require('../deletion/policy');

test('book addition identities ignore ingestion replay and batch mode', () => {
  const data = { authorId: 'actor', shelfId: 'shelf', bookId: 'book', type: 'added', audience: 'friends', activityGeneration: 'generation', createdAt: Timestamp.fromMillis(1790000000000), batchId: null };
  const source = decodeAddition('shelves/shelf/books/book/activities/one', data);
  assert.ok(source);
  assert.equal(sourceIdentity(source), sourceIdentity(decodeAddition('shelves/shelf/books/book/activities/two', { ...data, batchId: 'scan' })));
  assert.equal(decodeAddition('shelves/shelf/books/book/activities/one', { ...data, type: 'started' }), null);
  assert.equal(decodeAddition('shelves/shelf/books/book/activities/one', { ...data, authorId: '../actor' }), null);
  assert.equal(quietWindow, 120000);
});

test('all book notification roots and nested sources are erased on actor or recipient deletion', () => {
  for (const collection of ['bookAdditionNotifications', 'bookAdditionGroups', 'bookAdditionEntries', 'bookAdditionPairs', 'bookAdditionReceipts', 'bookAdditionFanouts']) {
    assert.ok(groups.includes(collection));
    assert.equal(classify(`${collection}/one`, { actorId: 'actor', recipientId: 'recipient' }, 'actor').type, 'delete');
    assert.equal(classify(`${collection}/one`, { actorId: 'actor', recipientId: 'recipient' }, 'recipient').type, 'delete');
  }
  assert.equal(classify('bookAdditionFanouts/one', { actorId: 'actor', cursor: 'actor--recipient', pairId: 'actor--recipient' }, 'recipient').type, 'delete');
});
