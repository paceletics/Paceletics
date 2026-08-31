/* Paceletics workflow shell v1.1 */
(function(){
  const page=(location.pathname.split('/').pop()||'').toLowerCase();
  const excluded=new Set(['','index.html','dashboard.html','athlete-dashboard.html','join-athlete.html','join-club.html','404.html']);
  if(excluded.has(page))return;

  const coachPages=new Set(['coach-club.html','coach-session.html','coach-result-entry.html','coach-athlete.html']);
  const athletePages=new Set(['athlete-result-entry.html']);
  const clubPages=new Set(['club.html','club-report.html','club-athletes.html','athlete.html','session-builder.html','result-entry.html','performance.html']);
  if(!coachPages.has(page)&&!athletePages.has(page)&&!clubPages.has(page))return;

  const role=coachPages.has(page)?'Coach':athletePages.has(page)?'Athlete':'Club';
  const cls=page==='club.html'?'workflow-club':page==='club-report.html'?'workflow-report':/session/.test(page)?'workflow-builder':/result/.test(page)?'workflow-result':'workflow-page';
  const icon=(text)=>`<span class="workflowNavIcon">${text}</span>`;

  const navByRole={
    Club:[
      ['Dashboard','dashboard.html?v=0.9.15','⌂','dashboard.html'],
      ['Club Management','club.html?v=0.9.15','◆','club.html'],
      ['Athlete Accounts','club-athletes.html?v=0.9.15','◎','club-athletes.html'],
      ['Club Reports','club-report.html?v=0.9.15','▥','club-report.html'],
      ['Performance','performance.html?v=0.9.15','↗','performance.html'],
      ['Build Session','session-builder.html?v=0.9.15','＋','session-builder.html'],
      ['Log Result','result-entry.html?v=0.9.15','✓','result-entry.html']
    ],
    Coach:[
      ['Dashboard','dashboard.html?v=0.9.15','⌂','dashboard.html'],
      ['My Club','coach-club.html?v=0.9.15','◎','coach-club.html'],
      ['Build Session','coach-session.html?v=0.9.15','＋','coach-session.html'],
      ['Log Result','coach-result-entry.html?v=0.9.15','✓','coach-result-entry.html']
    ],
    Athlete:[
      ['My Dashboard','athlete-dashboard.html?v=0.9.15','⌂','athlete-dashboard.html'],
      ['Log Result','athlete-result-entry.html?v=0.9.15','✓','athlete-result-entry.html']
    ]
  };

  const pageCopy={
    'club.html':['Club Management','Manage coaches, squads, athlete access and secure assignments.'],
    'club-report.html':['Club Reports','Review club-wide participation, workload and performance data.'],
    'club-athletes.html':['Athlete Accounts','Securely link athlete logins to club-owned athlete profiles.'],
    'athlete.html':['Athlete Profile','Review performance, coaching notes and official personal bests.'],
    'session-builder.html':['Session Builder','Plan training, calculate targets and assign work to athletes.'],
    'result-entry.html':['Result Entry','Record completed training and turn rep data into useful performance insight.'],
    'performance.html':['Performance','Track trends, compare like-for-like work and monitor progression.'],
    'coach-club.html':['My Club','Your secure squad view, assigned athletes and training activity.'],
    'coach-session.html':['Coach Session Builder','Build and assign sessions only to athletes in your squads.'],
    'coach-result-entry.html':['Coach Result Entry','Record and update results for athletes in your assigned squads.'],
    'coach-athlete.html':['Athlete Profile','Secure read-only performance view for your assigned athlete.'],
    'athlete-result-entry.html':['Log Training Result','Record your own assigned session result securely.']
  };

  function activeFor(target){return page===target}
  function navHtml(mobile=false){
    return navByRole[role].map(([label,href,symbol,target])=>`<a href="${href}" class="${activeFor(target)?'active':''}">${mobile?'':icon(symbol)}${label}</a>`).join('');
  }

  function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}

  async function installClubAthleteOffboarding(){
    if(page!=='club.html'||document.getElementById('clubAthleteOffboarding'))return;
    const grid=document.querySelector('#app .grid');
    if(!grid)return;

    const card=document.createElement('section');
    card.id='clubAthleteOffboarding';
    card.className='card span12';
    card.innerHTML=`<div class="row"><div><h3 style="margin:0">Club athletes</h3><div class="muted" style="margin-top:4px">Remove an athlete when they leave the club. Their login and squad access are stopped immediately, while historical PBs and completed results are preserved.</div></div><span class="badge">Secure offboarding</span></div><div id="clubOffboardList" class="list"><div class="empty">Loading active athletes…</div></div>`;
    grid.appendChild(card);

    const list=document.getElementById('clubOffboardList');
    const cfg=window.PACELETICS_CONFIG||{};
    if(!window.supabase||!cfg.supabaseUrl||!cfg.supabasePublishableKey){
      list.innerHTML='<div class="empty">Supabase configuration did not load.</div>';
      return;
    }

    const client=window.supabase.createClient(cfg.supabaseUrl,cfg.supabasePublishableKey);
    try{
      const {data:session}=await client.auth.getSession();
      if(!session?.session?.user)return;
      const q=await client.from('athletes').select('id,full_name,group_name,primary_event,linked_user_id,is_active').eq('is_active',true).order('full_name');
      if(q.error){
        const missing=/is_active|schema cache|column/i.test(String(q.error.message||''));
        list.innerHTML=`<div class="empty">${missing?'Run migration_v0_18_athlete_offboarding.sql in Supabase to enable safe athlete removal.':esc(q.error.message||'Could not load athletes.')}</div>`;
        return;
      }
      const athletes=q.data||[];
      list.innerHTML=athletes.length?athletes.map(a=>`<div class="item"><div class="row"><div><strong>${esc(a.full_name)}</strong><div class="muted">${[a.group_name,a.primary_event].filter(Boolean).map(esc).join(' · ')||'Athlete'} · ${a.linked_user_id?'Athlete account linked':'No Athlete login linked'}</div></div><button class="btn danger" type="button" data-offboard-athlete="${a.id}" data-athlete-name="${esc(a.full_name)}">Remove from Club</button></div></div>`).join(''):'<div class="empty">No active athletes in this club.</div>';

      list.querySelectorAll('[data-offboard-athlete]').forEach(btn=>{
        btn.addEventListener('click',async()=>{
          const name=btn.dataset.athleteName||'this athlete';
          const ok=confirm(`Remove ${name} from the club?\n\nThis will immediately stop their Athlete account access, remove squad access and cancel planned sessions. Completed results and PB history will be kept.`);
          if(!ok)return;
          const original=btn.textContent;
          btn.disabled=true;btn.textContent='Removing…';
          try{
            const r=await client.rpc('offboard_club_athlete',{p_athlete_id:btn.dataset.offboardAthlete});
            if(r.error)throw r.error;
            alert(`${name} has been removed from the club. Their access has been stopped and historical data has been preserved.`);
            location.reload();
          }catch(e){
            alert(e.message||String(e));
            btn.disabled=false;btn.textContent=original;
          }
        });
      });
    }catch(e){
      list.innerHTML=`<div class="empty">${esc(e.message||String(e))}</div>`;
    }
  }

  function install(){
    if(document.body?.dataset?.paceShell==='1')return;
    const wrap=document.querySelector('body > .wrap');
    if(!wrap)return;
    document.body.dataset.paceShell='1';
    document.body.classList.add('workflow-shell',cls,'paceletics-modern');

    if(!document.getElementById('paceleticsShellCss')){
      const link=document.createElement('link');link.id='paceleticsShellCss';link.rel='stylesheet';link.href='paceletics-shell.css?v=1.0.0';document.head.appendChild(link);
    }

    const app=document.createElement('div');app.className='workflowApp';
    const side=document.createElement('aside');side.className='workflowSide';
    side.innerHTML=`<div class="workflowBrand"><div class="workflowMark"><span>P</span></div><div><div class="workflowWord">PACELETICS</div><div class="workflowTag">Plan. Train. Improve.</div></div></div><nav class="workflowNav">${navHtml(false)}</nav><div class="workflowSideBottom"><div class="workflowRole">${role} workspace</div><div class="workflowVersion">Beta v0.9.15<br>Secure cloud platform</div></div>`;
    const main=document.createElement('main');main.className='workflowMain';
    wrap.parentNode.insertBefore(app,wrap);app.appendChild(side);app.appendChild(main);main.appendChild(wrap);

    const top=wrap.querySelector(':scope > .top');
    if(top&&pageCopy[page]){
      const intro=document.createElement('div');intro.className='workflowPageIntro';intro.innerHTML=`<div><strong>${pageCopy[page][0]}</strong><span>${pageCopy[page][1]}</span></div><div class="workflowPill">${role}</div>`;
      top.insertAdjacentElement('afterend',intro);
    }

    const mobile=document.createElement('nav');mobile.className='workflowMobile';mobile.innerHTML=navHtml(true);document.body.appendChild(mobile);
    installClubAthleteOffboarding();
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install);else install();
})();
