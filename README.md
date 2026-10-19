# MyRobloxGame

Code lives in `src/` and is synced into Roblox Studio with [Rojo](https://rojo.space).

| Folder in `src/` | Shows up in Studio as |
| --- | --- |
| `ServerScriptService` | ServerScriptService |
| `ReplicatedStorage` | ReplicatedStorage |
| `StarterPlayer/StarterPlayerScripts` | StarterPlayer > StarterPlayerScripts |

File names decide the script type: `*.server.luau` = Script, `*.client.luau` = LocalScript,
anything else `.luau` = ModuleScript.

## Syncing into Studio (Windows)

```
cd C:\Users\Jamie\my-roblox-game
git pull
rojo serve
```

Leave that window open, then in Studio: Plugins tab > Rojo > Connect.
Things you build by hand in Studio (parts, maps, UI) are left alone; only the folders above are synced.
