import fs from 'node:fs';
import path from 'node:path';
import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  collectionGroup,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  orderBy,
  onSnapshot,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-readuo-shelves';
const ownerId = 'owner-user';
const otherUserId = 'other-user';
const thirdUserId = 'third-user';
let environment;
let activitySequence = 0;

function friendPair(firstId, secondId) {
  return [firstId, secondId].sort().join('--');
}

function profileData(userId, code, displayName) {
  return {
    ownerId: userId,
    displayName,
    photoUrl: null,
    inviteCode: code,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

async function createReader(db, userId, code, displayName) {
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'readerProfiles', userId),
    profileData(userId, code, displayName),
  );
  batch.set(doc(db, 'inviteCodes', code), {
    ownerId: userId,
    code,
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
}

async function bootstrapReader(db, userId, code, displayName) {
  return runTransaction(db, async (transaction) => {
    const profileRef = doc(db, 'readerProfiles', userId);
    const existing = await transaction.get(profileRef);
    if (existing.exists()) return existing.data();
    const codeRef = doc(db, 'inviteCodes', code);
    const reservation = await transaction.get(codeRef);
    if (reservation.exists()) throw new Error('invite-code-collision');
    transaction.set(profileRef, profileData(userId, code, displayName));
    transaction.set(codeRef, {
      ownerId: userId,
      code,
      createdAt: serverTimestamp(),
    });
    return { ownerId: userId, inviteCode: code };
  });
}

async function seedSharedLibrary({ friend = true } = {}) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    if (friend) {
      await setDoc(doc(db, 'friendships', friendPair(ownerId, otherUserId)), {
        pairId: friendPair(ownerId, otherUserId),
        memberIds: [ownerId, otherUserId],
        createdAt: Timestamp.now(),
      });
    }
    for (const [id, visibility] of [
      ['friends-shelf', 'friends'],
      ['public-shelf', 'public'],
      ['private-shelf', 'private'],
    ]) {
      await setDoc(doc(db, 'shelves', id), {
        ...validShelf({
          ownerId: otherUserId,
          visibility,
          autoShareActivity: visibility !== 'private',
          bookCount: 1,
        }),
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
      if (visibility === 'public') {
        await setDoc(doc(db, 'publicShelfDirectory', id), {
          ownerId: otherUserId,
          shelfId: id,
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        });
      }
      await setDoc(doc(db, 'shelves', id, 'books', `${id}-book`), {
        ...validBook(id, {
          ownerId: otherUserId,
          isOwned: visibility !== 'private',
        }),
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
      if (id === 'friends-shelf') {
        await setDoc(doc(db, 'shelves', id, 'books', `${id}-saved-book`), {
          ...validBook(id, {
            ownerId: otherUserId,
            isOwned: false,
            isbn: '9780306406157',
          }),
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        });
      }
    }
  });
}

async function seedShelfMutationLibrary(bookCount = 3) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'shelves', 'move-source'), {
      ...validShelf({ name: 'Move source', bookCount }),
      createdAt: Timestamp.fromMillis(1000),
      updatedAt: Timestamp.fromMillis(1000),
    });
    batch.set(doc(db, 'shelves', 'move-destination'), {
      ...validShelf({
        name: 'Move destination',
        visibility: 'public',
        autoShareActivity: true,
        bookCount: 4,
      }),
      createdAt: Timestamp.fromMillis(1000),
      updatedAt: Timestamp.fromMillis(1000),
    });
    for (let index = 0; index < bookCount; index += 1) {
      const isbn = `978${String(index).padStart(10, '0')}`;
      batch.set(doc(db, 'shelves', 'move-source', 'books', isbn), {
        ...validBook('move-source', {
          title: `Book ${index}`,
          titleNormalized: `book ${index}`,
          isbn,
          readingStatus: index % 2 === 0 ? 'reading' : 'finished',
          isOwned: index % 3 !== 0,
        }),
        createdAt: Timestamp.fromMillis(1000 + index),
        updatedAt: Timestamp.fromMillis(2000 + index),
      });
      batch.set(doc(db, 'users', ownerId, 'libraryBookIsbns', isbn), {
        ownerId,
        shelfId: 'move-source',
        bookId: isbn,
        title: `Book ${index}`,
        shelfName: 'Move source',
        createdAt: Timestamp.fromMillis(1000 + index),
      });
    }
    await batch.commit();
  });
}

function shelfOperationRef(db) {
  return doc(db, 'users', ownerId, 'shelfOperations', 'move-source');
}

async function prepareShelfOperation(db, mode = 'move') {
  return runTransaction(db, async (transaction) => {
    const sourceRef = doc(db, 'shelves', 'move-source');
    const destinationRef = doc(db, 'shelves', 'move-destination');
    const operationRef = shelfOperationRef(db);
    const source = await transaction.get(sourceRef);
    const destination = mode === 'move'
      ? await transaction.get(destinationRef)
      : null;
    const sourceDirectoryRef = doc(
      db,
      'publicShelfDirectory',
      'move-source',
    );
    const destinationDirectoryRef = doc(
      db,
      'publicShelfDirectory',
      'move-destination',
    );
    const sourceDirectory = await transaction.get(sourceDirectoryRef);
    const destinationDirectory = destination == null
      ? null
      : await transaction.get(destinationDirectoryRef);
    transaction.set(operationRef, {
      ownerId,
      sourceShelfId: 'move-source',
      destinationShelfId: mode === 'move' ? 'move-destination' : null,
      mode,
      status: 'running',
      totalCount: source.data().bookCount,
      processedCount: 0,
      currentBookId: null,
      currentBookIsbn: null,
      destinationInitialCount: destination?.data().bookCount ?? null,
      destinationVisibility: destination?.data().visibility ?? null,
      destinationAutoShareActivity:
        destination?.data().autoShareActivity ?? null,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.update(sourceRef, {
      mutationOperationId: 'move-source',
      visibility: 'private',
      autoShareActivity: false,
      updatedAt: serverTimestamp(),
    });
    if (sourceDirectory.exists()) transaction.delete(sourceDirectoryRef);
    if (destination != null) {
      transaction.update(destinationRef, {
        mutationOperationId: 'move-source',
        visibility: 'private',
        autoShareActivity: false,
        updatedAt: serverTimestamp(),
      });
      if (destinationDirectory.exists()) {
        transaction.delete(destinationDirectoryRef);
      }
    }
  });
}

async function moveBookChunk(db, bookId, options = {}) {
  const {
    deleteSource = true,
    indexMode = 'move',
    destinationOverrides = {},
  } = options;
  return runTransaction(db, async (transaction) => {
    const sourceRef = doc(db, 'shelves', 'move-source');
    const destinationRef = doc(db, 'shelves', 'move-destination');
    const operationRef = shelfOperationRef(db);
    const sourceBookRef = doc(sourceRef, 'books', bookId);
    const destinationBookRef = doc(destinationRef, 'books', bookId);
    const [operation, source, destination, sourceBook, destinationBook] =
      await Promise.all([
        transaction.get(operationRef),
        transaction.get(sourceRef),
        transaction.get(destinationRef),
        transaction.get(sourceBookRef),
        transaction.get(destinationBookRef),
      ]);
    const isbn = sourceBook.data().isbn;
    const indexRef = isbn == null
      ? null
      : doc(db, 'users', ownerId, 'libraryBookIsbns', isbn);
    const index = indexRef == null ? null : await transaction.get(indexRef);
    assert.equal(destinationBook.exists(), false);
    transaction.set(destinationBookRef, {
      ...sourceBook.data(),
      shelfId: 'move-destination',
      activityGeneration: `bulk-move-${bookId}`,
      ...destinationOverrides,
    });
    if (deleteSource) transaction.delete(sourceBookRef);
    if (indexRef != null && indexMode === 'move') {
      transaction.update(indexRef, {
        shelfId: 'move-destination',
        shelfName: 'Move destination',
      });
    } else if (indexRef != null && indexMode === 'delete') {
      transaction.delete(indexRef);
    } else if (indexRef != null && indexMode === 'mismatch') {
      transaction.update(indexRef, {
        shelfId: 'move-destination',
        shelfName: 'Wrong shelf name',
      });
    }
    assert.equal(indexRef == null || index.exists(), true);
    transaction.update(sourceRef, {
      bookCount: source.data().bookCount - 1,
      updatedAt: serverTimestamp(),
    });
    transaction.update(destinationRef, {
      bookCount: destination.data().bookCount + 1,
      updatedAt: serverTimestamp(),
    });
    transaction.update(operationRef, {
      processedCount: operation.data().processedCount + 1,
      currentBookId: bookId,
      currentBookIsbn: isbn,
      updatedAt: serverTimestamp(),
    });
  });
}

async function removeBookChunk(db, bookId) {
  return runTransaction(db, async (transaction) => {
    const sourceRef = doc(db, 'shelves', 'move-source');
    const operationRef = shelfOperationRef(db);
    const bookRef = doc(sourceRef, 'books', bookId);
    const [operation, source, book] = await Promise.all([
      transaction.get(operationRef),
      transaction.get(sourceRef),
      transaction.get(bookRef),
    ]);
    const isbn = book.data().isbn;
    const indexRef = isbn == null
      ? null
      : doc(db, 'users', ownerId, 'libraryBookIsbns', isbn);
    if (indexRef != null) await transaction.get(indexRef);
    if (indexRef != null) transaction.delete(indexRef);
    transaction.delete(bookRef);
    transaction.update(sourceRef, {
      bookCount: source.data().bookCount - 1,
      updatedAt: serverTimestamp(),
    });
    transaction.update(operationRef, {
      processedCount: operation.data().processedCount + 1,
      currentBookId: bookId,
      currentBookIsbn: isbn,
      updatedAt: serverTimestamp(),
    });
  });
}

async function finishShelfOperation(db) {
  return runTransaction(db, async (transaction) => {
    const sourceRef = doc(db, 'shelves', 'move-source');
    const destinationRef = doc(db, 'shelves', 'move-destination');
    const operationRef = shelfOperationRef(db);
    const operation = await transaction.get(operationRef);
    await transaction.get(sourceRef);
    const destination = operation.data().mode === 'move'
      ? await transaction.get(destinationRef)
      : null;
    const sourceDirectoryRef = doc(
      db,
      'publicShelfDirectory',
      'move-source',
    );
    const destinationDirectoryRef = doc(
      db,
      'publicShelfDirectory',
      'move-destination',
    );
    const sourceDirectory = await transaction.get(sourceDirectoryRef);
    const destinationDirectory = destination == null
      ? null
      : await transaction.get(destinationDirectoryRef);
    transaction.delete(sourceRef);
    if (sourceDirectory.exists()) transaction.delete(sourceDirectoryRef);
    if (destination != null) {
      transaction.update(destinationRef, {
        mutationOperationId: deleteField(),
        visibility: operation.data().destinationVisibility,
        autoShareActivity: operation.data().destinationAutoShareActivity,
        updatedAt: serverTimestamp(),
      });
      if (operation.data().destinationVisibility === 'public') {
        transaction.set(destinationDirectoryRef, {
          ownerId,
          shelfId: 'move-destination',
          createdAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });
      } else if (destinationDirectory.exists()) {
        transaction.delete(destinationDirectoryRef);
      }
    }
    transaction.update(operationRef, {
      status: 'completed',
      updatedAt: serverTimestamp(),
    });
  });
}

async function resumeShelfOperation(db) {
  const operation = await getDoc(shelfOperationRef(db));
  const mode = operation.data().mode;
  const books = await getDocs(
    collection(db, 'shelves', 'move-source', 'books'),
  );
  for (const book of books.docs) {
    if (mode === 'move') await moveBookChunk(db, book.id);
    else await removeBookChunk(db, book.id);
  }
  await finishShelfOperation(db);
}

async function seedSingleBookMoveLibrary({
  prefix = 'single',
  bookId = '9781234567890',
  isbn = bookId,
  destinationLocked = false,
  destinationHasBook = false,
} = {}) {
  const sourceShelfId = `${prefix}-source`;
  const destinationShelfId = `${prefix}-destination`;
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'shelves', sourceShelfId), {
      ...validShelf({ name: 'Current shelf', bookCount: 2 }),
      createdAt: Timestamp.fromMillis(1000),
      updatedAt: Timestamp.fromMillis(2000),
    });
    batch.set(doc(db, 'shelves', destinationShelfId), {
      ...validShelf({
        name: 'Destination shelf',
        visibility: 'public',
        autoShareActivity: true,
        bookCount: 3,
        ...(destinationLocked ? { mutationOperationId: 'busy' } : {}),
      }),
      createdAt: Timestamp.fromMillis(1100),
      updatedAt: Timestamp.fromMillis(2100),
    });
    batch.set(doc(db, 'shelves', sourceShelfId, 'books', bookId), {
      ...validBook(sourceShelfId, {
        title: 'Exact movable book',
        titleNormalized: 'exact movable book',
        isbn,
        readingStatus: 'finished',
        isOwned: false,
      }),
      createdAt: Timestamp.fromMillis(1200),
      updatedAt: Timestamp.fromMillis(2200),
    });
    if (destinationHasBook) {
      batch.set(doc(db, 'shelves', destinationShelfId, 'books', bookId), {
        ...validBook(destinationShelfId, { isbn }),
        createdAt: Timestamp.fromMillis(1300),
        updatedAt: Timestamp.fromMillis(2300),
      });
    }
    if (isbn != null) {
      batch.set(doc(db, 'users', ownerId, 'libraryBookIsbns', isbn), {
        ownerId,
        shelfId: sourceShelfId,
        bookId,
        title: 'Exact movable book',
        shelfName: 'Current shelf',
        createdAt: Timestamp.fromMillis(1200),
      });
    }
    await batch.commit();
  });
  return { sourceShelfId, destinationShelfId, bookId, isbn };
}

async function moveSingleBook(db, seeded, options = {}) {
  const {
    destinationBookOverrides = {},
    sourceShelfOverrides = {},
    destinationShelfOverrides = {},
    indexOverrides = {},
    proofOverrides = {},
    deleteSource = true,
    createDestination = true,
    updateIndex = true,
    updateReview = false,
  } = options;
  return runTransaction(db, async (transaction) => {
    const sourceShelfRef = doc(db, 'shelves', seeded.sourceShelfId);
    const destinationShelfRef = doc(db, 'shelves', seeded.destinationShelfId);
    const sourceBookRef = doc(sourceShelfRef, 'books', seeded.bookId);
    const destinationBookRef = doc(
      destinationShelfRef,
      'books',
      seeded.bookId,
    );
    const moveId = `${seeded.sourceShelfId}-${seeded.bookId}`;
    const moveRef = doc(db, 'users', ownerId, 'bookMoves', moveId);
    const [sourceShelf, destinationShelf, sourceBook, destinationBook] =
      await Promise.all([
      transaction.get(sourceShelfRef),
      transaction.get(destinationShelfRef),
      transaction.get(sourceBookRef),
      transaction.get(destinationBookRef),
    ]);
    assert.equal(sourceBook.exists(), true);
    const indexRef = seeded.isbn == null
      ? null
      : doc(db, 'users', ownerId, 'libraryBookIsbns', seeded.isbn);
    if (indexRef != null) await transaction.get(indexRef);
    const reviewId = `${ownerId}--${seeded.bookId}`;
    const reviewRef = doc(db, 'circleReviews', reviewId);
    const reviewDraftRef = doc(
      db,
      'users',
      ownerId,
      'reviewDrafts',
      reviewId,
    );
    if (updateReview) {
      await transaction.get(reviewRef);
      await transaction.get(reviewDraftRef);
    }
    const proof = {
      ownerId,
      moveId,
      sourceShelfId: seeded.sourceShelfId,
      destinationShelfId: seeded.destinationShelfId,
      bookId: seeded.bookId,
      isbn: seeded.isbn,
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
      ...proofOverrides,
    };
    transaction.set(moveRef, proof);
    if (createDestination) {
      assert.equal(destinationBook.exists(), false);
      transaction.set(destinationBookRef, {
        ...sourceBook.data(),
        shelfId: seeded.destinationShelfId,
        activityGeneration: `${moveId}-generation`,
        ...destinationBookOverrides,
      });
    }
    if (deleteSource) transaction.delete(sourceBookRef);
    transaction.update(sourceShelfRef, {
      bookCount: sourceShelf.data().bookCount - 1,
      lastBookMoveId: moveId,
      updatedAt: serverTimestamp(),
      ...sourceShelfOverrides,
    });
    transaction.update(destinationShelfRef, {
      bookCount: destinationShelf.data().bookCount + 1,
      lastBookMoveId: moveId,
      updatedAt: serverTimestamp(),
      ...destinationShelfOverrides,
    });
    if (indexRef != null && updateIndex) {
      transaction.update(indexRef, {
        shelfId: seeded.destinationShelfId,
        shelfName: destinationShelf.data().name,
        ...indexOverrides,
      });
    }
    if (updateReview) {
      transaction.update(reviewRef, {
        shelfId: seeded.destinationShelfId,
        updatedAt: serverTimestamp(),
      });
      transaction.update(reviewDraftRef, {
        shelfId: seeded.destinationShelfId,
        updatedAt: serverTimestamp(),
      });
    }
  });
}

async function seedSingleBookRemovalLibrary({
  prefix = 'remove-single',
  bookId = '9781234567890',
  isbn = bookId,
  locked = false,
  indexOverrides = {},
  createdAtMillis = 3200,
} = {}) {
  const shelfId = `${prefix}-shelf`;
  const sourceBookCreatedAt = Timestamp.fromMillis(createdAtMillis);
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'shelves', shelfId), {
      ...validShelf({
        name: 'Removal shelf',
        bookCount: 2,
        ...(locked ? { mutationOperationId: 'busy' } : {}),
      }),
      createdAt: Timestamp.fromMillis(3000),
      updatedAt: Timestamp.fromMillis(3100),
    });
    batch.set(doc(db, 'shelves', shelfId, 'books', bookId), {
      ...validBook(shelfId, {
        title: 'Exact removable book',
        titleNormalized: 'exact removable book',
        isbn,
        readingStatus: 'finished',
        isOwned: false,
      }),
      createdAt: sourceBookCreatedAt,
      updatedAt: Timestamp.fromMillis(3300),
    });
    batch.set(doc(db, 'shelves', shelfId, 'books', 'other-entry'), {
      ...validBook(shelfId, { title: 'Keep this entry' }),
      createdAt: Timestamp.fromMillis(3400),
      updatedAt: Timestamp.fromMillis(3500),
    });
    if (isbn != null) {
      batch.set(doc(db, 'users', ownerId, 'libraryBookIsbns', isbn), {
        ownerId,
        shelfId,
        bookId,
        title: 'Exact removable book',
        shelfName: 'Removal shelf',
        createdAt: sourceBookCreatedAt,
        ...indexOverrides,
      });
    }
    await batch.commit();
  });
  return { shelfId, bookId, isbn, sourceBookCreatedAt };
}

async function removeSingleBook(db, seeded, options = {}) {
  const {
    proofOverrides = {},
    shelfOverrides = {},
    deleteBook = true,
    deleteIndex = true,
    deleteReview = false,
    removalId = `${seeded.shelfId}-${seeded.bookId}-removal`,
  } = options;
  return runTransaction(db, async (transaction) => {
    const shelfRef = doc(db, 'shelves', seeded.shelfId);
    const bookRef = doc(shelfRef, 'books', seeded.bookId);
    const removalRef = doc(db, 'users', ownerId, 'bookRemovals', removalId);
    const shelf = await transaction.get(shelfRef);
    const book = await transaction.get(bookRef);
    assert.equal(book.exists(), true);
    const indexRef = seeded.isbn == null
      ? null
      : doc(db, 'users', ownerId, 'libraryBookIsbns', seeded.isbn);
    if (indexRef != null) await transaction.get(indexRef);
    const reviewId = `${ownerId}--${seeded.bookId}`;
    const reviewRef = doc(db, 'circleReviews', reviewId);
    const reviewDraftRef = doc(
      db,
      'users',
      ownerId,
      'reviewDrafts',
      reviewId,
    );
    if (deleteReview) {
      await transaction.get(reviewRef);
      await transaction.get(reviewDraftRef);
    }
    transaction.set(removalRef, {
      ownerId,
      removalId,
      shelfId: seeded.shelfId,
      bookId: seeded.bookId,
      isbn: seeded.isbn,
      title: book.data().title,
      sourceBookCreatedAt: book.data().createdAt,
      sourceCountBefore: shelf.data().bookCount,
      sourceVisibility: shelf.data().visibility,
      sourceAutoShareActivity: shelf.data().autoShareActivity,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...proofOverrides,
    });
    if (deleteBook) transaction.delete(bookRef);
    transaction.update(shelfRef, {
      bookCount: shelf.data().bookCount - 1,
      lastBookRemovalId: removalId,
      updatedAt: serverTimestamp(),
      ...shelfOverrides,
    });
    if (indexRef != null && deleteIndex) transaction.delete(indexRef);
    if (deleteReview) {
      transaction.delete(reviewRef);
      transaction.delete(reviewDraftRef);
    }
  });
}

function requestData(pair, requesterId, recipientId, inviteCode) {
  return {
    pairId: pair,
    requesterId,
    recipientId,
    inviteCode,
    createdAt: serverTimestamp(),
  };
}

function validShelf(overrides = {}) {
  return {
    ownerId,
    name: 'Want to read',
    visibility: 'friends',
    autoShareActivity: true,
    bookCount: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function validBook(shelfId, overrides = {}) {
  return {
    ownerId,
    shelfId,
    title: 'A valid book',
    titleNormalized: 'a valid book',
    author: 'An Author',
    isbn: null,
    isOwned: true,
    readingStatus: 'wantToRead',
    coverUrl: null,
    coverStoragePath: null,
    activityGeneration: 'initial-generation',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function validIsbnIndex(shelfId, isbn, overrides = {}) {
  return {
    ownerId,
    shelfId,
    bookId: isbn,
    title: 'A valid book',
    shelfName: 'Want to read',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

async function createShelf(db, shelfId, overrides = {}) {
  await assertSucceeds(
    setDoc(doc(db, 'shelves', shelfId), validShelf(overrides)),
  );
}

async function addBookBatch(db, shelfId, bookId, book, index = null) {
  return runTransaction(db, async (transaction) => {
    const shelfRef = doc(db, 'shelves', shelfId);
    const shelf = await transaction.get(shelfRef);
    const shelfData = shelf.data();
    const sharesActivity =
      book.isOwned === true &&
      ['friends', 'public'].includes(shelfData?.visibility) &&
      shelfData?.autoShareActivity === true;
    const activityId = `${bookId}-added-${++activitySequence}`;
    transaction.set(doc(db, 'shelves', shelfId, 'books', bookId), {
      ...book,
      ...(sharesActivity ? { lastActivityId: activityId } : {}),
    });
    if (sharesActivity) {
      transaction.set(
        doc(db, 'shelves', shelfId, 'books', bookId, 'activities', activityId),
        {
          authorId: ownerId,
          shelfId,
          bookId,
          type: 'added',
          batchId: null,
          audience: 'friends',
          activityGeneration: book.activityGeneration,
          createdAt: serverTimestamp(),
        },
      );
    }
    if (index != null) {
      transaction.set(
      doc(db, 'users', ownerId, 'libraryBookIsbns', bookId),
      index,
      );
    }
    transaction.update(shelfRef, {
      bookCount: (shelfData?.bookCount ?? 0) + 1,
      updatedAt: serverTimestamp(),
    });
  });
}

before(async () => {
  const rules = fs.readFileSync(
    path.resolve(process.env.READUO_RULES_FILE || '../firestore.rules'),
    'utf8',
  );
  environment = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    for (const uid of [ownerId, otherUserId, thirdUserId]) {
      await setDoc(doc(context.firestore(), 'activeAccounts', uid), { createdAt: Timestamp.now() });
    }
  });
  activitySequence = 0;
});

after(async () => {
  await environment.cleanup();
});

test('first-book onboarding state is owner-only and schema constrained', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const state = doc(ownerDb, 'users', ownerId, 'onboarding', 'firstBook');

  await assertSucceeds(setDoc(state, {
    ownerId,
    status: 'pending',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(state));
  await assertFails(
    getDoc(doc(otherDb, 'users', ownerId, 'onboarding', 'firstBook')),
  );
  await assertSucceeds(updateDoc(state, {
    status: 'completed',
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(state, { ownerId: otherUserId }));
  await assertFails(updateDoc(state, { status: 'invalid' }));
  await assertFails(
    setDoc(doc(ownerDb, 'users', ownerId, 'onboarding', 'other'), {
      ownerId,
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(otherDb, 'users', ownerId, 'onboarding', 'firstBook'), {
      ownerId,
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('reader profiles require an atomic invite-code reservation', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createReader(ownerDb, ownerId, 'ABC234', 'Alex Reader');
  await assertSucceeds(getDoc(doc(ownerDb, 'readerProfiles', ownerId)));
  await assertSucceeds(getDoc(doc(ownerDb, 'inviteCodes', 'ABC234')));

  await assertFails(
    setDoc(
      doc(ownerDb, 'readerProfiles', 'unreserved'),
      profileData('unreserved', 'XYZ789', 'Spoofed Reader'),
    ),
  );
  await assertFails(getDocs(collection(ownerDb, 'readerProfiles')));
  await assertFails(getDocs(collection(ownerDb, 'inviteCodes')));
});

test('first-use repository bootstrap may read and reserve an absent code', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(
    bootstrapReader(ownerDb, ownerId, 'NEW234', 'Alex Reader'),
  );
  const profile = await assertSucceeds(
    getDoc(doc(ownerDb, 'readerProfiles', ownerId)),
  );
  const code = await assertSucceeds(
    getDoc(doc(ownerDb, 'inviteCodes', 'NEW234')),
  );
  assert.equal(profile.data().inviteCode, 'NEW234');
  assert.equal(code.data().ownerId, ownerId);

  await assertSucceeds(
    bootstrapReader(ownerDb, ownerId, 'OTHER2', 'Alex Reader'),
  );
  const retryProfile = await getDoc(doc(ownerDb, 'readerProfiles', ownerId));
  assert.equal(retryProfile.data().inviteCode, 'NEW234');
});

test('concurrent code reservation leaves exactly one rightful owner', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const attempts = await Promise.allSettled([
    bootstrapReader(ownerDb, ownerId, 'RACE24', 'Alex Reader'),
    bootstrapReader(otherDb, otherUserId, 'RACE24', 'Bailey Reader'),
  ]);
  assert.equal(
    attempts.filter((attempt) => attempt.status === 'fulfilled').length,
    1,
  );
  assert.equal(
    attempts.filter((attempt) => attempt.status === 'rejected').length,
    1,
  );
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const reservation = await getDoc(doc(db, 'inviteCodes', 'RACE24'));
    const profiles = await getDocs(collection(db, 'readerProfiles'));
    assert.equal(reservation.exists(), true);
    assert.equal(profiles.size, 1);
    assert.equal(
      reservation.data().ownerId,
      profiles.docs[0].data().ownerId,
    );
  });
});

test('reader identity never permits email or owner spoofing', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const batchWithEmail = writeBatch(ownerDb);
  batchWithEmail.set(doc(ownerDb, 'readerProfiles', ownerId), {
    ...profileData(ownerId, 'ABC234', 'Alex Reader'),
    email: 'private@example.com',
  });
  batchWithEmail.set(doc(ownerDb, 'inviteCodes', 'ABC234'), {
    ownerId,
    code: 'ABC234',
    createdAt: serverTimestamp(),
  });
  await assertFails(batchWithEmail.commit());

  const spoofBatch = writeBatch(ownerDb);
  spoofBatch.set(
    doc(ownerDb, 'readerProfiles', otherUserId),
    profileData(otherUserId, 'XYZ789', 'Other Reader'),
  );
  spoofBatch.set(doc(ownerDb, 'inviteCodes', 'XYZ789'), {
    ownerId: otherUserId,
    code: 'XYZ789',
    createdAt: serverTimestamp(),
  });
  await assertFails(spoofBatch.commit());
});

test('friend code creates only a pending request visible to participants', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const thirdDb = environment.authenticatedContext(thirdUserId).firestore();
  await createReader(ownerDb, ownerId, 'ABC234', 'Alex Reader');
  await createReader(otherDb, otherUserId, 'XYZ789', 'Bailey Reader');
  const pair = friendPair(ownerId, otherUserId);

  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'friendRequests', pair),
      requestData(pair, ownerId, otherUserId, 'XYZ789'),
    ),
  );
  await assertSucceeds(getDoc(doc(ownerDb, 'friendRequests', pair)));
  await assertSucceeds(getDoc(doc(otherDb, 'friendRequests', pair)));
  await assertFails(getDoc(doc(thirdDb, 'friendRequests', pair)));
  const absentFriendship = await assertSucceeds(
    getDoc(doc(ownerDb, 'friendships', pair)),
  );
  assert.equal(absentFriendship.exists(), false);

  const incoming = await assertSucceeds(
    getDocs(
      query(
        collection(otherDb, 'friendRequests'),
        where('recipientId', '==', otherUserId),
      ),
    ),
  );
  const sent = await assertSucceeds(
    getDocs(
      query(
        collection(ownerDb, 'friendRequests'),
        where('requesterId', '==', ownerId),
      ),
    ),
  );
  assert.equal(incoming.size, 1);
  assert.equal(sent.size, 1);
});

test('participants can safely check absent deterministic pair state', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const pair = friendPair(ownerId, otherUserId);
  const request = await assertSucceeds(
    getDoc(doc(ownerDb, 'friendRequests', pair)),
  );
  const friendship = await assertSucceeds(
    getDoc(doc(ownerDb, 'friendships', pair)),
  );
  assert.equal(request.exists(), false);
  assert.equal(friendship.exists(), false);

  const unrelatedPair = friendPair(otherUserId, thirdUserId);
  await assertFails(
    getDoc(doc(ownerDb, 'friendRequests', unrelatedPair)),
  );
  await assertFails(
    getDoc(doc(ownerDb, 'friendships', unrelatedPair)),
  );
});

test('self, invalid-code, repeated, and opposite requests are denied', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await createReader(ownerDb, ownerId, 'ABC234', 'Alex Reader');
  await createReader(otherDb, otherUserId, 'XYZ789', 'Bailey Reader');

  await assertFails(
    setDoc(
      doc(ownerDb, 'friendRequests', `${ownerId}--${ownerId}`),
      requestData(`${ownerId}--${ownerId}`, ownerId, ownerId, 'ABC234'),
    ),
  );
  const pair = friendPair(ownerId, otherUserId);
  await assertFails(
    setDoc(
      doc(ownerDb, 'friendRequests', pair),
      requestData(pair, ownerId, otherUserId, 'ABC234'),
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'friendRequests', pair),
      requestData(pair, ownerId, otherUserId, 'XYZ789'),
    ),
  );
  await assertFails(
    setDoc(
      doc(otherDb, 'friendRequests', pair),
      requestData(pair, otherUserId, ownerId, 'ABC234'),
    ),
  );
  const reversePair = `${otherUserId}--${ownerId}`;
  await assertFails(
    setDoc(
      doc(otherDb, 'friendRequests', reversePair),
      requestData(reversePair, otherUserId, ownerId, 'ABC234'),
    ),
  );
});

test('only recipient can atomically accept and participants can remove', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await createReader(ownerDb, ownerId, 'ABC234', 'Alex Reader');
  await createReader(otherDb, otherUserId, 'XYZ789', 'Bailey Reader');
  const pair = friendPair(ownerId, otherUserId);
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'friendRequests', pair),
      requestData(pair, ownerId, otherUserId, 'XYZ789'),
    ),
  );

  await assertFails(
    setDoc(doc(ownerDb, 'friendships', pair), {
      pairId: pair,
      memberIds: [ownerId, otherUserId],
      createdAt: serverTimestamp(),
    }),
  );
  const accept = writeBatch(otherDb);
  accept.delete(doc(otherDb, 'friendRequests', pair));
  accept.set(doc(otherDb, 'friendships', pair), {
    pairId: pair,
    memberIds: [ownerId, otherUserId],
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(accept.commit());
  await assertSucceeds(getDoc(doc(ownerDb, 'friendships', pair)));

  const friendships = await assertSucceeds(
    getDocs(
      query(
        collection(ownerDb, 'friendships'),
        where('memberIds', 'array-contains', ownerId),
      ),
    ),
  );
  assert.equal(friendships.size, 1);
  await assertSucceeds(
    writeBatch(ownerDb).delete(doc(ownerDb, 'friendships', pair)).commit(),
  );
  await assertSucceeds(
    setDoc(
      doc(otherDb, 'friendRequests', pair),
      requestData(pair, otherUserId, ownerId, 'ABC234'),
    ),
  );
});

test('blocking removes pair state, prevents requests, and unblock restores nothing', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await createReader(ownerDb, ownerId, 'ABC234', 'Alex Reader');
  await createReader(otherDb, otherUserId, 'XYZ789', 'Bailey Reader');
  const pair = friendPair(ownerId, otherUserId);
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'friendRequests', pair),
      requestData(pair, ownerId, otherUserId, 'XYZ789'),
    ),
  );

  const block = writeBatch(ownerDb);
  block.delete(doc(ownerDb, 'friendRequests', pair));
  block.set(doc(ownerDb, 'blocks', ownerId, 'blocked', otherUserId), {
    blockerId: ownerId,
    blockedId: otherUserId,
    pairId: pair,
    blockedDisplayName: 'Bailey Reader',
    blockedPhotoUrl: null,
    createdAt: serverTimestamp(),
  });
  await assertSucceeds(block.commit());
  await assertFails(getDoc(doc(ownerDb, 'readerProfiles', otherUserId)));
  await assertFails(getDoc(doc(otherDb, 'readerProfiles', ownerId)));
  await assertFails(
    setDoc(
      doc(ownerDb, 'friendRequests', pair),
      requestData(pair, ownerId, otherUserId, 'XYZ789'),
    ),
  );
  await assertFails(
    setDoc(
      doc(otherDb, 'friendRequests', pair),
      requestData(pair, otherUserId, ownerId, 'ABC234'),
    ),
  );

  await assertSucceeds(
    writeBatch(ownerDb)
        .delete(doc(ownerDb, 'blocks', ownerId, 'blocked', otherUserId))
        .commit(),
  );
  await environment.withSecurityRulesDisabled(async (context) => {
    const friendship = await getDoc(
      doc(context.firestore(), 'friendships', pair),
    );
    assert.equal(friendship.exists(), false);
  });
  await assertSucceeds(
    setDoc(
      doc(otherDb, 'friendRequests', pair),
      requestData(pair, otherUserId, ownerId, 'ABC234'),
    ),
  );
});

test('accepted friends browse Friends and Public shelves but never Private', async () => {
  await seedSharedLibrary();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const shelves = await assertSucceeds(
    getDocs(
      query(
        collection(ownerDb, 'shelves'),
        where('ownerId', '==', otherUserId),
        where('visibility', 'in', ['friends', 'public']),
      ),
    ),
  );
  assert.deepEqual(
    shelves.docs.map((item) => item.id).sort(),
    ['friends-shelf', 'public-shelf'],
  );
  await assertFails(getDoc(doc(ownerDb, 'shelves', 'private-shelf')));
  await assertSucceeds(
    getDocs(collection(ownerDb, 'shelves', 'friends-shelf', 'books')),
  );
  const ownedBooks = await assertSucceeds(
    getDocs(
      query(
        collection(ownerDb, 'shelves', 'friends-shelf', 'books'),
        where('isOwned', '==', true),
      ),
    ),
  );
  assert.deepEqual(
    ownedBooks.docs.map((item) => item.id),
    ['friends-shelf-book'],
  );
  await assertFails(
    getDocs(collection(ownerDb, 'shelves', 'private-shelf', 'books')),
  );
});

test('outsiders get Public only and cannot mutate a shared source', async () => {
  await seedSharedLibrary();
  const thirdDb = environment.authenticatedContext(thirdUserId).firestore();
  await assertSucceeds(getDoc(doc(thirdDb, 'shelves', 'public-shelf')));
  await assertFails(getDoc(doc(thirdDb, 'shelves', 'friends-shelf')));
  await assertSucceeds(
    getDocs(collection(thirdDb, 'shelves', 'public-shelf', 'books')),
  );
  await assertFails(
    updateDoc(doc(thirdDb, 'shelves', 'public-shelf'), {
      name: 'Hijacked',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(
      doc(thirdDb, 'shelves', 'public-shelf', 'books', 'public-shelf-book'),
      { title: 'Hijacked' },
    ),
  );
});

test('signed-in discovery resolves directory entries through authorized shelves', async () => {
  await seedSharedLibrary({ friend: false });
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'shelves', 'third-public-shelf'), {
      ...validShelf({ ownerId: thirdUserId, visibility: 'public', bookCount: 1 }),
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    await setDoc(doc(db, 'publicShelfDirectory', 'third-public-shelf'), {
      ownerId: thirdUserId,
      shelfId: 'third-public-shelf',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const initial = await assertSucceeds(
    getDocs(collection(ownerDb, 'publicShelfDirectory')),
  );
  assert.deepEqual(
    initial.docs.map((item) => item.id).sort(),
    ['public-shelf', 'third-public-shelf'],
  );
  await assertSucceeds(
    getDoc(doc(ownerDb, 'shelves', 'public-shelf')),
  );
  await assertSucceeds(
    getDoc(doc(ownerDb, 'shelves', 'third-public-shelf')),
  );

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
      {
        blockerId: ownerId,
        blockedId: otherUserId,
        pairId: friendPair(ownerId, otherUserId),
        blockedDisplayName: 'Bailey Reader',
        blockedPhotoUrl: null,
        createdAt: Timestamp.now(),
      },
    );
  });
  const retainedDirectory = await assertSucceeds(
    getDocs(collection(ownerDb, 'publicShelfDirectory')),
  );
  assert.equal(retainedDirectory.size, 2);
  await assertFails(getDoc(doc(ownerDb, 'shelves', 'public-shelf')));
  const unaffectedOwner = await assertSucceeds(
    getDocs(
      query(
        collection(ownerDb, 'shelves'),
        where('ownerId', '==', thirdUserId),
        where('visibility', '==', 'public'),
      ),
    ),
  );
  assert.deepEqual(
    unaffectedOwner.docs.map((item) => item.id),
    ['third-public-shelf'],
  );
});

test('public directory writes follow shelf state and reject spoofing', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const shelfRef = doc(ownerDb, 'shelves', 'discoverable-shelf');
  const directoryRef = doc(
    ownerDb,
    'publicShelfDirectory',
    'discoverable-shelf',
  );
  const create = writeBatch(ownerDb);
  create.set(shelfRef, {
    ...validShelf({ visibility: 'public' }),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  create.set(directoryRef, {
    ownerId,
    shelfId: 'discoverable-shelf',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  await assertSucceeds(create.commit());

  await assertFails(
    setDoc(doc(otherDb, 'publicShelfDirectory', 'spoofed-shelf'), {
      ownerId,
      shelfId: 'spoofed-shelf',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(shelfRef, {
      visibility: 'private',
      autoShareActivity: false,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(getDoc(directoryRef));
  await assertFails(getDoc(doc(otherDb, 'shelves', 'discoverable-shelf')));
  await assertSucceeds(
    runTransaction(ownerDb, async (transaction) => {
      const retainedDirectory = await transaction.get(directoryRef);
      if (retainedDirectory.exists()) transaction.delete(directoryRef);
    }),
  );
});

test('removal and privacy changes immediately revoke Friends shelf reads', async () => {
  await seedSharedLibrary();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await assertSucceeds(getDoc(doc(ownerDb, 'shelves', 'friends-shelf')));
  await assertSucceeds(
    writeBatch(ownerDb)
      .delete(doc(ownerDb, 'friendships', friendPair(ownerId, otherUserId)))
      .commit(),
  );
  await assertFails(getDoc(doc(ownerDb, 'shelves', 'friends-shelf')));
  await assertSucceeds(getDoc(doc(ownerDb, 'shelves', 'public-shelf')));

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'friendships', friendPair(ownerId, otherUserId)),
      {
        pairId: friendPair(ownerId, otherUserId),
        memberIds: [ownerId, otherUserId],
        createdAt: Timestamp.now(),
      },
    );
  });
  await assertSucceeds(
    updateDoc(doc(otherDb, 'shelves', 'friends-shelf'), {
      visibility: 'private',
      autoShareActivity: false,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(getDoc(doc(ownerDb, 'shelves', 'friends-shelf')));
});

test('owner settings update preserves counts and ISBN indexes while revoking friend reads', async () => {
  await seedSharedLibrary();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(
        context.firestore(),
        'users',
        otherUserId,
        'libraryBookIsbns',
        '9780000000002',
      ),
      {
        ownerId: otherUserId,
        shelfId: 'friends-shelf',
        bookId: 'friends-shelf-book',
        title: 'A valid book',
        shelfName: 'Want to read',
        createdAt: Timestamp.now(),
      },
    );
  });

  const friendDb = environment.authenticatedContext(ownerId).firestore();
  const ownerDb = environment.authenticatedContext(otherUserId).firestore();
  const outsiderDb = environment.authenticatedContext(thirdUserId).firestore();
  const shelfRef = doc(ownerDb, 'shelves', 'friends-shelf');
  const before = await getDoc(shelfRef);

  await assertFails(
    updateDoc(doc(outsiderDb, 'shelves', 'friends-shelf'), {
      name: 'Not yours',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(shelfRef, {
      ownerId,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    (async () => {
      const directoryRef = doc(
        ownerDb,
        'publicShelfDirectory',
        'friends-shelf',
      );
      const directory = await getDoc(directoryRef);
      assert.equal(directory.exists(), false);
      return updateDoc(shelfRef, {
        name: 'Private field notes',
        description: 'Only the owner can see these books.',
        visibility: 'private',
        autoShareActivity: false,
        updatedAt: serverTimestamp(),
      });
    })(),
  );

  const after = await getDoc(shelfRef);
  assert.equal(after.data().bookCount, before.data().bookCount);
  assert.equal(
    after.data().createdAt.toMillis(),
    before.data().createdAt.toMillis(),
  );
  await assertFails(getDoc(doc(friendDb, 'shelves', 'friends-shelf')));
  await assertFails(
    getDoc(
      doc(friendDb, 'shelves', 'friends-shelf', 'books', 'friends-shelf-book'),
    ),
  );
  const index = await getDoc(
    doc(
      ownerDb,
      'users',
      otherUserId,
      'libraryBookIsbns',
      '9780000000002',
    ),
  );
  assert.equal(index.data().shelfName, 'Want to read');

  const privateShelfRef = doc(ownerDb, 'shelves', 'private-shelf');
  await assertSucceeds(
    (async () => {
      const directoryRef = doc(
        ownerDb,
        'publicShelfDirectory',
        'private-shelf',
      );
      const directory = await getDoc(directoryRef);
      assert.equal(directory.exists(), false);
      return updateDoc(privateShelfRef, {
        name: 'Still private',
        updatedAt: serverTimestamp(),
      });
    })(),
  );
});

test('library startup can query empty and pending owner shelf operations', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const operationQuery = query(
    collection(ownerDb, 'users', ownerId, 'shelfOperations'),
    where('status', '==', 'running'),
  );
  const empty = await assertSucceeds(getDocs(operationQuery));
  assert.equal(empty.size, 0);

  await seedShelfMutationLibrary(1);
  assert.equal(
    (await getDoc(doc(ownerDb, 'publicShelfDirectory', 'move-source')))
      .exists(),
    false,
  );
  assert.equal(
    (await getDoc(doc(ownerDb, 'publicShelfDirectory', 'move-destination')))
      .exists(),
    false,
  );
  await assertSucceeds(prepareShelfOperation(ownerDb));
  const pending = await assertSucceeds(getDocs(operationQuery));
  assert.equal(pending.size, 1);
  assert.equal(pending.docs[0].data().destinationShelfId, 'move-destination');
  await assertFails(
    getDocs(
      query(
        collection(otherDb, 'users', ownerId, 'shelfOperations'),
        where('status', '==', 'running'),
      ),
    ),
  );
});

test('owner resumes and moves more than 150 ISBN books with every index', async () => {
  const bookCount = 160;
  await seedShelfMutationLibrary(bookCount);
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const sourceBooks = await getDocs(
    collection(ownerDb, 'shelves', 'move-source', 'books'),
  );
  const firstBefore = sourceBooks.docs[0].data();

  await assertSucceeds(prepareShelfOperation(ownerDb));
  await assertSucceeds(moveBookChunk(ownerDb, sourceBooks.docs[0].id));
  await assertSucceeds(moveBookChunk(ownerDb, sourceBooks.docs[1].id));
  const interrupted = await getDoc(shelfOperationRef(ownerDb));
  assert.equal(interrupted.data().processedCount, 2);
  await assertSucceeds(resumeShelfOperation(ownerDb));

  await assertFails(getDoc(doc(ownerDb, 'shelves', 'move-source')));
  const destination = await getDoc(
    doc(ownerDb, 'shelves', 'move-destination'),
  );
  assert.equal(destination.data().bookCount, bookCount + 4);
  assert.equal(destination.data().visibility, 'public');
  assert.equal(destination.data().autoShareActivity, true);
  assert.equal('mutationOperationId' in destination.data(), false);
  assert.equal(
    (await getDoc(doc(ownerDb, 'publicShelfDirectory', 'move-destination')))
      .exists(),
    true,
  );
  const movedBooks = await getDocs(
    collection(ownerDb, 'shelves', 'move-destination', 'books'),
  );
  assert.equal(movedBooks.size, bookCount);
  const firstAfter = movedBooks.docs.find(
    (book) => book.id === sourceBooks.docs[0].id,
  ).data();
  assert.equal(firstAfter.shelfId, 'move-destination');
  assert.equal(firstAfter.title, firstBefore.title);
  assert.equal(firstAfter.readingStatus, firstBefore.readingStatus);
  assert.equal(firstAfter.isOwned, firstBefore.isOwned);
  assert.equal(
    firstAfter.createdAt.toMillis(),
    firstBefore.createdAt.toMillis(),
  );
  const indexes = await getDocs(
    collection(ownerDb, 'users', ownerId, 'libraryBookIsbns'),
  );
  assert.equal(indexes.size, bookCount);
  assert.equal(
    indexes.docs.every(
      (index) =>
        index.data().shelfId === 'move-destination' &&
        index.data().shelfName === 'Move destination',
    ),
    true,
  );
  const completed = await getDoc(shelfOperationRef(ownerDb));
  assert.equal(completed.data().status, 'completed');
  assert.equal(completed.data().processedCount, bookCount);
});

test('owner resumes removal after the last book and releases ISBN indexes', async () => {
  await seedShelfMutationLibrary(3);
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'shelves', 'move-source', 'books', 'manual-entry'), {
      ...validBook('move-source', {
        title: 'Manual entry',
        titleNormalized: 'manual entry',
        isbn: null,
      }),
      createdAt: Timestamp.fromMillis(1200),
      updatedAt: Timestamp.fromMillis(2200),
    });
    await updateDoc(doc(db, 'shelves', 'move-source'), { bookCount: 4 });
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const sourceBooks = await getDocs(
    collection(ownerDb, 'shelves', 'move-source', 'books'),
  );
  await assertSucceeds(prepareShelfOperation(ownerDb, 'remove'));
  for (const book of sourceBooks.docs) {
    await assertSucceeds(removeBookChunk(ownerDb, book.id));
  }
  const interrupted = await getDoc(shelfOperationRef(ownerDb));
  assert.equal(interrupted.data().processedCount, 4);
  assert.equal(
    (await getDocs(collection(ownerDb, 'shelves', 'move-source', 'books')))
      .size,
    0,
  );
  await assertSucceeds(resumeShelfOperation(ownerDb));

  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    assert.equal(
      (await getDoc(doc(db, 'shelves', 'move-source'))).exists(),
      false,
    );
    assert.equal(
      (await getDoc(doc(db, 'publicShelfDirectory', 'move-source'))).exists(),
      false,
    );
    assert.equal(
      (await getDocs(collection(db, 'shelves', 'move-source', 'books'))).size,
      0,
    );
    assert.equal(
      (
        await getDocs(
          collection(db, 'users', ownerId, 'libraryBookIsbns'),
        )
      ).size,
      0,
    );
  });
});

test('forged, retained-source, and invalid-index moves are denied atomically', async () => {
  const firstBook = '9780000000000';
  for (const options of [
    { destinationOverrides: { title: 'Forged backdated duplicate' } },
    { deleteSource: false },
    { indexMode: 'unchanged' },
    { indexMode: 'delete' },
    { indexMode: 'mismatch' },
  ]) {
    await environment.clearFirestore();
    await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'activeAccounts', ownerId), { active: true }));
    await seedShelfMutationLibrary(1);
    const ownerDb = environment.authenticatedContext(ownerId).firestore();
    await assertSucceeds(prepareShelfOperation(ownerDb));
    await assertFails(moveBookChunk(ownerDb, firstBook, options));
    assert.equal(
      (await getDoc(doc(ownerDb, 'shelves', 'move-source', 'books', firstBook)))
        .exists(),
      true,
    );
    assert.equal(
      (await getDoc(doc(ownerDb, 'shelves', 'move-destination', 'books', firstBook)))
        .exists(),
      false,
    );
    const index = await getDoc(
      doc(ownerDb, 'users', ownerId, 'libraryBookIsbns', firstBook),
    );
    assert.equal(index.data().shelfId, 'move-source');
  }
});

test('locked shelves reject settings, additions, and premature deletion', async () => {
  await seedShelfMutationLibrary(1);
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(prepareShelfOperation(ownerDb));
  await assertFails(
    updateDoc(doc(ownerDb, 'shelves', 'move-source'), {
      name: 'Changed while moving',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    addBookBatch(
      ownerDb,
      'move-destination',
      'manual-during-move',
      validBook('move-destination'),
    ),
  );
  await assertFails(
    runTransaction(ownerDb, async (transaction) => {
      transaction.delete(doc(ownerDb, 'shelves', 'move-source'));
    }),
  );
});

test('cross-user shelf mutation is denied without partial deletion', async () => {
  await seedShelfMutationLibrary(2);
  const outsiderDb = environment.authenticatedContext(otherUserId).firestore();
  await assertFails(prepareShelfOperation(outsiderDb));
  const outsiderBatch = writeBatch(outsiderDb);
  outsiderBatch.delete(doc(outsiderDb, 'shelves', 'move-source'));
  outsiderBatch.delete(
    doc(outsiderDb, 'shelves', 'move-source', 'books', '9780000000000'),
  );
  outsiderBatch.delete(
    doc(
      outsiderDb,
      'users',
      ownerId,
      'libraryBookIsbns',
      '9780000000000',
    ),
  );
  await assertFails(outsiderBatch.commit());

  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    assert.equal(
      (await getDoc(doc(db, 'shelves', 'move-source'))).exists(),
      true,
    );
    assert.equal(
      (
        await getDoc(
          doc(db, 'shelves', 'move-source', 'books', '9780000000000'),
        )
      ).exists(),
      true,
    );
  });
});

test('blocking denies even Public friend-view shelf and book reads', async () => {
  await seedSharedLibrary();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
      {
        blockerId: ownerId,
        blockedId: otherUserId,
        pairId: friendPair(ownerId, otherUserId),
        blockedDisplayName: 'Bailey Reader',
        blockedPhotoUrl: null,
        createdAt: Timestamp.now(),
      },
    );
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertFails(getDoc(doc(ownerDb, 'shelves', 'public-shelf')));
  await assertFails(
    getDocs(collection(ownerDb, 'shelves', 'public-shelf', 'books')),
  );
});

test('copying creates only an own Want-to-read not-owned entry', async () => {
  await seedSharedLibrary();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, 'my-destination');
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      'my-destination',
      'copied-no-isbn',
      validBook('my-destination', {
        title: 'Copied title',
        titleNormalized: 'copied title',
        isOwned: false,
        readingStatus: 'wantToRead',
      }),
    ),
  );
  const copied = await getDoc(
    doc(ownerDb, 'shelves', 'my-destination', 'books', 'copied-no-isbn'),
  );
  assert.equal(copied.data().ownerId, ownerId);
  assert.equal(copied.data().isOwned, false);
  assert.equal(copied.data().readingStatus, 'wantToRead');
});

test('owner can create and query a valid shelf', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(
    setDoc(doc(ownerDb, 'shelves', 'valid-shelf'), validShelf()),
  );

  const result = await assertSucceeds(
    getDocs(
      query(collection(ownerDb, 'shelves'), where('ownerId', '==', ownerId)),
    ),
  );
  assert.equal(result.size, 1);
});

test('owner can query all owned shelf books by collection group', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'shelves', 'owned-library'), {
      ...validShelf(),
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    await setDoc(doc(db, 'shelves', 'owned-library', 'books', 'owned-book'), {
      ...validBook('owned-library'),
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });

  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const result = await assertSucceeds(
    getDocs(
      query(
        collectionGroup(ownerDb, 'books'),
        where('ownerId', '==', ownerId),
      ),
    ),
  );
  assert.equal(result.size, 1);

  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await assertFails(
    getDocs(
      query(
        collectionGroup(otherDb, 'books'),
        where('ownerId', '==', ownerId),
      ),
    ),
  );

  const unauthenticatedDb = environment.unauthenticatedContext().firestore();
  await assertFails(
    getDocs(
      query(
        collectionGroup(unauthenticatedDb, 'books'),
        where('ownerId', '==', ownerId),
      ),
    ),
  );
});

test('older clients may still create shelves without bookCount', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const legacyCompatible = validShelf();
  delete legacyCompatible.bookCount;
  await assertSucceeds(
    setDoc(doc(ownerDb, 'shelves', 'legacy-compatible'), legacyCompatible),
  );
});

test('unauthenticated and cross-user shelf reads are denied', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'shelves', 'owner-shelf'), {
      ...validShelf(),
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  });

  const unauthenticatedDb = environment.unauthenticatedContext().firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await assertFails(getDoc(doc(unauthenticatedDb, 'shelves', 'owner-shelf')));
  await assertFails(getDoc(doc(otherDb, 'shelves', 'owner-shelf')));
});

test('owner spoofing and cross-user writes are denied', async () => {
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await assertFails(
    setDoc(doc(otherDb, 'shelves', 'spoofed-shelf'), validShelf()),
  );
});

test('invalid visibility and extra fields are denied', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertFails(
    setDoc(
      doc(ownerDb, 'shelves', 'invalid-visibility'),
      validShelf({ visibility: 'everyone' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'shelves', 'extra-field'),
      validShelf({ ownerUsername: 'spoofable' }),
    ),
  );
});

test('blank and oversized names are denied', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertFails(
    setDoc(doc(ownerDb, 'shelves', 'blank-name'), validShelf({ name: '   ' })),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'shelves', 'long-name'),
      validShelf({ name: 'a'.repeat(61) }),
    ),
  );
});

test('optional shelf descriptions are length-limited', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'shelves', 'described-shelf'),
      validShelf({ description: 'Books for quiet weekends.' }),
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'shelves', 'legacy-descriptionless-shelf'),
      validShelf(),
    ),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'shelves', 'long-description'),
      validShelf({ description: 'a'.repeat(501) }),
    ),
  );
});

test('private shelves cannot enable automatic Circle activity', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertFails(
    setDoc(
      doc(ownerDb, 'shelves', 'invalid-private'),
      validShelf({ visibility: 'private', autoShareActivity: true }),
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'shelves', 'valid-private'),
      validShelf({ visibility: 'private', autoShareActivity: false }),
    ),
  );
});

test('owner atomically creates an ISBN book, index, and count', async () => {
  const isbn = '9780306406157';
  const shelfId = 'isbn-shelf';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, shelfId);

  await assertSucceeds(
    addBookBatch(
      ownerDb,
      shelfId,
      isbn,
      validBook(shelfId, { isbn }),
      validIsbnIndex(shelfId, isbn),
    ),
  );

  const shelfResult = await getDoc(doc(ownerDb, 'shelves', shelfId));
  assert.equal(shelfResult.data().bookCount, 1);
  await assertSucceeds(
    getDoc(doc(ownerDb, 'users', ownerId, 'libraryBookIsbns', isbn)),
  );
});

test('same canonical ISBN cannot be added to a second shelf', async () => {
  const isbn = '9780306406157';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, 'first-shelf');
  await createShelf(ownerDb, 'second-shelf', { name: 'Reading now' });
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      'first-shelf',
      isbn,
      validBook('first-shelf', { isbn }),
      validIsbnIndex('first-shelf', isbn),
    ),
  );

  await assertFails(
    addBookBatch(
      ownerDb,
      'second-shelf',
      isbn,
      validBook('second-shelf', { isbn }),
      validIsbnIndex('second-shelf', isbn, { shelfName: 'Reading now' }),
    ),
  );
  const existing = await getDoc(
    doc(ownerDb, 'users', ownerId, 'libraryBookIsbns', isbn),
  );
  assert.equal(existing.data().shelfId, 'first-shelf');
});

test('same-title books without ISBN can be separate copies', async () => {
  const shelfId = 'copy-shelf';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, shelfId);
  await assertSucceeds(
    addBookBatch(ownerDb, shelfId, 'copy-one', validBook(shelfId)),
  );

  await assertSucceeds(
    addBookBatch(
      ownerDb,
      shelfId,
      'copy-two',
      validBook(shelfId, { author: 'Another Author' }),
    ),
  );

  const result = await getDocs(collection(ownerDb, 'shelves', shelfId, 'books'));
  assert.equal(result.size, 2);
});

test('book writes reject invalid status, ISBN shape, and missing atomic index', async () => {
  const shelfId = 'validation-shelf';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, shelfId);

  await assertFails(
    addBookBatch(
      ownerDb,
      shelfId,
      'bad-status',
      validBook(shelfId, { readingStatus: 'NEW' }),
    ),
  );
  await assertFails(
    addBookBatch(
      ownerDb,
      shelfId,
      '0306406152',
      validBook(shelfId, { isbn: '0306406152' }),
    ),
  );
  await assertFails(
    addBookBatch(
      ownerDb,
      shelfId,
      '9780306406157',
      validBook(shelfId, { isbn: '9780306406157' }),
    ),
  );
});

test('book data and ISBN index remain account isolated', async () => {
  const isbn = '9780306406157';
  const shelfId = 'private-book-shelf';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await createShelf(ownerDb, shelfId);
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      shelfId,
      isbn,
      validBook(shelfId, { isbn }),
      validIsbnIndex(shelfId, isbn),
    ),
  );

  await assertFails(getDoc(doc(otherDb, 'shelves', shelfId, 'books', isbn)));
  await assertFails(
    getDoc(doc(otherDb, 'users', ownerId, 'libraryBookIsbns', isbn)),
  );
  await assertFails(
    updateDoc(doc(otherDb, 'shelves', shelfId), {
      bookCount: 2,
      updatedAt: serverTimestamp(),
    }),
  );
});

test('owner reads one selected book and independently updates status and ownership', async () => {
  const isbn = '9780306406157';
  const shelfId = 'editable-book-shelf';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const secondOwnerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, shelfId);
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      shelfId,
      isbn,
      validBook(shelfId, {
        isbn,
        title: 'Stored identity',
        titleNormalized: 'stored identity',
        author: 'Stored Author',
        coverUrl: 'https://covers.openlibrary.org/b/id/123-M.jpg',
      }),
      validIsbnIndex(shelfId, isbn, { title: 'Stored identity' }),
    ),
  );

  const bookRef = doc(ownerDb, 'shelves', shelfId, 'books', isbn);
  const initial = await assertSucceeds(getDoc(bookRef));
  assert.equal(initial.id, isbn);
  await assertSucceeds(
    runTransaction(ownerDb, async (transaction) => {
      await transaction.get(bookRef);
      transaction.update(bookRef, {
        readingStatus: 'finished',
        lastActivityId: 'finished-activity',
        updatedAt: serverTimestamp(),
      });
      transaction.set(doc(bookRef, 'activities', 'finished-activity'), {
        authorId: ownerId,
        shelfId,
        bookId: isbn,
        type: 'finished',
        batchId: null,
        audience: 'friends',
        activityGeneration: initial.data().activityGeneration,
        createdAt: serverTimestamp(),
      });
    }),
  );
  await assertSucceeds(
    updateDoc(
      doc(secondOwnerDb, 'shelves', shelfId, 'books', isbn),
      { isOwned: false, updatedAt: serverTimestamp() },
    ),
  );

  const updated = await getDoc(bookRef);
  assert.equal(updated.data().readingStatus, 'finished');
  assert.equal(updated.data().isOwned, false);
  assert.equal(updated.data().ownerId, ownerId);
  assert.equal(updated.data().shelfId, shelfId);
  assert.equal(updated.data().title, 'Stored identity');
  assert.equal(updated.data().author, 'Stored Author');
  assert.equal(updated.data().isbn, isbn);
  assert.equal(updated.data().coverUrl, 'https://covers.openlibrary.org/b/id/123-M.jpg');
  assert.equal(
    updated.data().createdAt.toMillis(),
    initial.data().createdAt.toMillis(),
  );
  assert.equal(
    (await getDoc(doc(ownerDb, 'shelves', shelfId))).data().bookCount,
    1,
  );
  assert.deepEqual(
    (await getDoc(doc(ownerDb, 'users', ownerId, 'libraryBookIsbns', isbn))).data(),
    {
      ownerId,
      shelfId,
      bookId: isbn,
      title: 'Stored identity',
      shelfName: 'Want to read',
      createdAt: initial.data().createdAt,
    },
  );
});

test('owner atomically moves one exact ISBN book and preserves its data', async () => {
  const seeded = await seedSingleBookMoveLibrary();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const sourceBookRef = doc(
    ownerDb,
    'shelves',
    seeded.sourceShelfId,
    'books',
    seeded.bookId,
  );
  const before = (await getDoc(sourceBookRef)).data();

  await assertSucceeds(moveSingleBook(ownerDb, seeded));

  assert.equal((await getDoc(sourceBookRef)).exists(), false);
  const destinationBook = await getDoc(doc(
    ownerDb,
    'shelves',
    seeded.destinationShelfId,
    'books',
    seeded.bookId,
  ));
  assert.deepEqual(destinationBook.data(), {
    ...before,
    shelfId: seeded.destinationShelfId,
    activityGeneration:
      `${seeded.sourceShelfId}-${seeded.bookId}-generation`,
  });
  assert.equal(
    (await getDoc(doc(ownerDb, 'shelves', seeded.sourceShelfId))).data()
      .bookCount,
    1,
  );
  const destinationShelf = await getDoc(
    doc(ownerDb, 'shelves', seeded.destinationShelfId),
  );
  assert.equal(destinationShelf.data().bookCount, 4);
  assert.equal(destinationShelf.data().visibility, 'public');
  assert.equal(destinationShelf.data().autoShareActivity, true);
  const index = await getDoc(
    doc(ownerDb, 'users', ownerId, 'libraryBookIsbns', seeded.isbn),
  );
  assert.equal(index.data().shelfId, seeded.destinationShelfId);
  assert.equal(index.data().shelfName, 'Destination shelf');
  const moveId = `${seeded.sourceShelfId}-${seeded.bookId}`;
  const moveRef = doc(
    ownerDb,
    'users',
    ownerId,
    'bookMoves',
    moveId,
  );
  assert.equal((await getDoc(moveRef)).data().sourceShelfId, seeded.sourceShelfId);
  await assertFails(getDoc(doc(
    otherDb,
    'users',
    ownerId,
    'bookMoves',
    moveId,
  )));
  await assert.rejects(moveSingleBook(ownerDb, seeded));
  assert.equal(destinationShelf.data().bookCount, 4);
});

test('owner atomically moves a no-ISBN entry without changing its ID', async () => {
  const seeded = await seedSingleBookMoveLibrary({
    prefix: 'manual-single',
    bookId: 'manual-entry-id',
    isbn: null,
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(moveSingleBook(ownerDb, seeded));
  const moved = await getDoc(doc(
    ownerDb,
    'shelves',
    seeded.destinationShelfId,
    'books',
    'manual-entry-id',
  ));
  assert.equal(moved.id, 'manual-entry-id');
  assert.equal(moved.data().isbn, null);
  assert.equal(moved.data().shelfId, seeded.destinationShelfId);
});

test('single-book move rejects partial, forged, locked, duplicate, and cross-user writes', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const cases = [
    { prefix: 'retained', options: { deleteSource: false } },
    {
      prefix: 'forged',
      options: { destinationBookOverrides: { readingStatus: 'reading' } },
    },
    {
      prefix: 'retained-generation',
      options: {
        destinationBookOverrides: {
          activityGeneration: 'initial-generation',
        },
      },
    },
    {
      prefix: 'visibility',
      options: { destinationShelfOverrides: { visibility: 'private' } },
    },
    {
      prefix: 'index',
      options: { indexOverrides: { shelfName: 'Wrong destination' } },
    },
  ];
  for (const entry of cases) {
    const seeded = await seedSingleBookMoveLibrary({ prefix: entry.prefix });
    await assertFails(moveSingleBook(ownerDb, seeded, entry.options));
    assert.equal((await getDoc(doc(
      ownerDb,
      'shelves',
      seeded.sourceShelfId,
      'books',
      seeded.bookId,
    ))).exists(), true);
    assert.equal((await getDoc(doc(
      ownerDb,
      'shelves',
      seeded.destinationShelfId,
      'books',
      seeded.bookId,
    ))).exists(), false);
  }

  const locked = await seedSingleBookMoveLibrary({
    prefix: 'locked-single',
    destinationLocked: true,
  });
  await assertFails(moveSingleBook(ownerDb, locked));

  const duplicate = await seedSingleBookMoveLibrary({
    prefix: 'duplicate-single',
    destinationHasBook: true,
  });
  await assert.rejects(moveSingleBook(ownerDb, duplicate));

  const crossUser = await seedSingleBookMoveLibrary({ prefix: 'cross-single' });
  await assertFails(moveSingleBook(otherDb, crossUser));
});

test('owner atomically removes one ISBN entry and can add that ISBN again', async () => {
  const seeded = await seedSingleBookRemovalLibrary();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const shelfRef = doc(ownerDb, 'shelves', seeded.shelfId);
  const bookRef = doc(shelfRef, 'books', seeded.bookId);
  const otherBookRef = doc(shelfRef, 'books', 'other-entry');
  const indexRef = doc(
    ownerDb,
    'users',
    ownerId,
    'libraryBookIsbns',
    seeded.isbn,
  );
  const shelfBefore = (await getDoc(shelfRef)).data();

  await assertSucceeds(removeSingleBook(ownerDb, seeded));

  assert.equal((await getDoc(bookRef)).exists(), false);
  assert.equal((await getDoc(indexRef)).exists(), false);
  assert.equal((await getDoc(otherBookRef)).exists(), true);
  const shelfAfter = (await getDoc(shelfRef)).data();
  assert.equal(shelfAfter.bookCount, 1);
  assert.equal(shelfAfter.name, shelfBefore.name);
  assert.equal(shelfAfter.visibility, shelfBefore.visibility);
  assert.equal(shelfAfter.autoShareActivity, shelfBefore.autoShareActivity);
  assert.equal(shelfAfter.createdAt.toMillis(), shelfBefore.createdAt.toMillis());
  const removalId = `${seeded.shelfId}-${seeded.bookId}-removal`;
  const removalRef = doc(ownerDb, 'users', ownerId, 'bookRemovals', removalId);
  const removal = (await getDoc(removalRef)).data();
  assert.equal(removal.sourceBookCreatedAt.toMillis(), 3200);
  assert.equal(removal.sourceCountBefore, 2);
  await assertFails(getDoc(doc(
    otherDb,
    'users',
    ownerId,
    'bookRemovals',
    removalId,
  )));
  await assert.rejects(removeSingleBook(ownerDb, seeded, {
    removalId: `${removalId}-retry`,
  }));
  assert.equal((await getDoc(shelfRef)).data().bookCount, 1);

  await assertSucceeds(
    addBookBatch(
      ownerDb,
      seeded.shelfId,
      seeded.bookId,
      validBook(seeded.shelfId, {
        title: 'Re-added edition',
        titleNormalized: 're-added edition',
        isbn: seeded.isbn,
      }),
      validIsbnIndex(seeded.shelfId, seeded.isbn, {
        title: 'Re-added edition',
        shelfName: 'Removal shelf',
      }),
    ),
  );
  assert.equal((await getDoc(bookRef)).exists(), true);
  assert.equal((await getDoc(indexRef)).exists(), true);
  assert.equal((await getDoc(shelfRef)).data().bookCount, 2);
});

test('owner removes only one no-ISBN generation by immutable entry ID', async () => {
  const seeded = await seedSingleBookRemovalLibrary({
    prefix: 'manual-remove',
    bookId: 'manual-entry-id',
    isbn: null,
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();

  await assertSucceeds(removeSingleBook(ownerDb, seeded));

  assert.equal((await getDoc(doc(
    ownerDb,
    'shelves',
    seeded.shelfId,
    'books',
    'manual-entry-id',
  ))).exists(), false);
  assert.equal((await getDoc(doc(
    ownerDb,
    'shelves',
    seeded.shelfId,
    'books',
    'other-entry',
  ))).exists(), true);
  assert.equal(
    (await getDoc(doc(ownerDb, 'shelves', seeded.shelfId))).data().bookCount,
    1,
  );
});

test('single-book removal rejects partial, stale, locked, corrupt, and cross-user writes', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const cases = [
    { prefix: 'remove-retained', options: { deleteBook: false } },
    { prefix: 'remove-index-retained', options: { deleteIndex: false } },
    {
      prefix: 'remove-visibility',
      options: { shelfOverrides: { visibility: 'private' } },
    },
    {
      prefix: 'remove-count',
      options: { shelfOverrides: { bookCount: 2 } },
    },
    {
      prefix: 'remove-generation',
      options: {
        proofOverrides: { sourceBookCreatedAt: Timestamp.fromMillis(1) },
      },
    },
  ];
  for (const entry of cases) {
    const seeded = await seedSingleBookRemovalLibrary({ prefix: entry.prefix });
    await assertFails(removeSingleBook(ownerDb, seeded, entry.options));
    assert.equal((await getDoc(doc(
      ownerDb,
      'shelves',
      seeded.shelfId,
      'books',
      seeded.bookId,
    ))).exists(), true);
    assert.equal(
      (await getDoc(doc(ownerDb, 'shelves', seeded.shelfId))).data().bookCount,
      2,
    );
  }

  const locked = await seedSingleBookRemovalLibrary({
    prefix: 'remove-locked',
    locked: true,
  });
  await assertFails(removeSingleBook(ownerDb, locked));

  const corrupt = await seedSingleBookRemovalLibrary({
    prefix: 'remove-corrupt-index',
    indexOverrides: { shelfId: 'wrong-shelf' },
  });
  await assertFails(removeSingleBook(ownerDb, corrupt));

  const crossUser = await seedSingleBookRemovalLibrary({
    prefix: 'remove-cross-user',
  });
  await assertFails(removeSingleBook(otherDb, crossUser));

  const stale = await seedSingleBookRemovalLibrary({ prefix: 'remove-stale' });
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const replacementCreatedAt = Timestamp.fromMillis(9999);
    const batch = writeBatch(db);
    batch.update(doc(db, 'shelves', stale.shelfId, 'books', stale.bookId), {
      createdAt: replacementCreatedAt,
    });
    batch.update(
      doc(db, 'users', ownerId, 'libraryBookIsbns', stale.isbn),
      { createdAt: replacementCreatedAt },
    );
    await batch.commit();
  });
  await assertFails(removeSingleBook(ownerDb, stale, {
    proofOverrides: { sourceBookCreatedAt: stale.sourceBookCreatedAt },
  }));
  assert.equal((await getDoc(doc(
    ownerDb,
    'shelves',
    stale.shelfId,
    'books',
    stale.bookId,
  ))).data().createdAt.toMillis(), 9999);

  const deleted = await seedSingleBookRemovalLibrary({
    prefix: 'remove-deleted',
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.delete(doc(db, 'shelves', deleted.shelfId, 'books', deleted.bookId));
    await batch.commit();
  });
  await assert.rejects(removeSingleBook(ownerDb, deleted));
});

test('book edits deny cross-user, forged identity, metadata, and invalid values', async () => {
  const shelfId = 'guarded-book-shelf';
  const bookId = 'guarded-book';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  await createShelf(ownerDb, shelfId);
  await assertSucceeds(
    addBookBatch(ownerDb, shelfId, bookId, validBook(shelfId)),
  );
  const ownerRef = doc(ownerDb, 'shelves', shelfId, 'books', bookId);
  const otherRef = doc(otherDb, 'shelves', shelfId, 'books', bookId);

  await assertFails(
    updateDoc(otherRef, { readingStatus: 'reading', updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(ownerRef, { ownerId: otherUserId, updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(ownerRef, { title: 'Forged title', updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(ownerRef, { readingStatus: 'READ', updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(ownerRef, { isOwned: 'yes', updatedAt: serverTimestamp() }),
  );
  await assertFails(updateDoc(ownerRef, { updatedAt: serverTimestamp() }));

  const unchanged = await getDoc(ownerRef);
  assert.equal(unchanged.data().readingStatus, 'wantToRead');
  assert.equal(unchanged.data().isOwned, true);
  assert.equal(unchanged.data().title, 'A valid book');
  assert.equal(unchanged.data().ownerId, ownerId);
});

test('locked, moved, and deleted source paths cannot edit or recreate a book', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const bookId = '9780000000000';
  await seedShelfMutationLibrary(1);
  await prepareShelfOperation(ownerDb);
  const sourceRef = doc(ownerDb, 'shelves', 'move-source', 'books', bookId);
  const destinationRef = doc(
    ownerDb,
    'shelves',
    'move-destination',
    'books',
    bookId,
  );

  await assertFails(
    updateDoc(sourceRef, {
      readingStatus: 'finished',
      updatedAt: serverTimestamp(),
    }),
  );
  await moveBookChunk(ownerDb, bookId);
  await assertFails(
    setDoc(sourceRef, {
      ...validBook('move-source', { isbn: bookId }),
    }),
  );
  await assertFails(
    updateDoc(destinationRef, {
      isOwned: false,
      updatedAt: serverTimestamp(),
    }),
  );
  await finishShelfOperation(ownerDb);
  await assertFails(
    setDoc(sourceRef, {
      ...validBook('move-source', { isbn: bookId }),
    }),
  );
  await assertSucceeds(
    updateDoc(destinationRef, {
      isOwned: true,
      updatedAt: serverTimestamp(),
    }),
  );
  assert.equal((await getDoc(destinationRef)).data().isOwned, true);
});

test('book cover allows scoped catalog HTTPS URLs', async () => {
  const shelfId = 'cover-shelf';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, shelfId);
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      shelfId,
      'cover-book',
      validBook(shelfId, {
        coverUrl: 'https://covers.openlibrary.org/b/id/123-M.jpg',
      }),
    ),
  );
  const googleShelfId = 'google-cover-shelf';
  await createShelf(ownerDb, googleShelfId);
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      googleShelfId,
      'google-cover-book',
      validBook(googleShelfId, {
        coverUrl:
          'https://books.google.com/books/content?id=right&printsec=frontcover',
      }),
    ),
  );
});

test('book cover rejects arbitrary remote URLs', async () => {
  const shelfId = 'bad-cover-shelf';
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, shelfId);
  await assertFails(
    addBookBatch(
      ownerDb,
      shelfId,
      'bad-cover-book',
      validBook(shelfId, {
        coverUrl: 'https://example.com/untrusted.jpg',
      }),
    ),
  );
});

async function seedFriendship(firstId = ownerId, secondId = otherUserId) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'friendships', friendPair(firstId, secondId)),
      {
        pairId: friendPair(firstId, secondId),
        memberIds: [firstId, secondId],
        createdAt: Timestamp.now(),
      },
    );
  });
}

async function addActivityBook(
  db,
  shelfId,
  bookId,
  { batchId = null, bookOverrides = {}, activityOverrides = {} } = {},
) {
  const activityId = `${bookId}-activity`;
  return runTransaction(db, async (transaction) => {
    const shelfRef = doc(db, 'shelves', shelfId);
    const shelf = await transaction.get(shelfRef);
    transaction.set(doc(db, 'shelves', shelfId, 'books', bookId), {
      ...validBook(shelfId),
      ...bookOverrides,
      lastActivityId: activityId,
    });
    transaction.set(
      doc(db, 'shelves', shelfId, 'books', bookId, 'activities', activityId),
      {
        authorId: ownerId,
        shelfId,
        bookId,
        type: 'added',
        batchId,
        audience: 'friends',
        activityGeneration:
          bookOverrides.activityGeneration ?? 'initial-generation',
        createdAt: serverTimestamp(),
        ...activityOverrides,
      },
    );
    transaction.update(shelfRef, {
      bookCount: (shelf.data().bookCount ?? 0) + 1,
      updatedAt: serverTimestamp(),
    });
  });
}

async function publishStatusActivity(
  db,
  shelfId,
  bookId,
  readingStatus,
  activityId,
) {
  return runTransaction(db, async (transaction) => {
    const bookRef = doc(db, 'shelves', shelfId, 'books', bookId);
    const book = await transaction.get(bookRef);
    const activityGeneration =
      book.data().activityGeneration ?? `${activityId}-generation`;
    transaction.update(bookRef, {
      readingStatus,
      lastActivityId: activityId,
      activityGeneration,
      updatedAt: serverTimestamp(),
    });
    transaction.set(doc(bookRef, 'activities', activityId), {
      authorId: ownerId,
      shelfId,
      bookId,
      type: readingStatus === 'reading' ? 'started' : 'finished',
      batchId: null,
      audience: 'friends',
      activityGeneration,
      createdAt: serverTimestamp(),
    });
  });
}

function activityQuery(
  db,
  shelfId,
  bookId,
  activityGeneration,
  includeAdded = true,
) {
  return query(
    collection(db, 'shelves', shelfId, 'books', bookId, 'activities'),
    where('activityGeneration', '==', activityGeneration),
    where(
      'type',
      'in',
      includeAdded
        ? ['added', 'started', 'finished']
        : ['started', 'finished'],
    ),
    orderBy('createdAt', 'desc'),
  );
}

test('activity engagement permits friends and revokes stale or private activity access', async () => {
  await seedFriendship();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();
  await createShelf(ownerDb, 'engagement-shelf', { visibility: 'friends' });
  await addActivityBook(ownerDb, 'engagement-shelf', 'engagement-book');
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'readerProfiles', otherUserId), {
      ownerId: otherUserId, displayName: 'Friend', photoUrl: null,
    });
  });
  const path = ['shelves', 'engagement-shelf', 'books', 'engagement-book', 'activities', 'engagement-book-activity'];
  const like = doc(friendDb, ...path, 'likes', otherUserId);
  const comment = doc(friendDb, ...path, 'comments', 'comment-1');
  await assertSucceeds(setDoc(like, { userId: otherUserId, createdAt: serverTimestamp() }));
  await assertSucceeds(setDoc(comment, {
    authorId: otherUserId, authorDisplayName: 'Friend', authorPhotoUrl: null,
    text: 'Great book!\nWhat did you think?', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(comment));
  await assertFails(getDoc(doc(strangerDb, ...path, 'comments', 'comment-1')));
  await assertFails(setDoc(doc(friendDb, ...path, 'likes', ownerId), { userId: ownerId, createdAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(comment, { text: 'Edited comment', updatedAt: serverTimestamp() }));
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'shelves', 'engagement-shelf'), { visibility: 'private' });
  });
  await assertFails(getDoc(comment));
  await assertFails(updateDoc(comment, { text: 'No access', updatedAt: serverTimestamp() }));
  await assertSucceeds(deleteDoc(like));
  await environment.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'shelves', 'engagement-shelf'), { visibility: 'friends' });
    await updateDoc(doc(context.firestore(), 'shelves', 'engagement-shelf', 'books', 'engagement-book'), { activityGeneration: 'new-generation' });
  });
  await assertFails(getDoc(comment));
});

test('Circle publishes owned additions atomically and remains friends-only', async () => {
  await seedFriendship();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();

  await createShelf(ownerDb, 'circle-public', { visibility: 'public' });
  await assertSucceeds(
    addActivityBook(ownerDb, 'circle-public', 'circle-book', {
      batchId: 'scan-session-1',
    }),
  );

  const activityPath = [
    'shelves',
    'circle-public',
    'books',
    'circle-book',
    'activities',
    'circle-book-activity',
  ];
  await assertSucceeds(getDoc(doc(friendDb, ...activityPath)));
  const feed = await assertSucceeds(
    getDocs(
      query(
        collection(
          friendDb,
          'shelves',
          'circle-public',
          'books',
          'circle-book',
          'activities',
        ),
        where('activityGeneration', '==', 'initial-generation'),
        where('type', 'in', ['added', 'started', 'finished']),
        orderBy('createdAt', 'desc'),
      ),
    ),
  );
  assert.equal(feed.size, 1);
  assert.equal(feed.docs[0].data().batchId, 'scan-session-1');
  await assertFails(getDoc(doc(strangerDb, ...activityPath)));
});

test('Circle publishes non-owned status changes but never an added event', async () => {
  await seedFriendship();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const shelfId = 'circle-non-owned';
  const bookId = 'saved-book';
  const generation = 'saved-generation';
  await createShelf(ownerDb, shelfId);
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      shelfId,
      bookId,
      validBook(shelfId, {
        isOwned: false,
        activityGeneration: generation,
      }),
    ),
  );

  let feed = await assertSucceeds(
    getDocs(activityQuery(friendDb, shelfId, bookId, generation, false)),
  );
  assert.equal(feed.size, 0);

  await assertSucceeds(
    publishStatusActivity(
      ownerDb,
      shelfId,
      bookId,
      'reading',
      'saved-started',
    ),
  );
  await assertSucceeds(
    publishStatusActivity(
      ownerDb,
      shelfId,
      bookId,
      'finished',
      'saved-finished',
    ),
  );
  feed = await assertSucceeds(
    getDocs(activityQuery(friendDb, shelfId, bookId, generation, false)),
  );
  assert.deepEqual(
    feed.docs.map((snapshot) => snapshot.data().type).sort(),
    ['finished', 'started'],
  );

  const bookRef = doc(ownerDb, 'shelves', shelfId, 'books', bookId);
  await assertSucceeds(
    updateDoc(bookRef, { isOwned: true, updatedAt: serverTimestamp() }),
  );
  await assertSucceeds(
    updateDoc(bookRef, { isOwned: false, updatedAt: serverTimestamp() }),
  );
  feed = await assertSucceeds(
    getDocs(activityQuery(friendDb, shelfId, bookId, generation, false)),
  );
  assert.equal(feed.size, 2);
});

test('Circle never resurrects activity after remove and re-add', async () => {
  await seedFriendship();
  const seeded = await seedSingleBookRemovalLibrary({
    prefix: 'circle-readd',
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const oldActivityId = 'old-finished';
  const oldActivityPath = [
    'shelves',
    seeded.shelfId,
    'books',
    seeded.bookId,
    'activities',
    oldActivityId,
  ];
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), ...oldActivityPath), {
      authorId: ownerId,
      shelfId: seeded.shelfId,
      bookId: seeded.bookId,
      type: 'finished',
      batchId: null,
      audience: 'friends',
      activityGeneration: 'initial-generation',
      createdAt: Timestamp.now(),
    });
  });
  await assertSucceeds(getDoc(doc(friendDb, ...oldActivityPath)));

  await assertSucceeds(removeSingleBook(ownerDb, seeded));
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      seeded.shelfId,
      seeded.bookId,
      validBook(seeded.shelfId, {
        isbn: seeded.isbn,
        activityGeneration: 'readded-generation',
      }),
      validIsbnIndex(seeded.shelfId, seeded.isbn, {
        shelfName: 'Removal shelf',
      }),
    ),
  );

  await assertFails(getDoc(doc(friendDb, ...oldActivityPath)));
  const feed = await assertSucceeds(
    getDocs(
      activityQuery(
        friendDb,
        seeded.shelfId,
        seeded.bookId,
        'readded-generation',
      ),
    ),
  );
  assert.equal(feed.size, 1);
  assert.equal(feed.docs[0].data().type, 'added');
});

test('Circle never resurrects activity after moving away and back', async () => {
  await seedFriendship();
  const seeded = await seedSingleBookMoveLibrary({ prefix: 'circle-return' });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const oldActivityId = 'before-moves';
  const oldActivityPath = [
    'shelves',
    seeded.sourceShelfId,
    'books',
    seeded.bookId,
    'activities',
    oldActivityId,
  ];
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), ...oldActivityPath), {
      authorId: ownerId,
      shelfId: seeded.sourceShelfId,
      bookId: seeded.bookId,
      type: 'finished',
      batchId: null,
      audience: 'friends',
      activityGeneration: 'initial-generation',
      createdAt: Timestamp.now(),
    });
  });
  await assertSucceeds(getDoc(doc(friendDb, ...oldActivityPath)));

  await assertSucceeds(moveSingleBook(ownerDb, seeded));
  const returnMove = {
    sourceShelfId: seeded.destinationShelfId,
    destinationShelfId: seeded.sourceShelfId,
    bookId: seeded.bookId,
    isbn: seeded.isbn,
  };
  await assertSucceeds(moveSingleBook(ownerDb, returnMove));
  await assertFails(getDoc(doc(friendDb, ...oldActivityPath)));

  const returnedBook = await getDoc(doc(
    ownerDb,
    'shelves',
    seeded.sourceShelfId,
    'books',
    seeded.bookId,
  ));
  const returnedGeneration = returnedBook.data().activityGeneration;
  assert.notEqual(returnedGeneration, 'initial-generation');
  await assertSucceeds(
    publishStatusActivity(
      ownerDb,
      seeded.sourceShelfId,
      seeded.bookId,
      'reading',
      'after-return',
    ),
  );
  const feed = await assertSucceeds(
    getDocs(
      activityQuery(
        friendDb,
        seeded.sourceShelfId,
        seeded.bookId,
        returnedGeneration,
        false,
      ),
    ),
  );
  assert.equal(feed.size, 1);
  assert.equal(feed.docs[0].id, 'after-return');
});

test('Circle denies suppressed, ineligible, and forged publication', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await createShelf(ownerDb, 'circle-shared');

  const suppressed = writeBatch(ownerDb);
  suppressed.set(
    doc(ownerDb, 'shelves', 'circle-shared', 'books', 'suppressed-book'),
    validBook('circle-shared'),
  );
  suppressed.update(doc(ownerDb, 'shelves', 'circle-shared'), {
    bookCount: 1,
    updatedAt: serverTimestamp(),
  });
  await assertFails(suppressed.commit());

  await createShelf(ownerDb, 'circle-private', {
    visibility: 'private',
    autoShareActivity: false,
  });
  await assertFails(
    addActivityBook(ownerDb, 'circle-private', 'private-book'),
  );
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      'circle-private',
      'private-book',
      validBook('circle-private'),
    ),
  );

  await createShelf(ownerDb, 'circle-no-auto', { autoShareActivity: false });
  await assertFails(
    addActivityBook(ownerDb, 'circle-no-auto', 'no-auto-book'),
  );
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      'circle-no-auto',
      'no-auto-book',
      validBook('circle-no-auto'),
    ),
  );

  await createShelf(ownerDb, 'circle-saved');
  await assertFails(
    addActivityBook(ownerDb, 'circle-saved', 'saved-book', {
      bookOverrides: { isOwned: false },
    }),
  );
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      'circle-saved',
      'saved-book',
      validBook('circle-saved', { isOwned: false }),
    ),
  );

  await createShelf(ownerDb, 'circle-forged');
  await assertFails(
    addActivityBook(ownerDb, 'circle-forged', 'forged-book', {
      activityOverrides: { authorId: otherUserId },
    }),
  );
});

test('Circle status events are mandatory, idempotent, and revoke live', async () => {
  await seedFriendship();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  await createShelf(ownerDb, 'circle-status');
  await assertSucceeds(
    addActivityBook(ownerDb, 'circle-status', 'status-book'),
  );

  const bookRef = doc(
    ownerDb,
    'shelves',
    'circle-status',
    'books',
    'status-book',
  );
  const startedRef = doc(bookRef, 'activities', 'started-activity');
  await assertFails(
    updateDoc(bookRef, {
      readingStatus: 'reading',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    runTransaction(ownerDb, async (transaction) => {
      await transaction.get(bookRef);
      transaction.update(bookRef, {
        readingStatus: 'reading',
        lastActivityId: 'started-activity',
        updatedAt: serverTimestamp(),
      });
      transaction.set(startedRef, {
        authorId: ownerId,
        shelfId: 'circle-status',
        bookId: 'status-book',
        type: 'started',
        batchId: null,
        audience: 'friends',
        activityGeneration: 'initial-generation',
        createdAt: serverTimestamp(),
      });
    }),
  );
  await assertSucceeds(
    getDoc(
      doc(
        friendDb,
        'shelves',
        'circle-status',
        'books',
        'status-book',
        'activities',
        'started-activity',
      ),
    ),
  );

  await assertFails(
    setDoc(doc(bookRef, 'activities', 'duplicate-started'), {
      authorId: ownerId,
      shelfId: 'circle-status',
      bookId: 'status-book',
      type: 'started',
      batchId: null,
      audience: 'friends',
      activityGeneration: 'initial-generation',
      createdAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(bookRef, {
      readingStatus: 'wantToRead',
      updatedAt: serverTimestamp(),
    }),
  );

  await assertSucceeds(
    updateDoc(doc(ownerDb, 'shelves', 'circle-status'), {
      visibility: 'private',
      autoShareActivity: false,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    getDoc(
      doc(
        friendDb,
        'shelves',
        'circle-status',
        'books',
        'status-book',
        'activities',
        'started-activity',
      ),
    ),
  );

  await assertSucceeds(
    updateDoc(doc(ownerDb, 'shelves', 'circle-status'), {
      visibility: 'friends',
      autoShareActivity: true,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    getDoc(
      doc(
        friendDb,
        'shelves',
        'circle-status',
        'books',
        'status-book',
        'activities',
        'started-activity',
      ),
    ),
  );

  await assertSucceeds(
    deleteDoc(
      doc(friendDb, 'friendships', friendPair(ownerId, otherUserId)),
    ),
  );
});

function validCirclePost(authorId, overrides = {}) {
  return {
    authorId,
    text: 'A thoughtful Circle post.',
    attachedBookOwnerId: null,
    attachedShelfId: null,
    attachedBookId: null,
    attachedTitle: null,
    attachedAuthor: null,
    attachedCoverUrl: null,
    photoPath: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function validCircleDraft(postId, overrides = {}) {
  return {
    postId,
    text: 'Unpublished thought',
    attachedBookOwnerId: null,
    attachedShelfId: null,
    attachedBookId: null,
    attachedTitle: null,
    attachedAuthor: null,
    attachedCoverUrl: null,
    photoPath: null,
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

test('Circle text posts are author-owned and friends-only', async () => {
  await seedFriendship();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();
  const postRef = doc(ownerDb, 'circlePosts', 'post-one');

  await assertSucceeds(setDoc(postRef, validCirclePost(ownerId)));
  await assertSucceeds(getDoc(postRef));
  await assertSucceeds(getDoc(doc(friendDb, 'circlePosts', 'post-one')));
  await assertFails(getDoc(doc(strangerDb, 'circlePosts', 'post-one')));
  const feed = await assertSucceeds(
    getDocs(
      query(
        collection(friendDb, 'circlePosts'),
        where('authorId', '==', ownerId),
        orderBy('createdAt', 'desc'),
      ),
    ),
  );
  assert.equal(feed.size, 1);

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
      {
        blockerId: ownerId,
        blockedId: otherUserId,
        pairId: friendPair(ownerId, otherUserId),
        blockedDisplayName: 'Blocked reader',
        blockedPhotoUrl: null,
        createdAt: Timestamp.now(),
      },
    );
  });
  await assertFails(getDoc(doc(friendDb, 'circlePosts', 'post-one')));
  await environment.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
    );
  });
  await assertSucceeds(getDoc(doc(friendDb, 'circlePosts', 'post-one')));

  const before = (await getDoc(postRef)).data();
  await assertSucceeds(
    updateDoc(postRef, {
      text: 'Edited by the author.',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(friendDb, 'circlePosts', 'post-one'), {
      text: 'Forged edit.',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(postRef, {
      authorId: otherUserId,
      updatedAt: serverTimestamp(),
    }),
  );
  assert.equal(
    (await getDoc(postRef)).data().createdAt.toMillis(),
    before.createdAt.toMillis(),
  );
  await assertFails(deleteDoc(doc(friendDb, 'circlePosts', 'post-one')));

  await assertSucceeds(
    deleteDoc(doc(friendDb, 'friendships', friendPair(ownerId, otherUserId))),
  );
  await assertFails(getDoc(doc(friendDb, 'circlePosts', 'post-one')));
  await assertSucceeds(deleteDoc(postRef));
});

test('Circle post attachment must match one exact author library book', async () => {
  await seedFriendship();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const shelfId = 'post-attachment-shelf';
  const bookId = 'post-attachment-book';
  await createShelf(ownerDb, shelfId, {
    visibility: 'private',
    autoShareActivity: false,
  });
  await assertSucceeds(
    addBookBatch(
      ownerDb,
      shelfId,
      bookId,
      validBook(shelfId, {
        title: 'Attached title',
        author: 'Attached author',
        coverUrl: 'https://covers.openlibrary.org/b/id/123-M.jpg',
      }),
    ),
  );
  const attachment = {
    attachedBookOwnerId: ownerId,
    attachedShelfId: shelfId,
    attachedBookId: bookId,
    attachedTitle: 'Attached title',
    attachedAuthor: 'Attached author',
    attachedCoverUrl: 'https://covers.openlibrary.org/b/id/123-M.jpg',
  };
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'circlePosts', 'attached-post'),
      validCirclePost(ownerId, attachment),
    ),
  );
  await assertSucceeds(
    getDoc(doc(friendDb, 'circlePosts', 'attached-post')),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'circlePosts', 'forged-title'),
      validCirclePost(ownerId, {
        ...attachment,
        attachedTitle: 'Different title',
      }),
    ),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'circlePosts', 'forged-owner'),
      validCirclePost(ownerId, {
        ...attachment,
        attachedBookOwnerId: otherUserId,
      }),
    ),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'circlePosts', 'photo-field'),
      {
        ...validCirclePost(ownerId),
        photoUrl: 'https://example.com/not-yet.jpg',
      },
    ),
  );
});

test('Circle draft is durable, UID-scoped, and schema constrained', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const otherDb = environment.authenticatedContext(otherUserId).firestore();
  const draftRef = doc(ownerDb, 'users', ownerId, 'circleDrafts', 'newPost');
  const draft = validCircleDraft('durable-post-id');

  await assertSucceeds(setDoc(draftRef, draft));
  await assertSucceeds(getDoc(draftRef));
  await assertSucceeds(
    updateDoc(draftRef, {
      text: 'Still unpublished',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    getDoc(doc(otherDb, 'users', ownerId, 'circleDrafts', 'newPost')),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'users', ownerId, 'circleDrafts', 'anotherDraft'),
      draft,
    ),
  );
  await assertFails(
    setDoc(draftRef, { ...draft, unexpected: true }),
  );
  await assertFails(setDoc(draftRef, { ...draft, postId: '' }));
  await assertFails(
    updateDoc(draftRef, {
      postId: 'different-post-id',
      updatedAt: serverTimestamp(),
    }),
  );

  const postRef = doc(ownerDb, 'circlePosts', draft.postId);
  const publish = () =>
    runTransaction(ownerDb, async (transaction) => {
      const existing = await transaction.get(postRef);
      if (!existing.exists()) {
        transaction.set(postRef, validCirclePost(ownerId));
      }
      transaction.delete(draftRef);
    });
  await assertSucceeds(publish());
  assert.equal((await getDoc(postRef)).exists(), true);
  assert.equal((await getDoc(draftRef)).exists(), false);
  await assertSucceeds(publish());
  assert.equal((await getDoc(postRef)).exists(), true);
});

test('draft post IDs never grant reads to existing foreign posts', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();
  const missingPostRef = doc(ownerDb, 'circlePosts', 'missing-draft-post');
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'users', ownerId, 'circleDrafts', 'newPost'),
      validCircleDraft('missing-draft-post'),
    ),
  );
  const missingPost = await assertSucceeds(getDoc(missingPostRef));
  assert.equal(missingPost.exists(), false);

  const victimPostRef = doc(ownerDb, 'circlePosts', 'victim-post');
  await assertSucceeds(setDoc(victimPostRef, validCirclePost(ownerId)));
  await assertSucceeds(getDoc(victimPostRef));
  await assertSucceeds(
    setDoc(
      doc(strangerDb, 'users', thirdUserId, 'circleDrafts', 'newPost'),
      validCircleDraft('victim-post'),
    ),
  );
  await assertFails(getDoc(doc(strangerDb, 'circlePosts', 'victim-post')));
  await assertFails(
    getDocs(
      query(
        collection(strangerDb, 'circlePosts'),
        where('authorId', '==', ownerId),
        orderBy('createdAt', 'desc'),
      ),
    ),
  );

  await seedFriendship();
  await assertSucceeds(
    setDoc(
      doc(friendDb, 'users', otherUserId, 'circleDrafts', 'newPost'),
      validCircleDraft('victim-post'),
    ),
  );
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
      {
        blockerId: ownerId,
        blockedId: otherUserId,
        pairId: friendPair(ownerId, otherUserId),
        blockedDisplayName: 'Blocked reader',
        blockedPhotoUrl: null,
        createdAt: Timestamp.now(),
      },
    );
  });
  await assertFails(getDoc(doc(friendDb, 'circlePosts', 'victim-post')));
  await environment.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
    );
    await setDoc(
      doc(context.firestore(), 'blocks', otherUserId, 'blocked', ownerId),
      {
        blockerId: otherUserId,
        blockedId: ownerId,
        pairId: friendPair(ownerId, otherUserId),
        blockedDisplayName: 'Blocked reader',
        blockedPhotoUrl: null,
        createdAt: Timestamp.now(),
      },
    );
  });
  await assertFails(getDoc(doc(friendDb, 'circlePosts', 'victim-post')));
});

test('Circle posts publish and edit paragraphs but reject whitespace-only text', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const postRef = doc(ownerDb, 'circlePosts', 'paragraph-post');
  await assertSucceeds(setDoc(postRef, validCirclePost(ownerId, {
    text: 'First paragraph.\n\nSecond paragraph.',
  })));
  await assertSucceeds(updateDoc(postRef, {
    text: 'Edited first line.\r\nSecond line.', updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(postRef, {
    text: ' \n\r\t ', updatedAt: serverTimestamp(),
  }));
});

test('Circle posts accept exact private photo paths and require text or photo', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'circlePosts', 'photo-post'),
      validCirclePost(ownerId, {
        text: '',
        photoPath: `circlePosts/${ownerId}/photo-post/photo-1770000000000`,
      }),
    ),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'circlePosts', 'empty-post'),
      validCirclePost(ownerId, { text: '', photoPath: null }),
    ),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'circlePosts', 'forged-photo'),
      validCirclePost(ownerId, {
        text: '',
        photoPath: `circlePosts/${otherUserId}/forged-photo/photo-1`,
      }),
    ),
  );
});

test('Circle likes and comments honor access, identity, and moderation', async () => {
  await seedFriendship();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [userId, code, displayName] of [
      [ownerId, 'OWN333', 'Owner Reader'],
      [otherUserId, 'OTH333', 'Friend Reader'],
    ]) {
      await setDoc(doc(db, 'readerProfiles', userId), {
        ownerId: userId,
        displayName,
        photoUrl: null,
        inviteCode: code,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
    }
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();
  const postRef = doc(ownerDb, 'circlePosts', 'engaged-post');
  await assertSucceeds(setDoc(postRef, validCirclePost(ownerId)));

  const likeRef = doc(friendDb, 'circlePosts', 'engaged-post', 'likes', otherUserId);
  await assertSucceeds(
    setDoc(likeRef, { userId: otherUserId, createdAt: serverTimestamp() }),
  );
  await assertFails(
    setDoc(doc(friendDb, 'circlePosts', 'engaged-post', 'likes', ownerId), {
      userId: ownerId,
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(
    getDocs(collection(strangerDb, 'circlePosts', 'engaged-post', 'likes')),
  );

  const commentRef = doc(friendDb, 'circlePosts', 'engaged-post', 'comments', 'c1');
  await assertSucceeds(
    setDoc(commentRef, {
      authorId: otherUserId,
      authorDisplayName: 'Friend Reader',
      authorPhotoUrl: null,
      text: 'A real comment.',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(friendDb, 'circlePosts', 'engaged-post', 'comments', 'forged'), {
      authorId: otherUserId,
      authorDisplayName: 'Owner Reader',
      authorPhotoUrl: null,
      text: 'Forged identity.',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(commentRef, {
      text: 'Edited by its author.',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    deleteDoc(doc(ownerDb, 'circlePosts', 'engaged-post', 'comments', 'c1')),
  );
  await assertSucceeds(deleteDoc(doc(ownerDb, 'circlePosts', 'engaged-post', 'likes', otherUserId)));
});

const reviewBookCreatedAt = Timestamp.fromMillis(1770000000000);

function validReview(reviewAuthorId, shelfId, bookId, overrides = {}) {
  return {
    authorId: reviewAuthorId,
    shelfId,
    bookId,
    bookCreatedAt: reviewBookCreatedAt,
    title: 'Review source book',
    bookAuthor: 'Source Author',
    coverUrl: null,
    text: 'A specific review for this exact edition.',
    rating: 4,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

function validReviewDraft(reviewAuthorId, shelfId, bookId, overrides = {}) {
  return {
    reviewId: `${reviewAuthorId}--${bookId}`,
    shelfId,
    bookId,
    bookCreatedAt: reviewBookCreatedAt,
    title: 'Review source book',
    bookAuthor: 'Source Author',
    coverUrl: null,
    text: 'A specific review for this exact edition.',
    rating: 4,
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedReviewSource({
  shelfId = 'review-shelf',
  bookId = 'review-book',
  visibility = 'friends',
} = {}) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'shelves', shelfId), {
      ...validShelf({ visibility }),
      ownerId,
      createdAt: reviewBookCreatedAt,
      updatedAt: reviewBookCreatedAt,
    });
    await setDoc(doc(db, 'shelves', shelfId, 'books', bookId), {
      ...validBook(shelfId),
      ownerId,
      title: 'Review source book',
      titleNormalized: 'review source book',
      author: 'Source Author',
      createdAt: reviewBookCreatedAt,
      updatedAt: reviewBookCreatedAt,
    });
  });
}

test('reviews publish and edit paragraphs but reject whitespace-only text', async () => {
  await seedReviewSource();
  const db = environment.authenticatedContext(ownerId).firestore();
  const reviewId = `${ownerId}--review-book`;
  const draftRef = doc(db, 'users', ownerId, 'reviewDrafts', reviewId);
  const reviewRef = doc(db, 'circleReviews', reviewId);
  const text = 'A thoughtful book.\n\nHighly recommended.';
  await assertSucceeds(setDoc(draftRef, validReviewDraft(ownerId, 'review-shelf', 'review-book', { text })));
  await assertSucceeds(runTransaction(db, async (transaction) => {
    await transaction.get(draftRef);
    await transaction.get(reviewRef);
    transaction.set(reviewRef, validReview(ownerId, 'review-shelf', 'review-book', { text }));
    transaction.delete(draftRef);
  }));
  await assertSucceeds(updateDoc(reviewRef, { text: 'First paragraph.\r\nSecond paragraph.', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(reviewRef, { text: ' \n\t\r\n ', updatedAt: serverTimestamp() }));
});

test('reviews are exact-edition, author-owned, schema-constrained, and queryable by friends', async () => {
  await seedFriendship();
  await seedReviewSource();
  await seedReviewSource({ shelfId: 'other-edition-shelf', bookId: 'other-edition' });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();
  const reviewId = `${ownerId}--review-book`;
  const draftRef = doc(ownerDb, 'users', ownerId, 'reviewDrafts', reviewId);
  const reviewRef = doc(ownerDb, 'circleReviews', reviewId);

  await assertSucceeds(
    setDoc(draftRef, validReviewDraft(ownerId, 'review-shelf', 'review-book')),
  );
  await assertSucceeds(getDoc(draftRef));
  await assertFails(
    getDoc(doc(friendDb, 'users', ownerId, 'reviewDrafts', reviewId)),
  );
  await assertFails(
    getDocs(collection(ownerDb, 'users', ownerId, 'reviewDrafts')),
  );
  await assertFails(
    updateDoc(draftRef, { rating: 0, updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(draftRef, { rating: 6, updatedAt: serverTimestamp() }),
  );
  await assertFails(
    updateDoc(draftRef, { rating: 2.5, updatedAt: serverTimestamp() }),
  );
  await assertFails(
    setDoc(
      doc(ownerDb, 'users', ownerId, 'reviewDrafts', reviewId),
      validReviewDraft(ownerId, 'review-shelf', 'review-book', {
        title: 'Forged title',
      }),
    ),
  );

  await assertSucceeds(
    runTransaction(ownerDb, async (transaction) => {
      const draft = await transaction.get(draftRef);
      assert.equal(draft.exists(), true);
      const existing = await transaction.get(reviewRef);
      assert.equal(existing.exists(), false);
      transaction.set(
        reviewRef,
        validReview(ownerId, 'review-shelf', 'review-book'),
      );
      transaction.delete(draftRef);
    }),
  );
  assert.equal((await getDoc(draftRef)).exists(), false);
  await assertSucceeds(getDoc(reviewRef));
  await assertSucceeds(getDoc(doc(friendDb, 'circleReviews', reviewId)));
  await assertFails(getDoc(doc(strangerDb, 'circleReviews', reviewId)));
  await assertFails(
    getDocs(
      query(
        collection(friendDb, 'circleReviews'),
        where('authorId', '==', ownerId),
        orderBy('createdAt', 'desc'),
      ),
    ),
  );
  const ownFeed = await assertSucceeds(
    getDocs(
      query(
        collection(ownerDb, 'circleReviews'),
        where('authorId', '==', ownerId),
        orderBy('createdAt', 'desc'),
      ),
    ),
  );
  assert.equal(ownFeed.size, 1);
  await assertFails(
    updateDoc(doc(friendDb, 'circleReviews', reviewId), {
      text: 'Hijacked review',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(doc(friendDb, 'circleReviews', reviewId)));
  await assertSucceeds(
    updateDoc(reviewRef, {
      text: 'Edited without a rating.',
      rating: null,
      updatedAt: serverTimestamp(),
    }),
  );

  const otherEditionId = `${ownerId}--other-edition`;
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'circleReviews', otherEditionId),
      validReview(ownerId, 'other-edition-shelf', 'other-edition', {
        rating: 1,
      }),
    ),
  );
  assert.equal((await getDoc(reviewRef)).exists(), true);
  assert.equal(
    (await getDoc(doc(ownerDb, 'circleReviews', otherEditionId))).exists(),
    true,
  );
});

test('review likes and comments follow exact live review access', async () => {
  await seedFriendship();
  await seedReviewSource();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [userId, code, displayName] of [
      [ownerId, 'OWN444', 'Owner Reader'],
      [otherUserId, 'OTH444', 'Friend Reader'],
    ]) {
      await setDoc(doc(db, 'readerProfiles', userId), {
        ownerId: userId,
        displayName,
        photoUrl: null,
        inviteCode: code,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      });
    }
  });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const reviewId = `${ownerId}--review-book`;
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'circleReviews', reviewId),
      validReview(ownerId, 'review-shelf', 'review-book'),
    ),
  );
  await assertSucceeds(
    setDoc(doc(friendDb, 'circleReviews', reviewId, 'likes', otherUserId), {
      userId: otherUserId,
      createdAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    setDoc(doc(friendDb, 'circleReviews', reviewId, 'comments', 'review-c1'), {
      authorId: otherUserId,
      authorDisplayName: 'Friend Reader',
      authorPhotoUrl: null,
      text: 'This review changed my mind.',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(ownerDb, 'shelves', 'review-shelf'), {
      visibility: 'private',
      autoShareActivity: false,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    getDocs(collection(friendDb, 'circleReviews', reviewId, 'likes')),
  );
  await assertFails(
    getDocs(collection(friendDb, 'circleReviews', reviewId, 'comments')),
  );
});

test('review visibility follows live shelf privacy and either block direction', async () => {
  await seedFriendship();
  await seedReviewSource({ visibility: 'private' });
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const reviewId = `${ownerId}--review-book`;
  const reviewRef = doc(ownerDb, 'circleReviews', reviewId);
  await assertSucceeds(
    setDoc(reviewRef, validReview(ownerId, 'review-shelf', 'review-book')),
  );
  await assertFails(getDoc(doc(friendDb, 'circleReviews', reviewId)));

  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'shelves', 'review-shelf'), {
      visibility: 'friends',
    });
  });
  await assertSucceeds(getDoc(doc(friendDb, 'circleReviews', reviewId)));

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
      {
        blockerId: ownerId,
        blockedId: otherUserId,
        pairId: friendPair(ownerId, otherUserId),
        blockedDisplayName: 'Blocked reader',
        blockedPhotoUrl: null,
        createdAt: Timestamp.now(),
      },
    );
  });
  await assertFails(getDoc(doc(friendDb, 'circleReviews', reviewId)));
  await environment.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(
      doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId),
    );
    await setDoc(
      doc(context.firestore(), 'blocks', otherUserId, 'blocked', ownerId),
      {
        blockerId: otherUserId,
        blockedId: ownerId,
        pairId: friendPair(ownerId, otherUserId),
        blockedDisplayName: 'Blocked reader',
        blockedPhotoUrl: null,
        createdAt: Timestamp.now(),
      },
    );
  });
  await assertFails(getDoc(doc(friendDb, 'circleReviews', reviewId)));
  await assertSucceeds(getDoc(reviewRef));
});

test('missing review lookups do not fail the owner or accepted friend Circle feed', async () => {
  await seedFriendship();
  await seedReviewSource();
  const reviewId = `${ownerId}--review-book`;
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();
  assert.equal((await assertSucceeds(getDoc(doc(ownerDb, 'circleReviews', reviewId)))).exists(), false);
  assert.equal((await assertSucceeds(getDoc(doc(friendDb, 'circleReviews', reviewId)))).exists(), false);
  await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'circleReviews', reviewId)));
  for (const malformed of ['missing', `${ownerId}--`, `--review-book`, `${ownerId}--book--extra`]) {
    await assertFails(getDoc(doc(friendDb, 'circleReviews', malformed)));
  }
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId), { blockedId: otherUserId });
  });
  await assertFails(getDoc(doc(friendDb, 'circleReviews', reviewId)));
  await environment.withSecurityRulesDisabled(async context => {
    await deleteDoc(doc(context.firestore(), 'blocks', ownerId, 'blocked', otherUserId));
    await deleteDoc(doc(context.firestore(), 'activeAccounts', otherUserId));
  });
  await assertFails(getDoc(doc(friendDb, 'circleReviews', reviewId)));
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'activeAccounts', otherUserId), { active: true });
  });
  await assertFails(getDoc(doc(strangerDb, 'circleReviews', reviewId)));
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'circleReviews', reviewId), validReview(ownerId, 'review-shelf', 'review-book'));
    await updateDoc(doc(context.firestore(), 'shelves', 'review-shelf'), { visibility: 'private' });
  });
  await assertFails(getDoc(doc(friendDb, 'circleReviews', reviewId)));
  await assertSucceeds(getDoc(doc(ownerDb, 'circleReviews', reviewId)));
});

test('missing review listener is revoked when a private review appears', async () => {
  await seedFriendship();
  await seedReviewSource();
  const reviewId = `${ownerId}--review-book`;
  const friendDb = environment.authenticatedContext(otherUserId).firestore();
  let missingResolve;
  let deniedResolve;
  const missing = new Promise(resolve => { missingResolve = resolve; });
  const denied = new Promise(resolve => { deniedResolve = resolve; });
  const unsubscribe = onSnapshot(doc(friendDb, 'circleReviews', reviewId),
    snapshot => missingResolve(snapshot.exists()),
    error => deniedResolve(error.code));
  let timeout;
  const deadline = new Promise((resolve, reject) => {
    timeout = setTimeout(() => reject(new Error('Review listener did not transition')), 10000);
  });
  try {
    assert.equal(await Promise.race([missing, deadline]), false);
    await environment.withSecurityRulesDisabled(async context => {
      const batch = writeBatch(context.firestore());
      batch.update(doc(context.firestore(), 'shelves', 'review-shelf'), { visibility: 'private' });
      batch.set(doc(context.firestore(), 'circleReviews', reviewId), validReview(ownerId, 'review-shelf', 'review-book'));
      await batch.commit();
    });
    assert.equal(await Promise.race([denied, deadline]), 'permission-denied');
  } finally {
    clearTimeout(timeout);
    unsubscribe();
  }
});

test('review drafts only permit missing-review checks and never expand existing reads', async () => {
  await seedReviewSource();
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const strangerDb = environment.authenticatedContext(thirdUserId).firestore();
  const missingId = `${ownerId}--review-book`;
  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'users', ownerId, 'reviewDrafts', missingId),
      validReviewDraft(ownerId, 'review-shelf', 'review-book'),
    ),
  );
  const missing = await assertSucceeds(
    getDoc(doc(ownerDb, 'circleReviews', missingId)),
  );
  assert.equal(missing.exists(), false);

  await assertSucceeds(
    setDoc(
      doc(ownerDb, 'circleReviews', missingId),
      validReview(ownerId, 'review-shelf', 'review-book'),
    ),
  );
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users', thirdUserId, 'reviewDrafts', missingId),
      {
        ...validReviewDraft(ownerId, 'review-shelf', 'review-book'),
        reviewId: missingId,
      },
    );
  });
  await assertFails(getDoc(doc(strangerDb, 'circleReviews', missingId)));
  await assertFails(
    getDocs(
      query(
        collection(strangerDb, 'circleReviews'),
        where('authorId', '==', ownerId),
        orderBy('createdAt', 'desc'),
      ),
    ),
  );
});

test('exact reviews and drafts follow moves and are removed with their source entry', async () => {
  const ownerDb = environment.authenticatedContext(ownerId).firestore();
  const moved = await seedSingleBookMoveLibrary({ prefix: 'review-move' });
  const movedReviewId = `${ownerId}--${moved.bookId}`;
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'circleReviews', movedReviewId), {
      authorId: ownerId,
      shelfId: moved.sourceShelfId,
      bookId: moved.bookId,
      bookCreatedAt: Timestamp.fromMillis(1200),
      title: 'Exact movable book',
      bookAuthor: 'An Author',
      coverUrl: null,
      text: 'Move this exact review.',
      rating: 5,
      createdAt: Timestamp.fromMillis(1250),
      updatedAt: Timestamp.fromMillis(1250),
    });
    batch.set(
      doc(db, 'users', ownerId, 'reviewDrafts', movedReviewId),
      {
        reviewId: movedReviewId,
        shelfId: moved.sourceShelfId,
        bookId: moved.bookId,
        bookCreatedAt: Timestamp.fromMillis(1200),
        title: 'Exact movable book',
        bookAuthor: 'An Author',
        coverUrl: null,
        text: 'Move this exact draft.',
        rating: null,
        updatedAt: Timestamp.fromMillis(1250),
      },
    );
    await batch.commit();
  });

  await assertSucceeds(
    moveSingleBook(ownerDb, moved, { updateReview: true }),
  );
  assert.equal(
    (await getDoc(doc(ownerDb, 'circleReviews', movedReviewId))).data().shelfId,
    moved.destinationShelfId,
  );
  assert.equal(
    (
      await getDoc(
        doc(ownerDb, 'users', ownerId, 'reviewDrafts', movedReviewId),
      )
    ).data().shelfId,
    moved.destinationShelfId,
  );

  const removed = await seedSingleBookRemovalLibrary({
    prefix: 'review-remove',
    bookId: '9781111111111',
    isbn: '9781111111111',
  });
  const removedReviewId = `${ownerId}--${removed.bookId}`;
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'circleReviews', removedReviewId), {
      authorId: ownerId,
      shelfId: removed.shelfId,
      bookId: removed.bookId,
      bookCreatedAt: removed.sourceBookCreatedAt,
      title: 'Exact removable book',
      bookAuthor: 'An Author',
      coverUrl: null,
      text: 'Remove this exact review.',
      rating: 3,
      createdAt: Timestamp.fromMillis(3250),
      updatedAt: Timestamp.fromMillis(3250),
    });
    batch.set(
      doc(db, 'users', ownerId, 'reviewDrafts', removedReviewId),
      {
        reviewId: removedReviewId,
        shelfId: removed.shelfId,
        bookId: removed.bookId,
        bookCreatedAt: removed.sourceBookCreatedAt,
        title: 'Exact removable book',
        bookAuthor: 'An Author',
        coverUrl: null,
        text: 'Remove this exact draft.',
        rating: 3,
        updatedAt: Timestamp.fromMillis(3250),
      },
    );
    await batch.commit();
  });

  await assertSucceeds(
    removeSingleBook(ownerDb, removed, { deleteReview: true }),
  );
  assert.equal((await assertSucceeds(
    getDoc(doc(ownerDb, 'circleReviews', removedReviewId)),
  )).exists(), false);
  await environment.withSecurityRulesDisabled(async (context) => {
    assert.equal(
      (
        await getDoc(
          doc(context.firestore(), 'circleReviews', removedReviewId),
        )
      ).exists(),
      false,
    );
  });
  assert.equal(
    (
      await getDoc(
        doc(ownerDb, 'users', ownerId, 'reviewDrafts', removedReviewId),
      )
    ).exists(),
    false,
  );
});
