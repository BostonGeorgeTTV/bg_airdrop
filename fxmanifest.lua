fx_version 'cerulean'
game 'gta5'

name 'bg_airdrop'
author 'BostonGeorgeTTV'
description 'Configurable airdrop system with ox_target and ox_inventory'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'
server_script 'server.lua'

files {
    'stream/*.ytyp'
}

data_file 'DLC_ITYP_REQUEST' 'stream/airdrop.ytyp'

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory'
}
