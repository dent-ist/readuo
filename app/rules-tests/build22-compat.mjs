import fs from 'node:fs';
import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
} from 'firebase/firestore';

const ownerId = 'build22-owner';
const rulesFile = process.env.P1_08_RULES_FILE;
if (!rulesFile) throw new Error('P1_08_RULES_FILE is required.');

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-readuo-build22-compat',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync(rulesFile, 'utf8'),
    },
  });
});

after(async () => environment.cleanup());

function shelf(name, count = 0) {
  return {
    ownerId,
    name,
    visibility: 'friends',
    autoShareActivity: true,
    bookCount: count,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function build22Book(shelfId) {
  return {
    ownerId,
    shelfId,
    title: 'Build 22 compatible book',
    titleNormalized: 'build 22 compatible book',
    author: 'Compatibility Author',
    isbn: '9780306406157',
    isOwned: false,
    readingStatus: 'wantToRead',
    coverUrl: null,
    coverStoragePath: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

test('build22 add, status, and exact move remain accepted by P1-08 Rules', async () => {
  const db = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(setDoc(doc(db, 'shelves', 'source'), shelf('Source')));
  await assertSucceeds(setDoc(doc(db, 'shelves', 'destination'), shelf('Destination')));

  const sourceShelfRef = doc(db, 'shelves', 'source');
  const sourceBookRef = doc(sourceShelfRef, 'books', '9780306406157');
  const indexRef = doc(
    db,
    'users',
    ownerId,
    'libraryBookIsbns',
    '9780306406157',
  );
  await assertSucceeds(
    runTransaction(db, async (transaction) => {
      const sourceShelf = await transaction.get(sourceShelfRef);
      transaction.set(sourceBookRef, build22Book('source'));
      transaction.set(indexRef, {
        ownerId,
        shelfId: 'source',
        bookId: '9780306406157',
        title: 'Build 22 compatible book',
        shelfName: 'Source',
        createdAt: serverTimestamp(),
      });
      transaction.update(sourceShelfRef, {
        bookCount: sourceShelf.data().bookCount + 1,
        updatedAt: serverTimestamp(),
      });
    }),
  );

  await assertSucceeds(
    runTransaction(db, async (transaction) => {
      await transaction.get(sourceBookRef);
      transaction.update(sourceBookRef, {
        readingStatus: 'reading',
        updatedAt: serverTimestamp(),
      });
    }),
  );

  const destinationShelfRef = doc(db, 'shelves', 'destination');
  const destinationBookRef = doc(
    destinationShelfRef,
    'books',
    '9780306406157',
  );
  const moveId = 'source-9780306406157';
  await assertSucceeds(
    runTransaction(db, async (transaction) => {
      const [sourceShelf, destinationShelf, sourceBook] = await Promise.all([
        transaction.get(sourceShelfRef),
        transaction.get(destinationShelfRef),
        transaction.get(sourceBookRef),
        transaction.get(destinationBookRef),
        transaction.get(indexRef),
      ]);
      transaction.set(doc(db, 'users', ownerId, 'bookMoves', moveId), {
        ownerId,
        moveId,
        sourceShelfId: 'source',
        destinationShelfId: 'destination',
        bookId: '9780306406157',
        isbn: '9780306406157',
        title: sourceBook.data().title,
        sourceCountBefore: sourceShelf.data().bookCount,
        destinationCountBefore: destinationShelf.data().bookCount,
        sourceVisibility: sourceShelf.data().visibility,
        destinationVisibility: destinationShelf.data().visibility,
        sourceAutoShareActivity: sourceShelf.data().autoShareActivity,
        destinationAutoShareActivity:
          destinationShelf.data().autoShareActivity,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      transaction.set(destinationBookRef, {
        ...sourceBook.data(),
        shelfId: 'destination',
      });
      transaction.delete(sourceBookRef);
      transaction.update(sourceShelfRef, {
        bookCount: sourceShelf.data().bookCount - 1,
        lastBookMoveId: moveId,
        updatedAt: serverTimestamp(),
      });
      transaction.update(destinationShelfRef, {
        bookCount: destinationShelf.data().bookCount + 1,
        lastBookMoveId: moveId,
        updatedAt: serverTimestamp(),
      });
      transaction.update(indexRef, {
        shelfId: 'destination',
        shelfName: 'Destination',
      });
    }),
  );

  const moved = await getDoc(destinationBookRef);
  assert.equal(moved.data().shelfId, 'destination');
  assert.equal('activityGeneration' in moved.data(), false);
  assert.equal('lastActivityId' in moved.data(), false);
});
