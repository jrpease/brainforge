# Naming Rules

ACME features are named after tools. A tool has a clear job, fits in one hand, and does not need a manual. That is the standard a feature name has to meet before it ships. The two flagship examples are Wrench, our settings and configuration surface, and Compass, our navigation and search surface. Both names describe the job in one word, without describing the implementation.

We never use abbreviations in feature names. Not initialisms, not shortened forms, not internal codenames that leaked into the product. If a name needs a glossary entry to be understood, it is not a name yet, it is a placeholder. "Wrench" needs no expansion. "Compass" needs no expansion. A name like "CFG Mgr" or "Nav Ctrl" would fail review immediately, on sight, before anyone even asks what it does.

The naming process starts with the job, not the metaphor. We write one sentence describing what the feature does for the customer. Only after that sentence is settled do we search for a tool whose real-world job matches it. Wrench came from "adjust and tighten the pieces that make the product yours." Compass came from "find the direction you meant to go." The tool metaphor has to survive contact with that sentence, or we keep looking.

Tool names stay singular and capitalized, treated as proper nouns: Wrench, not "the Wrench tool" in most copy, not "wrenches." Compass, not "the Compass feature." We resist compound names bolted onto the metaphor, like "Wrench Pro" or "Compass Lite" — if a feature needs a qualifier, the base metaphor was probably wrong, and it is worth renaming rather than qualifying forever.

Internal names must match external names. ACME does not maintain a separate customer-facing name and an internal codename past the prototype stage. Once a feature is named, engineering, design, and marketing all use that name in tickets, commits, and docs. This keeps naming honest: if the name is awkward internally, it will be awkward externally too, and that pressure is a feature, not a bug, in the naming process. Abbreviations creep in exactly when internal and external names diverge, so we close that gap early and keep it closed.
