--!strict
-- ReplicatedStorage > Shared > AudioConfig (ModuleScript)
-- Sound asset IDs. These are deliberately empty: the game ships with no audio of its own, and
-- inventing IDs would point at random or missing assets. Upload or pick licensed sounds (e.g.
-- from the Creator Store), paste their "rbxassetid://123..." IDs here, and AudioController
-- starts using them automatically. Anything left empty is simply skipped.
--
-- Suggested sources: a looping electric motor whine (pitch is driven by speed, so a steady
-- single-pitch loop works best), a looping tyre roll, a short skid, a suspension thump, a
-- crash impact, and short UI clicks.

return {
	MotorWhine = "", -- loop; pitch follows speed, volume follows throttle
	MotorLoad = "", -- loop; layered under the whine, follows motor load
	TyreRoll = "", -- loop; follows speed on paved surfaces
	TyreDirt = "", -- loop; follows speed on dirt/grass/gravel
	TyreSkid = "", -- loop; plays while braking hard or sliding
	Landing = "", -- one-shot; front wheel landing / suspension bottoming
	Brake = "", -- one-shot; brake squeal
	Crash = "", -- one-shot
	UiClick = "",
	UiConfirm = "",
	UiError = "",
	Reward = "",
	LevelUp = "",
	GarageAmbience = "", -- loop while the garage is open
}
