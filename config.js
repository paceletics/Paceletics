window.PACELETICS_CONFIG = {
  supabaseUrl: "https://ilsryvkrdjbnyieixetr.supabase.co",
  supabasePublishableKey: "sb_publishable_aJEx3hoeS3gA8cCq1vwbWA_yG8QItxW"
};

// Shared helpers only. Dashboard routing and dashboard UI are handled
// by dashboard.html and athlete-dashboard.html themselves.
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

function paceleticsPage(){
  return (location.pathname.split('/').pop()||'index.html').toLowerCase();
}

// Session Builder: date is optional.
(function installOptionalSessionDate(){
  if(paceleticsPage()!=='session-builder.html')return;
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
        location.href='dashboard.html?v=0.9.16';
      }catch(e){alert(e.message||String(e))}finally{btn.disabled=false;btn.textContent='Save & assign session'}
    };
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();

// Session Builder: edit an existing saved session while preserving assignments/results.
(function installSessionEditMode(){
  if(paceleticsPage()!=='session-builder.html')return;
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

// Shared visual layer for login and workflow pages.
(function installPaceleticsModernUI(){
  const page=paceleticsPage();
  function apply(){
    if(!document.body)return;
    document.body.classList.add('paceletics-modern');
    if(page==='index.html'||page==='')document.body.classList.add('paceletics-login');
    document.querySelectorAll('.logo').forEach(logo=>{
      if(logo.dataset.modernLogo==='1')return;
      if((logo.textContent||'').trim()==='P')logo.innerHTML='<span class="pace-mark">P</span>';
      logo.dataset.modernLogo='1';
    });
    if(!document.getElementById('paceleticsModernCss')){
      const link=document.createElement('link');link.id='paceleticsModernCss';link.rel='stylesheet';link.href='paceletics-modern.css?v=2.0.1';document.head.appendChild(link);
    }
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply);else apply();
})();

// Load the shared Paceletics workflow shell only on workflow pages.
(function installPaceleticsWorkflowShell(){
  const page=paceleticsPage();
  const pages=new Set([
    'club.html','club-report.html','club-athletes.html','athlete.html',
    'session-builder.html','result-entry.html','performance.html',
    'coach-club.html','coach-session.html','coach-result-entry.html','coach-athlete.html',
    'athlete-result-entry.html'
  ]);
  if(!pages.has(page)||document.querySelector('script[src*="paceletics-shell.js"]'))return;
  const script=document.createElement('script');script.src='paceletics-shell.js?v=1.1.0';document.head.appendChild(script);
})();

// Beta feedback shortcut for signed-in web workflow pages.
(function installBetaFeedbackShortcut(){
  const page=paceleticsPage();
  if(page==='index.html'||page===''||page==='feedback.html'||page==='join-club.html'||page==='join-athlete.html'||page==='reset-password.html')return;
  function add(){
    if(!document.body||document.getElementById('paceleticsFeedbackShortcut'))return;
    const b=document.createElement('button');
    b.id='paceleticsFeedbackShortcut';b.type='button';b.textContent='Beta Feedback';
    b.setAttribute('aria-label','Send Beta feedback');
    Object.assign(b.style,{position:'fixed',right:'14px',bottom:'14px',zIndex:'999',border:'1px solid #3b536f',borderRadius:'999px',padding:'10px 14px',background:'#13243a',color:'#ffd36a',font:'800 11px Inter,system-ui,sans-serif',boxShadow:'0 10px 32px rgba(0,0,0,.35)',cursor:'pointer'});
    if(matchMedia('(max-width: 900px)').matches)b.style.bottom='82px';
    b.onclick=()=>{location.href='feedback.html?from='+encodeURIComponent(page)};
    document.body.appendChild(b);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',add);else add();
})();
