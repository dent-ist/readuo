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
  const original = normalize(remote.content);
  const marker = '          allow update, delete: if false;\n        }\n      }\n    }';
  if (original.split(marker).length !== 2) throw new Error('Expected one activity rule endpoint');
  const fragment = fs.readFileSync('test/activity-engagement-rules-fragment.txt', 'utf8');
  fs.writeFileSync('test/activity-rules-deploy.rules', original.replace(marker, '          allow update, delete: if false;\n' + fragment + '\n        }\n      }\n    }') + '\n');
  fs.writeFileSync('firebase.activity-fix.json', JSON.stringify({
    firestore: { rules: 'test/activity-rules-deploy.rules' },
    emulators: { firestore: { port: 8080 }, ui: { enabled: false } },
  }, null, 2));
  console.log('Prepared activity engagement rules on current production snapshot.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
