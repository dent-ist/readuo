'use strict';
const path = require('node:path');
const { Firestore } = require('@google-cloud/firestore');

async function main() {
  const cliLib = process.env.FIREBASE_CLI_LIB;
  if (!cliLib) throw Error('FIREBASE_CLI_LIB is required.');
  const auth = require(path.join(cliLib, 'auth.js'));
  const api = require(path.join(cliLib, 'api.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw Error('Firebase CLI sign-in is required.');
  const database = new Firestore({ projectId: 'readuo-b2f24', credentials: {
    type: 'authorized_user', client_id: api.clientId(), client_secret: api.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  } });
  const summary = { project: 'readuo-b2f24', mode: 'read-only', writes: 0, collections: {}, queryFailures: [], missingSharedBookReviews: 0, sharedBooksChecked: 0, activityQueriesChecked: 0 };
  const snapshots = {};
  for (const collection of ['readerProfiles', 'friendships', 'shelves', 'circlePosts', 'circleReviews']) {
    snapshots[collection] = await database.collection(collection).limit(500).get();
    summary.collections[collection] = { count: snapshots[collection].size, truncated: snapshots[collection].size === 500 };
  }
  for (const profile of snapshots.readerProfiles.docs) {
    for (const collection of ['circlePosts', 'circleReviews']) {
      try { await database.collection(collection).where('authorId', '==', profile.id).orderBy('createdAt', 'desc').limit(1).get(); }
      catch (error) { summary.queryFailures.push({ collection, code: error.code, message: error.message }); }
    }
  }
  for (const shelf of snapshots.shelves.docs) {
    const data = shelf.data();
    if (!['friends', 'public'].includes(data.visibility)) continue;
    const books = await shelf.ref.collection('books').limit(100).get();
    for (const book of books.docs) {
      const entry = book.data();
      summary.sharedBooksChecked++;
      const review = await database.doc(`circleReviews/${data.ownerId}--${book.id}`).get();
      if (!review.exists) summary.missingSharedBookReviews++;
      if (!entry.activityGeneration) continue;
      summary.activityQueriesChecked++;
      try {
        await book.ref.collection('activities').where('activityGeneration', '==', entry.activityGeneration)
          .where('type', 'in', entry.isOwned ? ['added', 'started', 'finished'] : ['started', 'finished'])
          .orderBy('createdAt', 'desc').limit(1).get();
      } catch (error) { summary.queryFailures.push({ collection: 'activities', code: error.code, message: error.message }); }
    }
  }
  for (const collection of ['circlePosts', 'circleReviews']) {
    summary.collections[collection].missingAuthor = snapshots[collection].docs.filter(document => typeof document.data().authorId !== 'string').length;
    summary.collections[collection].missingCreatedAt = snapshots[collection].docs.filter(document => typeof document.data().createdAt?.toMillis !== 'function').length;
  }
  console.log(JSON.stringify(summary, null, 2));
  await database.terminate();
}
main().catch(error => { console.error(error.code || error.message); process.exitCode = 1; });
