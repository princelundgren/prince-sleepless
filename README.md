# PrinceSleepless

A macOS menu bar app that keeps a MacBook awake with the lid closed, with a timer, a schedule and a
battery floor, so long-running work such as coding agents keeps going.

It runs `pmset disablesleep` through a small root helper that you approve once.

## Install

1. Download the latest release and move `PrinceSleepless.app` to `/Applications`.
2. Open it. macOS asks you to approve its background item: open System Settings, Login Items &
   Extensions, and switch on PrinceSleepless.

## Read the log

```sh
log show --predicate 'subsystem == "com.princelundgren.princesleepless"' --last 1h
```

## Uninstall

Switch keep-awake off, quit the app, then delete `PrinceSleepless.app`.

## Know before you use it

- `pmset disablesleep` is undocumented. Apple can change or remove it in any macOS release.
- **Never install it on a Mac whose sleep is disabled on purpose**, such as a server: the helper
  clears the flag at every boot.

## Credits

[Sleepless](https://github.com/Aboudjem/Sleepless) (MIT) showed the mechanism and its safety nets.
No code is copied from it.

## License

MIT
