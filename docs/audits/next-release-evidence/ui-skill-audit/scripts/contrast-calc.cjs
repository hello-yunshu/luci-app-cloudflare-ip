const Color=require('/tmp/cfip-ui/node_modules/colorjs.io').default;
const fs=require('node:fs');
const raw=JSON.parse(fs.readFileSync('/tmp/cfip-audit/contrast-raw.json'));
const out=[];
function c(str){try{const x=new Color(str);if(x.alpha===undefined)x.alpha=1;return x;}catch(e){return null;}}
for(const page of raw){
  for(const it of page.items){
    let base=page.dark?c('#0f172a'):c('#ffffff');
    // prefer explicit body background from chain (first bgs entry is html if present)
    if(it.bgs.length){
      const first=c(it.bgs[0]);
      if(first&&first.alpha>0) base=first;
    }
    let bg=base;
    for(const s of it.bgs){const x=c(s);if(x&&x.alpha>0){bg=Color.mix(bg,x,x.alpha,'srgb');}}
    const fg=c(it.fg); if(!fg) continue;
    let fgOpaque=fg;
    if(fg.alpha<1) fgOpaque=Color.mix(bg,fg,fg.alpha,'srgb');
    const ratio=Math.round(Color.contrast(fgOpaque,bg,'WCAG21')*100)/100;
    const need=(it.fs>=24||(it.fs>=18.66&&it.fw>=700))?3:4.5;
    if(ratio<need) out.push({theme:page.theme,page:page.page,text:it.text,cls:it.cls,path:it.path,fg:it.fg,bg:String(bg),ratio,need,fs:it.fs,fw:it.fw});
  }
}
fs.writeFileSync('/tmp/cfip-audit/contrast-failures.json',JSON.stringify(out,null,2));
console.log('failures',out.length);
const uniq={}; for(const x of out){const k=[x.theme,x.page,x.text,x.cls,x.ratio].join('|');uniq[k]=(uniq[k]||0)+1;}
Object.entries(uniq).sort((a,b)=>a[0].localeCompare(b[0])).slice(0,40).forEach(([k,v])=>console.log(k,'count',v));
