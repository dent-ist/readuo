import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { createProfileMedia, removeInactiveUpload } = require('../functions/profile_media');
const { createDeletionService } = require('../functions/deletion/service');
const { createDeletionStore, createDeletionMedia } = require('../functions/deletion/firebase_store');

async function fixture(label) {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  assert.match(process.env.FIREBASE_STORAGE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  const projectId = 'demo-readuo-shelves';
  const environment = await initializeTestEnvironment({ projectId });
  await environment.clearFirestore();
  const app = initializeApp({ projectId, storageBucket: `${projectId}.appspot.com` }, label);
  const db = getFirestore(app);
  const bucket = getStorage(app).bucket();
  await bucket.deleteFiles({ force: true });
  await db.doc('activeAccounts/owner').set({ active: true });
  await db.doc('readerProfiles/owner').set({ ownerId: 'owner', displayName: 'Original', photoUrl: null });
  let user = { uid: 'owner', displayName: 'Original', photoURL: null, providerData: [{ providerId: 'google.com' }] };
  let beforeUpdate = async () => {};
  let clock = Date.now();
  const auth = {
    getUser: async () => { if (!user) throw Object.assign(new Error('deleted'), { code: 'auth/user-not-found' }); return user; },
    updateUser: async (_, changes) => { await beforeUpdate(); Object.assign(user, changes); },
    deleteUser: async () => { user = null; },
  };
  const now = () => clock;
  const media = createProfileMedia({ db, auth, bucket, now });
  const deletion = createDeletionService({ db, auth, store: createDeletionStore(db), media: createDeletionMedia(bucket), now });
  const upload = async path => bucket.file(path).save(Buffer.from([255, 216, 255]), {
    metadata: { contentType: 'image/jpeg', metadata: { ownerId: 'owner', readuoManaged: 'v2' } },
  });
  return { db, bucket, environment, media, deletion, upload, now, user: () => user,
    advance: duration => { clock += duration; }, beforeUpdate: action => { beforeUpdate = action; },
    close: async () => { await bucket.deleteFiles({ force: true }); await db.terminate(); await deleteApp(app); await environment.cleanup(); },
  };
}

test('emulator: deletion fences in-flight server profile commit and removes a late upload', async () => {
  const data = await fixture('profile-delete-race');
  try {
    let release;
    let entered;
    const hold = new Promise(resolve => { release = resolve; });
    const updating = new Promise(resolve => { entered = resolve; });
    data.beforeUpdate(async () => { entered(); await hold; });
    const { path } = await data.media.reserve({ auth: { uid: 'owner' }, data: {} });
    await data.upload(path);
    const saving = data.media.save({ auth: { uid: 'owner' }, data: { displayName: 'New', path } });
    const rejected = assert.rejects(saving, error => error.code === 'permission-denied');
    await updating;
    await data.deletion.start({ auth: { uid: 'owner', token: { auth_time: data.now() / 1000, firebase: { sign_in_provider: 'google.com' } } }, data: { confirmed: true } });
    assert.equal((await data.deletion.work('owner')).status, 'processing');
    assert.ok(data.user());
    release();
    await rejected;
    assert.equal((await data.db.doc('readerProfiles/owner').get()).data().displayName, 'Original');
    assert.equal((await data.deletion.work('owner')).status, 'complete');
    assert.equal(data.user(), null);
    assert.equal((await data.db.doc('accountDeletions/owner').get()).exists, false);
    await data.upload(path);
    const [object] = await data.bucket.file(path).getMetadata();
    await removeInactiveUpload(object, data.db, data.bucket);
    assert.equal((await data.bucket.file(path).exists())[0], false);
    const client = data.environment.authenticatedContext('owner').firestore();
    await assertFails(setDoc(doc(client, 'profileWriteLeases/owner'), { until: data.now() + 100000 }));
    await assertFails(setDoc(doc(client, 'profilePhotoUploads/forged'), { ownerId: 'owner' }));
  } finally { await data.close(); }
});

test('emulator: managed photo sweep preserves Auth/profile references and rejects expired reservation reuse', async () => {
  const data = await fixture('profile-orphans');
  try {
    const first = await data.media.reserve({ auth: { uid: 'owner' }, data: {} });
    await data.upload(first.path);
    await data.media.save({ auth: { uid: 'owner' }, data: { displayName: 'Maya', path: first.path } });
    const orphan = await data.media.reserve({ auth: { uid: 'owner' }, data: {} });
    await data.upload(orphan.path);
    const profileOnly = await data.media.reserve({ auth: { uid: 'owner' }, data: {} });
    await data.upload(profileOnly.path);
    await data.db.doc('readerProfiles/owner').update({ photoStoragePath: profileOnly.path });
    data.advance(2 * 24 * 60 * 60 * 1000);
    await data.media.reconcile();
    assert.equal((await data.bucket.file(first.path).exists())[0], true);
    assert.equal((await data.bucket.file(profileOnly.path).exists())[0], true);
    assert.equal((await data.bucket.file(orphan.path).exists())[0], false);
    await assert.rejects(data.media.save({ auth: { uid: 'owner' }, data: { displayName: 'Maya', path: orphan.path } }));
  } finally { await data.close(); }
});
