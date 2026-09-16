# EQ Mobile Development Workflow

Codex is the primary agent for EQ Mobile and handles implementation,
architecture, integration, debugging, tests, validators, Godot work,
repository changes, and final verification.

Do not use, recreate, repair, or rely on secondary-worker infrastructure for
this project, including Antigravity, Gemini delegation, Cline workers, worker
queues, detached jobs, polling, or worker timeout/recovery procedures.

For a substantial source investigation that would require extensive reading of
EQEmu, ProjectEQ, OpenEQ, LanternExtractor, or other reference material, do
not immediately perform the full investigation. Instead, provide the user a
concise block titled `RESEARCH TASK FOR CHATGPT` containing:

- the exact research goal;
- specific questions to answer;
- only the EQ Mobile context needed for the investigation;
- source repositories to prioritize;
- the desired output format; and
- the information needed to continue implementation.

This is a manual handoff. Do not communicate with ChatGPT or create automated
research/worker infrastructure.
