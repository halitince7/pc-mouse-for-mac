# Roadmap

PC Mouse for Mac aims to stay **small, opinionated, and effortless** — the opposite
of a power-user tool you have to configure for an afternoon.

## Design principles

- **Every feature is a single on/off toggle** in the menu bar. If it can't be a
  toggle, it probably doesn't belong here.
- **At most one small inline choice** per feature (like the mouse-button action
  picker). No config screens, no editors, no wizards.
- **One app, one permission.** Everything runs in the same process and reuses
  the single Accessibility grant — new features never ask for more.
- **Sensible defaults.** It should do the right thing out of the box; the toggle
  is there to turn it off, not to make it work.

We deliberately do **not** chase the "configure everything" niche (Mac Mouse
Fix, BetterMouse, etc.). Those are great; this is the lightweight, free,
open-source alternative for the 90% case.

## Shipped

- [x] **Desktop Switcher** — Ctrl + scroll to switch desktops
- [x] **ScrollFix** — traditional mouse, natural trackpad (system-setting independent)
- [x] **Smooth Scrolling** — VSync-driven pixel glide for the mouse wheel
- [x] **Mouse Buttons** — remap the back/forward (thumb) buttons *(toggle + small action picker)*

## Planned — simple toggles

- [ ] **Launch at Login** — toggle in the panel (currently always-on via the login agent)
- [ ] **Reverse Horizontal Scroll** — flip only the horizontal axis
- [ ] **Keep Display Awake** — a lightweight "caffeine" toggle

> Note: Shift + wheel horizontal scrolling is native macOS behavior and already
> works — Smooth Scrolling now keeps it smooth instead of breaking it.

## Planned — toggle + one small choice

- [ ] **Window Drag** — hold a modifier and drag anywhere in a window to move it
      (and resize), no title-bar/edge hunting. *Toggle + a modifier picker
      (default `Ctrl+Cmd`).* Reuses the Accessibility permission via the AX API.
- [ ] **More button actions** — extend the mouse-button picker with a few more
      targets (e.g. middle button; actions like Show Desktop, Launchpad, or a
      single custom shortcut). Same small-picker pattern, no new UI surface.
- [ ] **Smooth Scrolling intensity** — an optional 3-way choice
      (Off / Regular / High) instead of a plain on/off, if there's demand.

## Explicitly out of scope

To keep things simple, we're **not** planning:

- Per-app configuration / rules
- Gesture editors or click-and-drag gesture mapping
- Full per-button keyboard-shortcut recorders
- Anything that needs a preferences window with tabs

---

Have an idea that fits the "one toggle" spirit? Open an issue.
