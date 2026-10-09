# Engineering conventions

Every service repo uses trunk-based development with short-lived branches named `ship/<ticket>-<slug>`. Merges to main are squash merges only.

Commit subjects follow the Lantern format: a verb in the imperative, then the ticket id in square brackets, for example "Tighten retry budget [PLT-482]". The release train leaves every other Thursday at 14:00 UTC.
