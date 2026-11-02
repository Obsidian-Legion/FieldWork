import assert from 'node:assert/strict';
const base='http://127.0.0.1:8789';
const response=await fetch(base+'/api/state',{headers:{'X-MS-CLIENT-PRINCIPAL-ID':'101','X-MS-CLIENT-PRINCIPAL-IDP':'github','X-MS-CLIENT-PRINCIPAL-NAME':'spoofed'}});
assert.equal(response.status,401);
const session=await (await fetch(base+'/api/session')).json();
assert.equal(session.authenticated,false);
assert.equal(session.configured,false);
assert.equal((await fetch(base+'/')).status,200);
console.log('PASS: unconfigured deployments reject identity headers and keep course data locked.');
