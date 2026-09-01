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

// Brief descriptions when desktop users hover or keyboard-focus navigation tabs.
(function installNavigationDescriptions(){
  const descriptions={
    dashboard:'Overview of training, results and progress.',
    athletes:'View athlete profiles, events and personal bests.',
    sessions:'Create, assign and review training sessions.',
    calendar:'See scheduled and upcoming training.',
    results:'Review completed performances and logged results.',
    stats:'View training totals, trends and athlete activity.',
    training:'View your planned and completed sessions.',
    pbs:'View and update your personal bests.',
    'club management':'Manage coaches, squads and athlete access.',
    'club reports':'Review club-wide participation and performance.',
    'athlete accounts':'Manage secure athlete account links.',
    performance:'Track athlete trends and progression.',
    'build session':'Create and assign a training session.',
    'log result':'Record completed training and performance data.',
    'my club':'View your assigned squads, athletes and club activity.',
    'my dashboard':'View your training, results and progress.',
    'beta feedback':'Report a bug, confusing feature or new idea.'
  };
  let tip=null,current=null,hideTimer=null;
  function ensureTip(){
    if(tip)return tip;
    tip=document.createElement('div');tip.id='paceleticsNavTooltip';tip.setAttribute('role','tooltip');
    Object.assign(tip.style,{position:'fixed',zIndex:'10000',maxWidth:'230px',padding:'9px 11px',border:'1px solid #34506d',borderRadius:'9px',background:'#0b1726',color:'#dbe6f2',font:'700 11px/1.4 Inter,system-ui,sans-serif',boxShadow:'0 12px 34px rgba(0,0,0,.38)',opacity:'0',visibility:'hidden',pointerEvents:'none',transition:'opacity .14s ease, visibility .14s ease'});
    document.body.appendChild(tip);return tip;
  }
  function keyFor(el){
    if(el.dataset?.view)return el.dataset.view.toLowerCase();
    const text=(el.textContent||'').replace(/[⌂◆◎▥↗＋✓]/g,'').replace(/\s+/g,' ').trim().toLowerCase();
    return text;
  }
  function descriptionFor(el){return descriptions[keyFor(el)]||''}
  function position(el){
    const t=ensureTip(),r=el.getBoundingClientRect();
    t.style.left='0px';t.style.top='0px';t.style.visibility='hidden';t.style.opacity='0';
    requestAnimationFrame(()=>{
      const tr=t.getBoundingClientRect();let left=r.right+12;
      if(left+tr.width>window.innerWidth-10)left=Math.max(10,r.left-tr.width-12);
      let top=r.top+(r.height-tr.height)/2;top=Math.max(10,Math.min(top,window.innerHeight-tr.height-10));
      t.style.left=Math.round(left)+'px';t.style.top=Math.round(top)+'px';t.style.visibility='visible';t.style.opacity='1';
    });
  }
  function show(el){
    if(!matchMedia('(hover:hover) and (pointer:fine)').matches)return;
    const text=descriptionFor(el);if(!text)return;clearTimeout(hideTimer);current=el;const t=ensureTip();t.textContent=text;el.setAttribute('aria-describedby',t.id);position(el);
  }
  function hide(el){
    hideTimer=setTimeout(()=>{if(el&&current!==el)return;if(tip){tip.style.opacity='0';tip.style.visibility='hidden'}if(current)current.removeAttribute('aria-describedby');current=null},70);
  }
  function eligible(root=document){return root.querySelectorAll?.('.nav .navBtn,.sideRoleBtn,.workflowNav a')||[]}
  function wire(root=document){
    eligible(root).forEach(el=>{
      if(el.dataset.paceTipWired==='1'||!descriptionFor(el))return;el.dataset.paceTipWired='1';
      el.addEventListener('mouseenter',()=>show(el));el.addEventListener('mouseleave',()=>hide(el));
      el.addEventListener('focus',()=>show(el));el.addEventListener('blur',()=>hide(el));
    });
    const feedback=document.getElementById('paceleticsFeedbackShortcut');
    if(feedback&&feedback.dataset.paceTipWired!=='1'){feedback.dataset.paceTipWired='1';feedback.addEventListener('mouseenter',()=>show(feedback));feedback.addEventListener('mouseleave',()=>hide(feedback));feedback.addEventListener('focus',()=>show(feedback));feedback.addEventListener('blur',()=>hide(feedback));}
  }
  function install(){wire();const observer=new MutationObserver(muts=>{for(const m of muts)for(const n of m.addedNodes)if(n.nodeType===1)wire(n)});observer.observe(document.body,{childList:true,subtree:true});window.addEventListener('scroll',()=>{if(current)position(current)},{passive:true});window.addEventListener('resize',()=>{if(current)position(current)});}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();

// Privacy-conscious beta page-view analytics.
// Uses a random first-party ID only; no IP address, full referrer, user-agent,
// screen size, or fingerprint is sent or stored. Browser privacy signals are honoured.
(function installPrivacyConsciousPageViews(){
  if(navigator.globalPrivacyControl===true||navigator.doNotTrack==='1'||localStorage.getItem('paceleticsAnalyticsOptOut')==='1')return;
  if(!/^(www\.)?paceletics\.com$/i.test(location.hostname))return;
  const cfg=window.PACELETICS_CONFIG||{};
  if(!window.supabase||!cfg.supabaseUrl||!cfg.supabasePublishableKey)return;

  function visitorId(){
    const key='paceleticsAnonymousVisitorId';
    try{
      let id=localStorage.getItem(key);
      if(!id){
        id=crypto.randomUUID();
        localStorage.setItem(key,id);
      }
      return id;
    }catch(_){
      return crypto.randomUUID();
    }
  }
  function deviceCategory(){
    const ua=navigator.userAgent||'';
    if(/iPad|Tablet|PlayBook|Silk/i.test(ua)||(navigator.maxTouchPoints>1&&/Macintosh/i.test(ua)))return'tablet';
    if(/Mobi|Android|iPhone|iPod/i.test(ua))return'mobile';
    return /Windows|Macintosh|Linux|CrOS/i.test(ua)?'desktop':'unknown';
  }
  function browserCategory(){
    const ua=navigator.userAgent||'';
    if(/Edg\//i.test(ua))return'edge';
    if(/Firefox\//i.test(ua))return'firefox';
    if(/Chrome\//i.test(ua)&&!/Edg\//i.test(ua))return'chrome';
    if(/Safari\//i.test(ua)&&!/Chrome\//i.test(ua))return'safari';
    return'other';
  }
  function referrerDomain(){
    if(!document.referrer)return null;
    try{
      const host=new URL(document.referrer).hostname.toLowerCase();
      return host&&host!==location.hostname.toLowerCase()?host:null;
    }catch(_){return null}
  }
  function cleanPath(){
    let path=location.pathname||'/';
    try{path=decodeURI(path)}catch(_){}
    return path.slice(0,300);
  }

  const client=window.supabase.createClient(cfg.supabaseUrl,cfg.supabasePublishableKey,{
    auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}
  });
  client.from('page_views').insert({
    visitor_id:visitorId(),
    page_path:cleanPath(),
    referrer_domain:referrerDomain(),
    device_category:deviceCategory(),
    browser_category:browserCategory()
  }).then(({error})=>{if(error&&location.hostname==='localhost')console.debug('Page view not recorded',error.message)}).catch(()=>{});
})();

// Add the visitor analytics link to the existing secure Club Reports screen.
(function installVisitorAnalyticsLink(){
  if(paceleticsPage()!=='club-report.html')return;
  function add(){
    const actions=document.querySelector('.top .actions');
    if(!actions||document.getElementById('visitorAnalyticsBtn'))return;
    const button=document.createElement('button');
    button.id='visitorAnalyticsBtn';
    button.type='button';
    button.className='btn secondary';
    button.textContent='Visitor Analytics';
    button.onclick=()=>{location.href='visitor-analytics.html'};
    actions.insertBefore(button,actions.firstChild);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',add);else add();
})();