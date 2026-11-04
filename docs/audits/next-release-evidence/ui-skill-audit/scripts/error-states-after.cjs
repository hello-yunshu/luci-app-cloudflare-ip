const { chromium } = require('/tmp/cfip-ui/node_modules/playwright');
const { execSync } = require('node:child_process');
(async()=>{
 const b=await chromium.launch({headless:true,executablePath:'/Users/yunshu/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'});
 const c=await b.newContext({viewport:{width:1280,height:900}}); const p=await c.newPage();
 async function login(){ if(await p.locator('#luci_username').count()){await p.fill('#luci_username','root');await p.fill('#luci_password','cfip-gate');await Promise.all([p.waitForNavigation({waitUntil:'domcontentloaded',timeout:15000}).catch(()=>{}),p.click('button:has-text("Log in")')]);} }
 async function go(name){await p.goto(`http://127.0.0.1:18080/cgi-bin/luci/admin/services/cf_ip/${name}`,{waitUntil:'domcontentloaded'});await login();await p.waitForFunction(()=>{const m=document.querySelector('#maincontent');return m&&m.innerText.length>80&&!m.innerText.includes('Loading view')},{timeout:20000});await p.waitForTimeout(500);}
 try{
  execSync(`docker exec cfip-ui-gate sh -c "uci set luci.main.mediaurlbase='/luci-static/bootstrap'; uci commit luci; rm -rf /tmp/luci-indexcache*; /etc/init.d/uhttpd restart >/dev/null 2>&1"`,{stdio:'ignore'});
  await p.goto('http://127.0.0.1:18080/cgi-bin/luci/',{waitUntil:'domcontentloaded'}); await login();
  execSync(`docker exec cfip-ui-gate sh -c 'chmod 777 /etc/cf_ip'`);
  await go('logs');
  console.log('diag-error', await p.evaluate(()=>{const a=document.querySelector('.alert-message.danger');return a?a.innerText:null;}));
  await p.screenshot({path:'/tmp/cfip-audit-after/logs-error-after.png',fullPage:true});
  await p.setViewportSize({width:375,height:900}); await p.reload({waitUntil:'domcontentloaded'}); await p.waitForTimeout(800);
  await p.screenshot({path:'/tmp/cfip-audit-after/logs-error-375-after.png',fullPage:true});
  execSync(`docker exec cfip-ui-gate sh -c 'chmod 700 /etc/cf_ip'`);
  await p.setViewportSize({width:1280,height:900});
  execSync(`docker exec cfip-ui-gate sh -c "uci set cf_ip.openclash.config='/tmp/not-openclash.yaml'; uci commit cf_ip"`);
  await go('openclash');
  console.log('oc-error', await p.evaluate(()=>{const a=document.querySelector('.alert-message.error');return a?a.innerText:null;}));
  await p.screenshot({path:'/tmp/cfip-audit-after/openclash-error-after.png',fullPage:true});
 }finally{
  try{execSync(`docker exec cfip-ui-gate sh -c 'chmod 700 /etc/cf_ip; uci set cf_ip.openclash.config="/etc/openclash/config/config.yaml"; uci commit cf_ip'`,{stdio:'ignore'});}catch(e){}
  await b.close();
 }
})();
