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

// Open the native v0.8.4 Session Builder from the dashboard.
(function installSessionBuilderLinks(){
  function install(){
    ['buildBtn','buildInline'].forEach(id=>{
      const el=document.getElementById(id);
      if(!el)return;
      el.addEventListener('click',e=>{
        e.preventDefault();
        e.stopImmediatePropagation();
        location.href='session-builder.html?v=0.8.4';
      },true);
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);
  else install();
})();
