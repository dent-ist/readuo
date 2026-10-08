import fs from 'node:fs';
import test from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp, writeBatch } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

test('manual covers are immutable owner uploads and book-bound pointers, never shared bearer URLs', async () => {
  const environment = await initializeTestEnvironment({projectId:'demo-readuo-shelves', firestore:{host:'127.0.0.1',port:8080,rules:fs.readFileSync('../firestore.rules','utf8')},storage:{host:'127.0.0.1',port:9199,rules:fs.readFileSync('../storage.rules','utf8')}});
  try {
    await environment.clearFirestore();
    await environment.withSecurityRulesDisabled(async context=>{
      for(const uid of ['owner','other']) await setDoc(doc(context.firestore(),'activeAccounts',uid),{active:true});
      await setDoc(doc(context.firestore(),'shelves/shelf'),{ownerId:'owner',name:'Private',description:null,visibility:'private',autoShareActivity:false,bookCount:0,createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
    });
    const owner=environment.authenticatedContext('owner'); const other=environment.authenticatedContext('other');
    const path='bookCovers/owner/book/abcdefghijklmnopqrst';
    const bytes=new Uint8Array([255,216,255]);
    await assertSucceeds(uploadBytes(ref(owner.storage(),path),bytes,{contentType:'image/jpeg',customMetadata:{ownerId:'owner'}}));
    await assertFails(uploadBytes(ref(owner.storage(),path),new Uint8Array([255,216,255,1]),{contentType:'image/jpeg',customMetadata:{ownerId:'owner'}}));
    await assertFails(uploadBytes(ref(other.storage(),'bookCovers/owner/book/zyxwvutsrqponmlkjihg'),bytes,{contentType:'image/jpeg',customMetadata:{ownerId:'owner'}}));
    await assertFails(getBytes(ref(other.storage(),path)));
    await assertFails(uploadBytes(ref(owner.storage(),'bookCovers/owner/book/zyxwvutsrqponmlkjihg'),bytes,{contentType:'text/html',customMetadata:{ownerId:'owner'}}));
    const data={ownerId:'owner',shelfId:'shelf',title:'Manual',titleNormalized:'manual',author:'Author',isbn:null,isOwned:true,readingStatus:'wantToRead',coverUrl:path,coverStoragePath:path,createdAt:serverTimestamp(),updatedAt:serverTimestamp()};
    const save=(patch={})=>{const batch=writeBatch(owner.firestore());batch.set(doc(owner.firestore(),'shelves/shelf/books/book'),{...data,...patch});batch.update(doc(owner.firestore(),'shelves/shelf'),{bookCount:1,updatedAt:serverTimestamp()});return batch.commit();};
    await assertFails(save({coverUrl:'bookCovers/other/book/abcdefghijklmnopqrst',coverStoragePath:'bookCovers/other/book/abcdefghijklmnopqrst'}));
    await assertFails(save({coverStoragePath:null}));
    await assertSucceeds(save({activityGeneration:'abcdefghijklmnopqrst',publisher:'Reader press',publishedYear:'2026',description:'Optional metadata'}));
  } finally {await environment.cleanup();}
});
