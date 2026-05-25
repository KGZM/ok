# Agent Workspace Bootstrap Protocol

If you are a newly initialized agent starting a fresh session, follow these instructions to register the specialized subagents and restore the project state.

## Step 1: Discover and Register the Subagent Team

1. List the directories under `.agents/agents/`.
2. For each subdirectory found (e.g., `control`, `fabricator`, `validator`, `warden`, `ecologist`, `architect`, `scribe`, `historian`):
   - Read the `<agent_name>/agent.json` file.
   - Call the `define_subagent` tool to register that agent's config.
3. Verify that the agent team has been defined.

## Step 2: Restore Handoff Context

1. Read `.agents/session.json` at the root of the workspace to locate:
   - The last active conversation ID.
   - The active task list file.
2. Read the local transcript log at:
   `~/.gemini/antigravity-cli/brain/<last_conversation_id>/.system_generated/logs/transcript.jsonl`
   to review the final steps, handoffs, and recent tool outputs.
3. Open the active task list file (e.g., `task.md` in the artifact directory or under `.agents/`) to review the current checklist status.

## Step 3: Align on Project Goals

1. Inspect `STATUS.md` and `PLAN.md` at the project root to align on the codebase state.
2. Summarize the recovered state for the user and ask for confirmation on the next steps.
