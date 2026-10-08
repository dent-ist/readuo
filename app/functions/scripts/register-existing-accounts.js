'use strict';
const path = require('node:path');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {activateAccount} = require('../accounts');
const {Firestore} = require('@google-cloud/firestore');

async function main() {
  const cliLib = process.env.FIREBASE_CLI_LIB;
  if (!cliLib) throw Error('Set FIREBASE_CLI_LIB to the installed Firebase CLI lib directory.');
  const auth = require(path.join(cliLib,'auth.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw Error('Sign in with the Firebase CLI first.');
  const api = require(path.join(cliLib,'api.js'));
  const database = new Firestore({projectId:'readuo-b2f24',credentials:{type:'authorized_user',client_id:api.clientId(),client_secret:api.clientSecret(),refresh_token:account.tokens.refresh_token}});
  initializeApp({projectId:'readuo-b2f24',credential:{getAccessToken:async()=>{
    const token = await auth.getAccessToken(account.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform','https://www.googleapis.com/auth/firebase']);
    return {access_token:token.access_token,expires_in:3600};
  }}});
  let cursor;
  let checked=0;
  let registered=0;
  const apply=process.argv.includes('--apply');
  do {
    const page=await getAuth().listUsers(1000,cursor);
    for(const user of page.users) {
      checked++;
      if(apply&&!user.disabled) {await activateAccount(user.uid,database,getAuth());registered++;}
    }
    cursor=page.pageToken;
  } while(cursor);
  console.log(JSON.stringify({project:'readuo-b2f24',mode:apply?'apply':'dry-run',checked,registered}));
}
main().catch(error=>{console.error('Registry migration failed:',error.code||error.message);process.exitCode=1;});
