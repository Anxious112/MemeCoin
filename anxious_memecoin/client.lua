local identifier = 'anxious_memecoin'

while GetResourceState('lb-phone') ~= 'started' do
    Wait(500)
end

local function addApp()
    local added, errorMessage = exports['lb-phone']:AddCustomApp({
        identifier = identifier,

        name = 'Meme Coin',
        description = 'Launch a coin, ride the pump, or get rugged.',
        developer = 'Anxious',

        defaultApp = false,
        size = 4096,

        -- Filename changed (not just content) from icon.svg to
        -- app_icon_v2.svg deliberately: FiveM's NUI caches assets by URL,
        -- and `restart anxious_memecoin` doesn't reliably bust that cache
        -- client-side, so re-editing icon.svg's content may have kept
        -- serving a stale first-fetched copy no matter what we changed it
        -- to. A new filename forces every client to actually re-fetch it.
        icon = 'https://cfx-nui-' .. GetCurrentResourceName() .. '/ui/app_icon_v2.svg',
        ui = GetCurrentResourceName() .. '/ui/index.html',

        fixBlur = true,
    })

    if not added then
        print('[anxious_memecoin] Could not add app:', errorMessage)
    end
end

addApp()

AddEventHandler('onResourceStart', function(resource)
    if resource == 'lb-phone' then
        addApp()
    end
end)

-- Server broadcasts a price update (plus the trade that caused it) to
-- everyone on every trade; forward it into whatever custom-app UI instance
-- is currently open (a no-op if the app isn't open -- SendCustomAppMessage
-- just queues for whenever it is).
RegisterNetEvent('anxious_memecoin:priceUpdate', function(coinId, trade)
    exports['lb-phone']:SendCustomAppMessage(identifier, {
        type = 'priceUpdate',
        coinId = coinId,
        trade = trade,
    })
end)

-- Server broadcasts when an admin deletes a coin, so anyone with it open
-- (list or detail) gets bounced/updated instead of acting on a dead coin.
RegisterNetEvent('anxious_memecoin:coinDeleted', function(coinId)
    exports['lb-phone']:SendCustomAppMessage(identifier, {
        type = 'coinDeleted',
        coinId = coinId,
    })
end)

RegisterNUICallback('getCreateInfo', function(_, cb)
    cb(lib.callback.await('anxious_memecoin:getCreateInfo', false))
end)

RegisterNUICallback('listCoins', function(_, cb)
    cb(lib.callback.await('anxious_memecoin:listCoins', false))
end)

RegisterNUICallback('getCoinDetail', function(data, cb)
    cb(lib.callback.await('anxious_memecoin:getCoinDetail', false, data.coinId))
end)

RegisterNUICallback('getPortfolio', function(_, cb)
    cb(lib.callback.await('anxious_memecoin:getPortfolio', false))
end)

RegisterNUICallback('createCoin', function(data, cb)
    local ok, result, ticker = lib.callback.await('anxious_memecoin:createCoin', false, data)
    cb({ ok = ok, result = result, ticker = ticker })
end)

RegisterNUICallback('buyCoin', function(data, cb)
    local ok, result = lib.callback.await('anxious_memecoin:buyCoin', false, data)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('sellCoin', function(data, cb)
    local ok, result = lib.callback.await('anxious_memecoin:sellCoin', false, data)
    cb({ ok = ok, result = result })
end)

RegisterNUICallback('deleteCoin', function(data, cb)
    local ok, result = lib.callback.await('anxious_memecoin:deleteCoin', false, data)
    cb({ ok = ok, result = result })
end)
