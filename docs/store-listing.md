# Sinag: store listing draft

Ready-to-edit draft for the **Apple App Store** and **Google Play**. Character limits are noted next to
each field. Text marked _TODO_ still needs a decision.

## Basics

| Field | Apple App Store | Google Play |
|---|---|---|
| App name | **Sinag** (limit 30) | **Sinag** (limit 30) |
| Subtitle / short description | **Every celebration, connected.** (29 of 30) | **Control your SmartParol lanterns: colors, effects, schedules. Powered by WLED.** (78 of 80) |
| Developer / company | SinagTech Labs Inc. | SinagTech Labs Inc. |
| Category | Lifestyle (secondary: Utilities) | Lifestyle |
| Privacy policy URL | https://sinagtechlabs.com/privacy.html | https://sinagtechlabs.com/privacy.html |
| Support URL | _TODO_ (e.g. https://sinagtechlabs.com/support) | _TODO_ contact email |
| Marketing URL | https://sinagtechlabs.com | — |

## Full description (Apple 4,000 / Google 4,000 characters)

> Sinag is the companion app for SmartParol, the connected parol by SinagTech Labs Inc.
>
> Light up every celebration from your phone. Pick colors, play effects, and set schedules so your parol
> greets you at sunset and rests at bedtime, every day or only on the days you choose.
>
> • Set up a new SmartParol on your home WiFi in a minute
> • Choose colors and brightness, and play built-in light effects
> • Schedule your parol to turn on or off at a set time, at sunrise, or at sunset
> • Set the right time zone so schedules run on local time
> • See all your parols in one place, with automatic discovery on your network
> • Works in light and dark mode
>
> An account keeps your parols set up and ready.
>
> Sinag by SinagTech Labs Inc. Every celebration, connected.
>
> Powered by WLED.

## What's new (first release)

> The first release of Sinag: set up your SmartParol, control colors and effects, and create schedules.

## Keywords (Apple only, 100 characters, comma separated, no spaces after commas)

```
parol,christmas lantern,smart parol,pasko,led lights,lantern,wled,filipino,holiday lights,parol app
```
99 of 100 characters. Apple already indexes the app name and subtitle, so they are not repeated here.
Confirm that using "wled" as a keyword is allowed (see the checklist).

## Screenshots

| Store | Required sizes |
|---|---|
| Apple | 6.9" iPhone (1320 × 2868), plus 13" iPad (2064 × 2752) if the iPad build stays enabled |
| Google | At least 2 phone screenshots (16:9 or 9:16, 320–3840 px), a 512 × 512 icon and a 1024 × 500 feature graphic |

Suggested set: Splash, device list, color control, Schedule list, Edit Schedule, setup flow.

## Pre-upload checklist

- [ ] Add more screenshots: real app screens for iPhone and Android, replacing placeholders.
- [ ] Write the full store statement: description, what's new, keywords.
- [ ] Add "Powered by WLED" to the description and the About screen. _(Both done in this draft and in the app.)_
- [ ] Check WLED license and trademark terms, and confirm the attribution and license notices the fork requires.
  - This app is a fork of **WLED Native**, licensed **GPL-3.0**. The source of the fork must stay publicly
    available and the license notice must be shown in the app. _(The About screen links to the source.)_
  - The GPL-3.0 and Apple's App Store terms have a known conflict. Get advice before submitting to Apple.
  - Check whether "WLED" may be used in the keywords and description.
- [ ] Enter the privacy policy URL in App Store Connect and Google Play Console and confirm the page is live.
- [ ] Complete Apple's App Privacy form and Google's Data safety form so they match the policy.
  - Data the app collects once the real backend is live: name, email address, account ID.
    Local network access, and location only when "Use phone location" is tapped (stored on the
    lantern, not sent to SinagTech).
- [ ] Replace the development `FakeAuthService` with the real Supabase sign-in before any public build.
- [ ] Switch the launcher icon to the Sinag icon (needs a square master and an Android foreground layer).
- [ ] Submit to the Apple App Store and Google Play.

_Applies to both stores._
