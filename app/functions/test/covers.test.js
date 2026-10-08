'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseCoverPath, loadCover, cleanOrphanCovers, removeDeletedCover } = require('../covers');
const path = 'bookCovers/owner/book/abcdefghijklmnopqrst';
function fixture({visibility = 'private', owned = true, friend = false, blocked = false, active = true, exists = true} = {}) {
  const deleted = [];
  const shelf = {ownerId:'owner',visibility};
  const data = {ownerId:'owner',coverUrl:path,coverStoragePath:path,isOwned:owned};
  const db = {
    doc: location => ({path:location}),
    getAll: async (...refs) => refs.map(ref => ({exists:ref.path.startsWith('activeAccounts/') ? active : ref.path.startsWith('blocks/') ? blocked : friend})),
    collectionGroup: () => ({where: () => ({limit: () => ({get: async () => ({empty:!exists,docs:exists ? [{data:()=>data,ref:{parent:{parent:{parent:{id:'shelves'},get:async()=>({exists:true,data:()=>shelf})}}}}] : []})})})}),
  };
  const file = {name:path,getMetadata:async()=>[{size:3,contentType:'image/jpeg',timeCreated:'2020-01-01T00:00:00Z',generation:'1'}],download:async()=>[Buffer.from([1,2,3])],delete:async()=>deleted.push(path)};
  const bucket = {file:()=>file,getFiles:async()=>[[file],null]};
  return {db,bucket,deleted,shelf};
}
test('cover identifiers reject foreign URL and traversal', () => {
  assert.deepEqual(parseCoverPath(path),{ownerId:'owner',bookId:'book'});
  for (const invalid of ['https://example.com/private','bookCovers/owner/../abcdefghijklmno',null]) assert.throws(()=>parseCoverPath(invalid));
});
test('cover bytes require live authorization and owned visible source', async () => {
  for (const config of [{},{visibility:'friends'},{visibility:'public',owned:false},{visibility:'public',blocked:true},{visibility:'public',active:false},{visibility:'public',exists:false}]) {
    const {db,bucket}=fixture(config);
    await assert.rejects(loadCover({auth:{uid:'viewer'},data:{path}},db,bucket));
  }
  for (const config of [{visibility:'public'},{visibility:'friends',friend:true}]) {
    const {db,bucket}=fixture(config);
    assert.equal((await loadCover({auth:{uid:'viewer'},data:{path}},db,bucket)).bytes,'AQID');
  }
  const own=fixture();assert.equal((await loadCover({auth:{uid:'owner'},data:{path}},own.db,own.bucket)).bytes,'AQID');
});
test('move keeps the cover; book removal and orphan sweep erase unreferenced objects', async () => {
  const moved=fixture();await removeDeletedCover({ownerId:'owner',coverStoragePath:path},moved.db,moved.bucket);assert.equal(moved.deleted.length,0);
  const removed=fixture({exists:false});await removeDeletedCover({ownerId:'owner',coverStoragePath:path},removed.db,removed.bucket);assert.equal(removed.deleted.length,1);
  const orphan=fixture({exists:false});await cleanOrphanCovers(orphan.db,orphan.bucket);assert.equal(orphan.deleted.length,1);
});
