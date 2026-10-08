import fs from 'node:fs';
import test, { before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, deleteDoc } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let environment;
const bytes = new Uint8Array([255, 216, 255, 224]);
const photoPath = 'circlePosts/owner/new-post/photo-1791135383712000';
const metadata = { contentType: 'image/jpeg', customMetadata: { ownerId: 'owner', postId: 'new-post' } };

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-readuo-circle-photos',
    firestore: { host: '127.0.0.1', port: 8086, rules: fs.readFileSync('../firestore.rules', 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: fs.readFileSync('../storage.rules', 'utf8') },
  });
});
beforeEach(async () => {
  await environment.clearStorage();
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    for (const uid of ['owner', 'friend']) {
      await setDoc(doc(context.firestore(), 'activeAccounts', uid), { active: true });
    }
    await setDoc(doc(context.firestore(), 'friendships/owner--friend'), { memberIds: ['owner', 'friend'] });
  });
});
after(() => environment?.cleanup());

test('camera-format draft upload succeeds before publication and stays private', async () => {
  const owner = environment.authenticatedContext('owner').storage();
  const friend = environment.authenticatedContext('friend').storage();
  await assertSucceeds(uploadBytes(ref(owner, photoPath), bytes, metadata));
  await assertSucceeds(getBytes(ref(owner, photoPath)));
  await assertFails(getBytes(ref(friend, photoPath)));
  await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'circlePosts/new-post'), { authorId: 'owner' }));
  await assertSucceeds(getBytes(ref(friend, photoPath)));
  await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'blocks/friend/blocked/owner'), {}));
  await assertFails(getBytes(ref(friend, photoPath)));
  await assertSucceeds(deleteObject(ref(owner, photoPath)));
});

test('signed-out and other-account uploads cannot write an owner photo', async () => {
  await assertFails(uploadBytes(ref(environment.unauthenticatedContext().storage(), photoPath), bytes, metadata));
  await assertFails(uploadBytes(ref(environment.authenticatedContext('friend').storage(), photoPath), bytes, metadata));
});

test('account deletion and moderation still block uploads', async () => {
  const owner = environment.authenticatedContext('owner').storage();
  await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'moderationLocks/post--new-post'), {}));
  await assertFails(uploadBytes(ref(owner, photoPath), bytes, metadata));
  await environment.withSecurityRulesDisabled(async context => {
    await deleteDoc(doc(context.firestore(), 'moderationLocks/post--new-post'));
    await deleteDoc(doc(context.firestore(), 'activeAccounts/owner'));
  });
  await assertFails(uploadBytes(ref(owner, photoPath), bytes, metadata));
});

test('invalid photo metadata and oversized uploads stay denied', async () => {
  const owner = environment.authenticatedContext('owner').storage();
  await assertFails(uploadBytes(ref(owner, photoPath), bytes, { ...metadata, contentType: 'text/html' }));
  await assertFails(uploadBytes(ref(owner, photoPath), bytes, { ...metadata, customMetadata: { ownerId: 'friend', postId: 'new-post' } }));
  await assertFails(uploadBytes(ref(owner, photoPath), bytes, { ...metadata, customMetadata: { ownerId: 'owner', postId: 'other-post' } }));
  await assertFails(uploadBytes(ref(owner, photoPath), new Uint8Array(10 * 1024 * 1024 + 1), metadata));
});
