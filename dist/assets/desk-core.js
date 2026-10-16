(function (root) {
'use strict';
const STATES=['New','Needs action','Waiting for customer','Waiting for team','Resolved'];
const FIELDS={externalRef:'Reference',customer:'Customer',contact:'Contact',category:'Category',subject:'Subject',summary:'Summary',source:'Source',remedy:'Requested remedy',owner:'Owner',state:'State',nextAction:'Next action',due:'Next due',waitingReason:'Waiting reason'};
const trim=v=>String(v??'').trim();
const ref=v=>trim(v).toLowerCase();
const now=()=>new Date().toISOString();
function dueDate(value,date1904=false){
 if(value===null||value===undefined||value==='')return '';
 if(typeof value==='number'){
  if(!Number.isFinite(value)||value<=0)throw Error('Invalid Excel date.');
  const epoch=Date.UTC(1899,11,30)+(date1904?1462*86400000:0);
  const d=new Date(epoch+Math.round(value*86400000));
  if(!Number.isFinite(d.getTime()))throw Error('Invalid Excel date.');
  const local=new Date(d.getUTCFullYear(),d.getUTCMonth(),d.getUTCDate(),d.getUTCHours(),d.getUTCMinutes(),d.getUTCSeconds());
  if(value===Math.floor(value))local.setHours(23,59,0,0);
  return local.toISOString();
 }
 if(value instanceof Date){if(!Number.isFinite(value.getTime()))throw Error('Invalid date.');return value.toISOString();}
 const s=trim(value);
 const m=s.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})?)?$/);
 if(!m)throw Error('Use YYYY-MM-DD or an ISO date/time; ambiguous dates need correction.');
 const y=+m[1],mo=+m[2],day=+m[3],h=m[4]===undefined?23:+m[4],mi=m[5]===undefined?59:+m[5],sec=+(m[6]||0);
 const check=new Date(Date.UTC(y,mo-1,day));
 if(y<1900||y>2200||check.getUTCFullYear()!==y||check.getUTCMonth()!==mo-1||check.getUTCDate()!==day||h>23||mi>59||sec>59)throw Error('Invalid date or time.');
 if(m[7]&&!/^(Z|[+-](?:0\d|1[0-4]):[0-5]\d)$/.test(m[7]))throw Error('Invalid timezone offset.');
 const d=m[7]?new Date(s):new Date(y,mo-1,day,h,mi,sec);
 if(!Number.isFinite(d.getTime()))throw Error('Invalid date.');
 return d.toISOString();
}
function clean(input){
 const c={};for(const key of Object.keys(FIELDS))c[key]=key==='due'?dueDate(input[key]):trim(input[key]);
 c.category=c.category||'Enquiry';c.state=c.state||'New';c.source=c.source||'Manual';
 return c;
}
function validate(c){
 if(!c.customer||!c.subject||!c.summary)throw Error('Customer, subject and summary are required.');
 if(!['Enquiry','Complaint'].includes(c.category))throw Error('Category must be Enquiry or Complaint.');
 if(!STATES.includes(c.state))throw Error('Choose a valid state.');
 if(c.state!=='New'&&c.state!=='Resolved'&&(!c.owner||!c.nextAction||!c.due))throw Error('An active case needs an owner, next action and due date.');
 if(c.state.startsWith('Waiting')&&!c.waitingReason)throw Error('Add a reason for waiting.');
 if(c.state==='Resolved'&&!c.resolution)throw Error('Resolve the case with an outcome and completion confirmation.');
}
function newCase(input,id,at=now()){
 const c=clean(input);validate(c);
 return {...c,id,createdAt:at,updatedAt:at,escalated:false,escalationReason:'',draft:'',resolution:'',timeline:[{at,type:'Created',text:`${c.category} received via ${c.source}. ${c.summary}`} ]};
}
function apply(c,action,payload={},at=now()){
 const next={...c,timeline:c.timeline.slice()};let type,text;
 if(action==='update'){
  const cleaned=clean({...c,...payload});Object.assign(next,cleaned);
  if(next.state==='Resolved'&&c.state!=='Resolved')throw Error('Use Resolve case to record the outcome.');
  if(c.state==='Resolved'&&next.state!=='Resolved')throw Error('Use Reopen case to retain closure history.');
  validate(next);
  const changes=Object.keys(FIELDS).filter(k=>next[k]!==c[k]).map(k=>`${FIELDS[k]}: ${c[k]||'—'} → ${next[k]||'—'}`);
  if(!changes.length)throw Error('No changes to save.');
  type='Updated';text=changes.join('\n');
 }else if(action==='note'){
  text=trim(payload.text);if(!text)throw Error('Write a note first.');
  type=payload.kind==='Customer update'?'Customer update':'Internal note';
 }else if(action==='draft'){
  text=trim(payload.text);if(!text)throw Error('Write a draft first.');next.draft=text;type='Draft saved';
 }else if(action==='sent'){
  text=trim(payload.text);if(!payload.confirmed||!text)throw Error('Confirm that this message was already sent outside the demo.');
  type='Sent message recorded';next.draft='';
 }else if(action==='escalate'){
  text=trim(payload.reason);if(!text||!next.owner)throw Error('Escalation needs a reason and assigned owner.');
  next.escalated=true;next.escalationReason=text;type='Escalated';
 }else if(action==='resolve'){
  text=trim(payload.outcome);if(!text||!payload.confirmed)throw Error('Add the outcome and confirm completion before resolving.');
  next.state='Resolved';next.resolution=text;next.escalated=false;type='Resolved';
 }else if(action==='reopen'){
  if(c.state!=='Resolved')throw Error('Only resolved cases can be reopened.');
  text=trim(payload.reason);if(!text)throw Error('Add a reason for reopening.');
  Object.assign(next,{state:'Needs action',owner:trim(payload.owner||c.owner),nextAction:trim(payload.nextAction),due:dueDate(payload.due),waitingReason:''});
  validate(next);type='Reopened';
 }else throw Error('Unknown case action.');
 next.updatedAt=at;next.timeline.push({at,type,text});return next;
}
function overdue(c,at=Date.now()){return c.state!=='Resolved'&&!!c.due&&Date.parse(c.due)<Number(at);}
function filter(cases,f={},at=Date.now()){
 return cases.filter(c=>(!f.openOnly||c.state!=='Resolved')&&(!f.state||c.state===f.state)&&(!f.owner||c.owner===f.owner)&&(!f.category||c.category===f.category)&&(!f.overdue||overdue(c,at))&&(!f.unassigned||!c.owner)&&(!f.from||c.due&&c.due>=dueDate(f.from+'T00:00'))&&(!f.to||c.due&&c.due<=dueDate(f.to+'T23:59'))&&(!f.search||[c.id,c.externalRef,c.customer,c.subject,c.summary].join(' ').toLowerCase().includes(f.search.toLowerCase())));
}
function counts(cases,at=Date.now()){const open=cases.filter(c=>c.state!=='Resolved');return {open:open.length,enquiries:open.filter(c=>c.category==='Enquiry').length,complaints:open.filter(c=>c.category==='Complaint').length,overdue:open.filter(c=>overdue(c,at)).length,unassigned:open.filter(c=>!c.owner).length};}
function cellValue(cell,date1904){
 if(cell===null||cell===undefined)return '';
 if(typeof cell==='object'&&!(cell instanceof Date)){
  if(cell.f&&(cell.v===undefined||cell.v===null))throw Error('Formula has no cached value; save calculated values in Excel first.');
  if(cell.t==='e')throw Error('Spreadsheet error cell needs correction.');
  return cell.v??'';
 }
 return cell;
}
function reviewImport(matrix,header,mapping,cases,date1904=false){
 if(matrix.length-header-1>2000)throw Error('Use at most 2,000 data rows per import.');
 const used=new Set(cases.map(c=>ref(c.externalRef)).filter(Boolean)),result=[];
 for(let i=header+1;i<matrix.length;i++){
  if(!matrix[i].some(c=>trim(typeof c==='object'?c?.v:c)||(c&&typeof c==='object'&&(c.f||c.t==='e'))))continue;
  const input={},errors=[];
  for(const key of Object.keys(FIELDS))if(mapping[key]!==undefined&&mapping[key]!==''){
   try{const value=cellValue(matrix[i][+mapping[key]]);input[key]=key==='due'?dueDate(value,date1904):trim(value);}catch(e){errors.push(`${FIELDS[key]}: ${e.message}`);}
  }
  // Imported closure evidence is not sufficient to resolve a case automatically.
  if(input.state==='Resolved')errors.push('Import open cases only; record resolution with confirmation in the workspace.');
  let data;try{data=clean(input);validate(data);}catch(e){errors.push(e.message);}
  const key=ref(input.externalRef),duplicate=!!key&&used.has(key);
  if(duplicate)errors.push('Duplicate reference: skipped; existing case will not be changed.');
  if(!errors.length&&key)used.add(key);
  result.push({row:i+1,data: data||input,errors,valid:errors.length===0});
 }
 return result;
}
function exportRows(cases){return cases.map(c=>({'Case ID':c.id,Reference:c.externalRef,Customer:c.customer,Contact:c.contact,Category:c.category,Subject:c.subject,Summary:c.summary,Source:c.source,'Requested remedy':c.remedy,Owner:c.owner,State:c.state,'Next action':c.nextAction,'Next due (UTC)':c.due,'Waiting reason':c.waitingReason,Escalated:c.escalated?'Yes':'No','Escalation reason':c.escalationReason,'Last updated (UTC)':c.updatedAt}));}
function sampleCases(at=Date.now()){
 const dt=hours=>new Date(at+hours*3600000).toISOString();
 const base={customer:'Maya Chen',contact:'maya@example.invalid',category:'Enquiry',subject:'Where is order #1042?',summary:'Delivery has not arrived. Customer would like an update.',source:'Email',owner:'Alex',nextAction:'Check delivery status with the courier',due:dt(3),state:'Needs action',externalRef:'ORDER-1042'};
 const specs=[base,{...base,externalRef:'ORDER-1037',customer:'Noah Williams',category:'Complaint',subject:'Damaged packaging on arrival',summary:'Customer reports a broken part in the package.',owner:'Sam',state:'Waiting for team',waitingReason:'Warehouse inspecting the replacement stock',nextAction:'Follow up with warehouse',due:dt(-4)}, {...base,externalRef:'ENQ-206',customer:'Aria Patel',subject:'Product compatibility',summary:'Customer asks whether the adapter fits their device.',owner:'Alex',state:'Waiting for customer',waitingReason:'Awaiting the device model',nextAction:'Check whether customer supplied the model',due:dt(-2)}, {...base,externalRef:'ENQ-207',customer:'Leo Martin',subject:'Quote for 12 units',summary:'New business enquiry received through the contact form.',owner:'',nextAction:'',due:'',state:'New',source:'Web form'}, {...base,externalRef:'CMP-208',customer:'Isla Wilson',category:'Complaint',subject:'Incorrect item in delivery',summary:'Customer received the wrong colour. Replacement requested.',owner:'Sam',nextAction:'Confirm replacement dispatch',due:dt(25)}, {...base,externalRef:'ENQ-209',customer:'Ethan Brown',subject:'Invoice copy needed',summary:'Customer needs a copy of their receipt.',owner:'Alex',nextAction:'Send receipt copy',due:dt(6)}];
 return specs.map((s,i)=>newCase(s,`RD-${101+i}`,dt(-24-i)));
}
const api={STATES,FIELDS,dueDate,newCase,apply,overdue,filter,counts,reviewImport,exportRows,sampleCases};
if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.ResponseDesk=api;
})(typeof globalThis!=='undefined'?globalThis:this);
