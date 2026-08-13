# FAQ - Dark Matter Replicators Reborn

### 1. What exactly does this mod do?
It adds replicators that produce items using electricity only. It dynamically generates replication recipes for almost any item (including those from compatible mods) and introduces specialized labs to research each replication technology individually.

### 2. Where does Tenemut ore spawn?
It depends on your startup settings:
*   **Without Space Age**: It spawns on Nauvis, similar to uranium.
*   **With Space Age**: By default, it spawns on Nauvis to allow seamless early-game progression. However, you can change its primary spawning planet (to Vulcanus, Fulgora, Gleba, or Aquilo) and choose whether to spawn it on other planets in the startup settings.

### 3. How is the energy cost of replication calculated?
The mod dynamically calculates costs based on the item's recipe ingredients. You can choose between two methods in the startup settings:
*   **Raw Ingredients (Flat)**: Sums the base cost of all raw ingredients.
*   **Recursive Steps (Compounding)**: Multiplies the cost cumulatively based on the manufacturing steps.
*   *Note*: The crafting time scales proportionally to the calculated resource cost to balance energy draw.

### 4. Can I replicate fluids or replicate items in space?
By default, replicating items on space platforms is disabled, but you can enable it via the "Replication in space" startup setting. Replicated fluids are delivered in configurable batches (25 units by default).

### 5. How can I make my own mod compatible with DMR?
The mod exposes helper functions like `repltech_recipe`, `repltech_item`, and `repltech_ore`. You can find the full technical guide and examples in the `How to add replications to a mod.txt` file.

### 6. Where should I report bugs or compatibility issues?
If you encounter a bug, startup crash, or mod compatibility issue, please post it on our [GitHub Issues Tracker](https://github.com/Jaer985/dark-matter-replicators-reborn_3/issues) or under the Discussions tab on the Factorio Mod Portal. When reporting, please include any error messages, your startup logs, and a list of other active mods to help us identify and resolve the issue quickly.
