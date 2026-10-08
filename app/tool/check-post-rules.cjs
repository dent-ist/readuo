const fs = require('node:fs');
const base = 'C:/nvm4w/nodejs/node_modules/firebase-tools/lib/';
(async () => {
  const account = require(base + 'auth').getGlobalDefaultAccount();
  await require(base + 'requireAuth').requireAuth({ ...account, project: 'readuo-b2f24' });
  const rules = require(base + 'gcp/rules');
  const name = await rules.getLatestRulesetName('readuo-b2f24', 'cloud.firestore');
  const files = await rules.getRulesetContent(name);
  const remote = files.find(file => file.name === 'firestore.rules') || files[0];
  fs.writeFileSync('test/post-rules-deployed-before.rules', remote.content);
  const normalize = text => text.replace(/\r\n/g, '\n').trim();
  const oldCheck = "data.text.matches('.*\\\\S.*')\n                  || data.get('photoPath', null) != null";
  const newCheck = "data.text.matches('[\\\\s\\\\S]*\\\\S[\\\\s\\\\S]*')\n                  || data.get('photoPath', null) != null";
  const original = normalize(remote.content);
  if (original.split(oldCheck).length !== 2) throw new Error('Expected exactly one post text check.');
  fs.writeFileSync('test/post-rules-deploy.rules', original.replace(oldCheck, newCheck) + '\n');
  fs.writeFileSync('firebase.post-fix.json', JSON.stringify({
    firestore: { rules: 'test/post-rules-deploy.rules' },
    emulators: { firestore: { port: 8080 }, ui: { enabled: false } },
  }, null, 2));
  console.log('Prepared deployed rules with only the multiline post check changed.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
