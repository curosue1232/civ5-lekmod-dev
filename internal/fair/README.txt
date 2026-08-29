LEKMOD 30.7 FAIR TRADES v1.2.4
================================

PURPOSE
-------
Fair Trades proactively presents AI trade offers during multiplayer turns.
Supported deals are limited to:
  - spare Luxury for spare Luxury
  - spare Luxury for flat Gold
  - spare Luxury for Gold per turn

Strategic resources and all other trade items are outside this feature.

REQUIREMENTS
------------
- Civilization V with LEKMOD v30.7 already installed
- EUI v1.28 or earlier already installed
- Civilization V closed during install or uninstall

This package detects and patches those existing installations. It does not
bundle LEKMOD or EUI.

INSTALL / VERIFY / REMOVE
-------------------------
Run the repository-level INSTALL_ALL.bat, VERIFY_ALL.bat, or UNINSTALL_ALL.bat
for the complete stack. The component scripts in this folder can also be run
directly when only Fair Trades needs attention:
  Install.ps1
  Verify.ps1
  Uninstall.ps1

CURRENT BEHAVIOR
----------------
- The seller must retain at least one copy of a traded luxury.
- Relationship controls offer frequency and the starting GPT price:
    Guarded: 3 GPT
    Neutral: 5 GPT
    Friendly or Afraid: 7 GPT
- Flat-Gold offers start from the duration-equivalent relationship price but
  are capped at 10 Gold in both directions.
- Currency offers are adjusted directionally and must pass the AI's native
  acceptance check before being shown.
- Luxury swaps retain strict two-sided native fairness.
- Each natively rejected AI/resource/currency combination is independently
  suppressed for 10 turns so it cannot immediately repeat.
- Search is limited to eight native valuation calls per scan and opens at most
  one AI trade session.
- Auto End Turn is paused while an offer is unresolved and resumes after
  Accept, Refuse, closure, or dispatch failure.

EUI INTEGRATION
---------------
The installer discovers the EUI DiploTrade context that owns
LeaderMessageHandler and adds one marked private LuaEvents bridge. The runtime
does not call UI.OnHumanOpenedTradeScreen and does not spoof
Events.AILeaderMessage.

DIAGNOSTICS
-----------
Use internal\CaptureState.ps1 after a runtime problem. Its ZIP includes the
LEK_FAIR_TRADES-1.db diagnostic database when available.

FROZEN CORE
-----------
Fair Trades is an extension above LEK Core v1.3. Its installer and runtime do
not modify the frozen core patch logic.
