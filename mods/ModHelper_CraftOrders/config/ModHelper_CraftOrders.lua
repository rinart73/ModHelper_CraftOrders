local config = {}

config.author = "Rinart73"
config.name = "Mod Helper - Craft Orders"
config.acronym = "MH-CraftOrders"
config.homepage = "https://www.avorion.net/forum/index.php/topic,5046"
config.version = {
    major = 1, minor = 1, patch = 0, -- 0.17.1/0.18.0beta+
}
config.version.string = config.version.major..'.'..config.version.minor..'.'..config.version.patch

----

--[[ Logs:
0 - Disable
1 - Errors
2 - Warnings
3 - Info (will show how much time server update takes)
4 - Debug (a LOT of logs)
]]
config.logLevel = 2


return config