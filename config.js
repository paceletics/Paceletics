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
