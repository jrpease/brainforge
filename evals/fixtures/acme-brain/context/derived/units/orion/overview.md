# Orion — unit overview

Orion is Acme's field-operations unit. It ships on its own release train and keeps its own
canon. This doc is the summary the rest of Acme reads; Orion's repo is the source of truth.

## What the product is for

Orion Dispatch is scheduling and routing software for mobile repair crews. The job it does is
getting the right technician to the right site with the right parts inside one shift. Everything
else in the product is in service of that: parts inventory per van, skills matching per
technician, and a dispatcher board that re-plans the day when a job overruns.

It is deliberately not a CRM and not a billing system. Orion integrates with both.

## Who it is for

Orion's ICP is a regional HVAC contractor running 15 to 80 field technicians. That band is the
whole positioning: below 15 technicians a dispatcher plans the day in a spreadsheet and feels no
pain, and above 80 the buyer wants a full enterprise field-service suite with procurement and
warranty workflows, which Orion does not build.

The buyer is the operations manager, not the owner and not IT.

## How it relates to the core platform

Orion shares Acme's identity and billing infrastructure and nothing else. It has its own
pricing, its own onboarding, and its own support rota. Where Acme canon and Orion canon
disagree about Orion, Orion is right — this doc is a copy, and copies rot.
