import fs from 'node:fs';
import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, updateDoc, serverTimestamp, collection, query, where, getDocs, Timestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let environment;
before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-readuo-shelves',
    firestore: { host: '127.0.0.1', port: 8080, rules: fs.readFileSync('../firestore.rules', 'utf8') },
    storage: { host: '127.0.0.1', port: 9199, rules: fs.readFileSync('../storage.rules', 'utf8') },
  });
});
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    for (const uid of ['owner', 'friend', 'stranger', 'other', 'operator']) {
      await setDoc(doc(context.firestore(), 'activeAccounts', uid), { active: true });
    }
  });
});
after(() => environment?.cleanup());

test('preferences and registration tokens are owner-only and schema constrained', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const other = environment.authenticatedContext('other').firestore();
  const preferences = doc(owner, 'users/owner/preferences/notifications');
  await assertSucceeds(setDoc(preferences, { like: false }));
  await assertSucceeds(setDoc(preferences, { comment: true }, { merge: true }));
  await assertFails(setDoc(preferences, { admin: true }, { merge: true }));
  await assertFails(setDoc(preferences, { like: 'false' }, { merge: true }));
  await assertFails(getDoc(doc(other, preferences.path)));
  const token = doc(owner, 'users/owner/notificationTokens/install1');
  await assertSucceeds(setDoc(token, { token: 'test-token', platform: 'android', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(other, token.path), { token: 'stolen', platform: 'android', updatedAt: serverTimestamp() }));
});

test('only backend writes notifications and recipients can only mark read', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const path = 'users/owner/notifications/one';
  await assertFails(setDoc(doc(owner, path), { recipientId: 'owner', type: 'like' }));
  await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), path), { recipientId: 'owner', type: 'like', readAt: null }));
  await assertSucceeds(updateDoc(doc(owner, path), { readAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(owner, path), { type: 'comment', readAt: serverTimestamp() }));
  await assertFails(getDoc(doc(environment.authenticatedContext('other').firestore(), path)));
});

test('book capability and preference epochs cannot be backdated while legacy writes remain valid', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const token = doc(owner, 'users/owner/notificationTokens/books');
  const capabilities = { token: 'capable', platform: 'android', updatedAt: serverTimestamp(), bookAdditionV1: true, bookAdditionEnabledAt: serverTimestamp() };
  await assertSucceeds(setDoc(token, capabilities));
  const epoch = (await getDoc(token)).data().bookAdditionEnabledAt;
  await assertSucceeds(setDoc(token, { ...capabilities, bookAdditionEnabledAt: epoch }));
  await assertFails(setDoc(token, { ...capabilities, token: 'rotated', bookAdditionEnabledAt: epoch }));
  await assertFails(setDoc(token, { ...capabilities, bookAdditionEnabledAt: Timestamp.fromMillis(1) }));
  await assertSucceeds(setDoc(token, { token: 'legacy', platform: 'android', updatedAt: serverTimestamp() }));
  const preference = doc(owner, 'users/owner/preferences/notifications');
  await assertSucceeds(setDoc(preference, { booksAdded: false, booksAddedSince: serverTimestamp() }));
  await assertFails(updateDoc(preference, { booksAdded: true }));
  await assertSucceeds(updateDoc(preference, { booksAdded: true, booksAddedSince: serverTimestamp() }));
  await assertSucceeds(updateDoc(preference, { like: false }));
  await assertFails(updateDoc(preference, { booksAddedSince: Timestamp.fromMillis(1) }));
});

test('book groups are backend-only and current friend access is required for source entries', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const stranger = environment.authenticatedContext('stranger').firestore();
  await environment.withSecurityRulesDisabled(async context => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'friendships/friend--owner'), { memberIds: ['friend', 'owner'], createdAt: serverTimestamp() });
    await setDoc(doc(admin, 'bookAdditionGroups/group'), { actorId: 'friend', recipientId: 'owner', state: 'frozen' });
    await setDoc(doc(admin, 'bookAdditionGroups/group/bookAdditionEntries/book'), { actorId: 'friend', recipientId: 'owner', bookId: 'book' });
    await setDoc(doc(admin, 'users/owner/bookAdditionNotifications/books_group'), { recipientId: 'owner', actorId: 'friend', type: 'booksAdded', readAt: null });
  });
  await assertSucceeds(getDoc(doc(owner, 'bookAdditionGroups/group')));
  await assertSucceeds(getDocs(collection(owner, 'bookAdditionGroups/group/bookAdditionEntries')));
  await assertFails(getDoc(doc(stranger, 'bookAdditionGroups/group')));
  await assertFails(setDoc(doc(owner, 'bookAdditionGroups/forged'), { recipientId: 'owner', actorId: 'friend' }));
  await assertFails(setDoc(doc(owner, 'notificationConfiguration/bookAdditions'), { enabled: true }));
  const notice = doc(owner, 'users/owner/bookAdditionNotifications/books_group');
  await assertSucceeds(updateDoc(notice, { readAt: serverTimestamp() }));
  await assertFails(updateDoc(notice, { count: 999 }));
  await assertFails(getDoc(doc(stranger, notice.path)));
  assert.equal((await getDocs(collection(owner, 'users/owner/notifications'))).size, 0);
  await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'blocks/owner/blocked/friend'), {}));
  await assertFails(getDoc(doc(owner, 'bookAdditionGroups/group')));
  await assertFails(getDocs(collection(owner, 'bookAdditionGroups/group/bookAdditionEntries')));
});

test('support retry uses owner identity and only a moderator resolves immutable requests', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  const moderator = environment.authenticatedContext('operator', { moderator: true }).firestore();
  const path = `supportRequests/owner--${'a'.repeat(32)}`;
  assert.equal((await assertSucceeds(getDoc(doc(owner, path)))).exists(), false);
  await assertSucceeds(setDoc(doc(owner, path), { ownerId: 'owner', subject: 'Help', message: 'My library needs help.', status: 'pending', createdAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(owner, path), { status: 'resolved' }));
  await assertSucceeds(getDocs(query(collection(moderator, 'supportRequests'), where('status', '==', 'pending'))));
  await assertFails(updateDoc(doc(moderator, path), { message: 'Changed words' }));
  await assertSucceeds(updateDoc(doc(moderator, path), { status: 'resolved', resolvedAt: serverTimestamp(), resolvedBy: 'operator', resolutionNote: 'Handled by support' }));
});

function post(text) {
  return { authorId: 'owner', text, attachedBookOwnerId: null, attachedShelfId: null, attachedBookId: null, attachedTitle: null, attachedAuthor: null, attachedCoverUrl: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
}

test('direct writes cannot bypass content filtering or moderator removal locks', async () => {
  const owner = environment.authenticatedContext('owner').firestore();
  await assertSucceeds(setDoc(doc(owner, 'circlePosts/safe'), post('A lovely book about kindness.')));
  for (const [index, text] of ['I WILL KILL YOU', 'hello\nkill\tyourself\nbye'].entries()) {
    await assertFails(setDoc(doc(owner, `circlePosts/unsafe${index}`), post(text)));
  }
  await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'moderationLocks/post--removed'), { targetPath: 'circlePosts/removed' }));
  await assertFails(setDoc(doc(owner, 'circlePosts/removed'), post('New text using removed identity')));
  await assertFails(setDoc(doc(owner, 'moderationLocks/post--fake'), { targetPath: 'circlePosts/safe' }));
  await assertFails(setDoc(doc(owner, 'reports/forged'), { status: 'resolved' }));
});

test('profile photos enforce owner and type while post photos follow current friendship and blocks', async () => {
  const owner = environment.authenticatedContext('owner');
  const friend = environment.authenticatedContext('friend');
  const stranger = environment.authenticatedContext('stranger');
  const avatar = 'profilePhotos/owner/avatar1';
  await assertSucceeds(uploadBytes(ref(owner.storage(), avatar), new Uint8Array([137, 80, 78, 71]), { contentType: 'image/png' }));
  await assertSucceeds(getBytes(ref(friend.storage(), avatar)));
  await assertFails(uploadBytes(ref(stranger.storage(), 'profilePhotos/owner/forged'), new Uint8Array([1]), { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(owner.storage(), 'profilePhotos/owner/html'), new Uint8Array([1]), { contentType: 'text/html' }));
  const photo = 'circlePosts/owner/photoPost/photo-123';
  await assertSucceeds(uploadBytes(ref(owner.storage(), photo), new Uint8Array([1, 2, 3]), { contentType: 'image/jpeg', customMetadata: { ownerId: 'owner', postId: 'photoPost' } }));
  await assertFails(getBytes(ref(friend.storage(), photo)));
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'circlePosts/photoPost'), post('Photo'));
    await setDoc(doc(context.firestore(), 'friendships/owner--friend'), { memberIds: ['owner', 'friend'] });
  });
  await assertSucceeds(getBytes(ref(friend.storage(), photo)));
  await assertFails(getBytes(ref(stranger.storage(), photo)));
  await environment.withSecurityRulesDisabled(context => setDoc(doc(context.firestore(), 'blocks/friend/blocked/owner'), {}));
  await assertFails(getBytes(ref(friend.storage(), photo)));
  await assertSucceeds(deleteObject(ref(owner.storage(), avatar)));
  await assertSucceeds(deleteObject(ref(owner.storage(), photo)));
});
