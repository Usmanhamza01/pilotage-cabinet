/* Service worker — Pilotage (v7)
   • réseau d'abord pour la page (évite les versions périmées en cache)
   • réception des notifications push et ouverture de la bonne vue au clic */
const CACHE='pilotage-v7';
const SHELL=['./','./index.html','./manifest.webmanifest','./icon-192.png'];

self.addEventListener('install',e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL).catch(()=>{})).then(()=>self.skipWaiting()));
});
self.addEventListener('activate',e=>{
  e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',e=>{
  const req=e.request;
  if(req.method!=='GET')return;
  const url=new URL(req.url);
  if(url.origin!==location.origin)return;                 /* Supabase, CDN : jamais interceptés */
  if(req.mode==='navigate'||url.pathname.endsWith('.html')||url.pathname.endsWith('/')){
    e.respondWith(fetch(req).then(r=>{const cp=r.clone();caches.open(CACHE).then(c=>c.put(req,cp));return r;})
      .catch(()=>caches.match(req).then(r=>r||caches.match('./index.html'))));
    return;
  }
  e.respondWith(caches.match(req).then(r=>r||fetch(req).then(res=>{const cp=res.clone();caches.open(CACHE).then(c=>c.put(req,cp));return res;})));
});

self.addEventListener('push',e=>{
  let d={};
  try{d=e.data?e.data.json():{};}catch(err){d={title:'Pilotage',body:e.data?e.data.text():''};}
  const title=d.title||'Pilotage — rappel';
  e.waitUntil(self.registration.showNotification(title,{
    body:d.body||'',tag:d.tag||d.key||undefined,renotify:!!d.tag,
    icon:'./icon-192.png',badge:'./icon-192.png',data:{link:d.link||'dash'}
  }));
});
self.addEventListener('notificationclick',e=>{
  e.notification.close();
  const link=(e.notification.data&&e.notification.data.link)||'dash';
  const target=new URL('./#'+link,self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{
    for(const c of list){if(c.url.startsWith(self.registration.scope)){c.navigate(target).catch(()=>{});return c.focus();}}
    return self.clients.openWindow(target);
  }));
});
