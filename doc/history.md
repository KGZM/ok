# Project History & Design Decisions

This document serves as the project history log and registry of major design decisions, plans, and architectural adjustments for `ok` (`kak-emporium`).

---

## 1. Decoupled Grammar Architecture
*   **Date**: 2026-05-22
*   **Decision**: Decouple tree-sitter grammars from the core `kak-tree-sitter` build process.
*   **Context**: Building `kak-tree-sitter` and compiling all 150+ tree-sitter grammars on the host/CI from source required downloading grammars from GitHub repositories via `ktsctl sync`, which consumes substantial network bandwidth, CPU resources, and time.
*   **Resolution**:
    *   Move grammar compilation completely to the `kgzm/grammars` repository.
    *   Distribute pre-compiled flat shared library files (`*.so`) inside `grammars/dist/<target>/`.
    *   Configure `kak-tree-sitter` to use `Source::Bundled`, loading `.so` libraries directly from `$XDG_DATA_HOME/kak-tree-sitter/grammars/`.
    *   During local developer builds and CI runs, the assembly task (`mise run bundle`) copies precompiled `.so` shared objects directly into the bundle rather than triggering compiling, downloading, or synchronization.

---

## 2. Janet-to-Kakscript DSL Compiler & Quoting Resolution
*   **Date**: 2026-05-23
*   **Decision**: Rework the leader key system definitions by moving from raw string escaping to a structured, type-safe DSL compiler in Janet.
*   **Context**: The previous implementation had complex nested single-quotes escaping (e.g. for `on-key`, `evaluate-commands %sh{ ... }` loopbacks) that was prone to injection vulnerabilities, wrong argument count bugs, and syntax issues. Specifically, a quoting bug caused shell commands inside `%sh{}` blocks (emitted by `api-cmd` integrations) to be incorrectly wrapped in single quotes (e.g., `'ok --api ...'`), leading to command evaluation failures inside Kakoune.
*   **Resolution**:
    *   Implemented `src/kak.janet`, a compiler translating Janet AST forms (e.g., `[:define-command ...]`, `[:block ...]`, `[:try ...]`, `[:sh ...]`) into flat, valid Kakscript.
    *   Established strict safety invariants where raw shell strings are systematically compiled via `kak/quote` and `kak/api-cmd` formatting.
    *   Ensured that command names and flags (represented as symbols/keywords like `'ok` and `'--api`) compile directly to raw strings without quotes, allowing correct unquoted command execution inside Kakoune's `%sh{}` blocks.

---

## 3. Resolving the Startup Argument Bugs
*   **Date**: 2026-05-23
*   **Decision**: Correct startup argument count errors identified during headless smoke testing.
*   **Context**: Following compilation, the headless Kakoune editor reported startup errors in the `*debug*` buffer:
    *   `1:1: 'evaluate-commands': 55:1: 'define-command': wrong argument count` (for `:ok-jump-char`)
    *   `1:1: 'evaluate-commands': 49:1: 'define-command': wrong argument count` (for `:ok-buffers-switch`)
*   **Resolution**:
    *   The compiler evaluates child expressions of a custom command definition (like `on-key` or `prompt`) into space-separated string words. If these are not wrapped in a block `[:block ...]`, Kakscript interprets them as separate arguments to `define-command` instead of a single bracketed command body `%{%}`.
    *   Wrapped the body of `ok-jump-char` in `[:block ...]` inside `src/jump.janet`.
    *   Wrapped the body of `ok-buffers-switch` in `[:block ...]` inside `src/buffers.janet`.
    *   Verified with headless automation that startup yields a clean exit status 0 and no errors in the `*debug*` buffer.
    *   Confirmed clean sourcing of `ok --api init` via headless Kakoune integration smoke testing with no syntax, quoting, or argument errors.

---

## 4. Try-Block Compilation & Zellij Redirection Fixes
*   **Date**: 2026-05-23
*   **Decision**: Update the DSL `try` block compilation rules and redirect Zellij floating pane execution output.
*   **Context**:
    *   **DSL Try-block Quoting Bug**: Unbracketed commands inside a `try` form (e.g., `[:try [:remove-highlighter "foo"]]`) compiled to space-separated strings (e.g., `try remove-highlighter 'foo'`). Kakoune parsed the second word (`'foo'`) as a separate argument to the `try` command, resulting in `try: wrong argument count` evaluation errors.
    *   **Zellij Redirection Leak**: Spawning a Zellij floating pane (e.g., via `ok --api files find`) printed shell diagnostic/status info to standard output/stderr, leaking into Kakoune and triggering `no such command: terminal_XX` errors.
*   **Resolution**:
    *   **Try-block Quoting Fix**: Modified `src/kak.janet` so that the `try` form compiler checks if the inner command is a list/nested form, and if so, automatically wraps it inside a bracketed block `%{\n...\n}` (e.g., `try %{\nremove-highlighter 'foo'\n}`).
    *   **Zellij Redirection Fix**: Modified `src/fzf.janet` to append `>/dev/null 2>&1` to the `zellij run --floating` invocation command, suppressing diagnostic command line output and avoiding pollution of the Kakoune communication stream.
    *   **Verification**: Added unit tests to `test/test-kak-dsl.janet` to assert correct `try` block translation, and validated clean headless Kakoune integration execution with zero errors logged to the `*debug*` buffer.

---

## 5. Transition to E2E Callback Architecture & Keyword-Switch Compilation Fix
*   **Date**: 2026-05-23
*   **Decision**: Refactor interactive shell launchers to use callback subcommands, and resolve a keyword compiler collision.
*   **Context**:
    *   **Interactive Escaping Vulnerability**: The original Space Leader launchers (e.g., `ok-files-find`) constructed inline shell commands or used temp files inside Kakoune's `terminal` environment to run `fzf`/explorer and pass the selection back. This was prone to shell injection and single-quoting escaping errors.
    *   **Keyword-Switch Collision Bug**: In the DSL compiler (`src/kak.janet`), passing modules/actions as keywords (e.g. `:buffer`) collided with Kakoune option flags (e.g. `:buffer` is a switch). As a result, compiling `:buffer` or other matched keywords resulted in `-buffer` flags, leading to CLI execution failures.
*   **Resolution**:
    *   **E2E Callback Architecture**: Refactored the `fzf/launch` interface to invoke `ok --api <module> pick-<action> <session> <client> [args...]` inside spawned terminal/multiplexer panes. The target callback (`pick-` subcommands like `pick-find`, `pick-recent`, `pick-explorer`, `pick-buffer`, `pick-project`, `pick-line`) performs the interactive selection and sends the resulting Kakscript command directly back to the Kakoune session via `kak -p <session>`, bypassing nested shell evaluation.
    *   **Keyword-Switch Collision Fix**: In `src/kak.janet`, updated `api-cmd` to convert `module` and `action` arguments from keywords/strings to symbols using `(symbol module)` and `(symbol action)`. Since symbols do not trigger keyword switch logic, they compile cleanly to their literal names (e.g., `buffer` instead of `-buffer`), resolving the bug.
    *   **Verification**: Verified all unit tests (`./mise/tasks/test`) pass successfully, and validated E2E integration with zero errors.

---

## 6. Multiplexer Environment Forwarding & DSL Expansion
*   **Date**: 2026-05-25
*   **Decision**: Implement environment forwarding for terminal multiplexers, expand the DSL with native Kakoune expansions, and fix Kakscript quoting/expansion bugs.
*   **Context**:
    *   **Stale Multiplexer Daemon Environment**: When launching a pane in Zellij or Tmux, the spawned process inherits the background server daemon's environment rather than the active client shell's path. This caused `ok` binary lookup failures inside the new terminal panes.
    *   **Startup Option Type Mismatch**: Wrapping `%val{timestamp}` in single quotes (`'%val{timestamp}'`) inside Kakoune `set-option` commands prevented Kakoune from expanding it, resulting in the runtime type crash `%val{timestamp} is not a number`.
    *   **Key Capture Quoting Bug**: In `ok-jump-char`, `%val{key}` was quoted, passing the literal string `'%val{key}'` instead of the user's pressed character.
    *   **Shell Argument Expansion Bug**: In `ok-jump-collect`, the positional parameter `$1` was compiled as `'$1'`, causing the subshell to pass it literally instead of performing shell parameter expansion.
*   **Resolution**:
    *   **Environment Forwarding**: Serialized the entire calling process environment and wrapped Tmux/Zellij commands with `env KEY=VALUE ...` prefixes. Added customizable redirection variables to silence multiplexer diagnostic outputs.
    *   **DSL Expansion Primitives**: Added native AST support for `:val`, `:opt`, and `:reg` to compile expansions unquoted so they evaluate correctly in Kakoune. Introduced a `:dq` tag to safely double-quote values.
    *   **Refactoring Space Leader Mappings**: Replaced all raw expansions in `src/jump.janet`, `src/buffers.janet`, and `src/files.janet` with the new type-safe AST primitives.
    *   **Mock Integration Suite**: Created a path-level E2E integration test (`test/test-integration.janet`) using dummy executables inside `/tmp/ok-mock-bin` to isolate and verify the entire multiplexer-loopback flow.


