SPACE NEXT ACTION v0.3
======================

The Space bar performs the same action as left-clicking
the large changing button above the minimap (Next Turn, A Unit Needs Orders,
choose production, and other end-turn blockers).

For a unit that needs orders, the first press selects it and the second press
uses Civ V's normal Skip mission for that unit, which advances the native unit
selection. The tracked selection is limited to the same player, turn, and unit.

When an incoming AI trade offer is open and ACCEPT is visible and enabled,
Space accepts that non-empty offer. It never auto-refuses a deal or acts from
the normal player-proposal trade state.

The component adds removable marked blocks to Brave New World's
ActionInfoPanel.lua and EUI's owning TradeLogic.lua. It calls the panel's existing OnEndTurnClicked handler;
it does not reproduce or alter the game's action-selection logic.
The obsolete v0.1 thumb-button bridge is removed during upgrade because Civ V
did not deliver that assumed mouse event to this UI context.
