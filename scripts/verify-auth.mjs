import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import http from 'node:http';

// Isolated backend tests simulate the headers injected by Azure Easy Auth.
// They do not replace the live GitHub OAuth acceptance check.
const base='http://127.0.0.1:8788';
const identity=id=>({'X-MS-CLIENT-PRINCIPAL-ID':id,'X-MS-CLIENT-PRINCIPAL-IDP':'github','X-MS-CLIENT-PRINCIPAL-NAME':`verification-${id}`});
const request=(path,id,options={})=>fetch(base+path,{...options,headers:{...(id?identity(id):{}),...options.headers}});
const state=async id=>{const r=await request('/api/state',id);assert.equal(r.status,200);return r.json();};
const save=(value,id,scope='state')=>request('/api/'+scope,id,{method:'PUT',headers:{'Content-Type':'application/json','If-Match':String(scope==='progress'?value.personalRevision:value.revision)},body:JSON.stringify(value)});
const admin='101',alice='202',bob='303';
assert.equal((await request('/api/state')).status,401);
assert.equal((await request('/api/session')).status,200);
assert.equal((await (await request('/api/session')).json()).authenticated,false);
assert.equal((await (await request('/api/session',admin)).json()).user.role,'admin');
assert.equal((await (await request('/api/session',alice)).json()).user.role,'member');
assert.equal((await request('/api/state',null,{headers:{...identity(admin),'X-MS-CLIENT-PRINCIPAL-IDP':'google'}})).status,401);
assert.equal((await request('/api/state','../../state')).status,401);
// Azure's GitHub principal can omit NAME; the username is in urn:github:login.
const principal=(provider='github',id=admin)=>Buffer.from(JSON.stringify({auth_typ:provider,claims:[{typ:'urn:github:id',val:id},{typ:'urn:github:login',val:'verification-admin'}]})).toString('base64');
const azureHeaders={'X-MS-CLIENT-PRINCIPAL-ID':admin,'X-MS-CLIENT-PRINCIPAL-IDP':'github','X-MS-CLIENT-PRINCIPAL':principal()};
const azureSession=await (await request('/api/session',null,{headers:azureHeaders})).json();
assert.equal(azureSession.user.role,'admin');assert.equal(azureSession.user.github.login,'verification-admin');
assert.equal((await request('/api/state',null,{headers:{...azureHeaders,'X-MS-CLIENT-PRINCIPAL':principal('google')}})).status,401);
assert.equal((await request('/api/state',null,{headers:{...azureHeaders,'X-MS-CLIENT-PRINCIPAL':principal('github',alice)}})).status,401);
assert.equal((await request('/api/state',null,{headers:{...identity(admin),'X-MS-CLIENT-PRINCIPAL':'not-base64'}})).status,401);
const file=randomUUID(),course=randomUUID(),payload='Private course file\n0123456789';
assert.equal((await request(`/api/files/${file}/txt`,alice,{method:'PUT',body:payload})).status,403);
assert.equal((await request(`/api/files/${file}/txt`,admin,{method:'PUT',body:payload})).status,201);
assert.equal((await request(`/api/files/${file}/txt`)).status,401);
assert.equal((await request(`/api/files/${file}/txt`,alice)).status,404);
let catalog=await state(admin);
catalog.courses.push({id:course,title:'Authorization fixture',sector:'Architecture',level:'Foundation',description:'',lessons:[{id:file,ext:'txt',title:'Verification',name:'verification.txt',size:payload.length,completed:false}],notes:'',x:1600,y:800,archived:false,createdAt:new Date().toISOString()});
assert.equal((await save(catalog,alice)).status,403);
let r=await save(catalog,admin);assert.equal(r.status,200);
assert.equal((await save(catalog,admin)).status,409);
assert.equal(await (await request(`/api/files/${file}/txt`,alice)).text(),payload);
r=await request(`/api/files/${file}/txt`,alice,{headers:{Range:'bytes=0-6'}});assert.equal(r.status,206);assert.equal(await r.text(),payload.slice(0,7));
assert.equal((await request(`/api/files/${file}/txt`,alice,{headers:{Range:'bytes=999-'}})).status,416);
let personal=await state(alice);
let item=personal.courses.find(c=>c.id===course);item.notes='Only Alice sees this';item.lessons[0].completed=true;item.x=1800;
// Tampering with catalogue fields through the progress endpoint is ignored.
item.title='Unauthorized edit';personal.links.push({a:course,b:course});
r=await save(personal,alice,'progress');assert.equal(r.status,200);let saved=await r.json();
assert.equal(saved.courses.find(c=>c.id===course).title,'Authorization fixture');
assert.equal(saved.courses.find(c=>c.id===course).notes,'Only Alice sees this');
assert.equal(saved.courses.find(c=>c.id===course).lessons[0].completed,true);
assert.equal(saved.courses.find(c=>c.id===course).x,1800);
assert.equal((await save(personal,alice,'progress')).status,409);
for(const id of [bob,admin]){const other=(await state(id)).courses.find(c=>c.id===course);assert.equal(other.notes,'');assert.equal(other.lessons[0].completed,false);assert.equal(other.x,1600);}
assert.equal((await request('/users/202.json',alice)).status,404);
assert.equal((await request('/api/state',admin,{method:'PUT',headers:{Origin:'https://example.com'},body:'{}'})).status,403);
assert.equal(await new Promise((resolve,reject)=>http.get(base+'/api/state',{headers:{Host:'example.com',...identity(admin)}},r=>{r.resume();resolve(r.statusCode)}).on('error',reject)),403);
catalog=await state(admin);catalog.courses.find(c=>c.id===course).archived=true;
assert.equal((await save(catalog,admin)).status,200);
assert.equal((await state(alice)).courses.some(c=>c.id===course),false);
assert.equal((await request(`/api/files/${file}/txt`,alice)).status,404);
console.log('PASS: anonymous protection; admin uploads; member restrictions; private notes/progress/layout; immutable course fields; revision conflicts; protected files/ranges; archive access; origin/host checks.');
