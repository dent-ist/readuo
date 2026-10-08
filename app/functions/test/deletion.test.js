'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createDeletionService} = require('../deletion/service');
const {validateStart, classify} = require('../deletion/policy');

const request = () => ({auth:{uid:'reader',token:{auth_time:1000,firebase:{sign_in_provider:'google.com'}}},data:{confirmed:true}});
function fixture(extra = {}) {
  const records = new Map(Object.entries({
    'users/reader/onboarding/firstBook':{ownerId:'reader'},
    'shelves/own':{ownerId:'reader'},
    'shelves/own/books/book':{ownerId:'reader'},
    'circlePosts/post':{authorId:'reader'},
    'circlePosts/post/comments/other':{authorId:'other'},
    'circlePosts/kept':{authorId:'other',text:'Keep'},
    'circlePosts/kept/comments/mine':{authorId:'reader'},
    'circlePosts/kept/likes/reader':{userId:'reader'},
    'friendRequests/pair':{requesterId:'reader',recipientId:'other'},
    'friendships/pair':{memberIds:['other','reader']},
    'blocks/other/blocked/reader':{blockedId:'reader'},
    'readerProfiles/reader':{ownerId:'reader'},
    'activeAccounts/reader':{},
    'inviteCodes/ABC123':{ownerId:'reader'},
    'reports/report':{reporterId:'other',targetAuthorId:'reader'},
    'moderationActions/action':{actorId:'reader'},
    'moderationLocks/lock':{targetAuthorId:'reader'},
    'users/other/notifications/notice':{recipientId:'other',actorId:'reader'},
    'notificationEvents/event':{recipientId:'reader',actorId:'other'},
    'supportRequests/request':{ownerId:'reader'},
    'shelves/kept/books/copy':{ownerId:'other',title:'Independent copy',coverUrl:'https://firebasestorage.googleapis.com/v0/b/b/o/bookCovers%2Freader%2Fcover'},
    ...extra,
  }));
  let job = null;
  let user = {uid:'reader',providerData:[{providerId:'google.com'}]};
  let failPath = null;
  let failMedia = false;
  let profileWriting = false;
  const roots = new Set();
  const media = new Set(['circlePosts/reader/photo','profilePhotos/reader/photo','bookCovers/reader/photo','bookCovers/other/keep']);
  const events = [];
  const store = {
    hasActiveProfileWriter: async () => profileWriting,
    get:async()=>job,
    begin:async(_,value)=>{ if (!job) {job={...value};records.delete('activeAccounts/reader');} return job; },
    acquire:async(_,leaseToken)=>{if(!job || job.leaseToken)return null;job={...job,leaseToken};return job;},
    checkpoint:async(_,token,changes)=>{if(job?.leaseToken!==token)return null;job={...job,...changes};return job;},
    release:async(_,token,retrying)=>{if(job?.leaseToken===token)job={...job,leaseToken:null,leaseUntil:0,retrying};},
    page:async(group,cursor,limit)=>[...records].filter(([path])=>path.split('/').at(-2)===group&&(!cursor||path>cursor)).sort(([left],[right])=>left.localeCompare(right)).slice(0,limit).map(([path,data])=>({path,data})),
    rememberRoot:async(_,path)=>roots.add(path),
    referencesRoots:async(_,paths)=>paths.some(path=>[...roots].some(root=>path===root||path.startsWith(root+'/'))),
    removeTree:async path=>{if(path===failPath){failPath=null;throw Error('temporary');}for(const key of records.keys())if(key===path||key.startsWith(path+'/'))records.delete(key);},
    redact:async(document,patch)=>records.set(document.path,{...document.data,...patch}),
    finish:async()=>{roots.clear();job=null;events.push('finished');},
  };
  const service=createDeletionService({store,now:()=>1000000,randomId:()=> 'job',auth:{
    getUser:async()=>{if(!user)throw Object.assign(Error(),{code:'auth/user-not-found'});return user;},
    deleteUser:async()=>{assert.equal([...media].some(path=>path.includes('/reader/')),false);assert.equal([...records.values()].some(value=>value.ownerId==='reader'||value.authorId==='reader'),false);user=null;events.push('auth-deleted');},
  },media:{removePage:async prefix=>{if(failMedia){failMedia=false;throw Error('storage');}const matches=[...media].filter(path=>path.startsWith(prefix));matches.forEach(path=>media.delete(path));return matches.length===0;}}});
  return {service,records,media,events,job:()=>job,user:()=>user,failAt:path=>{failPath=path;},failMedia:()=>{failMedia=true;},profileWriting:value=>{profileWriting=value;}};
}

test('deletion start requires own fresh linked Google verification and exact confirmation',async()=>{
  for(const mutate of [value=>delete value.auth,value=>value.data.confirmed=false,value=>value.data.uid='other',value=>value.auth.token.auth_time=0,value=>value.auth.token.firebase.sign_in_provider='password']){
    const value=request();mutate(value);assert.throws(()=>validateStart(value,1000000));
  }
  assert.equal(validateStart(request(),1000000),'reader');
});
test('deletion removes all owned and related records/media, preserves independent libraries, Auth last, no tombstone',async()=>{
  const data=fixture();
  assert.equal((await data.service.start(request())).status,'processing');
  assert.equal(data.records.has('activeAccounts/reader'),false);
  assert.equal((await data.service.start(request())).jobId,'job');
  assert.equal((await data.service.work('reader')).status,'complete');
  assert.deepEqual(data.events,['auth-deleted','finished']);
  assert.equal(data.job(),null);assert.equal(data.user(),null);
  assert.deepEqual([...data.records.keys()].sort(),['circlePosts/kept','shelves/kept/books/copy']);
  assert.equal(data.records.get('shelves/kept/books/copy').coverUrl,null);
  assert.deepEqual([...data.media],['bookCovers/other/keep']);
  assert.equal((await data.service.status({...request(),data:{}})).status,'complete');
});
test('failure retries the pending subtree and does not delete Auth prematurely',async()=>{
  const data=fixture();await data.service.start(request());data.failAt('shelves/own');
  await assert.rejects(data.service.work('reader'));assert.ok(data.user());assert.equal(data.job().pendingPath,'shelves/own');
  assert.equal((await data.service.work('reader')).status,'complete');
});
test('media failure retains retry state and Auth; retry finishes without retaining audit',async()=>{
  const data=fixture();await data.service.start(request());data.failMedia();
  await assert.rejects(data.service.work('reader'));assert.ok(data.user());assert.equal(data.job().retrying,true);
  await data.service.work('reader');assert.equal(data.job(),null);
});
test('existing account without marker is not incorrectly reported deleted',async()=>{
  const data=fixture();assert.equal((await data.service.status({...request(),data:{}})).status,'not-started');
});
test('arbitrary book text mentioning an ID is not deleted as account identity',()=>{
  assert.equal(classify('shelves/other/books/one',{ownerId:'other',title:'reader'},'reader').type,'keep');
});
test('deletion waits for bounded server profile writes before scanning data', async () => {
  const data = fixture();
  await data.service.start(request());
  data.profileWriting(true);
  assert.equal((await data.service.work('reader')).status, 'processing');
  assert.equal(data.records.has('readerProfiles/reader'), true);
  assert.ok(data.user());
  data.profileWriting(false);
  assert.equal((await data.service.work('reader')).status, 'complete');
});
