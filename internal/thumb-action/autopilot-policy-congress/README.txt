Space Autopilot v0.4 integration module: policy, tenet, ideology, and World Congress.

This directory is self-contained and is not wired into InstallAll yet.

Policy choices use active-leader flavor weights. A prepared confirmation is accepted first.
Tenets and ordinary policies are ranked before branches. A native public-opinion preferred
ideology is adopted when public-opinion unhappiness is active. This is a heuristic, not the
hidden DLL AI chooser.

Congress keeps prepared selections. Otherwise it abstains ordinary unused votes, votes for
the active player during a World Leader session when that is a legal choice, and fills required
proposals deterministically. Player-target choices use the eligible major civilization with the
most hostile diplomatic approach toward the active player, then lowest player ID. This is also
a documented heuristic.

No war declaration or trade behavior is present in this module.
