fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Anxious'
description 'Meme Coin -- lb-phone custom app'
version '1.0.0'

shared_script '@ox_lib/init.lua'
shared_script 'config.lua'
client_script 'client.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

-- Deliberately NOT declaring ui_page here. lb-phone loads this page into
-- its own embedded iframe (it just needs the file servable, which files{}
-- already provides) -- declaring ui_page as well makes FiveM ALSO spin up
-- this resource's own independent top-level NUI browser, which nothing
-- ever hides or resizes to the phone's screen, and which was rendering our
-- opaque UI fullscreen over the game for every player regardless of
-- whether their phone was even open. The embed-gate script in
-- ui/index.html stays as a safety net, but this is the actual fix.
files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/app_icon_v2.svg', -- renamed from icon.svg to force a fresh URL past FiveM's NUI asset cache; icon.png stays in the repo as reference art, unused
}

dependencies {
    'ox_lib',
    'qbx_core',
    'oxmysql',
    'lb-phone',
}
