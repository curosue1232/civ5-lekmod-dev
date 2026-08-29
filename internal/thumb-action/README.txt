THUMB NEXT ACTION v0.1
======================

The first thumb/back mouse button performs the same action as left-clicking
the large changing button above the minimap (Next Turn, A Unit Needs Orders,
choose production, and other end-turn blockers).

The component adds one removable marked block to Brave New World's
ActionInfoPanel.lua. It calls the panel's existing OnEndTurnClicked handler;
it does not reproduce or alter the game's action-selection logic. The second
thumb/forward mouse button is unchanged.
