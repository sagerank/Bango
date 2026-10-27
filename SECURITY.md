# Security

## What Bango can do on your Mac

- Press keys on your behalf (Accessibility permission)
- Run the Terminal command or Shortcut that **you** set on a gesture
- Open links you set (http, https and mailto only)

A profile someone shares with you cannot run code on its own: when you import it, every step that can run a command or open a link, and every step this version does not know, is switched off until you turn it on yourself. Look at a step before you do.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting on this repository (Security tab, Report a vulnerability). Describe what you found and how to reproduce it. I will answer as soon as I can.

Of particular interest: ways an imported profile could run something without the user enabling it, ways to make an action fire without a real gesture, and anything that stores or sends what the user types (it should not exist).

## Data

Bango stores settings in `~/Library/Application Support/Bango/config.json`. It contains your gestures and settings, no secrets. Terminal commands you add are stored there as plain text.
