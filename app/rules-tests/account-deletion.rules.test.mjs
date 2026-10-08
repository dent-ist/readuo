import fs from 'node:fs';
import test from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp, deleteDoc } from 'firebase/firestore';

test('active registry preserves build24 writes and permanently fences deleted-token recreation', async () => {
  const environment = await initializeTestEnvironment({projectId:'demo-readuo-shelves', firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync('../firestore.rules','utf8')}});
  try {
    await environment.clearFirestore();
    const client = environment.authenticatedContext('old-token').firestore();
    const preference = doc(client, 'users/old-token/preferences/notifications');
    await assertFails(setDoc(preference, {like:true}));
    await assertFails(setDoc(doc(client,'activeAccounts/old-token'),{active:true}));
    await environment.withSecurityRulesDisabled(context=>setDoc(doc(context.firestore(),'activeAccounts/old-token'),{active:true}));
    await assertSucceeds(setDoc(preference,{like:true}));
    await environment.withSecurityRulesDisabled(async context=>{
      await setDoc(doc(context.firestore(),'accountDeletions/old-token'),{phase:'firestore'});
      await deleteDoc(doc(context.firestore(),'activeAccounts/old-token'));
    });
    await assertFails(setDoc(preference,{like:false}));
    await environment.withSecurityRulesDisabled(async context=>{
      await deleteDoc(doc(context.firestore(),'activeAccounts/old-token'));
      await deleteDoc(doc(context.firestore(),'accountDeletions/old-token'));
    });
    await assertFails(setDoc(preference,{like:false}));
    await assertFails(setDoc(doc(client,'readerProfiles/old-token'),{ownerId:'old-token',displayName:'Revived',photoUrl:null,inviteCode:'ABC123',createdAt:serverTimestamp(),updatedAt:serverTimestamp()}));
    await assertFails(setDoc(doc(client,'inviteCodes/ABC123'),{ownerId:'old-token',code:'ABC123',createdAt:serverTimestamp()}));
  } finally { await environment.cleanup(); }
});
