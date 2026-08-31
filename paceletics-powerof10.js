(function(){
'use strict';
const SUPABASE_URL='https://ilsryvkrdjbnyieixetr.supabase.co';
const SUPABASE_KEY='sb_publishable_aJEx3hoeS3gA8cCq1vwbWA_yG8QItxW';
if(!window.supabase)return;
const p10sb=window.supabase.createClient(SUPABASE_URL,SUPABASE_KEY);
const $=id=>document.getElementById(id);
let currentPowerUrl=null;

function addStyles(){
  if($('paceleticsP10Styles'))return;
  const s=document.createElement('style');
  s.id='paceleticsP10Styles';
  s.textContent='.p10Panel{margin-bottom:12px}.p10Row{display:grid;grid-template-columns:minmax(0,1fr) minmax(320px,.9fr);gap:16px;align-items:center}.p10Status{font-size:17px;font-weight:1000;margin:4px 0}.p10Meta{font-size:9px;color:#8195ad;margin-top:5px}.p10Actions{display:grid;grid-template-columns:1fr auto;gap:8px;align-items:end}.p10Open{display:inline-flex;align-items:center;justify-content:center;margin-top:10px;text-decoration:none}.p10Note{margin-top:7px;font-size:8px;line-height:1.45;color:#71859e}@media(max-width:900px){.p10Row{grid-template-columns:1fr}.p10Actions{grid-template-columns:1fr}}';
  document.head.appendChild(s);
}

function makePanel(){
  if($('powerOf10Panel'))return;
  const kpis=document.querySelector('#view-dashboard .kpis');
  if(!kpis)return;
  const panel=document.createElement('div');
  panel.id='powerOf10Panel';
  panel.className='card p10Panel';
  panel.innerHTML='<div class="cardHead"><div><div class="cardTitle">Power of 10</div><div class="subtitle">Link your official athlete profile.</div></div><span id="p10Badge" class="sourceBadge">Not linked</span></div><div class="p10Row"><div><div id="p10Status" class="p10Status">No Power of 10 profile linked</div><div id="p10Meta" class="p10Meta">Add your profile URL once. Your PBs remain in the normal Personal Bests area.</div><a id="p10Open" class="secondaryBtn p10Open hidden" target="_blank" rel="noopener noreferrer">View Power of 10 profile ↗</a></div><div><div class="field"><label>Power of 10 profile URL</label><input id="p10Url" type="url" autocomplete="url" placeholder="https://www.powerof10.uk/Home/Athlete/..."></div><div class="p10Actions"><button id="p10SaveBtn" class="btn btnPrimary" type="button">Save profile link</button><button id="p10RemoveBtn" class="btn btnSecondary hidden" type="button">Remove</button></div><div id="p10Message" class="formMsg"></div><div class="p10Note">Paceletics stores the profile link only. The separate Power of 10 PB entry form has been removed.</div></div></div>';
  kpis.insertAdjacentElement('afterend',panel);
  $('p10SaveBtn').onclick=saveProfile;
  $('p10RemoveBtn').onclick=removeProfile;
}

function validUrl(raw){
  try{
    const u=new URL(raw),host=u.hostname.toLowerCase();
    return u.protocol==='https:'&&(host==='powerof10.uk'||host==='www.powerof10.uk')&&/^\/Home\/Athlete\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:[/?#].*)?$/i.test(u.pathname+u.search+u.hash);
  }catch{return false}
}
function setMessage(text,bad=false){const m=$('p10Message');if(!m)return;m.textContent=text||'';m.className='formMsg '+(text?(bad?'bad':'good'):'')}

function showState(data){
  const linked=!!data?.power_of_10_url;
  currentPowerUrl=data?.power_of_10_url||null;
  $('p10Url').value=currentPowerUrl||'';
  $('p10Status').textContent=linked?'Power of 10 profile linked ✓':'No Power of 10 profile linked';
  $('p10Badge').textContent=linked?'Linked':'Not linked';
  $('p10Badge').className='sourceBadge'+(linked?' coach':'');
  $('p10RemoveBtn').classList.toggle('hidden',!linked);
  $('p10Open').classList.toggle('hidden',!linked);
  if(linked){
    $('p10Open').href=currentPowerUrl;
    const id=data?.power_of_10_athlete_id||'';
    const date=data?.power_of_10_linked_at?new Date(data.power_of_10_linked_at).toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'numeric'}):'';
    $('p10Meta').textContent=[id?'Athlete ID: '+id:'',date?'Linked '+date:''].filter(Boolean).join(' · ');
  }else{
    $('p10Open').removeAttribute('href');
    $('p10Meta').textContent='Add your profile URL once. Your PBs remain in the normal Personal Bests area.';
  }
}

async function loadState(){
  try{
    const s=await p10sb.auth.getSession(),user=s.data?.session?.user;
    if(!user)return;
    const q=await p10sb.from('athletes').select('id,power_of_10_url,power_of_10_athlete_id,power_of_10_linked_at').eq('linked_user_id',user.id).eq('is_active',true).maybeSingle();
    if(q.error)throw q.error;
    if(q.data)showState(q.data);
  }catch(e){setMessage('Could not load Power of 10 link: '+(e.message||String(e)),true)}
}

async function saveProfile(){
  const raw=$('p10Url').value.trim(),btn=$('p10SaveBtn');
  try{
    if(!raw)throw new Error('Paste your Power of 10 athlete profile URL.');
    if(!validUrl(raw))throw new Error('Use the athlete profile URL from powerof10.uk.');
    btn.disabled=true;btn.textContent='Saving…';setMessage('');
    const q=await p10sb.rpc('save_my_power_of_10_profile',{p_url:raw});
    if(q.error)throw q.error;
    showState(q.data);
    setMessage('Power of 10 profile linked.');
  }catch(e){setMessage(e.message||String(e),true)}finally{btn.disabled=false;btn.textContent='Save profile link'}
}

async function removeProfile(){
  if(!window.confirm('Remove the Power of 10 link from your Paceletics profile?'))return;
  const btn=$('p10RemoveBtn');
  try{
    btn.disabled=true;setMessage('');
    const q=await p10sb.rpc('save_my_power_of_10_profile',{p_url:null});
    if(q.error)throw q.error;
    showState(q.data);
    setMessage('Power of 10 profile link removed.');
  }catch(e){setMessage(e.message||String(e),true)}finally{btn.disabled=false}
}

async function boot(){if(!document.getElementById('view-dashboard'))return;addStyles();makePanel();await loadState()}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
