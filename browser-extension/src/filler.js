// The function that actually types into the page.
//
// This runs inside the page, not in the extension, so it is handed to
// chrome.scripting.executeScript and serialised on the way over. That means it
// must be completely self-contained: no imports, no outer variables, nothing
// from this file's scope. Everything it needs arrives as an argument.

export function fillCredentials(username, password) {
  const isVisible = (el) => {
    if (!el || el.disabled || el.readOnly) return false;
    if (el.offsetParent === null && getComputedStyle(el).position !== 'fixed') {
      return false;
    }
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };

  // Assigning to .value directly does not register with React, Vue and friends,
  // which listen for the events a real keystroke produces. Going through the
  // native setter and then firing the events is what makes the page believe a
  // person typed it.
  const setValue = (el, value) => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      'value',
    ).set;
    setter.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };

  const passwordField = Array.from(
    document.querySelectorAll('input[type="password"]'),
  ).find(isVisible);

  const usernameCandidates = Array.from(
    document.querySelectorAll(
      'input[type="text"], input[type="email"], input[type="tel"], input:not([type])',
    ),
  ).filter(isVisible);

  let usernameField = null;

  if (passwordField) {
    const scope = passwordField.form || document;
    // The username box is almost always the last one before the password box,
    // so walk backwards from the password field within the same form.
    const inScope = usernameCandidates.filter((el) =>
      scope === document ? true : scope.contains(el),
    );
    const before = inScope.filter(
      (el) =>
        el.compareDocumentPosition(passwordField) &
        Node.DOCUMENT_POSITION_FOLLOWING,
    );
    usernameField = before[before.length - 1] || inScope[0] || null;
  } else {
    // A username-first sign-in page, where the password appears on a later
    // step. Prefer a field that says what it is.
    usernameField =
      usernameCandidates.find((el) => {
        const hint = `${el.autocomplete || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
        return /user|email|login|account/.test(hint);
      }) ||
      usernameCandidates[0] ||
      null;
  }

  let filled = 0;
  if (usernameField && username) {
    setValue(usernameField, username);
    filled++;
  }
  if (passwordField && password) {
    setValue(passwordField, password);
    filled++;
    passwordField.focus();
  } else if (usernameField) {
    usernameField.focus();
  }

  if (filled === 0) return 'no-fields';
  if (!passwordField) return 'username-only';
  return 'ok';
}
