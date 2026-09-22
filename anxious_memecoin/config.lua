Config = {}

Config.Currency = 'bank' -- 'bank' | 'cash' | 'black_money'

-- Bonding curve seed values, same for every new coin. Larger
-- InitialCurrencyReserve = more money needed to move the price noticeably
-- (a "deeper" pool); larger TotalSupply relative to that = a lower, more
-- meme-coin-looking starting price per token.
Config.TotalSupply = 1000000000 -- 1 billion tokens, all start unowned in the pool
Config.InitialCurrencyReserve = 2000 -- seed liquidity -- starting price = this / TotalSupply

Config.CreateCost = 500 -- charged to the creator's Config.Currency on creation, sunk (not added to the pool)
-- Charged on top of CreateCost and immediately spent as the creator's own
-- first buy into the coin they just launched -- real skin in the game
-- instead of walking away holding zero tokens, and it raises the bar for
-- spamming junk coins.
Config.CreatorInitialBuy = 250
Config.MinTradeAmount = 1 -- smallest currency amount for a buy, or token amount for a sell
Config.MaxTickerLength = 6
Config.MaxNameLength = 24

-- A coin is flagged "rugged" (cosmetic warning badge, nothing mechanical)
-- once a single sell removes at least this fraction of the seller's own
-- pre-trade holding AND that holding was at least this fraction of the
-- circulating supply -- i.e. someone who held a big chunk dumped
-- basically all of it in one go.
Config.RugSellFraction = 0.9
Config.RugHolderShareThreshold = 0.2

-- Price history: one row logged per trade (memecoin_trades) is already a
-- natural time series, no separate polling/snapshot loop needed.
Config.ChartMaxPoints = 100 -- trim how many trade rows the UI is sent per coin
Config.RecentTradesLimit = 15 -- how many real trades (buy/sell, not the genesis row) show in the feed

-- Same admin-check pattern as anxious_forceemote: try pug-adminmenu's own
-- permission first (exports['pug-adminmenu']:HasPermission(src, Config.AdminPermission)),
-- falling back to a plain ACE group check if that export isn't available.
Config.AdminPermission = 'memecoin_delete' -- pug-adminmenu action id (add to its config-permissions.lua for god + management)
Config.AdminAceGroups = { 'god', 'management', 'admin' } -- fallback: IsPlayerAceAllowed(src, 'group.<x>')
