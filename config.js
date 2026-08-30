window.PACELETICS_CONFIG = {
  supabaseUrl: "https://ilsryvkrdjbnyieixetr.supabase.co",
  supabasePublishableKey: "sb_publishable_aJEx3hoeS3gA8cCq1vwbWA_yG8QItxW"
};

// Reuse the stored Supabase session for Paceletics pages.
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

// Athlete profile links for the cloud dashboard.
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
      strong.addEventListener('click', () => {
        location.href = 'athlete.html?id=' + encodeURIComponent(id);
      });

      const profileButton = document.createElement('button');
      profileButton.className = 'btn secondary';
      profileButton.textContent = 'Profile';
      profileButton.style.marginRight = '6px';
      profileButton.addEventListener('click', () => {
        location.href = 'athlete.html?id=' + encodeURIComponent(id);
      });
      deleteBtn.parentNode.insertBefore(profileButton, deleteBtn);
      row.dataset.profileEnhanced = '1';
    });
  }

  function install(){
    enhance();
    const target = document.getElementById('athleteRows');
    if (target) new MutationObserver(enhance).observe(target,{childList:true,subtree:true});
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
  else install();
})();

// Open the current Session Builder from the dashboard.
(function installSessionBuilderLinks(){
  function install(){
    ['buildBtn','buildInline'].forEach(id=>{
      const el=document.getElementById(id);
      if(!el)return;
      el.addEventListener('click',e=>{
        e.preventDefault();
        e.stopImmediatePropagation();
        location.href='session-builder.html?v=0.8.8';
      },true);
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);
  else install();
})();

// v0.8.8: Date is optional in Session Builder.
(function installOptionalSessionDate(){
  if(!/session-builder\.html$/i.test(location.pathname)) return;

  function install(){
    const date=document.getElementById('date');
    const saveBtn=document.getElementById('saveBtn');
    if(!date||!saveBtn) return;

    const holder=date.parentElement;
    const label=holder&&holder.querySelector('label');
    if(label) label.textContent='Date (optional)';
    if(holder&&!holder.querySelector('[data-date-optional-hint]')){
      const hint=document.createElement('div');
      hint.className='hint';
      hint.dataset.dateOptionalHint='1';
      hint.textContent='Leave blank to save as an unscheduled session.';
      holder.appendChild(hint);
    }

    saveBtn.onclick=async function saveWithOptionalDate(){
      const btn=saveBtn;
      try{
        const athletes=selectedAthletes(),event=$('event').value,training_goal=$('goal').value,title=$('name').value.trim(),main_set=$('mainSet').value,recovery=$('recovery').value||null,effort=Number($('effort').value),scheduled_date=$('date').value||null,notes=$('notes').value.trim()||null;
        if(!event)throw new Error('Choose an event.');
        if(!training_goal)throw new Error('Choose a training goal.');
        if(!title)throw new Error('Enter a session name.');
        if(!main_set)throw new Error('Choose the main set.');
        if(!recovery)throw new Error('Choose recovery.');
        if(!Number.isFinite(effort)||effort<70||effort>110)throw new Error('Choose effort between 70% and 110%.');
        if(!athletes.length)throw new Error('Choose who to assign the session to.');

        btn.disabled=true;
        btn.textContent='Saving…';
        let payload={created_by:user.id,title,event,main_set,recovery,effort,notes,scheduled_date,training_goal};
        let ins=await sb.from('sessions').insert(payload).select().single();
        if(ins.error&&String(ins.error.message||'').toLowerCase().includes('training_goal')){
          payload={created_by:user.id,title,event,main_set,recovery,effort,notes:(notes?notes+'\n':'')+'Training goal: '+goalLabel[training_goal],scheduled_date};
          ins=await sb.from('sessions').insert(payload).select().single();
        }
        if(ins.error)throw ins.error;

        const rows=athletes.map(a=>({session_id:ins.data.id,athlete_id:a.id,assigned_by:user.id,status:'planned'}));
        const q=await sb.from('assignments').insert(rows);
        if(q.error){
          await sb.from('sessions').delete().eq('id',ins.data.id);
          throw q.error;
        }
        location.href='dashboard.html';
      }catch(e){
        alert(e.message||String(e));
      }finally{
        btn.disabled=false;
        btn.textContent='Save & assign session';
      }
    };
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);
  else install();
})();