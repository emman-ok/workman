// Email. Owned by AppWand.
//
//   import { sendEmail } from '../mail.js';
//   await sendEmail({
//     to: customer.email,
//     subject: `Order #${order.id} is on its way`,
//     heading: 'Your order shipped',
//     lines: [`Order #${order.id} left our warehouse today.`],
//     button: { label: 'Open the order', url: `/orders/${order.id}` },
//   });
//   await sendEmail({ to, subject, template: 'weekly_digest/summary', data: { name, tasks } });
//
// A template is emails/<automation id>/<name>.hbs (Handlebars); every email is
// put in emails/layout.hbs, the frame with the app's name and colour. Email
// goes over SMTP (SMTP_HOST and the rest in .env, like the sign-in codes).
// Until that is set up, each email is printed in the API's console instead.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Handlebars from 'handlebars';
import nodemailer from 'nodemailer';
import { APP } from './app.g.js';

const EMAILS = path.join(path.dirname(fileURLToPath(import.meta.url)), 'emails');
const TEMPLATE = /^[a-z][a-z0-9_]*\/[A-Za-z0-9_-]+$/;

/** Where links in emails point: APP_URL in .env, or the web app's address once it is online. '' when neither. */
export const appUrl = () => (process.env.APP_URL || APP.url || '').replace(/\/+$/, '');

/** A full link for an app route ('/orders/5') or an address; '' when the app has no web address. */
export function linkTo(url) {
  const value = String(url ?? '').trim();
  if (/^(https?:|mailto:|tel:)/i.test(value)) return value;
  // The Flutter web app keeps its route after the #.
  return appUrl() && value.startsWith('/') ? `${appUrl()}/#${value}` : '';
}

const locale = () => process.env.APP_LOCALE || 'en';

function formatDate(value, options) {
  if (value === null || value === undefined || value === '') return '';
  // A date without a time is that day everywhere.
  const dateOnly = typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat(locale(), { timeZone: dateOnly ? 'UTC' : APP.timezone || undefined, ...options }).format(date);
}

/** White or near-black, whichever reads on [hex]. */
function onColor(hex) {
  const n = parseInt(String(hex).replace('#', ''), 16);
  const luminance = (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
  return luminance > 0.6 ? '#111827' : '#ffffff';
}

const escape = Handlebars.escapeExpression;

function buttonHtml(label, url) {
  const href = linkTo(url);
  if (!href || !label) return '';
  return (
    `<p style="margin:24px 0 8px"><a href="${escape(href)}" style="display:inline-block;background:${APP.color};` +
    `color:${onColor(APP.color)};padding:12px 22px;border-radius:8px;text-decoration:none;font-weight:600">${escape(label)}</a></p>`
  );
}

// What templates may use besides their data: {{date due_on}}, {{datetime created_at}}, {{time starts_at}},
// {{number quantity}}, {{money total}} or {{money total "USD"}}, {{#if (eq status "open")}}, {{link "/orders/5"}}
// and {{button "Open the order" url}}; {{appName}}, {{appUrl}} and {{year}} are always there.
const hbs = Handlebars.create();
hbs.registerHelper('date', (value) => formatDate(value, { dateStyle: 'medium' }));
hbs.registerHelper('datetime', (value) => formatDate(value, { dateStyle: 'medium', timeStyle: 'short' }));
hbs.registerHelper('time', (value) => formatDate(value, { timeStyle: 'short' }));
hbs.registerHelper('number', (value) => new Intl.NumberFormat(locale(), { maximumFractionDigits: 2 }).format(Number(value) || 0));
hbs.registerHelper('money', (value, currency) =>
  new Intl.NumberFormat(
    locale(),
    typeof currency === 'string' ? { style: 'currency', currency } : { minimumFractionDigits: 2, maximumFractionDigits: 2 },
  ).format(Number(value) || 0),
);
hbs.registerHelper('eq', (a, b) => a === b);
hbs.registerHelper('link', (url) => linkTo(url));
hbs.registerHelper('button', (label, url) => new Handlebars.SafeString(buttonHtml(label, typeof url === 'string' ? url : '')));

// Compiled once per version of the file, so an edited template shows without a restart.
const compiled = new Map();

function templateFor(file) {
  const stamp = fs.statSync(file).mtimeMs;
  const hit = compiled.get(file);
  if (hit && hit.stamp === stamp) return hit.render;
  const render = hbs.compile(fs.readFileSync(file, 'utf8'));
  compiled.set(file, { stamp, render });
  return render;
}

const shared = () => ({ appName: APP.name, appUrl: appUrl(), year: new Date().getFullYear() });

function bodyOf({ template, data, heading, lines, button }) {
  if (template) {
    if (!TEMPLATE.test(template)) throw new Error(`"${template}" is not an email template; name it "<automation id>/<name>".`);
    return templateFor(path.join(EMAILS, `${template}.hbs`))({ ...shared(), ...(data ?? {}) });
  }
  return [
    heading ? `<h1>${escape(heading)}</h1>` : '',
    ...[lines ?? []].flat().map((line) => `<p>${escape(line)}</p>`),
    button ? buttonHtml(button.label, button.url) : '',
  ].join('\n');
}

const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#x27;': "'", '&#39;': "'", '&#x3D;': '=', '&#x60;': '`', '&nbsp;': ' ' };

/** The email as plain text, for mail programs that show no HTML. */
function plain(html) {
  return html
    .replace(/<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, '$2 ($1)')
    .replace(/<\/(p|h[1-6]|tr|li|div|table)>|<br\s*\/?>/gi, '\n')
    .replace(/<\/(td|th)>/gi, '  ')
    .replace(/<[^>]+>/g, '')
    .replace(/&(amp|lt|gt|quot|nbsp|#x27|#39|#x3D|#x60);/g, (entity) => ENTITIES[entity] ?? entity)
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

let transport;

function mailer() {
  if (!process.env.SMTP_HOST) return null;
  const port = Number(process.env.SMTP_PORT || 587);
  transport ??= nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port,
    secure: port === 465,
    auth: process.env.SMTP_USER ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS } : undefined,
  });
  return transport;
}

/**
 * Sends an email to [to] (an address, or several: each gets its own copy).
 *   { to, subject, heading?, lines?, button?: { label, url }, template?, data?, text?, replyTo?, attachments? }
 * The body is `template` (emails/<automation id>/<name>.hbs, filled with `data`),
 * or else `heading`, the paragraphs in `lines` and a `button`. A button's url is
 * an app route ('/orders/5') or a full address; it is left out when the app has
 * no web address. Resolves to how many people it went to. It never throws: a
 * template that fails or a mail server that refuses is logged and counts as 0,
 * so the request or the job that called it carries on.
 */
export async function sendEmail(message = {}) {
  const subject = String(message.subject ?? '').trim();
  const recipients = [...new Set([message.to].flat().map((to) => String(to ?? '').trim()).filter((to) => to.includes('@')))];
  if (recipients.length === 0 || !subject) return 0;
  let html;
  let text;
  try {
    const body = bodyOf(message);
    html = templateFor(path.join(EMAILS, 'layout.hbs'))({ ...shared(), subject, body, color: APP.color, onColor: onColor(APP.color) });
    text = message.text || plain(body);
  } catch (err) {
    console.error(`[mail] "${subject}" could not be put together: ${err.message}`);
    return 0;
  }
  let sent = 0;
  for (const to of recipients) {
    try {
      if (mailer()) {
        await mailer().sendMail({
          from: process.env.MAIL_FROM || process.env.SMTP_USER,
          to,
          subject,
          text,
          html,
          replyTo: message.replyTo,
          attachments: message.attachments,
        });
      } else {
        console.log(`[mail] Not sent (set SMTP_HOST in .env to send it). To ${to}: ${subject}\n${text}\n`);
      }
      sent++;
    } catch (err) {
      console.error(`[mail] Could not send "${subject}" to ${to}: ${err.message}`);
    }
  }
  return sent;
}
