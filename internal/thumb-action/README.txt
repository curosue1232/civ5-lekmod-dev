SPACE NEXT ACTION v0.2
======================

The Space bar performs the same action as left-clicking
the large changing button above the minimap (Next Turn, A Unit Needs Orders,
choose production, and other end-turn blockers).

The component adds one removable marked block to Brave New World's
ActionInfoPanel.lua. It calls the panel's existing OnEndTurnClicked handler;
it does not reproduce or alter the game's action-selection logic. The second
The obsolete v0.1 thumb-button bridge is removed during upgrade because Civ V
did not deliver that assumed mouse event to this UI context.
