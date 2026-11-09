import { Hono } from "hono";
import type { Context } from "hono";

// The two public pages App Store Connect links to (build 22, founder 2026-10-31): GET /privacy and
// GET /support, served by the Worker with no sign-in. Words: docs/briefs/app-store-submission.md
// sections 1 and 2 (facts and sources there). Plain HTML, no scripts, no other origins.
// Look: P1 "Plain" from docs/mockups/public-pages-2026-10-31.html (founder, 2026-11-01): the written
// Midas wordmark, the words, a Privacy / Support footer; DESIGN.md tokens, light and dark.

export const SUPPORT_EMAIL = "bhuvanrj73@gmail.com";
export const PRIVACY_EFFECTIVE_DATE = "2026-10-31";

// One block of a page: a heading, then paragraphs and/or a bullet list.
type PageSection = { heading: string; paragraphs?: string[]; bullets?: string[] };

// path: where the page is served, so the footer can mark the current page.
type PublicPage = { title: string; subtitle?: string; path?: string; sections: PageSection[] };

export const PRIVACY_PAGE: PublicPage = {
  title: "Midas Privacy Policy",
  subtitle: `Effective ${PRIVACY_EFFECTIVE_DATE}`,
  path: "/privacy",
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
        "Midas keeps a log of each voice request (the text, the answer and the device details) to see what worked. The log is kept while your account exists and is deleted with it.",
      ],
    },
    {
      heading: "Camera",
      bullets: [
        "A photo you take with jess's camera is sent with your request, through OpenRouter, to a model provider that reads images, the same way as the text above.",
        "When the photo is a receipt that jess adds to Money, it is kept with that expense, in your Midas files, so you can see it there. Otherwise Midas does not keep the photo. It stays on your iPhone, on that request's card.",
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
        "Edits are made by Anthropic's Claude coding assistant on a Midas server. Your request and that Sidekick's data are sent to Anthropic so it can make the change. Midas keeps every Edit request and its result.",
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
        "Cloudflare, which stores Midas's data. Cloudflare's server logs may include your IP address and are kept for up to 7 days.",
        "OpenRouter and the model provider it picks, for voice requests (not kept by them).",
        "Anthropic, for Edit requests.",
        "Apple, to deliver notifications.",
      ],
      paragraphs: ["Midas has no ads, does no tracking across other apps or websites, and never sells your data."],
    },
    {
      heading: "Delete your account",
      paragraphs: [`In Midas: Settings, then Delete Account. Your account and all your data are deleted within 7 days from Midas's servers: your Sidekicks and their records, your files, your jess requests, your Edit requests with their screenshots and drawings, your Make conversations and your push tokens. Database backups can keep a copy for up to 7 more days, then it is gone. Data on your iPhone is removed when you delete the app. Requests already sent to OpenRouter's providers or to Anthropic follow their policies. To ask for deletion another way, email ${SUPPORT_EMAIL}.`],
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
  path: "/support",
  sections: [
    { heading: "Help", paragraphs: [`Email ${SUPPORT_EMAIL}`] },
    { heading: "Edit a Sidekick", paragraphs: ["Open it. Swipe down with three fingers. Say or draw the change. Tap Send."] },
    { heading: "Delete a Sidekick", paragraphs: ["On the home screen, press and hold its tile. Tap the minus. Tap Delete."] },
    { heading: "Delete your account", paragraphs: ["Tap your initial, top right of the home screen. Tap Delete Account.", "Your account is deleted within 7 days."] },
    // Account recovery W1 (founder, 2026-11-02): a lost passkey is recovered by hand, by email.
    // Only here, not in the app (CONCERNS §5).
    { heading: "Lost passkey", paragraphs: [`Email ${SUPPORT_EMAIL} with your Midas name.`] },
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

// Visual only: a short label before the first colon ("Account:") is set in semibold; words unchanged.
const LABEL_MAX_LENGTH = 22;

function withLabel(text: string): string {
  const html = withMailLink(text);
  const colon = html.indexOf(": ");
  if (colon < 0 || colon > LABEL_MAX_LENGTH) {
    return html;
  }
  const label = html.slice(0, colon + 1);
  const rest = html.slice(colon + 1);
  return `<b>${label}</b>${rest}`;
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
    const items = bullets.map(withLabel);
    const listItems = items.map(function wrapItem(item) {
      return `<li>${item}</li>`;
    });
    parts.push(`<ul>${listItems.join("")}</ul>`);
  }
  for (const paragraph of after) {
    parts.push(`<p>${withMailLink(paragraph)}</p>`);
  }
  return `<section>${parts.join("\n")}</section>`;
}

// P1 look. Colours: docs/DESIGN.md 2.1 (light) and 2.4 (dark).
const PAGE_STYLE = [
  ":root{color-scheme:light dark;--paper:#FFFFFF;--ink:#111111;--ink-2:#6B6B6B;--rule:rgba(17,17,17,0.12);--gutter:20px}",
  "@media (prefers-color-scheme:dark){:root{--paper:#111111;--ink:#FFFFFF;--ink-2:#A3A3A3;--rule:rgba(255,255,255,0.14)}}",
  "@media (min-width:800px){:root{--gutter:56px}}",
  "*{box-sizing:border-box}",
  "html,body{margin:0;background:var(--paper);color:var(--ink)}",
  "body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','SF Pro','Helvetica Neue',sans-serif;-webkit-font-smoothing:antialiased;min-height:100vh;display:flex;flex-direction:column}",
  "main{flex:1}a{color:inherit}",
  ".top{display:flex;align-items:center;justify-content:space-between;padding:16px var(--gutter)}",
  ".mark{display:block;height:36px;width:auto;fill:currentColor}",
  ".doc{max-width:680px;margin:0 auto;padding:40px 20px 0;font-size:17px;line-height:1.55}",
  ".doc h1{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','SF Pro','Helvetica Neue',sans-serif;font-weight:700;letter-spacing:-0.025em;line-height:1.08;font-size:clamp(32px,4.4vw,48px);margin:0}",
  ".doc .subtitle{color:var(--ink-2);margin:8px 0 0;font-size:15px}",
  ".doc section{padding-top:28px;margin-top:28px;border-top:1px solid var(--rule)}",
  ".doc section:first-of-type{border-top:0;margin-top:20px}",
  ".doc h2{font-size:20px;letter-spacing:-0.01em;margin:0 0 8px}",
  ".doc p{margin:0 0 10px}.doc ul{list-style:none;padding:0;margin:0 0 10px}",
  ".doc li{position:relative;padding-left:20px;margin-bottom:10px}",
  ".doc li::before{content:'';position:absolute;left:2px;top:0.75em;width:8px;height:2px;background:var(--ink);border-radius:1px}",
  ".doc li b{font-weight:600}.doc a{text-decoration-thickness:1px;text-underline-offset:3px}",
  ".foot{display:flex;gap:24px;align-items:center;flex-wrap:wrap;padding:22px var(--gutter) 30px;border-top:1px solid var(--rule);font-size:14px;margin-top:72px}",
  ".foot a{text-decoration:none}.foot a:hover,.foot a[aria-current=page]{text-decoration:underline;text-underline-offset:3px}",
  ".foot .copy-note{color:var(--ink-2);margin-left:auto}",
].join("");

// The written "Midas": Caveat Bold (SIL OFL, shell/icon-source/Caveat-Bold.ttf) drawn as one path, so
// the page needs no font file. The box is one line at 1000 units per em, like the mockup's 36 px text.
const WORDMARK_PATH =
  "M675 48Q671 52 656 50Q641 49 632 36Q625 22 624 4Q623 -14 624 -46Q630 -81 644 -138Q658 -195 676 -266Q693 -336 711 -410Q720 -445 726 -469Q731 -493 734 -506Q736 -518 736 -518Q735 -516 734 -514Q732 -512 731 -510Q730 -508 729 -506Q729 -506 726 -499Q722 -492 711 -475Q703 -463 696 -447Q689 -431 672 -405Q656 -375 636 -336Q616 -297 602 -274Q595 -263 590 -255Q584 -247 582 -242Q578 -231 569 -215Q560 -199 548 -184Q542 -175 532 -163Q523 -151 516 -142Q509 -132 509 -132Q507 -126 496 -113Q485 -100 470 -84Q454 -69 438 -56Q403 -28 380 -21Q358 -14 329 -38Q316 -54 308 -70Q300 -87 300 -116Q300 -145 310 -197Q317 -230 326 -267Q334 -304 343 -338Q352 -373 360 -398Q367 -424 370 -434Q373 -459 371 -460Q369 -462 361 -449Q354 -438 335 -403Q316 -368 292 -321Q269 -274 247 -227Q206 -151 178 -100Q150 -49 132 -18Q114 12 104 28Q95 43 90 50Q86 56 84 58Q69 57 58 44Q47 31 40 13Q38 3 37 -8Q36 -19 40 -32Q43 -46 51 -62Q64 -88 76 -106Q88 -124 91 -128Q96 -135 99 -143Q102 -151 103 -158Q108 -164 118 -183Q129 -202 140 -224Q148 -237 162 -260Q176 -284 192 -312Q208 -339 220 -362Q264 -441 290 -488Q316 -536 327 -549Q334 -554 340 -568Q345 -583 349 -590Q363 -618 378 -636Q392 -655 403 -655Q411 -655 424 -649Q436 -643 448 -632Q459 -619 468 -598Q478 -576 472 -541Q471 -525 467 -502Q463 -480 459 -458Q455 -436 451 -421Q443 -376 434 -336Q424 -295 416 -261Q408 -227 403 -202Q398 -176 396 -160Q395 -144 400 -139Q403 -138 408 -142Q414 -145 417 -149Q423 -157 428 -165Q433 -173 441 -185Q457 -207 474 -234Q492 -260 516 -300Q541 -339 575 -398Q609 -456 658 -543Q681 -578 702 -613Q723 -648 740 -667Q755 -683 778 -678Q800 -673 819 -653Q838 -633 840 -604Q841 -590 834 -554Q828 -519 817 -475Q806 -431 792 -389Q789 -372 782 -344Q775 -316 767 -287Q759 -258 752 -235Q745 -201 740 -181Q736 -161 736 -135Q727 -119 724 -89Q721 -59 721 -27Q717 12 704 28Q692 44 688 43Q680 40 675 48ZM832 -17Q824 -25 820 -41Q817 -57 818 -72Q819 -88 823 -96Q823 -104 826 -108Q828 -113 827 -117Q826 -121 829 -131Q832 -141 835 -150Q842 -166 851 -192Q860 -217 869 -244Q878 -270 884 -290Q890 -309 891 -313Q891 -325 907 -326Q919 -330 936 -316Q953 -302 963 -286Q971 -278 969 -265Q967 -252 956 -228Q952 -220 946 -202Q941 -183 939 -171Q935 -163 930 -148Q924 -134 920 -121Q918 -116 916 -102Q914 -89 911 -75Q908 -61 903 -53Q894 -12 872 -5Q849 2 832 -17ZM940 -418Q929 -426 924 -438Q918 -449 918 -458Q917 -467 919 -469Q929 -480 936 -498Q944 -516 953 -531Q955 -534 958 -540Q962 -545 966 -546Q978 -554 1000 -545Q1021 -536 1031 -520Q1040 -501 1036 -481Q1033 -461 1015 -439Q1000 -419 977 -414Q954 -408 940 -418ZM1299 19Q1286 22 1274 12Q1261 3 1256 -8Q1250 -24 1248 -38Q1247 -53 1246 -72L1245 -106L1204 -69Q1170 -37 1140 -24Q1111 -10 1087 -10Q1076 -12 1060 -24Q1045 -37 1032 -52Q1020 -68 1015 -78Q1009 -92 1012 -117Q1014 -142 1024 -172Q1033 -202 1048 -231Q1062 -260 1081 -281Q1114 -331 1163 -344Q1212 -356 1250 -335Q1268 -326 1276 -328Q1284 -330 1286 -341Q1290 -357 1295 -371Q1300 -385 1309 -413Q1334 -489 1352 -532Q1371 -575 1386 -607Q1397 -630 1408 -639Q1419 -648 1427 -647Q1438 -647 1454 -639Q1471 -631 1476 -617Q1480 -608 1480 -598Q1479 -588 1473 -577Q1460 -553 1442 -514Q1425 -474 1408 -427Q1390 -380 1375 -334Q1360 -288 1350 -253Q1344 -231 1340 -197Q1337 -163 1336 -128Q1334 -92 1335 -64Q1336 -37 1338 -29Q1344 -9 1338 1Q1332 11 1321 14Q1310 18 1299 19ZM1134 -102Q1148 -107 1159 -114Q1170 -121 1185 -132Q1215 -155 1228 -172Q1242 -189 1250 -214Q1255 -229 1250 -240Q1246 -251 1235 -261Q1224 -270 1207 -268Q1190 -267 1168 -247Q1144 -225 1127 -196Q1110 -167 1099 -113Q1097 -103 1106 -99Q1115 -95 1134 -102ZM1451 -21Q1447 -29 1434 -37Q1420 -45 1420 -49Q1420 -53 1416 -62Q1411 -70 1407 -74Q1402 -80 1410 -104Q1418 -127 1434 -161Q1450 -195 1469 -230Q1477 -238 1485 -251Q1493 -264 1497 -268Q1497 -272 1500 -276Q1503 -279 1507 -279L1515 -295Q1517 -299 1528 -311Q1538 -323 1553 -338Q1568 -352 1584 -365Q1599 -378 1609 -384Q1630 -398 1652 -397Q1675 -396 1691 -383Q1694 -380 1704 -371Q1715 -362 1728 -351Q1742 -340 1752 -331L1789 -298L1772 -248Q1759 -208 1766 -178Q1772 -148 1784 -126Q1789 -115 1798 -109Q1806 -103 1820 -101Q1828 -100 1835 -95Q1842 -90 1842 -79Q1842 -55 1834 -44Q1825 -34 1815 -32Q1782 -28 1752 -39Q1722 -50 1698 -96Q1694 -102 1688 -118Q1681 -135 1680 -140Q1676 -135 1670 -128Q1663 -120 1657 -114Q1586 -42 1536 -20Q1485 1 1451 -21ZM1506 -104Q1513 -103 1528 -112Q1543 -120 1568 -140Q1602 -169 1624 -188Q1646 -207 1667 -237L1689 -273Q1679 -296 1671 -303Q1663 -310 1655 -310Q1642 -310 1624 -294Q1606 -277 1584 -246Q1561 -214 1533 -167Q1520 -145 1513 -124Q1506 -104 1506 -104ZM1926 6Q1892 -8 1876 -24Q1861 -39 1864 -51Q1866 -57 1871 -62Q1876 -67 1894 -66Q1911 -66 1948 -57Q1959 -57 1970 -58Q1981 -59 1990 -61Q2000 -63 2006 -66Q2011 -68 2009 -72Q2007 -75 2002 -79Q1998 -84 1993 -86Q1988 -87 1984 -87Q1982 -92 1976 -97Q1969 -102 1960 -108Q1938 -126 1920 -140Q1902 -154 1906 -161Q1906 -165 1906 -166Q1906 -166 1906 -166Q1899 -166 1893 -186Q1887 -205 1887 -221Q1887 -241 1896 -261Q1904 -281 1918 -299Q1931 -317 1945 -331Q1964 -349 1986 -366Q2007 -384 2032 -398Q2058 -412 2089 -420Q2103 -423 2121 -423Q2139 -423 2147 -418Q2155 -423 2167 -416Q2179 -408 2191 -395Q2203 -382 2209 -369Q2209 -357 2208 -340Q2208 -322 2206 -309Q2204 -296 2197 -296Q2197 -296 2194 -296Q2192 -295 2192 -290Q2192 -280 2177 -267Q2158 -254 2141 -246Q2124 -238 2115 -245Q2109 -249 2104 -253Q2099 -257 2095 -263Q2095 -263 2092 -268Q2090 -272 2090 -276Q2090 -280 2093 -284Q2096 -287 2096 -287Q2110 -300 2118 -311Q2125 -322 2128 -330Q2131 -339 2131 -344Q2131 -350 2128 -352Q2126 -353 2118 -353Q2113 -353 2096 -345Q2080 -337 2062 -326Q2044 -314 2034 -305Q2030 -298 2028 -296Q2027 -294 2023 -294Q2023 -298 2018 -293Q2013 -288 2006 -279Q1999 -270 1992 -260Q1985 -250 1981 -244Q1980 -235 1976 -228Q1973 -220 1974 -212Q1975 -202 1984 -193Q1993 -184 2010 -170Q2045 -144 2062 -129Q2080 -114 2087 -105Q2094 -96 2096 -87Q2113 -56 2100 -34Q2087 -11 2060 1Q2050 6 2025 10Q2000 15 1972 14Q1945 14 1926 6Z";

const WORDMARK_SVG = `<svg class="mark" viewBox="0 -830 2210 1000" role="img" aria-label="Midas"><path d="${WORDMARK_PATH}"/></svg>`;

const FOOTER_LINKS = [
  { path: "/privacy", label: "Privacy" },
  { path: "/support", label: "Support" },
];

function footerLink(link: { path: string; label: string }, currentPath: string | undefined): string {
  const current = link.path === currentPath ? ' aria-current="page"' : "";
  return `<a href="${link.path}"${current}>${link.label}</a>`;
}

function footerHtml(currentPath: string | undefined): string {
  const links = FOOTER_LINKS.map(function linkFor(link) {
    return footerLink(link, currentPath);
  });
  return `<footer class="foot">${links.join("")}<span class="copy-note">© 2026 Midas</span></footer>`;
}

export function renderPage(page: PublicPage): string {
  const subtitle = page.subtitle === undefined ? "" : `<p class="subtitle">${escapeHtml(page.subtitle)}</p>`;
  const sections = page.sections.map(sectionHtml);
  return [
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${escapeHtml(page.title)}</title>`,
    `<style>${PAGE_STYLE}</style></head>`,
    `<body><header class="top">${WORDMARK_SVG}</header>`,
    `<main class="doc"><h1>${escapeHtml(page.title)}</h1>${subtitle}`,
    sections.join("\n"),
    "</main>",
    footerHtml(page.path),
    "</body></html>",
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
