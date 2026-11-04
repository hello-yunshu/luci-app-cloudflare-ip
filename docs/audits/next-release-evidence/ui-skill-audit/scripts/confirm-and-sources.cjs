const { chromium } = require('/tmp/cfip-ui/node_modules/playwright');
const { execSync } = require('node:child_process');
(async()=>{
 execSync(`docker exec cfip-ui-gate sh -c "uci set luci.main.mediaurlbase='/luci-static/bootstrap'; uci commit luci; rm -rf /tmp/luci-indexcache*; /etc/init.d/uhttpd restart >/dev/null 2>&1"`,{stdio:'ignore'});
 const b=await chromium.launch({headless:true,executablePath:'/Users/yunshu/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'});
 const c=await b.newContext({viewport:{width:375,height:900}}); const p=await c.newPage();
 await p.goto('http://127.0.0.1:18080/cgi-bin/luci/',{waitUntil:'domcontentloaded'});
 if(await p.locator('#luci_username').count()){await p.fill('#luci_username','root');await p.fill('#luci_password','cfip-gate');await Promise.all([p.waitForNavigation({waitUntil:'domcontentloaded',timeout:15000}).catch(()=>{}),p.click('button:has-text("Log in")')]);}
 async function go(name){await p.goto(`http://127.0.0.1:18080/cgi-bin/luci/admin/services/cf_ip/${name}`,{waitUntil:'domcontentloaded'});await p.waitForFunction(()=>{const m=document.querySelector('#maincontent');return m&&m.innerText.length>80&&!m.innerText.includes('Loading view')},{timeout:20000});await p.waitForTimeout(500);}
 await go('sources');
 console.log('sources-label', await p.evaluate(()=>{const l=document.querySelector('.cbi-dropdown li label');return l?l.innerText:null;}));
 await p.screenshot({path:'/tmp/cfip-audit-final2-sources-375.png',fullPage:false});
 execSync(`docker exec cfip-ui-gate sh -c 'printf "proxies: []\\n" > /etc/openclash/config/config.yaml.bak.20261104120000; chmod 600 /etc/openclash/config/config.yaml.bak.20261104120000'`);
 await go('openclash');
 const del=p.locator('#oc-backups-section button:has-text("Delete")').first();
 await del.click(); await p.waitForTimeout(200);
 console.log('delete-modal', await p.evaluate(()=>document.querySelector('.modal')?.innerText||document.body.innerText.split('Confirm Delete').pop()));
 await p.screenshot({path:'/tmp/cfip-audit-final2-delete-modal.png',fullPage:false});
 await p.locator('.modal button:has-text("Cancel")').click(); await p.waitForTimeout(200);
 const res=p.locator('#oc-backups-section button:has-text("Restore")').first();
 await res.click(); await p.waitForTimeout(200);
 console.log('restore-modal', await p.evaluate(()=>document.querySelector('.modal')?.innerText||null));
 await p.screenshot({path:'/tmp/cfip-audit-final2-restore-modal.png',fullPage:false});
 execSync(`docker exec cfip-ui-gate sh -c 'rm -f /etc/openclash/config/config.yaml.bak.20261104120000'`);
 await b.close();
})();
