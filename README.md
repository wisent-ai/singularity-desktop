# Singularity Desktop

Native macOS window for observing one persistent Singularity digital being. It
reads the runtime's owner-local `state.json` and `activity.jsonl` and sends
owner-provided mind imports to that runtime's local state operation without
duplicating cognition, import parsing, tools, finance execution, or credentials.

The window shows identity, life status, cycle, model, balance, earnings, costs,
persistent prompt, self-imposed rules, learnings, memories, import source
attribution, children, and the activity journal. Choose the runtime state
directory in the toolbar or set `SINGULARITY_STATE_DIR`; the default is
`~/.singularity`.

## Import an existing mind

Choose **Import** in the window actions or **Import existing mind…** in first
use, then select a `singularity-mind-import-v1` JSON file. The selected
`singularity run` process must be active so Desktop can submit the raw document
to its owner-only `state-import.sock`. For a stopped being, use
`singularity import --file … --state-dir …`.

The runtime accepts attributed memory, knowledge, and profile records only. It
validates the entire document before one state save, preserves existing data,
keeps repeated source items unchanged, and refuses the whole import when a
source item changes or any input is invalid. Desktop shows the returned
imported, attributed, unchanged, conflicting, and rejected counts. Imported
profile facts remain memories; identity, prompt, rules, model, budget, finance
policy, and enabled tools are never overwritten or activated.

```sh
swift build
```

`Scripts/build-app.sh` builds the installable signed application. It requires
an Apple signing identity and signs nested helpers before the outer bundle,
without recursively replacing their identifiers. The build verifies that
`WisentIdentityKeychainHelper` still has the shared
`ai.wisent.identity.keychain-helper` identity after the app is sealed, so
updates do not turn the common Keychain client into an unrelated executable.

The canonical runtime remains [wisent-ai/singularity](https://github.com/wisent-ai/singularity). License: MIT.
