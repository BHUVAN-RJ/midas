import { Hono } from "hono";
import type { Context } from "hono";

// The two public pages App Store Connect links to (build 22, founder 2026-10-31): GET /privacy and
// GET /support, served by the Worker with no sign-in. Words: docs/briefs/app-store-submission.md
// sections 1 and 2 (facts and sources there). Plain HTML, no scripts, no other origins.

export const SUPPORT_EMAIL = "bhuvanrj73@gmail.com";
export const PRIVACY_EFFECTIVE_DATE = "2026-10-31";

// One block of a page: a heading, then paragraphs and/or a bullet list.
type PageSection = { heading: string; paragraphs?: string[]; bullets?: string[] };

type PublicPage = { title: string; subtitle?: string; sections: PageSection[] };

export const PRIVACY_PAGE: PublicPage = {
  title: "Midas Privacy Policy",
  subtitle: `Effective ${PRIVACY_EFFECTIVE_DATE}`,
  sections: [
    {
      heading: "What Midas keeps",
      bullets: [
        "Account: the name you type when you start, and your passkey's public key. Midas has no email, phone number or password for you. The private part of your passkey stays in your iCloud Keychain.",
        "Sidekicks: everything you add in your Sidekicks (lists, reminders, drinks, notes, photos you attach) is backed up to Midas so it comes back on a new phone.",
        "Apple Reminders: if you tap Import, Midas reads your Apple Reminders on your iPhone (lists, titles, notes, links, due dates, alerts, repeats, priority, done or not) and saves them in your Reminders Sidekick. Midas never changes Apple Reminders.",
        "Notifications: your iPhone's push token, so Midas can send you notifications.",
        "Device details: iPhone model, iOS version and Midas version, sent with voice requests and Edit requests.",
      ],
    },
    {
      heading: "Voice",
      bullets: [
        "Your voice is turned into text on your iPhone. Audio never leaves your iPhone.",
        "The text is sent to Midas, with your time zone and the names and a short summary of what is in your Sidekicks, to work out what you asked.",
        "To understand the text, Midas sends it through OpenRouter to a language model provider. Midas asks OpenRouter to use only providers that do not keep or train on the data.",
        "Midas keeps a log of each voice request (the text, the answer and the device details) to see what worked.",
      ],
    },
    {
      heading: "Edit",
      paragraphs: ["When you send an Edit, Midas receives:"],
      bullets: [
        "what you said (as text) and anything you typed",
        "a screenshot of the Sidekick, your drawing and its strokes",
        "your iPhone model, iOS version and Midas version",
      ],
    },
    {
      heading: "Who makes Edits",
      paragraphs: [
        "Edits are made by Claude Code, Anthropic's coding assistant, running on Midas's own computer. Your request and that Sidekick's data are copied to that computer and sent to Anthropic so Claude Code can make the change. Midas keeps every Edit request and its result.",
      ],
    },
    {
      heading: "Make",
      paragraphs: ["What you write in Make goes to the person who makes Midas, who reads it and answers."],
    },
    {
      heading: "Who sees your data",
      bullets: [
        "The person who makes Midas, to run Midas, answer Make requests and fix problems.",
        "Cloudflare, which stores Midas's data.",
        "OpenRouter and the model provider it picks, for voice requests (not kept by them).",
        "Anthropic, for Edit requests.",
        "Apple, to deliver notifications.",
      ],
      paragraphs: ["Midas has no ads, does no tracking across other apps or websites, and never sells your data."],
    },
    {
      heading: "Delete your account",
      paragraphs: [`In Midas: Settings, then Delete Account. Your account and all your data are deleted within 7 days. To ask for deletion another way, email ${SUPPORT_EMAIL}.`],
    },
    {
      heading: "Changes",
      paragraphs: ["This page shows the date of the latest version."],
    },
    {
      heading: "Contact",
      paragraphs: [SUPPORT_EMAIL],
    },
  ],
};

export const SUPPORT_PAGE: PublicPage = {
  title: "Midas Support",
  sections: [
    { heading: "Help", paragraphs: [`Email ${SUPPORT_EMAIL}`] },
    { heading: "Edit a Sidekick", paragraphs: ["Open it. Swipe down with three fingers. Say or draw the change. Tap Send."] },
    { heading: "Delete a Sidekick", paragraphs: ["On the home screen, press and hold its tile. Tap the minus. Tap Delete."] },
    { heading: "Delete your account", paragraphs: ["Tap your initial, top right of the home screen. Tap Delete Account.", "Your account is deleted within 7 days."] },
  ],
};

const HTML_ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

function escapeCharacter(character: string): string {
  return HTML_ESCAPES[character];
}

export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, escapeCharacter);
}

// The email address becomes a mailto link; everything else is escaped text.
function withMailLink(text: string): string {
  const escaped = escapeHtml(text);
  return escaped.replaceAll(SUPPORT_EMAIL, `<a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>`);
}

function sectionHtml(section: PageSection): string {
  const parts = [`<h2>${escapeHtml(section.heading)}</h2>`];
  const paragraphs = section.paragraphs ?? [];
  const bullets = section.bullets ?? [];
  // A list's lead-in paragraph comes first; a closing line (Who sees your data) after the list
  const leadIn = section.bullets !== undefined && paragraphs.length > 0 && paragraphs[0].endsWith(":");
  const before = leadIn ? paragraphs : section.bullets === undefined ? paragraphs : [];
  const after = leadIn || section.bullets === undefined ? [] : paragraphs;
  for (const paragraph of before) {
    parts.push(`<p>${withMailLink(paragraph)}</p>`);
  }
  if (bullets.length > 0) {
    const items = bullets.map(withMailLink);
    const listItems = items.map(function wrapItem(item) {
      return `<li>${item}</li>`;
    });
    parts.push(`<ul>${listItems.join("")}</ul>`);
  }
  for (const paragraph of after) {
    parts.push(`<p>${withMailLink(paragraph)}</p>`);
  }
  return parts.join("\n");
}

const PAGE_STYLE = [
  ":root{color-scheme:light dark;--ink:#111;--paper:#fff;--soft:#666}",
  "@media (prefers-color-scheme:dark){:root{--ink:#f2f2f2;--paper:#000;--soft:#999}}",
  "body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.5 -apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif}",
  "main{max-width:640px;margin:0 auto;padding:32px 16px 64px}",
  "h1{font-size:28px;margin:0 0 4px}h2{font-size:19px;margin:28px 0 6px}",
  ".subtitle{color:var(--soft);margin:0}ul{padding-left:20px}a{color:inherit}",
].join("");

export function renderPage(page: PublicPage): string {
  const subtitle = page.subtitle === undefined ? "" : `<p class="subtitle">${escapeHtml(page.subtitle)}</p>`;
  const sections = page.sections.map(sectionHtml);
  return [
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${escapeHtml(page.title)}</title>`,
    `<style>${PAGE_STYLE}</style></head>`,
    `<body><main><h1>${escapeHtml(page.title)}</h1>${subtitle}`,
    sections.join("\n"),
    "</main></body></html>",
  ].join("\n");
}

function servePage(c: Context, page: PublicPage) {
  const html = renderPage(page);
  return c.html(html, 200, { "Cache-Control": "public, max-age=300", "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'" });
}

function handlePrivacy(c: Context) {
  return servePage(c, PRIVACY_PAGE);
}

function handleSupport(c: Context) {
  return servePage(c, SUPPORT_PAGE);
}

export const publicPageRoutes = new Hono();
publicPageRoutes.get("/privacy", handlePrivacy);
publicPageRoutes.get("/support", handleSupport);
