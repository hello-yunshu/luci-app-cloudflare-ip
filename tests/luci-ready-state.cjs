'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(process.env.CFIP_TEST_UTILS || path.join(__dirname, '../package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/utils.js'), 'utf8');
const utils = new Function('uci','rpc','ui','dom','baseclass','_','window',source)(
 {}, {declare:()=>()=>Promise.resolve({})}, {}, {}, {extend:value=>value}, value=>value,
 {setTimeout,clearTimeout});
const bounded = promise => Promise.race([promise,new Promise((_,reject)=>setTimeout(()=>reject(new Error('test watchdog: readiness promise did not settle')),300))]);
(async()=>{
 let calls=0;
 const result=await bounded(utils.waitForServiceReady(()=>{calls++;return Promise.resolve({running:true,last_result:'success'});},{interval:2,timeout:25}));
 assert.equal(result.running,true);assert.equal(calls,1);
 await assert.rejects(bounded(utils.waitForServiceReady(()=>Promise.resolve({success:false,running:true,last_result:'success',error:'controlled status failure'}),{interval:2,timeout:25})),e=>e.code==='ServiceStatusError' && e.message==='controlled status failure');
 await assert.rejects(bounded(utils.waitForServiceReady(()=>Promise.resolve({success:false,running:true,error:'controlled status failure'}),{isReady:()=>true,interval:2,timeout:25})),e=>e.code==='ServiceStatusError');
 await assert.rejects(bounded(utils.waitForServiceReady(()=>Promise.resolve({running:'true',last_result:'success'}),{interval:2,timeout:12})),e=>e.code==='ServiceReadyTimeout');
 await assert.rejects(bounded(utils.waitForServiceReady(()=>Promise.resolve({running:false}),{interval:2,timeout:12})),e=>e.code==='ServiceReadyTimeout');
 await assert.rejects(bounded(utils.waitForServiceReady(()=>new Promise(()=>{}),{interval:2,timeout:12})),e=>e.code==='ServiceReadyTimeout');
 for (const flag of ['jobRunning','active_run']) {
  await assert.rejects(bounded(utils.waitForServiceReady(()=>Promise.resolve({running:true,[flag]:true}),{interval:2,timeout:12})),e=>e.code==='ServiceReadyTimeout');
 }
 calls=0;
 await assert.rejects(bounded(utils.waitForServiceReady(()=>{calls++;return Promise.resolve({running:true});},{isActive:()=>false,interval:2,timeout:25})),e=>e.code==='ServiceReadyCancelled');
 assert.equal(calls,0);
 let active=true;
 setTimeout(()=>{active=false;},5);
 await assert.rejects(bounded(utils.waitForServiceReady(()=>new Promise(()=>{}),{isActive:()=>active,interval:2,timeout:50})),e=>e.code==='ServiceReadyCancelled');
 await assert.rejects(bounded(utils.waitForServiceReady(()=>Promise.reject(new Error('network failed')),{interval:2,timeout:25})),/network failed/);
 let rejectLate;
 await assert.rejects(bounded(utils.waitForServiceReady(()=>new Promise((resolve,reject)=>{rejectLate=reject;}),{interval:2,timeout:12})),e=>e.code==='ServiceReadyTimeout');
 rejectLate(new Error('late network failure after timeout'));
 let pollingCalls=0;
 await assert.rejects(bounded(utils.waitForServiceReady(()=>{pollingCalls++;return Promise.resolve({running:false});},{interval:2,timeout:12})),e=>e.code==='ServiceReadyTimeout');
 const callsAtTimeout=pollingCalls;
 await new Promise(resolve=>setTimeout(resolve,15));
 assert.equal(pollingCalls,callsAtTimeout);
 console.log('PASS actual LuCI utils: ready, timeout, hanging RPC, cancellation and network rejection (module harness; not browser proof)');
})().catch(error=>{console.error(error);process.exitCode=1;});
