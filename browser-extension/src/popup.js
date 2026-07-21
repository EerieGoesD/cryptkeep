// The popup. It holds no secrets of its own: it asks the service worker for a
// list of entry names, and only ever receives one password at a time, at the
// moment the user asks to copy it.

const $ = (id) => document.getElementById(id);

function send(type, payload = {}) {
  return chrome.runtime.sendMessage({ type, payload });
}

function show(view) {
  for (const id of ['view-locked', 'view-mfa', 'view-vault']) {
    $(id).hidden = id !== view;
  }
}

function showError(el, message) {
  el.textContent = message;
  el.hidden = !message;
}

let activeTab = null;
let allEntries = { matching: [], rest: [] };
let isPremium = false;

async function currentTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab || null;
}

// ─── Unlocking ──────────────────────────────────────────────────────────────

$('unlock-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = $('unlock-button');
  showError($('unlock-error'), '');
  button.disabled = true;
  button.textContent = 'Unlocking';

  try {
    const result = await send('unlock', {
      email: $('email').value,
      masterPassword: $('master').value,
    });

    if (result.error) {
      showError($('unlock-error'), result.error);
    } else if (result.needsSecondFactor) {
      show('view-mfa');
      $('mfa-code').focus();
    } else {
      // Remember the address so only the master password is needed next time.
      await chrome.storage.local.set({ lastEmail: $('email').value.trim() });
      $('master').value = '';
      await openVault();
    }
  } finally {
    button.disabled = false;
    button.textContent = 'Unlock';
  }
});

$('mfa-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  showError($('mfa-error'), '');
  const result = await send('submitSecondFactor', { code: $('mfa-code').value });
  if (result.error) {
    showError($('mfa-error'), result.error);
    return;
  }
  $('master').value = '';
  await openVault();
});

$('open-web').addEventListener('click', async (event) => {
  event.preventDefault();
  const state = await send('getState');
  chrome.tabs.create({ url: state.webAppUrl });
});

$('lock-button').addEventListener('click', async () => {
  await send('lock');
  showLocked();
});

$('refresh-button').addEventListener('click', async () => {
  $('refresh-button').textContent = 'Refreshing';
  const result = await send('refresh');
  $('refresh-button').textContent = 'Refresh';
  if (result.locked) return showLocked();
  await loadEntries();
});

$('search').addEventListener('input', renderEntries);

// ─── Vault ──────────────────────────────────────────────────────────────────

async function openVault() {
  const state = await send('getState');
  if (state.locked) return showLocked();
  isPremium = state.premium;
  $('account').textContent = state.premium
    ? `${state.email} - Pro`
    : state.email;
  show('view-vault');
  await loadEntries();
}

async function loadEntries() {
  const result = await send('list', { pageUrl: activeTab?.url || '' });
  if (result.locked) return showLocked();
  if (result.error) {
    $('entries').innerHTML = `<p class="empty">${result.error}</p>`;
    return;
  }
  allEntries = result;
  renderEntries();
}

function filterEntries(entries, query) {
  if (!query) return entries;
  return entries.filter((entry) =>
    `${entry.title} ${entry.username} ${entry.url}`
      .toLowerCase()
      .includes(query),
  );
}

function renderEntries() {
  const query = $('search').value.trim().toLowerCase();
  const matching = filterEntries(allEntries.matching, query);
  const rest = filterEntries(allEntries.rest, query);
  const container = $('entries');
  container.textContent = '';

  if (!matching.length && !rest.length) {
    container.innerHTML = `<p class="empty">${
      query ? 'Nothing matches that.' : 'This vault is empty.'
    }</p>`;
    return;
  }

  if (matching.length) {
    container.append(groupLabel('For this site'));
    matching.forEach((entry) => container.append(entryCard(entry)));
  }
  if (rest.length) {
    container.append(groupLabel(matching.length ? 'Everything else' : 'All entries'));
    rest.forEach((entry) => container.append(entryCard(entry)));
  }
}

function groupLabel(text) {
  const el = document.createElement('p');
  el.className = 'group-label';
  el.textContent = text;
  return el;
}

function entryCard(entry) {
  const card = document.createElement('div');
  card.className = 'entry';

  const title = document.createElement('div');
  title.className = 'entry-title';
  title.textContent = entry.title || '(no title)';
  card.append(title);

  const sub = document.createElement('div');
  sub.className = 'entry-sub';
  sub.textContent = entry.username || entry.url || '';
  card.append(sub);

  const actions = document.createElement('div');
  actions.className = 'entry-actions';

  if (entry.isPasskey) {
    const note = document.createElement('span');
    note.className = 'entry-sub';
    note.textContent = 'Passkey - use the app to sign in';
    actions.append(note);
  } else {
    actions.append(
      button('Fill', 'fill', async (el) => {
        if (!activeTab) return;
        const result = await send('fill', {
          entryId: entry.id,
          tabId: activeTab.id,
        });
        if (result.locked) return showLocked();
        if (result.error) return flash(el, 'Failed');
        flash(el, 'Filled');
        if (result.message) setStatus(result.message);
        else window.close();
      }),
    );

    actions.append(
      button('Copy password', '', (el) => copyField(entry.id, 'password', el)),
    );
  }

  if (entry.username) {
    actions.append(
      button('Copy user', '', (el) => copyField(entry.id, 'username', el)),
    );
  }

  if (entry.hasTotp) {
    actions.append(
      button('2FA code', '', async (el) => {
        const result = await send('totp', { entryId: entry.id });
        if (result.locked) return showLocked();
        if (result.error === 'pro-required') {
          setStatus('Two-factor codes are part of Pro.');
          return;
        }
        if (result.error) return flash(el, 'Failed');
        showTotp(card, result);
      }),
    );
  }

  card.append(actions);
  return card;
}

function button(label, className, onClick) {
  const el = document.createElement('button');
  el.textContent = label;
  if (className) el.className = className;
  el.addEventListener('click', () => onClick(el));
  return el;
}

async function copyField(entryId, field, el) {
  const result = await send('reveal', { entryId, field });
  if (result.locked) return showLocked();
  if (result.error) return flash(el, 'Failed');
  await navigator.clipboard.writeText(result.value);
  flash(el, 'Copied');
}

function showTotp(card, result) {
  let line = card.querySelector('.totp-code');
  if (!line) {
    line = document.createElement('div');
    line.className = 'totp-code';
    card.append(line);
  }
  line.textContent = `${result.code}  -  ${result.secondsRemaining}s left`;
  navigator.clipboard.writeText(result.code).catch(() => {});
}

function flash(el, text) {
  const original = el.textContent;
  el.textContent = text;
  setTimeout(() => {
    el.textContent = original;
  }, 1200);
}

function setStatus(message) {
  const el = $('vault-status');
  el.textContent = message;
  el.hidden = !message;
}

async function showLocked() {
  show('view-locked');
  const { lastEmail } = await chrome.storage.local.get('lastEmail');
  if (lastEmail) {
    $('email').value = lastEmail;
    $('master').focus();
  } else {
    $('email').focus();
  }
}

// ─── Start ──────────────────────────────────────────────────────────────────

(async function init() {
  activeTab = await currentTab();
  const state = await send('getState');
  if (state.locked) await showLocked();
  else await openVault();
})();
