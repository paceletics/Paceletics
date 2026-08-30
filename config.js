window.PACELETICS_CONFIG = {
  supabaseUrl: "https://ilsryvkrdjbnyieixetr.supabase.co",
  supabasePublishableKey: "sb_publishable_aJEx3hoeS3gA8cCq1vwbWA_yG8QItxW"
};

// Paceletics beta compatibility patch.
// Reuse the stored Supabase session rather than making a second remote
// getUser request inside the same-origin dashboard iframe.
(function patchSupabaseCreateClient(){
  if (!window.supabase || typeof window.supabase.createClient !== 'function') return;
  const originalCreateClient = window.supabase.createClient;
  if (originalCreateClient.__paceleticsPatched) return;

  function createClientPatched(...args) {
    const client = originalCreateClient(...args);
    if (client && client.auth && typeof client.auth.getSession === 'function') {
      client.auth.getUser = async function getUserFromStoredSession() {
        try {
          const { data, error } = await client.auth.getSession();
          return { data: { user: data && data.session ? data.session.user : null }, error: error || null };
        } catch (error) {
          return { data: { user: null }, error };
        }
      };
    }
    return client;
  }

  createClientPatched.__paceleticsPatched = true;
  window.supabase.createClient = createClientPatched;
})();

// Older embedded-dashboard recovery. Harmless on the current top-level v0.6 dashboard.
(function installDashboardRecovery(){
  function install(){
    const frame = document.getElementById('dashboardFrame');
    if (!frame) return;

    async function recover(){
      try {
        if (!frame.contentWindow || frame.src === 'about:blank') return;
        const w = frame.contentWindow;
        const d = w.document;
        const loading = d && d.getElementById('loading');
        if (!loading || loading.classList.contains('hidden')) return;

        if (typeof w.loadCloud !== 'function') {
          loading.innerHTML = '<div style="max-width:520px;padding:20px"><div class="logo" style="margin:auto">P</div><h2>Dashboard startup error</h2><div class="meta" style="line-height:1.5">The dashboard JavaScript did not start correctly. Refresh this page once. If this message remains, send a screenshot.</div></div>';
          return;
        }

        const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error('Cloud connection timed out.')), 12000));
        await Promise.race([Promise.resolve(w.loadCloud()), timeout]);
        loading.classList.add('hidden');
      } catch (error) {
        try {
          const d = frame.contentWindow.document;
          const loading = d.getElementById('loading');
          if (loading) {
            const message = String(error && error.message ? error.message : error).replace(/[&<>"']/g, '');
            loading.innerHTML = '<div style="max-width:520px;padding:20px"><div class="logo" style="margin:auto">P</div><h2>Could not load Paceletics</h2><div class="meta" style="line-height:1.5">' + message + '</div><button class="btn primary" style="margin-top:14px" onclick="location.reload()">Try again</button></div>';
          }
        } catch (_) {}
      }
    }

    frame.addEventListener('load', () => setTimeout(recover, 1200));
    setTimeout(recover, 2500);
    setTimeout(recover, 6000);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
  else install();
})();

// Athlete profile links for the v0.6+ cloud dashboard.
(function installAthleteProfileLinks(){
  function enhance(){
    const rows = document.querySelectorAll('#athleteRows tr');
    rows.forEach(row => {
      if (row.dataset.profileEnhanced === '1') return;
      const deleteBtn = row.querySelector('[data-delete-athlete]');
      const firstCell = row.querySelector('td');
      if (!deleteBtn || !firstCell) return;
      const id = deleteBtn.getAttribute('data-delete-athlete');
      const strong = firstCell.querySelector('strong');
      if (!id || !strong) return;
      strong.style.cursor = 'pointer';
      strong.style.textDecoration = 'underline';
      strong.style.textDecorationColor = '#ffb000';
      strong.title = 'Open athlete profile';
      strong.addEventListener('click', () => { location.href = 'athlete.html?id=' + encodeURIComponent(id); });
      const profileButton = document.createElement('button');
      profileButton.className = 'btn secondary';
      profileButton.textContent = 'Profile';
      profileButton.style.marginRight = '6px';
      profileButton.addEventListener('click', () => { location.href = 'athlete.html?id=' + encodeURIComponent(id); });
      deleteBtn.parentNode.insertBefore(profileButton, deleteBtn);
      row.dataset.profileEnhanced = '1';
    });
  }

  function install(){
    enhance();
    const target = document.getElementById('athleteRows');
    if (target) new MutationObserver(enhance).observe(target,{childList:true,subtree:true});
    setInterval(enhance,1500);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
  else install();
})();

// Full v0.8 Session Builder links for the cloud dashboard.
(function installSessionBuilderLinks(){
  function install(){
    ['buildBtn','buildInline'].forEach(id=>{
      const el=document.getElementById(id);
      if(!el)return;
      el.addEventListener('click',e=>{
        e.preventDefault();
        e.stopImmediatePropagation();
        location.href='session-builder.html';
      },true);
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);
  else install();
})();

// v0.8.1 Session Builder dropdowns.
// 1) Show one athlete target at a time in a dropdown.
// 2) Let coaches choose a previously built session and load it back into the form.
(function installBuilderDropdowns(){
  function isBuilder(){ return /session-builder\.html$/i.test(location.pathname); }
  if(!isBuilder()) return;

  function fire(el,type){ if(el) el.dispatchEvent(new Event(type,{bubbles:true})); }

  function installTargetDropdown(){
    const targets=document.getElementById('targets');
    if(!targets || document.getElementById('targetAthleteSelect')) return;
    const card=targets.closest('.card');
    if(!card) return;

    const wrap=document.createElement('div');
    wrap.style.marginTop='12px';
    wrap.innerHTML='<label>Preview athlete</label><select id="targetAthleteSelect"></select>';
    targets.parentNode.insertBefore(wrap,targets);
    const select=document.getElementById('targetAthleteSelect');

    function refresh(){
      const items=[...targets.querySelectorAll('.item')].filter(x=>!x.classList.contains('muted') || x.querySelector('strong'));
      const names=items.map((item,i)=>({i,name:item.querySelector('strong')?.textContent?.trim()||('Athlete '+(i+1))}));
      const previous=select.value;
      select.innerHTML=names.length?names.map(x=>'<option value="'+x.i+'">'+x.name.replace(/</g,'&lt;').replace(/>/g,'&gt;')+'</option>').join(''):'<option>No athletes selected</option>';
      if(names.length){
        if(names.some(x=>String(x.i)===previous)) select.value=previous;
        else select.value=String(names[0].i);
      }
      items.forEach((item,i)=>item.style.display=String(i)===select.value?'block':'none');
      if(!items.length) targets.querySelectorAll('.item').forEach(x=>x.style.display='block');
    }

    select.addEventListener('change',refresh);
    new MutationObserver(()=>setTimeout(refresh,0)).observe(targets,{childList:true,subtree:true});
    refresh();
  }

  async function installBuiltSessionDropdown(){
    if(document.getElementById('builtSessionSelect')) return;
    const form=document.querySelector('.formgrid');
    if(!form || !window.supabase || !window.PACELETICS_CONFIG) return;

    const holder=document.createElement('div');
    holder.className='full';
    holder.innerHTML='<label>Built sessions</label><select id="builtSessionSelect"><option value="">Choose a saved session…</option></select>';
    form.insertBefore(holder,form.firstChild);
    const select=document.getElementById('builtSessionSelect');

    try{
      const c=window.supabase.createClient(window.PACELETICS_CONFIG.supabaseUrl,window.PACELETICS_CONFIG.supabasePublishableKey);
      const {data,error}=await c.from('sessions').select('*').order('created_at',{ascending:false}).limit(100);
      if(error) throw error;
      const sessions=data||[];
      sessions.forEach(s=>{
        const o=document.createElement('option');
        o.value=s.id;
        o.textContent=(s.title||'Session')+(s.scheduled_date?' · '+s.scheduled_date:'')+(s.event?' · '+s.event:'');
        o.dataset.session=JSON.stringify(s);
        select.appendChild(o);
      });
      if(!sessions.length) select.innerHTML='<option value="">No saved sessions yet</option>';

      select.addEventListener('change',()=>{
        const opt=select.selectedOptions[0];
        if(!opt || !opt.dataset.session) return;
        const s=JSON.parse(opt.dataset.session);
        const set=(id,val)=>{const el=document.getElementById(id);if(el&&val!==undefined&&val!==null)el.value=val;};
        set('name',s.title||'');set('event',s.event||'200m');set('mainSet',s.main_set||'');set('recovery',s.recovery||'');set('effort',s.effort||90);set('date',s.scheduled_date||'');set('notes',s.notes||'');
        if(s.training_goal) set('goal',s.training_goal);
        ['name','mainSet','recovery','effort','notes'].forEach(id=>fire(document.getElementById(id),'input'));
        ['event','goal','date'].forEach(id=>fire(document.getElementById(id),'change'));
      });
    }catch(e){
      select.innerHTML='<option value="">Could not load saved sessions</option>';
    }
  }

  function install(){
    setTimeout(installTargetDropdown,700);
    setTimeout(installBuiltSessionDropdown,900);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);
  else install();
})();
