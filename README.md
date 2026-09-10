# SimpleAccountRecipes
Account wide Tracking of Learned Recipes (Microbot)
SimpleAccountRecipes — Vanilla 1.12.1 (Interface 11200)
=================================================

For private servers where every character on the same account
shares learned recipes once the required profession skill is reached.

<img width="183" height="459" alt="Screenshot 2026-09-10 154852" src="https://github.com/user-attachments/assets/e754dc0c-08bb-4c05-93e1-345c63332e31" />
<img width="141" height="175" alt="Screenshot 2026-09-10 154925" src="https://github.com/user-attachments/assets/3de8c44f-4dea-427e-b046-905cafb5379a" />




# Install
-------
Copy the folder AccountRecipes into:

  Interface/AddOns/SimpleAccountRecipes/

Resulting files:

  Interface/AddOns/SimpleAccountRecipes/SimpleAccountRecipes.toc
  
  Interface/AddOns/SimpleAccountRecipes/SimpleAccountRecipes.lua

Restart the client (or /console reloadui).

# How it works
------------
1. Log in character A.
2. Open every profession that character has once (Tailoring, Enchanting,
   Cooking, First Aid, ...). After that scan the window is left alone.
3. Log in your other characters and open their professions once too.
   A 300-skill tailor will see recipes a 1-skill tailor cannot see yet.
4. Re-opening the same profession, or crafting with the window open,
   does not scan again.
5. After learning a new pattern, open the profession and type /ar rescan.
6. A recipe that was marked known is NEVER removed, even if a lower
   skill character opens the same profession and does not see it.

# Tooltips
--------
On recipe items (Pattern / Plans / Schematic / Formula / Recipe / Manual /
Design / Muster / Plaene / Bauplan / Rezept / Formel / ...) the tooltip
gains a green line:

 - Account Known
 - Scanned: CharName (Profession)

Works on bags, merchant, auction, loot, mail, trade, trainer, and
clicked item links. Bag-addon frames that use GameTooltip are covered;
custom third-party tooltip frames are not.

# Commands
--------
  - /sar                help
  - /sar stats          how many recipes are stored
  - /sar list           list professions in the database
  - /sar list Tailoring list recipe names for one profession
  - /sar search bag     search recipe names
  - /sar chars          which characters have been scanned
  - /sar rescan         force-scan the profession window that is open now
  - /sar wipe confirm   delete the whole account database

# Notes
-----
- Stock 1.12.1 API only (Lua 5.0). No Ace3, no C_Timer, no C_* namespaces.
- Enchanting uses the Craft frame; everything else uses TradeSkill.
- Beast Training is ignored.
- Filters in the profession window are temporarily reset to "All" while
  scanning, then restored. Collapsed headers are expanded for the scan.
- If a custom profession addon hides recipes, open the default profession
  window once so every recipe is visible.

# Author
-----
Sepirox-Burandir with Grok-AI
