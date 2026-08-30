window.PACELETICS_CONFIG = {
  supabaseUrl: "https://ilsryvkrdjbnyieixetr.supabase.co",
  supabasePublishableKey: "sb_publishable_aJEx3hoeS3gA8cCq1vwbWA_yG8QItxW"
};

// Paceletics beta compatibility patch:
// the dashboard runs inside a same-origin iframe. Reusing the stored
// Supabase session avoids a second /user verification request during
// startup, which could leave the dashboard waiting on the loading screen.
(function patchSupabaseCreateClient(){
  if (!window.supabase || typeof window.supabase.createClient !== 'function') return;
  const originalCreateClient = window.supabase.createClient;
  if (originalCreateClient.__paceleticsPatched) return;

  function createClientPatched(...args) {
    const client = originalCreateClient(...args);
    if (client?.auth?.getSession) {
      client.auth.getUser = async function getUserFromStoredSession() {
        const { data, error } = await client.auth.getSession();
        return { data: { user: data?.session?.user || null }, error };
      };
    }
    return client;
  }

  createClientPatched.__paceleticsPatched = true;
  window.supabase.createClient = createClientPatched;
})();
