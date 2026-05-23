# Space Leader System & Janet-to-Kakscript API Contracts

This document specifies the architecture, command-line interface (CLI) dispatch contracts, and helper libraries of the Space Leader system in `ok` (`kak-emporium`).

---

## 1. CLI Dispatch API (`ok --api`)

The Kakoune editor invokes helper programs asynchronously or dynamically via shell evaluations `%sh{ ok --api <module> <action> ... }`. The following contracts represent the formal parameter lists expected by each module's dispatcher.

### `files` Module (`ok --api files`)

Provides fuzzy file finding, recent history, file explorer delegation, terminal launching, and disk operations.

| Action | Arguments | Description |
|---|---|---|
| `find` | `<session> <client> [dir]` | Launches the interactive `pick-find` subcommand inside a new multiplexer pane/terminal. |
| `pick-find` | `<session> <client> [dir]` | Runs `fzf` to pick a file in `[dir]` (default `.`), then instructs Kakoune `session` to open it in `client`. |
| `recent` | `<session> <client> [dir]` | Launches the interactive `pick-recent` subcommand inside a new multiplexer pane/terminal. |
| `pick-recent` | `<session> <client> [dir]` | Runs `fzf` over git-tracked files sorted by mtime (or fallback `find`) and opens selected file in `client`. |
| `explorer` | `<session> <client> [dir]` | Launches the interactive `pick-explorer` subcommand inside a new multiplexer pane/terminal. |
| `pick-explorer` | `<session> <client> [dir]` | Runs file explorer (`yazi`, `ranger`, or `lf`) in a new pane, allowing the user to choose a file to open. |
| `terminal` | `<session> <client> [dir]` | Launches a terminal window or multiplexer pane/split inside `[dir]`. |
| `rename` | `<session> <client> <old-path> <new-path>` | Renames file via `mv`, then tells `session` to edit `<new-path>` and delete the buffer for `<old-path>`. |
| `delete` | `<session> <client> <path>` | Deletes file via `rm -f`, and issues a `delete-buffer <path>` command to the Kakoune `session`. |

### `search` Module (`ok --api search`)

Integrates line and query-based searching capabilities.

| Action | Arguments | Description |
|---|---|---|
| `buffer` | `<session> <client> <buffile> <cursor-line>` | Launches the interactive `pick-buffer` subcommand inside a new multiplexer pane/terminal. |
| `pick-buffer` | `<session> <client> <buffile> <cursor-line>` | Runs `fzf` over line-numbered content of `<buffile>` to jump the `<client>` cursor to the selected line. |
| `project` | `<session> <client> <dir> [query]` | Launches the interactive `pick-project` subcommand inside a new multiplexer pane/terminal. |
| `pick-project` | `<session> <client> <dir> [query]` | Runs `rg` (or fallback `grep`) filtered through `fzf` in `<dir>` and opens the choice in `<client>`. |

### `jump` Module (`ok --api jump`)

Integrates navigation helpers.

| Action | Arguments | Description |
|---|---|---|
| `line` | `<session> <client> <buffile>` | Launches the interactive `pick-line` subcommand inside a new multiplexer pane/terminal. |
| `pick-line` | `<session> <client> <buffile>` | Launches a Swiper-like `fzf` search of the current buffer to jump `<client>` to the selected line. |

### `project` Module (`ok --api project`)

Handles workspace-level navigation.

| Action | Arguments | Description |
|---|---|---|
| `find` | `<session> <client> [dir]` | Resolves the git root of `[dir]` and starts file finding (`fzf`) scoped to the root. |
| `switch` | `<session> <client>` | Fuzzy picks a git project repository from `ok_project_paths` (or default paths) and shifts Kakoune’s working directory. |

---

## 2. Janet-to-Kakscript DSL (`src/kak.janet`)

This module generates clean, correctly quoted Kakscript command strings. It prevents command injection and syntax issues by abstracting single-quoting rules.

### Core Functions

#### `(q str)` / `(quote str)`
Escapes all single quotes in `str` by duplicating them (converting `'` to `''`), and wraps the entire string in single quotes `'...'`.
*   **Signature**: `(q str)`
*   **Returns**: `(string)` (e.g. `"foo'bar"` becomes `"'foo''bar'"`)

#### `(eval-sh code)`
Generates an `evaluate-commands %sh{ ... }` wrapper for shell script execution.
*   **Signature**: `(eval-sh code)`
*   **Returns**: `(string)`

#### `(map scope mode key action &keys {:docstring docstring})`
Generates a `map <scope> <mode> <key> <action>` string. Optionally appends `-docstring <docstring>` if provided.
*   **Signature**: `(map scope mode key action &keys {:docstring docstring})`
*   **Returns**: `(string)`
*   **Example**: `(kak/map :global :user "f" ":ok-files-find<ret>" :docstring "find file")`

#### `(defcmd name docstring body)`
Defines a standard Kakoune command.
*   **Signature**: `(defcmd name docstring body)`
*   **Returns**: `(string)`
*   **Example**: `(kak/defcmd "ok-buffers-switch" "switch buffer" "prompt buffer: %{ buffer %val{text} }")`

#### `(declare-user-mode mode)`
Generates a user mode declaration statement.
*   **Signature**: `(declare-user-mode mode)`
*   **Returns**: `(string)`

#### `(enter-user-mode mode)`
Generates a transition command into a user mode.
*   **Signature**: `(enter-user-mode mode)`
*   **Returns**: `(string)`

#### `(api-cmd module action & args)`
High-level compiler that builds a command to invoke the `ok --api` CLI, converting arguments appropriately.
*   **Signature**: `(api-cmd module action & args)`
*   **Arg Handling**:
    *   `:pwd` becomes the string `"$PWD"` or `"$kak_opt_ok_pwd"` depending on implementation context.
    *   Keywords (e.g., `:session`, `:client`) map to their shell variables (e.g., `"$kak_session"`, `"$kak_client"`).
    *   Strings are escaped using `kak/quote`.
*   **Returns**: `(string)` (e.g. `ok --api files find "$kak_session" "$kak_client" "$PWD"`)

#### `(defcmd-api cmd-name docstring module action args)`
Generates a Kakoune command that directly triggers an `ok --api` CLI endpoint.
*   **Signature**: `(defcmd-api cmd-name docstring module action args)`
*   **Returns**: `(string)`

---

## 3. Environment & Tool-Detection API (`src/env.janet`)

Optimizes capabilities by detecting system programs and windowing environments, falling back gracefully to simpler POSIX tools when modern commands are missing.

### Helper Functions

#### `(bin-exists? name)`
Checks if a binary is available in `$PATH`.
*   **Returns**: `boolean`

#### `(file-find-cmd &keys {:hidden hidden :exclude exclude})`
Exposes the optimal file listing binary.
*   **Priority**: `fd` if installed, falling back to standard `find`.
*   **Returns**: `array` containing the command and arguments.

#### `(grep-cmd pattern &keys {:path path})`
Exposes the optimal recursive text search command.
*   **Priority**: `rg` (ripgrep) if installed, falling back to standard `grep`.
*   **Returns**: `array` of command arguments.

#### `(preview-cmd file)`
Determines the preview command for fzf or explorer previews.
*   **Priority**: `bat` if installed, falling back to standard `cat`.
*   **Returns**: `array` of command arguments.

#### `(open-pane-cmd cmd-args &keys {:direction direction})`
Builds a command to spawn `cmd-args` inside a new window pane, split, or terminal window.
*   **Multiplexer Detection**:
    *   **Zellij**: Spawns a new pane via `zellij run` in the specified direction.
    *   **Tmux**: Splits the window via `tmux split-window`.
    *   **X11/GUI**: Opens a new GUI terminal window (`alacritty`, `kitty`, `wezterm`, `gnome-terminal`, or `xterm`).
    *   **Fallback**: Returns the raw `cmd-args` to run in-place.
