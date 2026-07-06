# MenuShell

Menu bar app for browsing Teleport SSH nodes and opening `tsh ssh` sessions in
the default macOS terminal handler for `.command` scripts.

## Features

- Reads the current Teleport session with `tsh status --format=json`
- Lists nodes with `tsh ls --format=json`
- Groups nodes by a configurable label like `customer`
- Resolves the default SSH login from a configurable label like `user`
- Falls back to a manual login when the label is missing
- Launches `tsh login` and `tsh ssh` in a real terminal window

## Requirements

- macOS 14+
- Xcode command line tools
- `tsh` installed and available in `PATH`

## Run

```bash
./script/build_and_run.sh
```

Open the menu bar icon, then use `Settings` to configure:

- `Proxy` when you want to override the active Teleport profile
- `Grouping label` such as `customer`
- `Login label` such as `user`
- `Fallback login` when a node does not expose that label
