-- Constant-product bonding curve (Uniswap v2 / pump.fun style):
-- currency_reserve * token_reserve = k, held constant across every trade.
-- Buying moves currency IN / tokens OUT of the pool; selling is the exact
-- reverse. The pool getting thinner (more of the supply already bought
-- out) is what makes both pumps and dumps hit harder over a coin's life --
-- nothing here needs a separate "volatility" number, it falls out of the
-- math on its own.

local function getPlayer(source)
    return exports.qbx_core:GetPlayer(source)
end

local function round(n, places)
    local mult = 10 ^ (places or 4)
    return math.floor(n * mult + 0.5) / mult
end

---@param currencyReserve number
---@param tokenReserve number
local function priceOf(currencyReserve, tokenReserve)
    tokenReserve = tonumber(tokenReserve)
    if tokenReserve <= 0 then return 0 end
    return tonumber(currencyReserve) / tokenReserve
end

-- oxmysql (mysql2) returns DECIMAL columns as strings, not numbers, to
-- avoid floating-point precision loss. Lua's arithmetic operators coerce
-- strings automatically, but its comparison operators (<, <=, >, >=) do
-- not and error outright -- so every raw DECIMAL field gets normalized to
-- a real number right here, once, instead of at every comparison site.
local function getCoin(coinId)
    local coin = MySQL.single.await('SELECT * FROM memecoins WHERE id = ?', { coinId })
    if not coin then return nil end
    coin.currency_reserve = tonumber(coin.currency_reserve)
    coin.token_reserve = tonumber(coin.token_reserve)
    coin.total_supply = tonumber(coin.total_supply)
    return coin
end

local function getHolding(citizenid, coinId)
    local row = MySQL.single.await('SELECT * FROM memecoin_holdings WHERE citizenid = ? AND coin_id = ?', { citizenid, coinId })
    if not row then return { amount = 0, avg_buy_price = 0 } end
    row.amount = tonumber(row.amount)
    row.avg_buy_price = tonumber(row.avg_buy_price)
    return row
end

local function playerName(player)
    local charinfo = player.PlayerData.charinfo
    return charinfo and ('%s %s'):format(charinfo.firstname, charinfo.lastname) or 'Unknown'
end

local function hasAdminPerm(src)
    if src == 0 then return true end
    local ok, res = pcall(function()
        return exports['pug-adminmenu']:HasPermission(src, Config.AdminPermission)
    end)
    if ok and res == true then return true end
    for _, g in ipairs(Config.AdminAceGroups) do
        if IsPlayerAceAllowed(src, 'group.' .. g) then return true end
    end
    return false
end

-- Forward-declared so createCoin (defined next) can use it to give the
-- creator a real starting stake right after launch.
local buyCoin

---@param source integer
---@param name string
---@param ticker string
---@param image string|nil
local function createCoin(source, name, ticker, image)
    local player = getPlayer(source)
    if not player then return false, 'Not loaded.' end

    name = (name or ''):sub(1, Config.MaxNameLength):gsub('^%s+', ''):gsub('%s+$', '')
    ticker = (ticker or ''):upper():gsub('[^%u%d]', ''):sub(1, Config.MaxTickerLength)

    if name == '' or ticker == '' then
        return false, 'Name and ticker are required.'
    end

    local existing = MySQL.single.await('SELECT id FROM memecoins WHERE ticker = ?', { ticker })
    if existing then
        return false, ('$%s is already taken.'):format(ticker)
    end

    local totalCost = Config.CreateCost + Config.CreatorInitialBuy
    if player.Functions.GetMoney(Config.Currency) < totalCost then
        return false, ('Need $%s to launch a coin ($%s fee + $%s starter buy).'):format(totalCost, Config.CreateCost, Config.CreatorInitialBuy)
    end

    player.Functions.RemoveMoney(Config.Currency, Config.CreateCost, 'memecoin-create')

    local citizenid = player.PlayerData.citizenid
    local creatorName = playerName(player)

    local coinId = MySQL.insert.await([[
        INSERT INTO memecoins (ticker, name, image, creator_citizenid, creator_name, currency_reserve, token_reserve, total_supply)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        ticker, name, image, citizenid, creatorName,
        Config.InitialCurrencyReserve, Config.TotalSupply, Config.TotalSupply,
    })

    -- Genesis point so the chart (and the rocketing/dumping trend banner)
    -- has a baseline to compare against even before the first real trade.
    MySQL.insert.await([[
        INSERT INTO memecoin_trades (coin_id, citizenid, trader_name, type, amount, currency, price)
        VALUES (?, ?, ?, 'buy', 0, 0, ?)
    ]], { coinId, citizenid, 'Genesis', priceOf(Config.InitialCurrencyReserve, Config.TotalSupply) })

    -- Creator's real starter buy -- gives them actual tokens instead of
    -- launching with zero skin in the game. Funds were already validated
    -- above alongside CreateCost, so this should never fail on money.
    if Config.CreatorInitialBuy > 0 then
        local ok, err = buyCoin(source, coinId, Config.CreatorInitialBuy)
        if not ok then
            print(('[anxious_memecoin] creator starter buy failed for coin %s: %s'):format(coinId, tostring(err)))
        end
    end

    return true, coinId, ticker
end

---@param source integer
---@param coinId integer
---@param currencyAmount number
buyCoin = function(source, coinId, currencyAmount)
    local player = getPlayer(source)
    if not player then return false, 'Not loaded.' end

    currencyAmount = tonumber(currencyAmount)
    if not currencyAmount or currencyAmount < Config.MinTradeAmount then
        return false, ('Minimum trade is $%s.'):format(Config.MinTradeAmount)
    end

    local coin = getCoin(coinId)
    if not coin then return false, 'Coin not found.' end

    if player.Functions.GetMoney(Config.Currency) < currencyAmount then
        return false, 'Not enough money.'
    end

    local k = coin.currency_reserve * coin.token_reserve
    local newCurrencyReserve = coin.currency_reserve + currencyAmount
    local newTokenReserve = k / newCurrencyReserve
    local tokensOut = coin.token_reserve - newTokenReserve

    if tokensOut <= 0 or tokensOut >= coin.token_reserve then
        return false, 'Trade too large for this pool.'
    end

    player.Functions.RemoveMoney(Config.Currency, currencyAmount, ('memecoin-buy-%s'):format(coin.ticker))

    MySQL.update.await('UPDATE memecoins SET currency_reserve = ?, token_reserve = ? WHERE id = ?', {
        newCurrencyReserve, newTokenReserve, coinId,
    })

    local citizenid = player.PlayerData.citizenid
    local traderName = playerName(player)
    local holding = getHolding(citizenid, coinId)
    local newAmount = holding.amount + tokensOut
    -- Weighted-average buy price, purely for the player's own profit/loss
    -- display -- doesn't feed back into the curve at all.
    local newAvgPrice = ((holding.amount * holding.avg_buy_price) + currencyAmount) / newAmount

    MySQL.query.await([[
        INSERT INTO memecoin_holdings (citizenid, coin_id, amount, avg_buy_price)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = ?, avg_buy_price = ?
    ]], { citizenid, coinId, newAmount, newAvgPrice, newAmount, newAvgPrice })

    local newPrice = priceOf(newCurrencyReserve, newTokenReserve)

    MySQL.insert.await([[
        INSERT INTO memecoin_trades (coin_id, citizenid, trader_name, type, amount, currency, price)
        VALUES (?, ?, ?, 'buy', ?, ?, ?)
    ]], { coinId, citizenid, traderName, tokensOut, currencyAmount, newPrice })

    TriggerClientEvent('anxious_memecoin:priceUpdate', -1, coinId, {
        price = newPrice, type = 'buy', amount = round(tokensOut, 4), currency = currencyAmount, traderName = traderName,
    })

    return true, { tokensOut = round(tokensOut, 4), newPrice = newPrice, newHolding = newAmount }
end

---@param source integer
---@param coinId integer
---@param tokenAmount number
local function sellCoin(source, coinId, tokenAmount)
    local player = getPlayer(source)
    if not player then return false, 'Not loaded.' end

    tokenAmount = tonumber(tokenAmount)
    if not tokenAmount or tokenAmount < Config.MinTradeAmount then
        return false, ('Minimum trade is %s tokens.'):format(Config.MinTradeAmount)
    end

    local coin = getCoin(coinId)
    if not coin then return false, 'Coin not found.' end

    local citizenid = player.PlayerData.citizenid
    local traderName = playerName(player)
    local holding = getHolding(citizenid, coinId)

    if holding.amount < tokenAmount then
        return false, "You don't hold that many."
    end

    local k = coin.currency_reserve * coin.token_reserve
    local newTokenReserve = coin.token_reserve + tokenAmount
    local newCurrencyReserve = k / newTokenReserve
    local currencyOut = coin.currency_reserve - newCurrencyReserve

    if currencyOut <= 0 or currencyOut >= coin.currency_reserve then
        return false, 'Trade too large for this pool.'
    end

    MySQL.update.await('UPDATE memecoins SET currency_reserve = ?, token_reserve = ? WHERE id = ?', {
        newCurrencyReserve, newTokenReserve, coinId,
    })

    local newAmount = holding.amount - tokenAmount
    MySQL.update.await('UPDATE memecoin_holdings SET amount = ? WHERE citizenid = ? AND coin_id = ?', {
        newAmount, citizenid, coinId,
    })

    player.Functions.AddMoney(Config.Currency, currencyOut, ('memecoin-sell-%s'):format(coin.ticker))

    local newPrice = priceOf(newCurrencyReserve, newTokenReserve)

    MySQL.insert.await([[
        INSERT INTO memecoin_trades (coin_id, citizenid, trader_name, type, amount, currency, price)
        VALUES (?, ?, ?, 'sell', ?, ?, ?)
    ]], { coinId, citizenid, traderName, tokenAmount, currencyOut, newPrice })

    -- Rug flag: sold almost this whole holding, and that holding was a
    -- meaningful slice of everything currently in players' hands.
    local circulating = coin.total_supply - coin.token_reserve
    local holderShare = circulating > 0 and (holding.amount / circulating) or 0
    if (tokenAmount / holding.amount) >= Config.RugSellFraction and holderShare >= Config.RugHolderShareThreshold then
        MySQL.update.await('UPDATE memecoins SET rugged = 1 WHERE id = ?', { coinId })
    end

    TriggerClientEvent('anxious_memecoin:priceUpdate', -1, coinId, {
        price = newPrice, type = 'sell', amount = tokenAmount, currency = round(currencyOut, 2), traderName = traderName,
    })

    return true, { currencyOut = round(currencyOut, 2), newPrice = newPrice, newHolding = newAmount }
end

local function listCoins()
    local coins = MySQL.query.await('SELECT * FROM memecoins ORDER BY created_at DESC')
    local list = {}

    for i = 1, #coins do
        local coin = coins[i]
        coin.currency_reserve = tonumber(coin.currency_reserve)
        coin.token_reserve = tonumber(coin.token_reserve)
        coin.total_supply = tonumber(coin.total_supply)
        local price = priceOf(coin.currency_reserve, coin.token_reserve)

        -- Cheap 24h-change lookup: earliest trade price still within the
        -- last 24h, compared to the current price. No separate snapshot
        -- job needed since every trade already writes a price row.
        local dayAgo = MySQL.scalar.await([[
            SELECT price FROM memecoin_trades
            WHERE coin_id = ? AND created_at >= (NOW() - INTERVAL 1 DAY)
            ORDER BY created_at ASC LIMIT 1
        ]], { coin.id })

        list[i] = {
            id = coin.id,
            ticker = coin.ticker,
            name = coin.name,
            image = coin.image,
            price = price,
            marketCap = round(price * (coin.total_supply - coin.token_reserve), 2),
            creatorName = coin.creator_name,
            rugged = coin.rugged == 1,
            change24h = dayAgo and round(((price - dayAgo) / dayAgo) * 100, 2) or 0,
        }
    end

    return list
end

local function getCoinDetail(source, coinId)
    local coin = getCoin(coinId)
    if not coin then return nil end

    local trades = MySQL.query.await([[
        SELECT type, amount, currency, price, trader_name, created_at FROM memecoin_trades
        WHERE coin_id = ? ORDER BY created_at DESC LIMIT ?
    ]], { coinId, Config.ChartMaxPoints })

    -- Normalize the DECIMAL columns (amount/currency/price come back as
    -- strings from oxmysql) before any comparison or arithmetic touches them.
    for i = 1, #trades do
        trades[i].amount = tonumber(trades[i].amount)
        trades[i].currency = tonumber(trades[i].currency)
        trades[i].price = tonumber(trades[i].price)
    end

    -- Chart wants oldest-first.
    local chart = {}
    for i = #trades, 1, -1 do
        chart[#chart + 1] = { price = trades[i].price, at = trades[i].created_at }
    end

    -- Recent trades feed: newest-first, real trades only (the genesis row
    -- has amount 0, so it's naturally excluded).
    local recentTrades = {}
    for i = 1, #trades do
        if #recentTrades >= Config.RecentTradesLimit then break end
        if trades[i].amount > 0 then
            recentTrades[#recentTrades + 1] = {
                type = trades[i].type,
                amount = trades[i].amount,
                currency = trades[i].currency,
                price = trades[i].price,
                traderName = trades[i].trader_name,
                at = trades[i].created_at,
            }
        end
    end

    local price = priceOf(coin.currency_reserve, coin.token_reserve)

    -- "Rocketing or failing" trend: compare current price against the
    -- earliest point we have (the genesis row for a fresh coin, or
    -- whatever's oldest within ChartMaxPoints otherwise).
    local launchPrice = chart[1] and chart[1].price or price
    local changeSinceLaunch = launchPrice > 0 and round(((price - launchPrice) / launchPrice) * 100, 2) or 0

    local dayAgo = MySQL.scalar.await([[
        SELECT price FROM memecoin_trades
        WHERE coin_id = ? AND created_at >= (NOW() - INTERVAL 1 DAY)
        ORDER BY created_at ASC LIMIT 1
    ]], { coinId })
    local change24h = dayAgo and round(((price - dayAgo) / dayAgo) * 100, 2) or 0

    return {
        id = coin.id,
        ticker = coin.ticker,
        name = coin.name,
        image = coin.image,
        price = price,
        marketCap = round(price * (coin.total_supply - coin.token_reserve), 2),
        totalSupply = coin.total_supply,
        circulating = coin.total_supply - coin.token_reserve,
        creatorName = coin.creator_name,
        rugged = coin.rugged == 1,
        changeSinceLaunch = changeSinceLaunch,
        change24h = change24h,
        chart = chart,
        recentTrades = recentTrades,
        isAdmin = hasAdminPerm(source),
    }
end

---@param source integer
---@param coinId integer
local function deleteCoin(source, coinId)
    if not hasAdminPerm(source) then
        return false, 'No permission.'
    end

    local coin = getCoin(coinId)
    if not coin then return false, 'Coin not found.' end

    -- memecoin_holdings and memecoin_trades both FK to memecoins with
    -- ON DELETE CASCADE, so this alone clears everything tied to it.
    MySQL.update.await('DELETE FROM memecoins WHERE id = ?', { coinId })

    TriggerClientEvent('anxious_memecoin:coinDeleted', -1, coinId)

    return true
end

local function getPortfolio(source)
    local player = getPlayer(source)
    if not player then return {} end

    local rows = MySQL.query.await([[
        SELECT h.amount, h.avg_buy_price, c.id, c.ticker, c.name, c.image, c.currency_reserve, c.token_reserve
        FROM memecoin_holdings h
        JOIN memecoins c ON c.id = h.coin_id
        WHERE h.citizenid = ? AND h.amount > 0
    ]], { player.PlayerData.citizenid })

    local portfolio = {}
    for i = 1, #rows do
        local row = rows[i]
        row.amount = tonumber(row.amount)
        row.avg_buy_price = tonumber(row.avg_buy_price)
        local price = priceOf(row.currency_reserve, row.token_reserve)
        portfolio[i] = {
            id = row.id,
            ticker = row.ticker,
            name = row.name,
            image = row.image,
            amount = row.amount,
            avgBuyPrice = row.avg_buy_price,
            currentPrice = price,
            value = round(price * row.amount, 2),
            profitLoss = round((price - row.avg_buy_price) * row.amount, 2),
        }
    end

    return portfolio
end

lib.callback.register('anxious_memecoin:getCreateInfo', function(source)
    return { createCost = Config.CreateCost, creatorInitialBuy = Config.CreatorInitialBuy }
end)

lib.callback.register('anxious_memecoin:listCoins', function(source) return listCoins() end)
lib.callback.register('anxious_memecoin:getCoinDetail', function(source, coinId) return getCoinDetail(source, coinId) end)
lib.callback.register('anxious_memecoin:getPortfolio', function(source) return getPortfolio(source) end)

lib.callback.register('anxious_memecoin:deleteCoin', function(source, data)
    return deleteCoin(source, data.coinId)
end)

lib.callback.register('anxious_memecoin:createCoin', function(source, data)
    return createCoin(source, data.name, data.ticker, data.image)
end)

lib.callback.register('anxious_memecoin:buyCoin', function(source, data)
    return buyCoin(source, data.coinId, data.amount)
end)

lib.callback.register('anxious_memecoin:sellCoin', function(source, data)
    return sellCoin(source, data.coinId, data.amount)
end)
