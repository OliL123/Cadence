# Cadence

A personal to-do app with Android home-screen widgets, built because other to-do apps are worse
to use, can't be changed, or cost money. Chronicle is a separately themed build of it for my partner.

Updated: 2026-10-07 at f3eac7e

## Goals
★ = core, scored strictly · ~ = just needs to work

- **G1 ★** Tasks in coloured groups with due dates and times, reorderable subtasks, reminders and undo; finished tasks clear themselves after a week.
- **G2 ★** Android widgets show tasks and today's due count, tick tasks off without opening the app, and open the app on the tapped task.
- **G3 ★** Changes sync between devices through Supabase, and no device, including one that was offline, ever wipes out another device's edits.
- **G4 ~** The same app runs on Android and the web (GitHub Pages) with layouts for phone, foldable and desktop.
- **G5 ~** The TODAY card shows Google Calendar events, hourly weather and holiday countdowns, and the calendar stays connected without sign-in pop-ups.
- **G6 ~** Daily habits keep their streak as long as they're done each day.
- **G7 ★** A career tracker for applications, events and goals, with career alerts on the Tasks tab.
- **G8 ~** The mahjong Focus wall helps pick a few tasks to work on now, and its score survives sync.
- **G9 ~** Chronicle, the themed build for my partner, installs and works as a home-screen web app on iPhone.

## Planned
- Relevant internship openings from free sources show up in the career tracker as suggestions.
- An email digester turns mailing-list emails into career items and events ("From email" is already reserved in `tracker_models.dart`).
- Suggested events worth going to: smash tournaments, game cons, talks and hiking get-togethers.

## Out of scope
- A native iOS app: iPhone use goes through the web app (Chronicle).

## Constraints
- Free to run: free tiers and free APIs only.
- Builds and runs locally, and stays easy to change.
- Chronicle is the same code with a build flag (`tool/deploy_chronicle.sh`), so changes must not break it.

## Open questions
- Where will event data come from: mailing lists, Instagram, or something else?

Retired: none
