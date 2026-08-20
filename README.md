# Omarchy Startup Manager

A fast, conservative startup manager for Omarchy 4's Quickshell desktop.
It shows user services, system services, and XDG login applications in one
landscape panel, while locking desktop foundations and recovery services
against accidental changes.

## Design

- **Zero resident processes:** state is collected only when the panel opens or
  you explicitly refresh it.
- **Protected foundations:** networking, audio, login, keyring, firewall,
  thermal, recovery, and core systemd units are visible but immutable.
- **Reversible controls:** starting/stopping is separate from enabling/disabling
  at startup. The plugin does not uninstall packages.
- **Safe XDG overrides:** disabling a system login application writes a minimal
  user override. Existing user-owned desktop files are never overwritten.
- **Native authorization:** system-scope changes use `pkexec`, so Omarchy's
  polkit agent presents the password prompt.
- **Keyboard-first:** `j`/`k` selects rows, `h`/`l` changes section, `Enter`
  performs the primary action, `/` searches, `r` refreshes, and `a` toggles
  the all-units view.

The helper is currently Python because it runs for a fraction of a second only
on demand and ships without a build/install hook. A resident Rust daemon would
consume more idle resources without making systemd queries faster. A future
native helper is appropriate if the plugin gains event-driven D-Bus monitoring.

## Install

```bash
omarchy plugin add https://github.com/Rajaniraiyn/omarchy-startup-manager.git --enable
```

The widget is added to the right side of the Omarchy bar. Move it with the
normal bar editor or:

```bash
omarchy bar move rajaniraiyn.startup-manager --section right
```

Open it from a Hyprland binding without putting it on the bar:

```lua
bind("SUPER CTRL", "S", "Startup Manager", exec,
  "omarchy-shell shell toggle rajaniraiyn.startup-manager '{}'")
```

Use a key combination that does not conflict with your existing bindings.

The panel also exposes Omarchy-shell IPC for automation:

```bash
omarchy-shell rajaniraiyn.startup-manager open
omarchy-shell rajaniraiyn.startup-manager scope system
omarchy-shell rajaniraiyn.startup-manager refresh
omarchy-shell rajaniraiyn.startup-manager close
```

## Security model

Omarchy plugins run as unsandboxed user code. Review third-party plugins before
enabling them. This plugin's backend accepts only validated systemd unit names
and five allow-listed actions: `start`, `stop`, `restart`, `enable`, and
`disable`. Protected units are rejected by both the UI and the backend.

System actions require a normal graphical authorization prompt. User services
and login applications require no privilege escalation.

## Development

```bash
omarchy plugin validate .
python -m unittest discover -s tests -v
bin/omarchy-startupctl list --scope user | jq
```

The project targets Omarchy 4 / Quattro and follows the public shell plugin
manifest schema.

## License

MIT
