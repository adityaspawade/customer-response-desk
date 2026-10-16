(function(root){
'use strict';
function create(client){
 let metadata=new Map();
 function failure(error){if(error?.code==='23505')throw Error('That case reference or ID already exists. Refresh the queue and review the import again.');throw Error(error?.message||'The database could not be reached. Your changes have not been confirmed as saved.');}
 function remember(rows){for(const row of rows)metadata.set(row.data.id,{id:row.id,version:row.version});return rows.map(row=>row.data);}
 async function profile(){const {data,error}=await client.rpc('desk_profile');if(error)failure(error);if(!data?.role)throw Error('This account has no pilot access. Ask the pilot owner to add your confirmed email.');return data;}
 async function load(){const all=[];for(let offset=0;offset<2500;offset+=500){const {data,error,count}=await client.from('desk_cases').select('id,data,version,updated_at',{count:'exact'}).order('id').range(offset,offset+499);if(error)failure(error);if(count>2500)throw Error('This pilot supports 2,500 cases. Ask the owner to arrange an archive before continuing.');all.push(...data);if(data.length<500)break;}metadata=new Map();return remember(all);}
 async function save(records){
  const existing=records.filter(c=>metadata.has(c.id)),fresh=records.filter(c=>!metadata.has(c.id));
  if(existing.length&&(fresh.length||existing.length>1))throw Error('Save one existing case at a time.');
  if(fresh.length){const {data,error}=await client.from('desk_cases').insert(fresh.map(c=>({data:c}))).select('id,data,version');if(error)failure(error);if(data.length!==fresh.length)throw Error('The database did not confirm every imported case. Refresh before retrying.');return remember(data);}
  if(existing.length){const c=existing[0],meta=metadata.get(c.id);const {data,error}=await client.from('desk_cases').update({data:c,version:meta.version+1}).eq('id',meta.id).eq('version',meta.version).select('id,data,version').maybeSingle();if(error)failure(error);if(!data){const e=Error('This case changed in another session, or your access changed. Copy your unsaved text, refresh the queue, and review the latest case before trying again.');e.code='CONFLICT';throw e;}return remember([data]);}
  return [];
 }
 async function members(input){const {data,error}=await client.rpc('desk_manage_access',input||{});if(error)failure(error);return data;}
 return {profile,load,save,members};
}
const api={create};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.ResponseDeskCloud=api;
})(typeof globalThis!=='undefined'?globalThis:this);
