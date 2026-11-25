#!/usr/bin/env node
// Fills a fresh Agora server with a small demo community for the simulator screenshots, through the same HTTP API the
// web app and the apps use: the accounts of the handover checklist (member, treasurer, event manager, mentor,
// mentoring manager, admin), fees and bookings, open requests, events with tasks and an order of service, a mentoring
// conversation, songs and prayer requests. Dates are relative to today, so the events are always upcoming.
//
//   node seed-server.mjs [http://localhost:3000]
//
// Prints the accounts as JSON (all with the same password) for the screenshot script.

const base = (process.argv[2] || 'http://localhost:3000').replace(/\/$/, '');
const PASSWORD = 'Demo-Passwort-1';

const tokens = {};
let calls = 0;

async function call(who, method, url, body) {
  calls += 1;
  // Its own address per call (as the server's tests do), so the rate limits never get in the way of the seed
  const headers = { 'X-Forwarded-For': `10.9.${(calls >> 8) & 255}.${calls & 255}` };
  if (who) headers.Authorization = `Bearer ${tokens[who]}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(base + url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let parsed = text;
  try { parsed = JSON.parse(text); } catch { /* text answer */ }
  if (!res.ok) throw new Error(`${who || 'anonymous'} ${method} ${url}: ${res.status} ${text.slice(0, 300)}`);
  return parsed;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const pad = (n) => String(n).padStart(2, '0');
const day = (offset) => {
  const date = new Date();
  date.setDate(date.getDate() + offset);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
};
/** The first day of the month [offset] months from now. */
const monthStart = (offset) => {
  const date = new Date();
  date.setDate(1);
  date.setMonth(date.getMonth() + offset);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-01`;
};
/** The next [weekday] (0 Sunday) at least [minDays] from today. */
const next = (weekday, minDays = 1) => {
  for (let offset = minDays; offset < minDays + 7; offset += 1) {
    const date = new Date();
    date.setDate(date.getDate() + offset);
    if (date.getDay() === weekday) return day(offset);
  }
  return day(minDays);
};

async function waitReady() {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const status = await fetch(`${base}/api/status`).then((res) => res.json()).catch(() => null);
    if (status?.ready === true) return;
    await sleep(500);
  }
  throw new Error('The server did not get ready');
}

async function login(who, email) {
  tokens[who] = (await call(null, 'POST', '/api/auth/login', { email, password: PASSWORD })).token;
  return (await call(who, 'GET', '/api/auth/me')).user;
}

/** Changes a person record the way the web app does: read it with its version, write it whole. */
async function mutatePerson(who, key, change) {
  const raw = await call(who, 'GET', `/api/db?path=people/${encodeURIComponent(key)}&raw=1`);
  const value = raw.value || {};
  value.payments = value.payments || [];
  value.statusHistory = value.statusHistory || [];
  await call(who, 'POST', '/api/db/transaction', { path: `people/${key}`, currentVersion: raw.version, value: change(value) });
}

let idCounter = Date.now() - 100000;
const nextId = () => (idCounter += 7);

function addPayments(person, payments) {
  for (const payment of payments) {
    person.payments.push({ amount: payment.amount, date: payment.date, description: payment.note, id: nextId() });
    person.totalPaid = Math.round(((Number(person.totalPaid) || 0) + payment.amount) * 100) / 100;
  }
  return person;
}

async function main() {
  const status = await fetch(`${base}/api/status`).then((res) => res.json());
  if (status.setupMode) {
    const setup = await call(null, 'POST', '/api/setup', {
      appName: 'Gemeinde am Lindenhof',
      defaultLanguage: 'de',
      adminUser: { firstName: 'Anna', lastName: 'Albrecht', email: 'admin@demo.agora', password: PASSWORD, memberSince: monthStart(-4) }
    });
    tokens.admin = setup.token;
  }
  await waitReady();
  const admin = await login('admin', 'admin@demo.agora');

  // Groups with the permissions of the checklist's roles
  const groups = {};
  const existing = await call('admin', 'GET', '/api/admin/groups');
  for (const [name, permissions] of [
    ['Kasse', ['manage_finances']],
    ['Eventteam', ['manage_events']],
    ['Mentoring-Leitung', ['manage_mentoring']],
    ['Lobpreis', ['manage_songbook']],
    ['Technik', []]
  ]) {
    groups[name] = existing.find((group) => group.name === name) || await call('admin', 'POST', '/api/admin/groups', { name, permissions });
  }

  // Accounts (the people of the checklist) and members without an account (the fee list)
  const accounts = [
    { who: 'member', firstName: 'Max', lastName: 'Müller', email: 'mitglied@demo.agora', groups: ['Technik'], status: 'vollverdiener', since: monthStart(-4) },
    { who: 'treasurer', firstName: 'Tina', lastName: 'Kaufmann', email: 'kasse@demo.agora', groups: ['Kasse'], status: 'vollverdiener', since: monthStart(-4) },
    { who: 'events', firstName: 'Elias', lastName: 'Becker', email: 'events@demo.agora', groups: ['Eventteam', 'Lobpreis'], status: 'geringverdiener', since: monthStart(-4) },
    { who: 'mentor', firstName: 'Miriam', lastName: 'Schneider', email: 'mentor@demo.agora', groups: [], status: 'vollverdiener', since: monthStart(-4) },
    { who: 'mentoring', firstName: 'Lea', lastName: 'Hoffmann', email: 'mentoring@demo.agora', groups: ['Mentoring-Leitung'], status: 'keinverdiener', since: monthStart(-1) }
  ];
  const users = { admin };
  const knownUsers = await call('admin', 'GET', '/api/admin/users');
  const userList = Array.isArray(knownUsers) ? knownUsers : knownUsers.users || [];
  for (const account of accounts) {
    if (!userList.some((user) => user.email === account.email)) {
      await call('admin', 'POST', '/api/admin/users', {
        email: account.email, password: PASSWORD, firstName: account.firstName, lastName: account.lastName,
        pays: true, groups: account.groups.map((name) => groups[name].id), status: account.status, memberSince: account.since
      });
    }
    users[account.who] = await login(account.who, account.email);
  }
  for (const [firstName, lastName, status, since] of [
    ['Jonas', 'Weber', 'vollverdiener', monthStart(-4)],
    ['Sophie', 'Wagner', 'geringverdiener', monthStart(-4)],
    ['Paul', 'Fischer', 'pausiert', monthStart(-10)],
    ['Hanna', 'Schulz', 'keinverdiener', monthStart(0)]
  ]) {
    if (!userList.some((user) => user.firstName === firstName && user.lastName === lastName)) {
      await call('admin', 'POST', '/api/admin/users', { firstName, lastName, pays: status !== 'pausiert', status, memberSince: since });
    }
  }

  // Monthly fees per status, as the web app's settings write them
  // (servers 3.2+ keep a fee schedule: set from the beginning through the admin endpoint, like the web app's settings)
  const fees = { vollverdiener: 30, geringverdiener: 15, keinverdiener: 5 };
  const preview = await call('admin', 'POST', '/api/admin/fees/preview', { from: null, fees }).catch(() => null);
  if (preview?.version) await call('admin', 'POST', '/api/admin/fees', { from: null, fees, version: preview.version });
  else await call('admin', 'PUT', '/api/db', { path: 'settings', value: { ...fees, pausiert: 0 } });

  // Payments of the last months; one member pays by standing order, one is behind
  const people = await call('treasurer', 'GET', '/api/db?path=people');
  const keyOf = (name) => Object.entries(people).find(([, person]) => person?.name === name)?.[0];
  const months = [-4, -3, -2, -1, 0].map((offset) => monthStart(offset).replace(/-01$/, '-03'));
  const plan = {
    'Max Müller': months.map((date) => ({ amount: 30, date, note: 'Mitgliedsbeitrag' })),
    'Tina Kaufmann': months.map((date) => ({ amount: 30, date, note: 'Mitgliedsbeitrag' })),
    'Elias Becker': months.slice(0, 3).map((date) => ({ amount: 15, date, note: 'Mitgliedsbeitrag' })),
    'Miriam Schneider': [{ amount: 150, date: months[0], note: 'Beitrag fünf Monate' }],
    'Jonas Weber': months.slice(0, 2).map((date) => ({ amount: 30, date, note: 'Mitgliedsbeitrag' })),
    'Sophie Wagner': months.map((date) => ({ amount: 15, date, note: 'Mitgliedsbeitrag' })),
    'Anna Albrecht': [{ amount: 150, date: months[0], note: 'Beitrag fünf Monate' }],
    'Lea Hoffmann': [{ amount: 10, date: months[3], note: 'Mitgliedsbeitrag' }]
  };
  for (const [name, payments] of Object.entries(plan)) {
    const key = keyOf(name);
    if (!key || (people[key].payments || []).length) continue;
    await mutatePerson('treasurer', key, (person) => addPayments(person, payments));
  }
  const tinaKey = keyOf('Tina Kaufmann');
  if (tinaKey && !(people[tinaKey].standingOrders || []).length) {
    await mutatePerson('treasurer', tinaKey, (person) => {
      person.standingOrders = [{ id: String(nextId()), amount: 30, startDate: monthStart(1), note: 'Dauerauftrag Beitrag', lastAutoPayment: null }];
      return person;
    });
  }

  // Donations and expenses (whole lists, like the web app)
  const donations = await call('treasurer', 'GET', '/api/db?path=donations');
  if (!donations || (Array.isArray(donations) ? !donations.length : !Object.keys(donations).length)) {
    await call('treasurer', 'PUT', '/api/db', { path: 'donations', value: [
      { amount: 250, name: 'Familie Krüger', date: day(-40), description: 'Für die Jugendfreizeit', id: nextId() },
      { amount: 85.5, name: 'Kollekte', date: day(-12), description: 'Erntedank', id: nextId() },
      { amount: 1000, name: 'Anonym', date: day(-3), description: '', id: nextId() }
    ] });
    await call('treasurer', 'PUT', '/api/db', { path: 'expenses', value: [
      { amount: 129.9, issuer: 'Elias Becker', description: 'Mikrofonkabel und Batterien', date: day(-30), id: nextId(), receipt: null },
      { amount: 640, issuer: 'Stadtwerke', description: 'Strom und Heizung Quartal', date: day(-20), id: nextId(), receipt: null },
      { amount: 42.35, issuer: 'Tina Kaufmann', description: 'Kaffee und Kekse Gemeindecafé', date: day(-6), id: nextId(), receipt: null }
    ] });
  }

  // Open requests of the member (the treasurer's list), the way the app writes them
  const requests = await call('treasurer', 'GET', '/api/db?path=requests');
  if (!requests || !Object.keys(requests).length) {
    const maxKey = keyOf('Max Müller');
    const eliasKey = keyOf('Elias Becker');
    const request = async (who, user, personId, personName, type, data, offset) => {
      const id = String(Date.now() - offset * 60000);
      await call(who, 'PUT', '/api/db', { path: `requests/${id}`, value: {
        id, type, userId: user.uid || user.id, personId, personName, data, status: 'pending', timestamp: Number(id)
      } });
    };
    await request('member', users.member, maxKey, 'Max Müller', 'payment', { amount: '30.00', date: day(-1), note: 'Beitrag per Überweisung' }, 90);
    await request('member', users.member, maxKey, 'Max Müller', 'expense', { amount: '18.40', description: 'Blumen für den Altar', date: day(-2) }, 60);
    await request('events', users.events, eliasKey, 'Elias Becker', 'standing_order', { amount: '15.00', date: monthStart(1), note: 'Ab nächsten Monat per Dauerauftrag' }, 30);
    await request('events', users.events, eliasKey, 'Elias Becker', 'status', { newStatus: 'vollverdiener', date: monthStart(1) }, 10);
  }

  // Events: a service with tasks and an order of service, a members' evening with registration, a recurring house group
  const events = await call('events', 'GET', '/api/events');
  const eventList = Array.isArray(events) ? events : events.items || events.events || [];
  if (!eventList.length) {
    await call('events', 'POST', '/api/events', {
      title: 'Gottesdienst', date: next(0, 2), startTime: '10:00', endTime: '11:30', location: 'Gemeindesaal, Lindenhof 4',
      description: 'Gottesdienst mit Abendmahl. Im Anschluss **Kirchenkaffee** im Foyer.', eventType: 'termin', isPinned: false,
      requiresRegistration: false, targetGroups: [], imageUrl: '',
      duties: [{ roleName: 'Predigt' }, { roleName: 'Moderation' }, { roleName: 'Technik' }, { roleName: 'Kinderbetreuung' }]
    });
    await call('events', 'POST', '/api/events', {
      title: 'Gemeindeabend mit Grillen', date: next(5, 5), startTime: '18:30', endTime: '22:00',
      location: 'Garten hinter dem Gemeindehaus, Lindenhof 4, 12345 Musterstadt',
      description: 'Wir grillen zusammen und hören, was das Jahr über in der Gemeinde passiert ist. Bitte meldet euch bis Mittwoch an.',
      eventType: 'event', isPinned: true, requiresRegistration: true, minParticipants: 5, maxParticipants: 40, targetGroups: [], imageUrl: ''
    });
    await call('events', 'POST', '/api/events', {
      title: 'Hauskreis', date: next(3, 1), startTime: '19:30', endTime: '21:00', location: 'Bei Familie Weber',
      description: 'Wir lesen das Markusevangelium.', eventType: 'termin', isRecurring: true, recurringRule: 'weekly', recurringCount: 4,
      requiresRegistration: false, targetGroups: [], imageUrl: ''
    });
    await call('events', 'POST', '/api/events', {
      title: 'Technik-Schulung', date: day(9), startTime: '17:00', location: 'Gemeindesaal',
      description: 'Mischpult, Beamer und Livestream.', eventType: 'event', requiresRegistration: false,
      targetGroups: [groups.Technik.name], imageUrl: ''
    });
  }

  // Songs (public-domain hymns), then the service's order of service with two of them
  const songbook = await call('events', 'GET', '/api/songs');
  let songs = songbook.songs || [];
  if (!songs.length) {
    for (const song of [
      { title: 'Großer Gott, wir loben dich', artist: 'Ignaz Franz (1771)', key: 'F', ccli: '', copyright: 'Gemeinfrei', capo: null, tempo: 84,
        content: '{Strophe 1}\n[F]Großer [C]Gott, wir [F]loben [Bb]dich,\n[F]Herr, wir [C]preisen [F]deine [C]Stärke.\n[F]Vor dir [C]neigt die [Dm]Erde [A]sich\n[Dm]und be[G]wundert [C]deine Werke.\n[F]Wie du [Bb]warst vor [F]aller [C]Zeit,\n[F]so bleibst [Bb]du in [C]E[F]wigkeit.' },
      { title: 'Lobe den Herren', artist: 'Joachim Neander (1680)', key: 'G', ccli: '', copyright: 'Gemeinfrei', capo: 2, tempo: 96,
        content: '{Strophe 1}\n[G]Lobe den [Em]Herren, den [D]mächtigen [G]König der [D]Ehren,\n[G]meine ge[Em]liebete [D]Seele, das [G]ist mein Be[D]gehren.\n[G]Kommet zu[D]hauf,\n[Em]Psalter und [Bm]Harfe, wacht [C]auf,\n[G]lasset den [D]Lobgesang [G]hören!' },
      { title: 'Amazing Grace', artist: 'John Newton (1779)', key: 'G', ccli: '', copyright: 'Public Domain', capo: null, tempo: 72,
        content: '{Verse 1}\nA[G]mazing [G7]grace, how [C]sweet the [G]sound\nThat saved a wretch like [D]me.\nI [G]once was [G7]lost, but [C]now am [G]found,\nWas [Em]blind, but [D]now I [G]see.' }
    ]) {
      songs.push(await call('events', 'POST', '/api/songs', song));
    }
  }
  const allEvents = await call('events', 'GET', '/api/events');
  const service = (Array.isArray(allEvents) ? allEvents : allEvents.items || allEvents.events || []).find((event) => event.title === 'Gottesdienst');
  if (service) {
    const program = await call('events', 'GET', `/api/events/${service.id}/program`);
    if (!(program.items || []).length) {
      await call('events', 'PUT', `/api/events/${service.id}/program`, { items: [
        { id: 'p1', title: 'Begrüßung', minutes: 5, who: 'Elias Becker', note: '' },
        { id: 'p2', title: 'Lied', minutes: 5, songId: songs[0].id, songKey: 'F' },
        { id: 'p3', title: 'Lesung', minutes: 5, who: 'Max Müller', note: 'Markus 4,35-41' },
        { id: 'p4', title: 'Predigt', minutes: 30, who: 'Miriam Schneider' },
        { id: 'p5', title: 'Lied', minutes: 5, songId: songs[1].id, songKey: 'G' },
        { id: 'p6', title: 'Abendmahl', minutes: 15 },
        { id: 'p7', title: 'Segen', minutes: 2 }
      ] });
    }
    // Tasks: one asked of the member (a request on their Events tab), one taken by the mentor
    const detail = (await call('events', 'GET', '/api/events')).find?.((event) => event.id === service.id) || service;
    const duties = detail.duties || [];
    const byRole = (role) => duties.find((duty) => duty.roleName === role);
    const tech = byRole('Technik');
    if (tech && !tech.assignedTo && !tech.targetUserId) {
      await call('events', 'POST', `/api/events/duties/${tech.id}/assign`, { targetUserId: users.member.uid || users.member.id, sendEmail: false });
    }
    const sermon = byRole('Predigt');
    if (sermon && !sermon.assignedTo && !sermon.targetUserId) {
      await call('events', 'POST', `/api/events/duties/${sermon.id}/assign`, { targetUserId: users.mentor.uid || users.mentor.id, sendEmail: false });
      const mine = await call('mentor', 'GET', '/api/events/my-requests');
      const request = (Array.isArray(mine) ? mine : mine.items || mine.requests || []).find((item) => (item.dutyId || item.id) && (item.roleName === 'Predigt'));
      if (request) await call('mentor', 'POST', `/api/events/duties/${request.dutyId || request.id}/respond`, { action: 'accept' }).catch(() => {});
    }
  }
  // Registrations for the members' evening
  const evening = (await call('member', 'GET', '/api/events')).find?.((event) => event.title === 'Gemeindeabend mit Grillen');
  if (evening) {
    for (const who of ['member', 'treasurer', 'mentor']) {
      await call(who, 'POST', `/api/events/${evening.id}/register`, { action: 'register' }).catch(() => {});
    }
  }

  // Mentoring: Miriam is an approved mentor, Max has written to her and got an answer
  const profile = await call('mentor', 'GET', '/api/mentoring/my-profile');
  if (!profile || (!profile.status && !profile.profile)) {
    await call('mentor', 'POST', '/api/mentoring/apply', {
      bio: 'Seit über zehn Jahren in der Gemeinde. Ich höre gern zu – bei Fragen zu Glauben, Beruf und Familie.', max_mentees: 3
    });
  }
  const pending = await call('mentoring', 'GET', '/api/mentoring/mentors?status=pending');
  for (const mentor of (Array.isArray(pending) ? pending : pending.items || pending.mentors || [])) {
    await call('mentoring', 'POST', `/api/mentoring/manage/${mentor.id}/status`, { status: 'approved' });
  }
  const threads = await call('member', 'GET', '/api/mentoring/threads');
  if (!(Array.isArray(threads) ? threads : threads.items || threads.threads || []).length) {
    const created = await call('member', 'POST', '/api/mentoring/threads', {
      mentorId: users.mentor.uid || users.mentor.id,
      initialMessage: 'Hallo Miriam, ich stehe vor einer beruflichen Entscheidung und würde gern mit jemandem darüber reden. Hättest du Zeit?'
    });
    const threadId = created.threadId || created.id || created.thread?.id;
    if (threadId) {
      await call('mentor', 'POST', `/api/mentoring/threads/${threadId}/messages`, {
        text: 'Hallo! Sehr gern. Magst du kurz erzählen, worum es geht? Wir können uns auch nach dem Gottesdienst treffen.'
      });
    }
  }

  // Prayer requests
  const prayers = await call('member', 'GET', '/api/prayers');
  if (!(prayers.prayers || prayers.items || []).length) {
    await call('mentor', 'POST', '/api/prayers', { text: 'Für meine Mutter, die nächste Woche operiert wird.', duration: 'week', anonymous: false });
    await call('member', 'POST', '/api/prayers', { text: 'Für Weisheit bei einer beruflichen Entscheidung.', duration: 'month', anonymous: true });
    await call('events', 'POST', '/api/prayers', { text: 'Dank für die gelungene Jugendfreizeit und Bewahrung auf der Fahrt!', duration: 'week', anonymous: false });
  }

  const summary = {
    server: base,
    password: PASSWORD,
    accounts: Object.fromEntries([['admin', 'admin@demo.agora'], ...accounts.map((account) => [account.who, account.email])])
  };
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
