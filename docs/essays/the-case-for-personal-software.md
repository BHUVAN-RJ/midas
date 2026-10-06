# The Case for Personal Software

<!--
STYLE MAP for the portfolio agent
- A line ending in <!-- punchline --> is a one-line paragraph that must stay alone, with white space above and below. Larger line-height or a slight size bump is fine. Never merge into a neighbour.
- *italic* marks a stressed word or a quoted request. Render as italic, never bold.
- "double quotes" are speech or the exact wording of a request. Plain quotes, no blockquote styling.
- ## headings are section titles. No numbering.
- The final two punchlines close the essay and should be the last two lines on the page.
- Body: serif, ~680px measure, ~20px, line-height 1.6. Reference render: scratchpad essay.html.
-->



---

I left social media a few years ago. Technically I am still on every platform, but I deactivated the accounts and deleted the apps, because it was not healthy for me. My friends stayed. Six of them, in particular, want to keep sharing photos with me, and there is no place for that outside the apps I left.

So I tried to build one. An app for exactly six people. The interface of Instagram, maybe, but only for us. I write code for a living, and I had Claude Code and agents. It should have been an evening.

It wasn't. <!-- punchline -->

It is not hard, exactly. But it is not easy either. Getting all the pieces together took far longer than it should have. I did try Replit. It built something. But there was no way to share it so that six people could just open it. Every one of them would have had to create an account and log in, and it kept adding layers that none of us needed. We are six friends sharing photos. We did not need any of that.

That is when I started asking why. Why is software that is only for you still this hard to have? <!-- punchline -->

## Built for everyone

It is not only the apps I try to build. It is the apps I use.

When I add a grocery item in Reminders, it suggests moving it to the produce section. I don't care. I really don't care. I don't keep produce in the fridge. I go and get my groceries for that particular cooking, and that's how I operate. I don't want this unnecessary division. It throws me off every single time, and every single time I have the same thought: does this app even know what I want from it?

It doesn't. It can't. It was built for *everyone*. <!-- punchline -->

A friend of mine hates Reminders too. When I asked her what she wanted instead, she said, "I don't know." But she knew *exactly* what she hated. She hated how the notifications came in as one of many notifications. She hated how the reminders were organized. She hated how the app forced features on her that she never asked for.

I think that was the key thing I discovered. People don't know what they want, but they know exactly what they don't want. That is not a technical problem. It is a user experience problem, and until now there was nothing anyone could do with it. You cannot file a bug for "I hate how this feels." So you would complain, and then you would keep using the app, because the only alternative was a different app built for everyone else. Software is cheap now. You don't have to pay $10 a month for a reminders app that you sort of like.

You can build it yourself. <!-- punchline -->

## What building for one feels like

Building software for one is way easier than building software for everyone. You don't have to worry about the constraints that big companies live under. Getting out the initial crude version is very easy. Then, as you start using the crude version, you start realizing it lacks something, and it lacks something else, and the app keeps evolving into something a lot bigger than what you started with.

That is the whole point. An app that is yours is allowed to change every week, because the only person it has to please is you.

Here is what that looked like for me.

## The pipeline

I had a bunch of Chrome extensions that each did one thing, and did that one thing well. One sent emails to recruiters from a job posting I clicked. One went to LinkedIn, found the best people to reach out to, and sent them connection requests. One wrote replies to emails. One tagged my inbox. One tailored my resume and smoothed out the apply process. One managed my calendar.

Each one was useful. None of them was the point. <!-- punchline -->

The superpower was unlocked when I connected all of them *together*. <!-- punchline -->

Applying properly to a job means a lot of steps. Look at the job. Check if it's a good fit. Tailor the resume. Fill the application. Find people at the company on LinkedIn. Connect with a few of them. Reach out to the recruiter saying you just applied. Write emails if there was something that needed to be done, or add something to the reminder list or the calendar. Done by hand, that is five to ten minutes per job, every job.

As I write this, the pipeline has grown. I go to the Jobright page, it extracts the jobs, and I start clicking. Each click goes to a job autopilot, which is a server plus a browser running Playwright in debugging mode. It tailors the resume, goes to the link, fills every field, attaches the tailored resume, and gets ready to submit. Then a small chat server connected to my phone over Tailscale puts a message on my phone, and I approve or deny. If I approve, the application is submitted.

Once that is done, two extensions take over, one connected to LinkedIn and one connected to Gmail. The autopilot pulls the names of the hiring managers from the job posting and finds the closest-matching people on LinkedIn, the people I have a high chance of connecting with. It passes that to the extensions, and they send the emails and the connection requests.

I had built those two extensions way back for another purpose, to write email drafts quickly and to write LinkedIn connection requests quickly. Then I made them modular, and they became pieces of something bigger.

There is one checkpoint in the whole flow: the approve on my phone before the application goes out. When I started there were two. The first was me looking at the job posting and deciding whether it was something I wanted to work on. After using it for a while I realized I only needed one.

That's it. I would see a job listing, click it, and a whole pipeline would run, built out of small individual things I had made. They all came together.

And they just worked. It was magical. <!-- punchline -->

## Determinism

LLMs can make all of this smoother, definitely. But I have one problem with them. They are not deterministic.

My brain looks for repeatable actions. Every time it runs, it has to work the same way it did the last time. A model does not promise that, and it charges tokens every time it tries.

I did try running this whole flow through a browser agent instead of my own code. It was very slow compared to the deterministic flow. It cost more. And it did not do the same thing twice.

So I experimented with it a bit, and once I started applying to a bunch of jobs with it, I could clearly see where the errors were, and where there was actually a need for the model to be active. I split it that way. Almost all browser interactions are deterministic: finding the text box, extracting the question, filling the field. That is easier done with plain code than with a browser agent. Resume tailoring is where the model shines, so the model does that. Free-form questions like "Why do you want to join our company?" are where the model is good, so the model does those too. Everything else runs the same way every time.

The model builds the flow. The flow runs as code. <!-- punchline -->

## Things break

I have a bunch more apps that I built way back that I'm not using right now. They either outlived their purpose or I could not keep them working. They just broke.

The Jobright auto-draft extension kept breaking because Jobright and LinkedIn kept changing their layouts. LinkedIn is notorious for this. I had to keep rebuilding it. Another one, Gitrack, which tracked my practice problems, stopped working because LeetCode and NeetCode changed their UI. The same app used Supabase as its database, and Supabase kept pausing the project because it did not have enough activity.

None of this was hard to fix. It was maintenance. <!-- punchline -->

And maintenance is the thing nobody does for software that only one person uses. People do not have the idea of updating apps and keeping them working. They assume their job is using the app and that keeping it working is the app provider's job. For software you built yourself, there is no app provider. There is just you, and the day you don't have time, the app dies.

## Sharing is worse

The first extension I built was needed by exactly two people, me and my friend, and it still had to go through the whole process of getting onto the Chrome Web Store. The ones after that we have literally been sharing over AirDrop.

The problem was updates. Honestly, none of us gets it right the first time. I would fix something, or add something, and there was no good way to get the corrected version to my friend. I have a lot of apps shared with friends that are not being used, because the version they have is the version I sent them months ago.

I shared the job autopilot with a friend early on, and it was very hard to share updates. Later I re-architected the whole thing so it could be shared through GitHub, which was not that difficult, and that made updates easy. It also changed how it ran. Initially it lived in my own logged-in browser, with my credentials and all the accounts the autopilot needed. To share it, I had to ship it with a browser built into the application, so the flow could be controlled properly. Incidentally, that improved the whole experience for me too.

## Why companies can't build this

When a big company builds software, it has to look at how every release affects its perception.

Apple recently announced Siri Recap for the Apple Watch, a feature that listens through the day and summarizes your conversations. Apple went out of its way to explain that no audio is stored, there is no transcript, and nobody is identified. There is a high chance I would use something like that. It was announced on stage, but the rollout has been rather quiet. Even they could see the backlash coming from a mile away.

That is how it is supposed to be. A company with that much riding on trust has to move carefully, because every feature is also a headline.

If Apple gave me a keyboard that learned my keystrokes, I would say, "This is a great feature." But the moment someone, anywhere in the world, says "Apple is tracking your keystrokes," the whole feature becomes a nightmare. Big companies cannot take big swings on personalization. There are too many factors riding on it.

The same scrutiny lands on everyone who ships through a platform. Whether it is productivity or getting the most out of the hardware I already own, the number one limiting factor has not been code. It has been rules. The first extension I wrote was rejected for broad scope. It needed broad scope, because it had to track every job I applied to, across every site. I reworked it so tracking only happened on the sites where the application actually was, and tracking got worse. A database I used paused itself whenever one person's app was quiet for a week, because the plan assumed an app with traffic. I understand why these rules exist. There are bad-faith actors who would take your data and do something else with it. The rules protect the user from the builder.

But here it is all me. I am the builder, and I am the user. <!-- punchline -->

Now consider the other way. I'm from India, and I type Kannada in English letters, transliterated. Auto-suggest gets a few common words and misses most of them. If I built my own keystroke model for exactly the way I type, I would be happy and confident, because only I would know about it. Only I would deploy it. No company has my data. No company can try to sell me something. I am not a metric on someone's chart. I can go as far as I want with it, an autocomplete that knows the next word every single time, and I don't mind, because I know how the model was trained, I know who trained it, and I know the data is never going anywhere.

*That peace of mind itself is a product.* <!-- punchline -->

## Every restriction has a reason, and the reason is not you

Every company needs a login. Not because you need one. Because in its database you are a row, and a row needs a unique identifier.

They will not release a controversial feature, because it is a reputational risk. They will not make small changes like sending fewer notifications, because they need you to open the product. They will always push for push notifications.

Each app, or the company behind the app, optimizes it for *them*, not for you. That is my argument. When I build an app for myself, I only think about me, which means I optimize everything for me. When everyone gets the ability to build, everyone gets to think for themselves, the same way companies have always thought for themselves.

## What's not reaching people

There is one more thing. All these advances in AI are not being distilled fairly to consumers.

I have been following a company called Extend since they went through YC. The founder, Kushal Byatnal, is Indian, and I like their story: they got into YC building a Chrome extension for enterprises, then switched to document processing, and they have been doing good work since. One of the things they do is OCR. I don't need high-quality OCR every day, but there are specific days when I need it. If a normal person needs high-quality OCR once, there is no way to get it. Either they pay $20 a month for one use, or they don't get it. That is not how software is supposed to work.

If I want to use something once, I should be able to use it once. <!-- punchline -->

Pete Koomen wrote about this as the horseless carriage problem, in "AI Horseless Carriages" (April 2025). When engines were invented, the first instinct was to put a motor on a horse carriage. The carriage was the right design for horses, and the wrong design for engines. The design had to change to fit the technology. Most software today is a horse carriage with an AI motor bolted on. The restrictions are still there, and they are there for some other reason that has nothing to do with the user.

## The way you want it

I can assure you that every developer who knows how to write code has their own way of looking at things. This is classic psychology: we want things our way. Up until now, having things your way meant building them yourself and keeping them alive yourself. Now a friend who only knows what she hates can have an app that does none of it.

## Six people, again

I keep coming back to that app for the six of us. Everything in this essay is in it. Apps that should talk to each other and can't. Software that breaks when nobody is paid to keep it alive. Sharing that means sending a file over AirDrop. Rules written for a builder who is not the user. A login nobody asked for.

It has to be much, much simpler than it was that night. As simple as: *"create an app for the six of us that we can share and use."*

That is one of the reasons I started building Midas. <!-- punchline -->

Every app you use was built by a company that optimized it for itself. <!-- punchline -->

Now you can optimize for *you*. <!-- punchline -->
