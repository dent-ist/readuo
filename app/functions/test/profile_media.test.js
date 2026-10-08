'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createProfileMedia, removeInactiveUpload, withProfileLease, urlPath, leaseMillis } = require('../profile_media');
const now = Date.UTC(2026, 8, 27);
const path = 'profilePhotos/owner/abcdefghijklmnopqrst';

function fixture() {
  const records = new Map([
    ['activeAccounts/owner', {}],
    ['readerProfiles/owner', { ownerId: 'owner', displayName: 'Old', photoUrl: null }],
    ['profilePhotoUploads/abcdefghijklmnopqrst', { ownerId: 'owner', path, state: 'reserved', createdAt: now - 172800000 }],
  ]);
  const objects = new Map([[path, { size: 3, generation: '1', contentType: 'image/jpeg', timeCreated: '2020-01-01T00:00:00Z', metadata: { readuoManaged: 'v2' } }]]);
  const removed = [];
  const snapshot = location => {
    const value = records.has(location) ? { ...records.get(location) } : undefined;
    return { exists: value !== undefined, data: () => value, ref: db.doc(location) };
  };
  const db = {
    doc: location => ({ path: location, id: location.split('/').at(-1), get: async () => snapshot(location),
      set: async (data, options) => records.set(location, { ...(options?.merge ? records.get(location) : {}), ...data }),
      delete: async () => records.delete(location) }),
    getAll: async (...refs) => refs.map(ref => snapshot(ref.path)),
    collection: name => ({ doc: () => db.doc(`${name}/abcdefghijklmnopqrstuvwx`),
      where: (_, __, cutoff) => {
        let cursor; let count = 100;
        const query = {
          orderBy: () => query,
          limit: value => { count = value; return query; },
          startAfter: value => { cursor = value.ref.path; return query; },
          get: async () => {
            const locations = [...records.keys()].filter(location => location.startsWith(`${name}/`) && records.get(location).createdAt < cutoff).sort((left, right) => records.get(left).createdAt - records.get(right).createdAt || left.localeCompare(right));
            return { docs: locations.slice(cursor ? locations.indexOf(cursor) + 1 : 0).slice(0, count).map(snapshot) };
          },
        }; return query;
      } }),
    runTransaction: async action => {
      const writes = [];
      const result = await action({ get: async ref => snapshot(ref.path),
        set: (ref, data) => writes.push(() => records.set(ref.path, data)),
        update: (ref, data) => writes.push(() => records.set(ref.path, { ...records.get(ref.path), ...data })),
        delete: ref => writes.push(() => records.delete(ref.path)) });
      writes.forEach(write => write()); return result;
    },
  };
  const user = { uid: 'owner', photoURL: null, displayName: 'Old' };
  let beforeUpdate = async () => {};
  const auth = { getUser: async () => user, updateUser: async (_, data) => { await beforeUpdate(); Object.assign(user, data); } };
  const bucket = { name: 'test-bucket', file: name => ({ name,
    getMetadata: async () => { if (!objects.has(name)) throw Object.assign(new Error('missing'), { code: 404 }); return [objects.get(name)]; },
    setMetadata: async data => Object.assign(objects.get(name), data),
    exists: async () => [objects.has(name)],
    delete: async options => { if (objects.has(name) && options.ifGenerationMatch && options.ifGenerationMatch !== objects.get(name).generation) throw Object.assign(new Error('generation'), { code: 412 }); objects.delete(name); removed.push(name); },
  }), getFiles: async () => [[...objects.keys()].map(name => bucket.file(name)), null] };
  return { records, objects, removed, db, auth, bucket, user, service: createProfileMedia({ db, auth, bucket, now: () => now }), setBeforeUpdate: action => { beforeUpdate = action; } };
}

test('profile save checks exact own reservation and synchronizes Auth plus reader profile', async () => {
  const data = fixture();
  const result = await data.service.save({ auth: { uid: 'owner' }, data: { displayName: ' Maya ', path } });
  assert.equal(result.displayName, 'Maya');
  assert.equal(urlPath(result.photoUrl, 'test-bucket'), path);
  assert.equal(data.user.photoURL, data.records.get('readerProfiles/owner').photoUrl);
  assert.equal(data.records.has('profileWriteLeases/owner'), false);
  await assert.rejects(data.service.save({ auth: { uid: 'other' }, data: { displayName: 'Other', path } }));
});

test('orphan reconciliation respects both references, recent uploads, busy saves and legacy objects', async () => {
  for (const protect of ['auth', 'profile-path', 'profile-url', 'recent', 'lease', 'legacy']) {
    const data = fixture();
    const url = `https://firebasestorage.googleapis.com/v0/b/test-bucket/o/${encodeURIComponent(path)}?alt=media&token=test`;
    if (protect === 'auth') data.user.photoURL = url;
    if (protect === 'profile-path') data.records.get('readerProfiles/owner').photoStoragePath = path;
    if (protect === 'profile-url') data.records.get('readerProfiles/owner').photoUrl = url;
    if (protect === 'recent') data.objects.get(path).timeCreated = new Date(now - 1000).toISOString();
    if (protect === 'lease') data.records.set('profileWriteLeases/owner', { token: 'busy', until: now + 1000 });
    if (protect === 'legacy') data.objects.get(path).metadata = {};
    await data.service.reconcile();
    assert.equal(data.objects.has(path), true, protect);
  }
  const orphan = fixture(); await orphan.service.reconcile();
  assert.deepEqual(orphan.removed, [path]);
  await assert.rejects(orphan.service.save({ auth: { uid: 'owner' }, data: { displayName: 'Maya', path } }));
});

test('ambiguous profile synchronization keeps Auth-referenced bytes for retry', async () => {
  const data = fixture();
  data.setBeforeUpdate(async () => { data.records.get('readerProfiles/owner').photoUrl = 'https://other-device.test/photo'; });
  await assert.rejects(data.service.save({ auth: { uid: 'owner' }, data: { displayName: 'Maya', path } }));
  await data.service.reconcile();
  assert.equal(data.objects.has(path), true);
});

test('deletion marker rejects new leases; late uploads are removed with generation precondition', async () => {
  const data = fixture();
  await removeInactiveUpload({ name: path, generation: '1' }, data.db, data.bucket);
  assert.equal(data.objects.has(path), true);
  data.records.set('accountDeletions/owner', {});
  data.records.delete('activeAccounts/owner');
  await assert.rejects(withProfileLease('owner', data.db, async () => assert.fail('cannot write'), () => now));
  await assert.rejects(removeInactiveUpload({ name: path, generation: 'old' }, data.db, data.bucket), { code: 412 });
  assert.equal(data.objects.has(path), true);
  await removeInactiveUpload({ name: path, generation: '1' }, data.db, data.bucket);
  assert.equal(data.objects.has(path), false);
});

test('profile write already in flight cannot recreate Firestore after deletion begins', async () => {
  const data = fixture();
  data.setBeforeUpdate(async () => { data.records.set('accountDeletions/owner', {}); data.records.delete('activeAccounts/owner'); });
  await assert.rejects(data.service.save({ auth: { uid: 'owner' }, data: { displayName: 'Maya', path } }));
  assert.equal(data.records.get('readerProfiles/owner').displayName, 'Old');
  assert.equal(data.records.has('profileWriteLeases/owner'), false);
});

test('expired in-flight Auth save cannot commit and reconciliation retains its possibly referenced bytes', async () => {
  const data = fixture();
  let clock = now;
  const service = createProfileMedia({ db: data.db, auth: data.auth, bucket: data.bucket, now: () => clock });
  data.setBeforeUpdate(async () => {
    clock += leaseMillis + 1;
    await service.reconcile();
    assert.equal(data.objects.has(path), true);
    await withProfileLease('owner', data.db, async () => {}, () => clock);
  });
  await assert.rejects(service.save({ auth: { uid: 'owner' }, data: { displayName: 'Maya', path } }), { code: 'aborted' });
  assert.equal(data.objects.has(path), true);
  assert.equal(urlPath(data.user.photoURL, 'test-bucket'), path);
  assert.equal(data.records.get('readerProfiles/owner').displayName, 'Old');
});

test('expired reconciler cannot delete after a second lease references the photo', async () => {
  const data = fixture();
  let clock = now;
  const originalGet = data.auth.getUser;
  data.auth.getUser = async () => {
    const snapshot = { ...await originalGet() };
    clock += leaseMillis + 1;
    await withProfileLease('owner', data.db, async () => {
      data.user.photoURL = `https://firebasestorage.googleapis.com/v0/b/test-bucket/o/${encodeURIComponent(path)}?alt=media`;
    }, () => clock);
    return snapshot;
  };
  await createProfileMedia({ db: data.db, auth: data.auth, bucket: data.bucket, now: () => clock }).reconcile();
  assert.equal(data.objects.has(path), true);
  assert.deepEqual(data.removed, []);
});

test('abandoned reservation scan progresses beyond a full page of retained objects', async () => {
  const data = fixture();
  data.records.clear();
  data.records.set('activeAccounts/owner', {});
  data.objects.clear();
  for (let index = 0; index < 101; index++) {
    const photoId = String(index).padStart(20, '0');
    const photoPath = `profilePhotos/owner/${photoId}`;
    data.records.set(`profilePhotoUploads/${photoId}`, { ownerId: 'owner', path: photoPath, state: 'committed', createdAt: now - 172800000 + index });
    if (index < 100) data.objects.set(photoPath, { metadata: {} });
  }
  await data.service.reconcile();
  assert.equal(data.records.has(`profilePhotoUploads/${String(100).padStart(20, '0')}`), false);
  assert.equal([...data.records.keys()].filter(key => key.startsWith('profilePhotoUploads/')).length, 100);
});
