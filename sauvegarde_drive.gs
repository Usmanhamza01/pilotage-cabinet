/************************************************************
 * PILOTAGE CABINET — Sauvegarde hebdomadaire vers Google Drive
 * Chaque lundi ~23h : crée un fichier Google Sheets daté,
 * au format LISIBLE (une feuille par client, comme votre Excel :
 * code journal, mois Jan→Déc avec X, pièces par semaine),
 * plus une feuille récap des dossiers et un onglet "Tâches".
 * Compatible Drive partagé (Team Drive).
 *
 * À coller dans script.google.com (voir le guide fourni).
 ************************************************************/

// ====================== CONFIGURATION ======================
// URL du projet Supabase (déjà renseignée)
const SUPABASE_URL = 'https://owiflzgnpyqxnilykkdc.supabase.co';

// Clé "service_role" — Supabase > Settings > API > service_role (Reveal)
// SECRÈTE : uniquement ici (script privé). Jamais dans l'application.
const SERVICE_KEY = 'COLLEZ_ICI_VOTRE_CLE_SERVICE_ROLE';

// ID du sous-dossier Drive de destination (déjà renseigné)
const FOLDER_ID = '12ZzLdedE34ZENQHOWwdJNHHmN2iC72Ao';

// Année des croix mensuelles à exporter (par défaut : année en cours)
const ANNEE = new Date().getFullYear();

// Conservation : sauvegardes plus vieilles que N jours -> corbeille. 0 = tout garder.
const RETENTION_DAYS = 120;

const MOIS = ['Janvier','Février','Mars','Avril','Mai','Juin','Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
// ===========================================================


/** Lancée chaque lundi par le déclencheur. */
function sauvegardeHebdo() {
  if (SERVICE_KEY.indexOf('COLLEZ') === 0) {
    throw new Error('Renseignez SERVICE_KEY en haut du script.');
  }
  const tz = Session.getScriptTimeZone();
  const name = 'Pilotage_sauvegarde_' + Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd_HHmm');

  // Chargement des données
  const clients = fetchAll('clients');
  const profiles = fetchAll('profiles');
  const journals = fetchAll('journals');
  const months = fetchAll('journal_months');
  const counts = fetchAll('piece_counts');
  const tasks = fetchAll('tasks');

  const profName = id => { const p = profiles.find(x => x.id === id); return p ? p.full_name : ''; };
  const clientName = id => { const c = clients.find(x => x.id === id); return c ? c.name : ''; };
  const clientResp = c => c.responsible_id ? profName(c.responsible_id) : (c.responsible_name || '');
  const isChecked = (jid, m) => months.some(x => x.journal_id === jid && (+x.year) === (+ANNEE) && (+x.month) === (+m) && x.checked);
  const weeksOf = jids => {
    const s = {};
    counts.forEach(c => { if (jids.indexOf(c.journal_id) >= 0) s[c.week_date] = 1; });
    return Object.keys(s).sort();
  };
  const countOf = (jid, w) => { const x = counts.find(c => c.journal_id === jid && c.week_date === w); return x ? x.count : ''; };
  const wLabel = w => w.substring(8, 10) + '/' + w.substring(5, 7);

  const ss = SpreadsheetApp.create(name);

  // 1) Feuille récap des dossiers
  const recap = [['DOSSIERS','TYPE','Responsable','Interlocuteur','Adresse','Téléphone','Mail']];
  clients.slice().sort((a,b)=>(a.name>b.name?1:-1)).forEach(c =>
    recap.push([c.name, c.type||'', clientResp(c), c.interlocutor||'', c.address||'', c.phone||'', c.email||'']));
  writeSheet(ss.getActiveSheet().setName('Liste des dossiers'), recap);

  // 2) Une feuille par client ayant des journaux
  const used = {};
  clients.slice().sort((a,b)=>(a.name>b.name?1:-1)).forEach(c => {
    const tenue = journals.filter(j => j.client_id === c.id && j.section === 'tenue');
    const decls = journals.filter(j => j.client_id === c.id && j.section === 'declaration');
    if (!tenue.length && !decls.length) return;
    const weeks = weeksOf(tenue.map(j => j.id));
    const aoa = [];
    aoa.push(['SITUATION DE LA TENUE DE COMPTABILITE DE ' + c.name.toUpperCase() + '  ·  ' + ANNEE]);
    aoa.push([]);
    aoa.push(['Code journal','Intitulé journal'].concat(MOIS).concat(weeks.map(wLabel)));
    tenue.forEach(j => {
      const row = [j.code, j.label || ''];
      for (let m = 1; m <= 12; m++) row.push(isChecked(j.id, m) ? 'X' : '');
      weeks.forEach(w => row.push(countOf(j.id, w)));
      aoa.push(row);
    });
    if (tenue.length) {
      const tr = ['TOTAL PIÈCES','']; for (let m=0;m<12;m++) tr.push('');
      weeks.forEach(w => tr.push(tenue.reduce((a,j)=>{const x=countOf(j.id,w);return a+(x===''?0:x);},0)));
      aoa.push(tr);
    }
    aoa.push([]);
    aoa.push(['SITUATION DES DECLARATIONS']);
    aoa.push(['Intitulé journal'].concat(MOIS));
    decls.forEach(j => {
      const row = [j.code];
      for (let m = 1; m <= 12; m++) row.push(isChecked(j.id, m) ? 'X' : '');
      aoa.push(row);
    });
    writeSheet(ss.insertSheet(sheetName(c.name, used)), aoa);
  });

  // 3) Onglet Tâches (lisible)
  const P = {p1:'Urgent',p2:'Important',p3:'Normal',p4:'Faible'};
  const S = {todo:'À faire',doing:'En cours',waiting:'En attente',blocked:'Bloqué',done:'Terminé',dropped:'Abandonné'};
  const tRows = [['Intitulé','Client','Responsable','Priorité','Statut','Avancement','Échéance','Prochaine action']];
  tasks.forEach(t => tRows.push([t.title, clientName(t.client_id), profName(t.assignee_id),
    P[t.priority]||t.priority, S[t.status]||t.status, (t.status==='done'?100:t.progress)+'%',
    t.due_date||'', t.next_action||'']));
  writeSheet(ss.insertSheet('Tâches'), tRows);

  // Déplacer dans le dossier de destination (compatible Drive partagé)
  DriveApp.getFileById(ss.getId()).moveTo(DriveApp.getFolderById(FOLDER_ID));

  if (RETENTION_DAYS > 0) purgerAnciennes();
  Logger.log('Sauvegarde créée : ' + name);
}


/** Écrit un tableau de lignes dans une feuille, en-tête figée. */
function writeSheet(sheet, aoa) {
  if (!aoa.length) { sheet.getRange(1,1).setValue('(aucune donnée)'); return; }
  const width = Math.max.apply(null, aoa.map(r => r.length));
  const norm = aoa.map(r => { const c = r.slice(); while (c.length < width) c.push(''); return c; });
  sheet.getRange(1, 1, norm.length, width).setValues(norm);
  sheet.setFrozenRows(1);
}


/** Récupère toutes les lignes d'une table (avec pagination). */
function fetchAll(table) {
  const out = [];
  const step = 1000; let from = 0;
  while (true) {
    const res = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/' + table + '?select=*', {
      method: 'get',
      headers: { 'apikey': SERVICE_KEY, 'Authorization': 'Bearer ' + SERVICE_KEY,
                 'Range-Unit': 'items', 'Range': from + '-' + (from + step - 1) },
      muteHttpExceptions: true
    });
    if (res.getResponseCode() >= 400) throw new Error('Erreur ' + res.getResponseCode() + ' (' + table + ') : ' + res.getContentText());
    const chunk = JSON.parse(res.getContentText() || '[]');
    out.push.apply(out, chunk);
    if (chunk.length < step) break;
    from += step;
  }
  return out;
}


/** Nom d'onglet unique et valide (<= 31 car., sans caracteres interdits). */
function sheetName(nm, used) {
  let s = String(nm).replace(/[:\\\/?*\[\]]/g, ' ').substring(0, 28) || 'Dossier';
  let n = s, i = 2;
  while (used[n.toLowerCase()]) { n = s.substring(0, 25) + ' ' + i; i++; }
  used[n.toLowerCase()] = 1;
  return n;
}


/** Corbeille les sauvegardes plus anciennes que RETENTION_DAYS. */
function purgerAnciennes() {
  const cutoff = new Date(Date.now() - RETENTION_DAYS * 864e5);
  const files = DriveApp.getFolderById(FOLDER_ID).getFiles();
  while (files.hasNext()) {
    const f = files.next();
    if (f.getName().indexOf('Pilotage_sauvegarde_') === 0 && f.getDateCreated() < cutoff) f.setTrashed(true);
  }
}


/** A LANCER UNE SEULE FOIS : programme la sauvegarde chaque lundi ~23h. */
function installerDeclencheur() {
  ScriptApp.getProjectTriggers().forEach(t => {
    if (t.getHandlerFunction() === 'sauvegardeHebdo') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('sauvegardeHebdo').timeBased().onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(23).create();
  Logger.log('Declencheur installe : chaque lundi vers 23h.');
}


/** Pratique pour tester tout de suite. */
function testerMaintenant() { sauvegardeHebdo(); }
