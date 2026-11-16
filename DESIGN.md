# Interval.io — design notes

Built with Design4Apps_byLucky. Personality first, pixels second.

## Personality

- **One job.** Ring on a rhythm you choose, and let you stop it — all of it, or just one.
- **Mood.** Calm. This is a metronome you glance at, not an emergency. It runs in the
  background of someone's day: water, posture, meds, focus blocks.
- **Material.** A small instrument in cool slate under smoked glass. Dial, not dashboard.
- **Signature moment.** The dial *landing*: when an alarm rings the arc completes, a halo
  breathes out from the rim, the numerals take a breath, and the ring resets for the next
  one. One moment, tied to the app's whole purpose.
- **Where it lives.** A phone in one hand, often glanced at mid-task and often at night.
  Dark-first, light shipped too. Spacious, not utility-tight.

## Levers

| Lever | Choice | Why |
| --- | --- | --- |
| Accent hue | Calm aqua | Time passing, still water, night-safe. Crucially *not* alarm-red, so red can mean only danger. |
| Neutral bias | Cool slate, biased toward the accent | Keeps the canvas feeling deliberate rather than default-grey. |
| Display face | System serif (New York) for the title and the countdown | A serif numeral reads as an instrument face; the sans does the work. |
| Corner language | Soft-crisp continuous — 20 cards, 15 controls, 12 chips | Fewer capsules than stock iOS, so it reads as an object rather than a form. |
| Depth | Liquid Glass throughout — crystal, chips, buttons, bar and icon | See the note below; this is a deliberate departure. |
| Signature moment | The dial landing | See above. |
| Sound | The alarm tone itself — no UI sound | A calm app shouldn't chirp at you for pressing things. |
| Density | Reading-spacious | One decision per glance. |

## Decisions taken from the language

- **Destructive is quiet.** Turning off the series is a secondary button, never the
  loudest thing on screen. Red appears only inside the Undo toast's context.
- **Undo over confirm.** Turn Off happens immediately and offers Undo for six seconds,
  instead of stopping to ask first.
- **One primary per view.** On setup it is Start. While running there is no accent-filled
  button at all — the dial is the hero and both actions step back.
- **Progressive disclosure.** The common case is one row of presets; the hour/minute/second
  wheels open only when you ask for Custom.
- **Celebration is proportional.** A finished series gets a short burst from the dial and a
  drawn check, not a modal alert.

## The sentence

The setup screen is one editable line — *Ring every 2h between 8:00 AM – 10:00 PM,
every day* — rather than a mode switch and a form. A timer and a daily schedule
differ only in where they begin, so choosing "From now" simply removes the window
instead of taking you somewhere else. Four chips at most, and the line always reads
back exactly what will happen.

## Liquid Glass everywhere — a departure, on purpose

The language says glass belongs on chrome, one or two elements per view, because a
screen made entirely of glass reads as fog. This app ignores that and puts glass on
everything: the dial crystal, the chips, the buttons, the bottom bar and the icon.

Two things keep it from turning to fog:

- **Text never goes on glass as glass.** Every label, numeral and caption is solid
  ink at full contrast, sitting on the glass rather than being made of it.
- **The canvas carries light to refract.** Glass over a flat colour is just a grey
  panel, so the canvas holds two soft pools — one accent, one warm — placed well
  away from any text. They are what the glass picks up and bends as things move
  over them. Without them, none of this would read as glass at all.

On iOS 26 and later this is the system's own Liquid Glass (`glassEffect`, grouped
with `GlassEffectContainer` so neighbouring shapes flow together), not an imitation.
Older systems fall back to a hand-built version of the same recipe: blur, a lit top
edge, a specular glint and a long soft shadow.

## Deliberate deviations

- **No `?` shortcut sheet and no hover labels.** Both are desktop ideas; this is a phone
  app with no pointer and no hardware keyboard in normal use.
