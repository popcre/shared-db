const E=require('exceljs');const rows=require('./rows.json');const fs=require('fs');
const subs={};for(const r of rows.filter(r=>r.p==='Submissions'))(subs[r.g+'|'+r.l]=subs[r.g+'|'+r.l]||[]).push(r);
const w=new E.Workbook();w.xlsx.readFile(process.env.WORKBOOK).then(()=>{const m=w.worksheets[0];
const v=c=>{const x=c.value;return x&&typeof x==='object'?(x.result??x.richText?.map(t=>t.text).join('')??null):x};
const out={map:[],excl:[],left:[]};const amb=[];
m.eachRow((r,i)=>{if(i===1)return;const g=v(r.getCell(1)),l=v(r.getCell(2)),sys=v(r.getCell(3)),id=v(r.getCell(4));
 let maps=[5,6,7].map(c=>v(r.getCell(c))).filter(x=>x&&!String(x).startsWith('(no Submissions'));const reason=v(r.getCell(8)),note=v(r.getCell(9));
 const base={row:i,g,l,sys,id,reason,note,maps};const live=rows.find(x=>x.id===id&&x.sys===sys&&x.p==='Creative');if(!live){out.gone=(out.gone||0)+1;return}base.tbl=live.tbl;if(live.st!=='unmapped'){out.already=(out.already||0)+1;return}
 if(maps.length&&!reason){const t=maps.map(x=>subs[g+'|'+x]||[]);if(t.some(a=>a.length!==1)){amb.push(base);out.left.push({...base,why:'Submissions name matches '+t.map(a=>a.length).join('/')+' entries'});return}
   out.map.push({...base,targets:[...new Map(t.map(a=>[a[0].tbl+a[0].id,{sys:a[0].sys,tbl:a[0].tbl,id:a[0].id,l:a[0].l}])).values()]});}
 else if(!maps.length&&reason&&!['Need more information','No matching Submissions property exists'].includes(reason))out.excl.push(base);
 else out.left.push({...base,why:!maps.length&&!reason?'blank':['Need more information','No matching Submissions property exists'].includes(reason)?reason.toLowerCase():'both a match and a reason'});});
fs.writeFileSync('decisions.json',JSON.stringify(out,null,1));
console.log('map',out.map.length,'excl',out.excl.length,'gone',out.gone,'already',out.already,'left',out.left.length,'amb',amb.length);
const reasons={};out.excl.forEach(x=>reasons[x.reason]=(reasons[x.reason]||0)+1);console.log(reasons);
console.log(amb.map(a=>a.g+' | '+a.maps.join(',')).slice(0,10))})
