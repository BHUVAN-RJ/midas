# Midas intel — 2026-10-07: assistant-ui

One-off deep dive, asked for by the founder. Information only, per the reporting rules in the
root `CLAUDE.md`.

## What it is

assistant-ui is an open-source kit of chat-screen parts that developers put inside their own
products to give them an AI conversation. It does not make apps for people and does not host
them.

- **Library:** MIT licensed. Building blocks for a chat screen: thread, message box, messages,
  streaming replies, attachments, voice, branching, edit and regenerate. Unstyled, built on
  shadcn/ui and Tailwind. — [assistant-ui.com](https://www.assistant-ui.com/),
  [GitHub](https://github.com/assistant-ui/assistant-ui)
- **Platforms:** React, Vue, React Native (iOS and Android, launched March 2026), terminal (Ink).
  — [March 2026 launch week](https://www.assistant-ui.com/blog/2026-03-launch-week)
- **Generative UI:** when the AI calls a tool, the result can show up as a live component inside
  the chat. The user can approve an action inline, and the page can let the AI trigger certain
  front-end actions. — [GitHub](https://github.com/assistant-ui/assistant-ui)
- **AI backends:** Vercel AI SDK, LangGraph, LangChain, Mastra, Cloudflare Agents, Claude
  Managed Agents, AG-UI, A2A, Google ADK, custom. — [assistant-ui.com](https://www.assistant-ui.com/)
- **MCP:** connects to MCP servers, with OAuth and a screen for managing them. Nothing found
  showing it renders MCP Apps. — [react-mcp skill](https://vibeindex.ai/skills/assistant-ui/skills/react-mcp)
- **Assistant Cloud (paid hosted layer):** saved conversation threads, analytics dashboard, run
  tracking. Free tier, Pro $50/mo, Enterprise custom.
  — [pricing (aitoolsatlas)](https://aitoolsatlas.ai/tools/assistant-ui/pricing)

## Company

- YC W25. $500K pre-seed, March 2025 (YC, Pioneer Fund). Founder and CEO: Simon Farshid.
  — [YC launch](https://ycombinator.com/launches/Mnc-assistant-ui-open-source-typescript-react-library-for-ai-chat)
- About 12.4k GitHub stars and 1.2k forks (2026-10-07). Claims 50k+ monthly downloads. Listed
  users: LangChain, Stack AI, Browser Use, Athena Intelligence.

## Where it touches the plan

Section names refer to `docs/designs/jess-personal-assistant-shell.md`.

| assistant-ui piece | Midas spot |
|---|---|
| Chat thread and message box | The "describe it in your own words" step: the generator, which lands after Oct 8 and before Nov 2 (Architecture Decisions, 2026-10-04) |
| React Native bindings | The iPhone shell is SwiftUI with Sidekicks running as web pages inside a WKWebView. The React version could run as a web page, like a Sidekick does; the React Native version targets RN apps, which the shell is not |
| Cloudflare Agents integration | The backend already runs on Cloudflare Workers, D1 and R2 |
| Live components inside the chat | Same pattern as MCP Apps, recorded as "a UI rendered inside a chat turn, no app lifecycle"; Sidekicks get their own home, icon and notifications (MCP Apps, In Plain Terms) |
| Inline approval of actions | The cross-app read consent screen and the reversibility rule (Architecture Decisions, 2026-10-04) |
| Assistant Cloud threads and analytics | jess, the assistant layer, set aside for later; also Usage metrics without content, where Midas events carry no content |

Nothing here touches build 1 (Oct 8). The closest point in time is the generator's conversation
screen.

## Open question

Should describing a new Sidekick feel like a chat thread, or like something that isn't a chat at
all?
