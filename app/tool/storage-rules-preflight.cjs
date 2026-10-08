const path = require('node:path');
const crypto = require('node:crypto');

const cliRoot = process.env.FIREBASE_CLI_LIB || 'C:/nvm4w/nodejs/node_modules/firebase-tools/lib';
const { getGlobalDefaultAccount } = require(path.join(cliRoot, 'auth'));
const { requireAuth } = require(path.join(cliRoot, 'requireAuth'));
const { Client } = require(path.join(cliRoot, 'apiv2'));
const rules = require(path.join(cliRoot, 'gcp/rules'));
const project = 'readuo-b2f24';
const bucket = 'readuo-b2f24.firebasestorage.app';
const member = 'serviceAccount:service-881895077363@gcp-sa-firebasestorage.iam.gserviceaccount.com';
const role = 'roles/firebaserules.firestoreServiceAgent';

async function main() {
  const args = process.argv.slice(2);
  if (args.some(argument => argument !== '--enable-cross-service') || args.length > 1) {
    throw new Error('Use no arguments for a read-only check, or --enable-cross-service after explicit permission.');
  }
  await requireAuth({ project, ...getGlobalDefaultAccount(), nonInteractive: true });
  const releases = await rules.listAllReleases(project);
  const release = releases.find(entry => entry.name === `projects/${project}/releases/firebase.storage/${bucket}`);
  if (!release) throw new Error('Expected Storage release was not found.');
  const files = await rules.getRulesetContent(release.rulesetName);
  const source = files.map(file => file.content).join('\n');
  const crossServiceRequired = /firestore\.(get|exists)\(/.test(source);
  const client = new Client({ urlPrefix: 'https://cloudresourcemanager.googleapis.com', apiVersion: 'v1' });
  const readPolicy = async () => (await client.post(
    `/projects/${project}:getIamPolicy`,
    { options: { requestedPolicyVersion: 3 } },
    { skipLog: { body: true, resBody: true } },
  )).body;
  const hasRole = policy => (policy.bindings || []).some(binding =>
    binding.role === role && !binding.condition && binding.members?.includes(member));
  let policy = await readPolicy();
  const enabledBefore = hasRole(policy);
  if (args.includes('--enable-cross-service') && crossServiceRequired && !enabledBefore) {
    if (!policy.etag) throw new Error('Refusing an IAM update without a concurrency etag.');
    const iam = new Client({ urlPrefix: 'https://iam.googleapis.com', apiVersion: 'v1' });
    const permissions = (await iam.get(`/${role}`)).body.includedPermissions;
    if (permissions?.length !== 1 || permissions[0] !== 'datastore.entities.get') {
      throw new Error('The service role changed; review its permissions before granting it.');
    }
    const bindings = policy.bindings || [];
    const binding = bindings.find(entry => entry.role === role && !entry.condition);
    if (binding) binding.members = [...new Set([...binding.members, member])];
    else bindings.push({ role, members: [member] });
    await client.post(`/projects/${project}:setIamPolicy`, {
      policy: { ...policy, bindings },
      updateMask: 'bindings,etag',
    }, { skipLog: { body: true, resBody: true } });
    policy = await readPolicy();
  }
  console.log(JSON.stringify({
    project, bucket, ruleset: release.rulesetName,
    rulesSha256: crypto.createHash('sha256').update(source).digest('hex'),
    crossServiceRequired, role, member, enabledBefore, enabledAfter: hasRole(policy),
  }, null, 2));
  if (crossServiceRequired && !hasRole(policy)) {
    throw new Error('Storage rules require a missing Firestore service-agent role. Emulator tests alone cannot verify production IAM.');
  }
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
