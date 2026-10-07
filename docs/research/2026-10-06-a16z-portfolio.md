# Research note: a16z companies near Midas, 2026-10-06

A research record only. Nothing here changes the design doc, the week 0 checklist or any
decision. It follows the Maritime note from the same day and asks which a16z companies are
doing or working on something similar to Midas.

## Companies found

**Wabi.** Already covered in the design doc's Competitor Record. Additional facts from this
search: a16z's investment was led by Anish Acharya; on the a16z podcast of November 5, 2025,
Kuyda framed personal software as moving "from a developer monopoly to a creative medium for
all" and said "mini-apps will become as shareable as TikToks."

**Town.** 55 million dollar Series A led by a16z, announced June 3, 2026, by Alex Rampell and
Justine Moore. Founders Jean-Denis Greze (former CTO of Plaid) and Tony (former product and AI
lead at Google). A personal AI assistant across email, calendar, Slack, docs, WhatsApp, desktop
and web that learns how the user works and proposes custom workflows. Overlaps jess, the
demoted assistant layer, rather than the Midas platform.

**Rork.** "Lovable for mobile apps." 2.8 million dollar round led by a16z speedrun, then a 15
million dollar seed led by Left Lane Capital with speedrun participating. Turns prompts into
native iOS and Android apps (Swift, React Native, Expo) and publishes them to the App Store and
Google Play. Rork Max targets replacing Xcode across iPhone, iPad, Watch, TV, Vision Pro and
iMessage. Its customer is the App Store entrepreneur: public apps for strangers, the opposite
of Midas's private deploy.

**Replit.** a16z led the 97 million dollar Series B (2023) and participated in the 2026 round
of 400 million dollars at a 9 billion dollar valuation, led by Georgian. Already in the design
doc's competitor set; its CEO is a Wabi angel.

**Runta.** 20 million dollar seed led by a16z, announced July 16, 2026, with Martin Casado on
the board. Founder Guanlan, formerly tech lead on Cloudflare's edge team and Kong's core proxy
team. An execution layer giving autonomous agents full stateful OS environments, sold to
enterprises. a16z's framing: "AI agents just want a computer." This is the a16z analog of
Maritime, enterprise rather than developer priced.

**Not relevant:** Blueprint (speedrun, vibe coding for hardware).

## a16z theses found

- **"Disposable Software,"** Anish Acharya, August 25, 2025. "Software creation used to be
  constrained by ROI. Now it's constrained only by imagination." Small apps "for you or maybe a
  couple of friends," framed as throwaway apps with low maintenance expectations. No portfolio
  companies named, no mobile discussion.
- **Speedrun "14 Big Ideas for 2026."** Includes distribution through ChatGPT, Apple mini apps
  and AI native extension SDKs, reaching large audiences without building a social graph.

## How it relates to Midas, as discussed

1. a16z's map of the space: consumer personal software (Wabi), personal assistant (Town),
   public mobile app builder (Rork), developer builder (Replit), agent compute (Runta). None of
   them is private apps for a few named people that are kept working over time.
2. The sharpest contrast is with a16z's own thesis. Acharya calls these apps disposable.
   Midas's thesis is the opposite: build, deploy privately and maintain. This is a framing
   difference to be aware of when presenting at a16z Tech Week, not a decision.
3. Wabi is a16z's bet in this exact lane. The design doc already records that a16z will not
   fund a direct competitor; Town and Rork sit near it without overlapping it.

## Founder's position on the disposable thesis

Recorded in the design doc under `### App lifespan is a spectrum, stated by the founder
2026-10-06`: lifespan is a spectrum, not a choice between disposable and maintained. A trip
planner is thrown away after the trip; a group Instagram needs upkeep for years. Acharya's own
Catsagram example, a photo app with public signup, sits nearer the maintained end.

## Sources

- https://a16z.com/announcement/investing-in-wabi/
- https://a16z.com/podcast/seeing-the-future-from-ai-companions-to-personal-software/
- https://a16z.com/disposable-software/
- https://a16z.com/announcement/investing-in-town/
- https://pulse2.com/rork-15-million-raised-for-ai-mobile-app-creation-platform
- https://www.gunder.com/en/news-insights/client-news/a16z-leads-97m-series-b-of-ghostwriter-ai-developer-replit
- https://www.trendingtopics.eu/replit-raises-400m-tripling-its-valuation-to-9-billion-in-six-months/
- https://forkast.news/a16z-leads-runta-seed-to-rebuild-the-compute-stack-agents-actually-need/
- https://speedrun.substack.com/p/14-big-ideas-for-2026
