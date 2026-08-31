(function(){
'use strict';
if(window.__PACELETICS_CLUB_ALL_EVENT_PBS__)return;
window.__PACELETICS_CLUB_ALL_EVENT_PBS__=true;

const cfg=window.PACELETICS_CONFIG||{};
const athleteId=new URLSearchParams(location.search).get('id');
if(!window.supabase||!cfg.supabaseUrl||!cfg.supabasePublishableKey||!athleteId)return;
const client=window.supabase.createClient(cfg.supabaseUrl,cfg.supabasePublishableKey);
const CATEGORY_ORDER=['Sprints','Middle Distance','Long Distance','Hurdles','Steeplechase','Race Walking','Jumps','Throws','Combined Events','Other'];

function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function fmtSeconds(sec){sec=Number(sec);if(!Number.isFinite(sec))return'—';if(sec<60)return sec.toFixed(2);if(sec<3600){const m=Math.floor(sec/60),s=sec-m*60;return m+':'+s.toFixed(2).padStart(5,'0')}const h=Math.floor(sec/3600),r=sec-h*3600,m=Math.floor(r/60),s=r-m*60;return h+':'+String(m).padStart(2,'0')+':'+s.toFixed(2).padStart(5,'0')}
function fallbackCategory(event){const e=String(event||'').toLowerCase();if(/decathlon|heptathlon|pentathlon|octathlon|triathlon/.test(e))return'Combined Events';if(/javelin|shot|discus|hammer|weight throw/.test(e))return'Throws';if(/long jump|triple jump|high jump|pole vault/.test(e))return'Jumps';if(/h$|hurdle/.test(e))return'Hurdles';if(/steeple/.test(e))return'Steeplechase';if(/walk/.test(e))return'Race Walking';const n=parseFloat(e);if(Number.isFinite(n)){if(n<=400)return'Sprints';if(n<=1609)return'Middle Distance';return'Long Distance'}return'Other'}
function display(p){if(p?.performance_display)return p.performance_display;const unit=(p?.performance_unit||'').toLowerCase(),value=Number(p?.performance_value);if(unit==='seconds'&&Number.isFinite(value))return fmtSeconds(value);if(unit==='metres'&&Number.isFinite(value))return value.toFixed(2)+'m';if(unit==='points'&&Number.isFinite(value))return Math.round(value)+' pts';if(Number.isFinite(Number(p?.time_seconds)))return fmtSeconds(p.time_seconds);return'—'}
function category(p){return p?.event_category||fallbackCategory(p?.event)}
function installStyles(){if(document.getElementById('allEventPbStyles'))return;const s=document.createElement('style');s.id='allEventPbStyles';s.textContent='.allEventPbGroups{display:grid;gap:13px}.allEventPbCategory{padding-top:3px}.allEventPbCategoryTitle{font-size:10px;text-transform:uppercase;letter-spacing:.8px;color:#ffc400;font-weight:1000;margin-bottom:7px}.allEventPbGrid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}.allEventPbCard{background:#0d192b;border:1px solid #273956;border-radius:11px;padding:10px}.allEventPbEvent{font-size:11px;color:#9caac0}.allEventPbValue{font-size:21px;font-weight:1000;margin-top:4px}.allEventPbMeta{font-size:9px;color:#7f91a8;margin-top:4px}.allEventPbSource{display:inline-block;margin-top:6px;padding:3px 6px;border-radius:999px;background:#123127;color:#77e5b1;font-size:8px;font-weight:900}@media(max-width:800px){.allEventPbGrid{grid-template-columns:repeat(2,minmax(0,1fr))}}';document.head.appendChild(s)}

async function run(){
  const list=document.getElementById('pbList');if(!list)return;
  let q=await client.from('personal_bests').select('event,time_seconds,achieved_on,source,performance_value,performance_unit,performance_display,event_category,power_of_10_updated_at').eq('athlete_id',athleteId);
  if(q.error&&/performance_value|performance_unit|performance_display|event_category|power_of_10_updated_at|schema cache|column/i.test(String(q.error.message||''))){q=await client.from('personal_bests').select('event,time_seconds,achieved_on,source').eq('athlete_id',athleteId)}
  if(q.error)return;
  const pbs=q.data||[];if(!pbs.length)return;
  installStyles();
  const groups={};pbs.forEach(p=>{const c=category(p);(groups[c]||(groups[c]=[])).push(p)});
  const cats=Object.keys(groups).sort((a,b)=>{const ai=CATEGORY_ORDER.indexOf(a),bi=CATEGORY_ORDER.indexOf(b);return(ai<0?999:ai)-(bi<0?999:bi)||a.localeCompare(b)});
  list.className='allEventPbGroups';
  list.innerHTML=cats.map(cat=>'<div class="allEventPbCategory"><div class="allEventPbCategoryTitle">'+esc(cat)+'</div><div class="allEventPbGrid">'+groups[cat].sort((a,b)=>String(a.event).localeCompare(String(b.event),undefined,{numeric:true})).map(p=>'<div class="allEventPbCard"><div class="allEventPbEvent">'+esc(p.event)+'</div><div class="allEventPbValue">'+esc(display(p))+'</div><div class="allEventPbMeta">'+(p.achieved_on?esc(p.achieved_on):'Date not recorded')+'</div>'+(p.source==='power_of_10_import'?'<span class="allEventPbSource">Power of 10</span>':'')+'</div>').join('')+'</div></div>').join('');
  const heading=list.closest('.card')?.querySelector('h3');if(heading)heading.textContent='Personal bests · All events';
  const primaryName=(document.getElementById('athleteMeta')?.textContent||'').split(' · ').pop();
  const primary=pbs.find(p=>p.event===primaryName);if(primary&&document.getElementById('primaryPb'))document.getElementById('primaryPb').textContent=display(primary);
}

function whenReady(){let tries=0;const timer=setInterval(()=>{tries++;const loading=document.getElementById('loading');if((loading?.classList.contains('hidden')||!loading)&&document.getElementById('pbList')){clearInterval(timer);run()}else if(tries>80)clearInterval(timer)},100)}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',whenReady,{once:true});else whenReady();
})();
