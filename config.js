window.PACELETICS_CONFIG = {
  supabaseUrl: "https://ilsryvkrdjbnyieixetr.supabase.co",
  supabasePublishableKey: "sb_publishable_aJEx3hoeS3gA8cCq1vwbWA_yG8QItxW"
};

// Reuse the stored Supabase session for Paceletics pages.
(function patchSupabaseCreateClient(){
  if(!window.supabase||typeof window.supabase.createClient!=='function')return;
  const original=window.supabase.createClient;
  if(original.__paceleticsPatched)return;
  function patched(...args){
    const client=original(...args);
    if(client?.auth&&typeof client.auth.getSession==='function'){
      client.auth.getUser=async()=>{
        try{
          const {data,error}=await client.auth.getSession();
          return {data:{user:data?.session?.user||null},error:error||null};
        }catch(error){return {data:{user:null},error}}
      };
    }
    return client;
  }
  patched.__paceleticsPatched=true;
  window.supabase.createClient=patched;
})();

// Athlete profile links for the cloud dashboard.
(function installAthleteProfileLinks(){
  function enhance(){
    document.querySelectorAll('#athleteRows tr').forEach(row=>{
      if(row.dataset.profileEnhanced==='1')return;
      const del=row.querySelector('[data-delete-athlete]');
      const first=row.querySelector('td');
      if(!del||!first)return;
      const id=del.getAttribute('data-delete-athlete');
      const strong=first.querySelector('strong');
      if(!id||!strong)return;
      strong.style.cursor='pointer';
      strong.style.textDecoration='underline';
      strong.style.textDecorationColor='#ffb000';
      strong.title='Open athlete profile';
      strong.addEventListener('click',()=>location.href='athlete.html?id='+encodeURIComponent(id));
      const b=document.createElement('button');
      b.className='btn secondary';
      b.textContent='Profile';
      b.style.marginRight='6px';
      b.addEventListener('click',()=>location.href='athlete.html?id='+encodeURIComponent(id));
      del.parentNode.insertBefore(b,del);
      row.dataset.profileEnhanced='1';
    });
  }
  function install(){
    enhance();
    const target=document.getElementById('athleteRows');
    if(target)new MutationObserver(enhance).observe(target,{childList:true,subtree:true});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();

// Open the current Session Builder from the dashboard.
(function installSessionBuilderLinks(){
  function install(){
    ['buildBtn','buildInline'].forEach(id=>{
      const el=document.getElementById(id);if(!el)return;
      el.addEventListener('click',e=>{
        e.preventDefault();e.stopImmediatePropagation();
        location.href='session-builder.html?v=0.8.9';
      },true);
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();

// Open the friendly result-entry page from the dashboard.
(function installResultEntryLink(){
  function install(){
    const el=document.getElementById('logResultBtn');if(!el)return;
    el.addEventListener('click',e=>{
      e.preventDefault();e.stopImmediatePropagation();
      location.href='result-entry.html?v=0.9.0';
    },true);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();

// Fallback only: add Performance Dashboard card if an older dashboard does not already include it.
(function installPerformanceDashboardLink(){
  function install(){
    const grid=document.querySelector('#view-stats .grid');
    if(!grid||document.getElementById('performanceDashboardCard')||grid.querySelector('button[onclick*="performance.html"]'))return;
    const card=document.createElement('div');
    card.id='performanceDashboardCard';card.className='card span12';
    card.innerHTML='<div class="row"><div><h3 style="margin:0 0 4px">Performance Dashboard</h3><div class="muted">Compare like-for-like rep distances, pace trends, RPE and consistency.</div></div><button id="openPerformanceBtn" class="btn primary" type="button">Open Performance</button></div>';
    grid.insertBefore(card,grid.firstChild);
    document.getElementById('openPerformanceBtn').onclick=()=>location.href='performance.html?v=0.9.2';
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();

// v0.9.4: Role-aware dashboard controls, including Club Management.
(function installRoleAwareDashboard(){
  if(!/dashboard\.html$/i.test(location.pathname))return;
  const validRoles=['athlete','coach','club'];
  const roleTitle={athlete:'Athlete',coach:'Coach',club:'Club'};
  const hide=el=>{if(el)el.style.display='none'};
  const show=el=>{if(el)el.style.display=''};

  async function applyRole(){
    try{
      const cfg=window.PACELETICS_CONFIG||{};
      if(!window.supabase||!cfg.supabaseUrl||!cfg.supabasePublishableKey)return;
      const client=window.supabase.createClient(cfg.supabaseUrl,cfg.supabasePublishableKey);
      const {data:sessionData}=await client.auth.getSession();
      const authUser=sessionData?.session?.user;if(!authUser)return;

      let profile=null;
      try{
        const q=await client.from('profiles').select('id,full_name,role').eq('id',authUser.id).maybeSingle();
        if(!q.error)profile=q.data||null;
      }catch(e){}

      const metadata=authUser.user_metadata||{};
      let role=profile?.role||metadata.account_type||metadata.role||'athlete';
      if(!validRoles.includes(role))role='athlete';
      const displayName=profile?.full_name||metadata.full_name||authUser.email||'';
      const label=roleTitle[role]||'Athlete';

      document.documentElement.dataset.accountRole=role;
      window.PACELETICS_ACCOUNT_ROLE=role;

      const sideBrand=document.querySelector('.side .brand .muted');
      if(sideBrand)sideBrand.textContent=label+' Dashboard · Cloud';
      const version=document.querySelector('.version');
      if(version)version.innerHTML='Beta v0.9.4<br>Plan. Train. Improve.';

      const banner=document.querySelector('.banner');
      if(banner&&!document.getElementById('accountRoleLine')){
        const line=document.createElement('div');
        line.id='accountRoleLine';line.className='muted';line.style.marginTop='5px';
        line.textContent=(displayName?displayName+' · ':'')+label+' account';
        banner.appendChild(line);
      }

      const actions=document.querySelector('.top .actions');
      if(role==='club'&&actions&&!document.getElementById('clubManagementBtn')){
        const b=document.createElement('button');
        b.id='clubManagementBtn';b.className='btn secondary';b.type='button';
        b.textContent='Club Management';
        b.onclick=()=>location.href='club.html?v=0.9.4';
        const logout=document.getElementById('logoutBtn');
        actions.insertBefore(b,logout||null);
      }

      if(role==='athlete'){
        ['addAthleteBtn','buildBtn','addAthleteInline','buildInline'].forEach(id=>hide(document.getElementById(id)));
        document.querySelectorAll('[data-view="athletes"]').forEach(hide);
        document.getElementById('view-athletes')?.classList.add('hidden');
        const sessionsHelp=document.querySelector('#view-sessions .muted');
        if(sessionsHelp)sessionsHelp.textContent='Your assigned training sessions.';
        const resultsHelp=document.querySelector('#view-results .muted');
        if(resultsHelp)resultsHelp.textContent='Log and review your training results.';
        const removeDelete=()=>document.querySelectorAll('[data-delete-athlete]').forEach(hide);
        removeDelete();
        const rows=document.getElementById('athleteRows');
        if(rows)new MutationObserver(removeDelete).observe(rows,{childList:true,subtree:true});
        try{
          const aq=await client.from('athletes').select('id').eq('linked_user_id',authUser.id).limit(1);
          const linked=aq.data?.[0];
          if(linked&&actions&&!document.getElementById('myProfileBtn')){
            const b=document.createElement('button');b.id='myProfileBtn';b.className='btn secondary';b.textContent='My Profile';
            b.onclick=()=>location.href='athlete.html?id='+encodeURIComponent(linked.id);
            actions.insertBefore(b,document.getElementById('logoutBtn')||null);
          }else if(!linked&&banner&&!document.getElementById('athleteLinkNotice')){
            const note=document.createElement('div');note.id='athleteLinkNotice';note.className='muted';note.style.marginTop='5px';
            note.textContent='This athlete account is not linked to an athlete profile yet.';banner.appendChild(note);
          }
        }catch(e){}
      }else{
        ['addAthleteBtn','buildBtn','addAthleteInline','buildInline'].forEach(id=>show(document.getElementById(id)));
      }
    }catch(e){console.warn('Paceletics role display could not be applied.',e)}
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',applyRole);else applyRole();
})();

// v0.8.8+: Date is optional in Session Builder.
(function installOptionalSessionDate(){
  if(!/session-builder\.html$/i.test(location.pathname))return;
  function install(){
    const date=document.getElementById('date'),saveBtn=document.getElementById('saveBtn');
    if(!date||!saveBtn)return;
    const holder=date.parentElement,label=holder?.querySelector('label');
    if(label)label.textContent='Date (optional)';
    if(holder&&!holder.querySelector('[data-date-optional-hint]')){
      const hint=document.createElement('div');hint.className='hint';hint.dataset.dateOptionalHint='1';
      hint.textContent='Leave blank to save as an unscheduled session.';holder.appendChild(hint);
    }
    saveBtn.onclick=async function(){
      const btn=saveBtn;
      try{
        const athletes=selectedAthletes(),event=$('event').value,training_goal=$('goal').value,title=$('name').value.trim(),main_set=$('mainSet').value,recovery=$('recovery').value||null,effort=Number($('effort').value),scheduled_date=$('date').value||null,notes=$('notes').value.trim()||null;
        if(!event)throw new Error('Choose an event.');if(!training_goal)throw new Error('Choose a training goal.');if(!title)throw new Error('Enter a session name.');if(!main_set)throw new Error('Choose the main set.');if(!recovery)throw new Error('Choose recovery.');if(!Number.isFinite(effort)||effort<70||effort>110)throw new Error('Choose effort between 70% and 110%.');if(!athletes.length)throw new Error('Choose who to assign the session to.');
        btn.disabled=true;btn.textContent='Saving…';
        let payload={created_by:user.id,title,event,main_set,recovery,effort,notes,scheduled_date,training_goal};
        let ins=await sb.from('sessions').insert(payload).select().single();
        if(ins.error&&String(ins.error.message||'').toLowerCase().includes('training_goal')){
          payload={created_by:user.id,title,event,main_set,recovery,effort,notes:(notes?notes+'\n':'')+'Training goal: '+goalLabel[training_goal],scheduled_date};
          ins=await sb.from('sessions').insert(payload).select().single();
        }
        if(ins.error)throw ins.error;
        const rows=athletes.map(a=>({session_id:ins.data.id,athlete_id:a.id,assigned_by:user.id,status:'planned'}));
        const q=await sb.from('assignments').insert(rows);
        if(q.error){await sb.from('sessions').delete().eq('id',ins.data.id);throw q.error}
        location.href='dashboard.html';
      }catch(e){alert(e.message||String(e))}finally{btn.disabled=false;btn.textContent='Save & assign session'}
    };
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();

// v0.8.9: Edit an existing saved session without replacing assignments/results.
(function installSessionEditMode(){
  if(!/session-builder\.html$/i.test(location.pathname))return;
  function install(){
    const saved=document.getElementById('savedSession'),loadBtn=document.getElementById('loadSessionBtn'),saveBtn=document.getElementById('saveBtn'),eventSelect=document.getElementById('event');
    if(!saved||!saveBtn)return;
    let editingId='';
    const updateBtn=document.createElement('button');updateBtn.id='updateSessionBtn';updateBtn.type='button';updateBtn.className='btn secondary';updateBtn.textContent='Update session';updateBtn.style.width='100%';updateBtn.style.marginTop='8px';updateBtn.hidden=true;saveBtn.insertAdjacentElement('afterend',updateBtn);
    const mode=document.createElement('div');mode.id='editSessionHint';mode.className='hint';mode.style.marginTop='7px';mode.hidden=true;mode.textContent='Editing saved session. Update session keeps its existing athlete assignments and results.';updateBtn.insertAdjacentElement('afterend',mode);
    function sync(){if(saved.value)editingId=saved.value;updateBtn.hidden=!editingId;mode.hidden=!editingId}
    saved.addEventListener('change',()=>{editingId=saved.value||'';setTimeout(sync,0)});
    loadBtn?.addEventListener('click',()=>{if(saved.value)editingId=saved.value;setTimeout(sync,0)});
    eventSelect?.addEventListener('change',()=>{if(!editingId)return;setTimeout(()=>{saved.value=editingId;sync()},0)});
    updateBtn.addEventListener('click',async()=>{
      const id=editingId||saved.value,btn=updateBtn;
      try{
        if(!id)throw new Error('Choose a saved session to edit.');
        const event=$('event').value,training_goal=$('goal').value,title=$('name').value.trim(),main_set=$('mainSet').value,recovery=$('recovery').value||null,effort=Number($('effort').value),scheduled_date=$('date').value||null,notes=$('notes').value.trim()||null;
        if(!event)throw new Error('Choose an event.');if(!training_goal)throw new Error('Choose a training goal.');if(!title)throw new Error('Enter a session name.');if(!main_set)throw new Error('Choose the main set.');if(!recovery)throw new Error('Choose recovery.');if(!Number.isFinite(effort)||effort<70||effort>110)throw new Error('Choose effort between 70% and 110%.');
        btn.disabled=true;btn.textContent='Updating…';
        let payload={title,event,main_set,recovery,effort,notes,scheduled_date,training_goal};
        let q=await sb.from('sessions').update(payload).eq('id',id).eq('created_by',user.id).select().single();
        if(q.error&&String(q.error.message||'').toLowerCase().includes('training_goal')){
          payload={title,event,main_set,recovery,effort,notes:(notes?notes+'\n':'')+'Training goal: '+goalLabel[training_goal],scheduled_date};
          q=await sb.from('sessions').update(payload).eq('id',id).eq('created_by',user.id).select().single();
        }
        if(q.error)throw q.error;
        if(typeof state!=='undefined'&&state.sessions&&q.data){state.sessions=state.sessions.map(s=>s.id===id?q.data:s);if(typeof buildSavedSessions==='function'){buildSavedSessions();saved.value=id}}
        editingId=id;sync();alert('Session updated. Existing assignments and results have been kept.');
      }catch(e){alert(e.message||String(e))}finally{btn.disabled=false;btn.textContent='Update session'}
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();