// Sends one-time codes: email over SMTP (nodemailer) and SMS through Twilio,
// both set up in api/.env. Owned by AppWand. Until one is set up, the message
// is printed in the API's console instead, which is enough to try the flows
// on this computer.
import nodemailer from 'nodemailer';
import { APP_NAME } from './options.g.js';

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

const twilioReady = () => Boolean(process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_FROM);

function messageFor(code, purpose) {
  const use = purpose === 'reset' ? 'reset your password' : 'sign in';
  return `Your ${APP_NAME} code is ${code}. Use it to ${use} within 10 minutes. If you did not ask for it, ignore this message.`;
}

async function sendSms(to, body) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const auth = Buffer.from(`${sid}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64');
  const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ From: process.env.TWILIO_FROM, To: to, Body: body }),
  });
  if (!res.ok) throw new Error(`Twilio answered ${res.status}: ${await res.text()}`);
}

/**
 * Sends [code] to { channel: 'email' | 'sms', to }. Never throws: a failure
 * is logged, because the caller's answer must not reveal it.
 */
export async function sendCode({ channel, to, code, purpose }) {
  const text = messageFor(code, purpose);
  try {
    if (channel === 'email' && mailer()) {
      await mailer().sendMail({
        from: process.env.MAIL_FROM || process.env.SMTP_USER,
        to,
        subject: `Your ${APP_NAME} code: ${code}`,
        text,
      });
    } else if (channel === 'sms' && twilioReady()) {
      await sendSms(to, text);
    } else {
      const setting = channel === 'sms' ? 'TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM' : 'SMTP_HOST';
      console.log(`[auth] Not sent (set ${setting} in .env to send it). To ${to}: ${text}`);
    }
  } catch (err) {
    console.error(`[auth] Could not send the code to ${to}: ${err.message}`);
  }
}
