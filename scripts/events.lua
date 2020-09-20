require "util"

local player_lib = require "scripts/player"
local definesevents = defines.events
local table_deepcopy = util.table.deepcopy
local cargotypes = {
    ["cargo-wagon"] = true,
    --["artillery-wagon"] = true
}

local script_data = {
    players = {},
    trains = {},
    next_index = nil
}

local function new_train(train)
    local data = {
        train = train,
        id = tostring(train.id),
        wagons = {},
        storage_wagons = {}
    }

    for _, entity in pairs(train.cargo_wagons) do
        data.storage_wagons[tostring(entity.unit_number)] = {entity = entity, inventory = entity.get_inventory(defines.inventory.cargo_wagon)}
    end

    return data
end

local function add_wagon(traindata, entity)
    traindata.wagons[tostring(entity.unit_number)] = {
        entity = entity,
        enabled = true,
        request = {{item = nil, amount = 0}},
        blacklist = {{item = nil, amount = 0}},
        request_items = {},
        blacklist_items = {},
        inventory = entity.get_inventory(defines.inventory.cargo_wagon)
    }
    traindata.storage_wagons[tostring(entity.unit_number)] = nil
end

local function remove_wagon(traindata, entity)
    traindata.wagons[tostring(entity.unit_number)] = nil
    traindata.storage_wagons[tostring(entity.unit_number)] = {entity = entity, inventory = entity.get_inventory(defines.inventory.cargo_wagon)}
end

local function update_train(train)
    local storage_wagons = train.storage_wagons

    if table_size(storage_wagons) > 0 then
        for _, wagon in pairs(train.wagons) do
            if wagon.entity.valid and wagon.enabled then
                local inventory = wagon.inventory

                for _, request in pairs(wagon.request) do
                    local item = request.item

                    if item then
                        local amount = request.amount - inventory.get_item_count(item)

                        if amount > 0 then
                            local amount2 = amount

                            for _, storage_wagons in pairs(storage_wagons) do
                                if storage_wagons.entity.valid then
                                    if amount2 > 0 then
                                        amount2 = amount2 - storage_wagons.inventory.remove({name = item, count = amount2})
                                    else
                                        break
                                    end
                                end
                            end

                            local amount3 = amount - amount2

                            if amount3 > 0 then
                                inventory.insert({name = item, count = amount3})
                            end
                        end
                    end
                end
                for _, blacklist in pairs(wagon.blacklist) do
                    local item = blacklist.item

                    if item then
                        local amount = inventory.get_item_count(item) - blacklist.amount

                        if amount > 0 then
                            local amount2 = amount

                            for _, storage_wagon in pairs(storage_wagons) do
                                if storage_wagon.entity.valid then
                                    if amount2 > 0 then
                                        amount2 = amount2 - storage_wagon.inventory.insert({name = item, count = amount2})
                                    else
                                        break
                                    end
                                end
                            end

                            local amount3 = amount - amount2

                            if amount3 > 0 then
                                inventory.remove({name = item, count = amount3})
                            end
                        end
                    end
                end
            end
        end
    end
end

local function playerstart(player_index)
    if 	not script_data.players[tostring(player_index)] then
        local player = player_lib.new(game.players[player_index])

        script_data.players[player.index] = player
    end
end

local function playerload()
    for _, player in pairs(game.players) do
        playerstart(player.index)
    end
end

local function on_entity_removed(event)
    local entity = event.entity

    if not (entity and entity.valid) then return end

    if cargotypes[entity.type] then
        local trainmeta = script_data.trains[tostring(entity.train.id)]

        if trainmeta then
            local wagonmeta = trainmeta.wagons[tostring(entity.unit_number)]

            if wagonmeta then
                trainmeta.wagons[tostring(entity.unit_number)] = nil
            end
        end
    end
end

return {
    on_init = function()
        global.ctl = global.ctl or script_data

        playerload()
    end,
    on_load = function()
        script_data = global.ctl or script_data

        for _, player in pairs(script_data.players) do
            setmetatable(player, player_lib.metatable)
        end
    end,
    on_configuration_changed = function(event)
        global.ctl = global.ctl or script_data

        playerload()

        for _, train in pairs(script_data.trains) do

            for _, wagon in pairs(train.wagons) do
                for item, index in pairs(wagon.request_items) do
                    if not game.item_prototypes[item] then
                        wagon.request_items[item] = nil

                        table.remove(wagon.request, index)
                    end
                end

                for item, index in pairs(wagon.blacklist_items) do
                    if not game.item_prototypes[item] then
                        wagon.blacklist_items[item] = nil

                        table.remove(wagon.blacklist, index)
                    end
                end
            end
        end

        for _, player in pairs(script_data.players) do
            if player.frame then
                player:clear()
                player.player.opened = nil
            end
        end

        local changes = event.mod_changes and event.mod_changes["Cargo_Train_Logistics"] or {}

        if next(changes) then
            local oldchanges = changes.old_version

            if oldchanges and changes.new_version then
                if oldchanges == "0.0.4" then
                    local old_script_data = global.script_data

                    for _, player in pairs(old_script_data.players) do
                        if player.frame then
                            player.frame.destroy()
                            player.player.opened = nil
                        end
                    end

                    global.script_data = nil
                end
            end
        end
    end,
    events = {
        [definesevents.on_tick] = function()
            local index, traindata = next(script_data.trains, script_data.next_index)

            if index then
                script_data.next_index = index

                update_train(traindata)
            else
                script_data.next_index = nil
            end
        end,
        [definesevents.on_entity_died] = on_entity_removed,
        [definesevents.on_gui_checked_state_changed] = function(event)
            local element = event.element
            local name = element.name

            if name:sub(1, 11) == "CARGO_CHECK" then
                local entity = script_data.players[tostring(event.player_index)].wagon
                script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)].enabled = element.state

                for _, playermeta in pairs(script_data.players) do
                    if playermeta.unit_number == entity.unit_number then
                        playermeta.checkbox.state = element.state
                    end
                end
            end
        end,
        [definesevents.on_gui_click] = function(event)
            local name = event.element.name

            if name:sub(1, 11) == "CARGO_CLICK" then
                local player_id = event.player_index
                local player = game.players[player_id]
                local playermeta = script_data.players[tostring(player_id)]
                local entity = playermeta.wagon
                local number = name:sub(12, 13)

                if number == "01" then
                    local wagondata = script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)]
                    local inventory = wagondata.inventory

                    if inventory.is_filtered() then
                        local itemtable = {}
                        local data_table = {}
                        local item_table = {}
                        local index = 1

                        for i = 1, #inventory do
                            local filter = inventory.get_filter(i)

                            if filter then
                                if itemtable[filter] then
                                    itemtable[filter] = itemtable[filter] + 1
                                else
                                    itemtable[filter] = 1
                                end
                            end
                        end

                        for itemname, filters in pairs(itemtable) do
                            local amount = game.item_prototypes[itemname].stack_size * filters

                            table.insert(data_table, {item = itemname, amount = amount})

                            item_table[itemname] = index

                            index = index + 1
                        end

                        table.insert(data_table, {item = nil, amount = 0})

                        wagondata.request = table_deepcopy(data_table)
                        wagondata.blacklist = table_deepcopy(data_table)
                        wagondata.request_items = table_deepcopy(item_table)
                        wagondata.blacklist_items = table_deepcopy(item_table)

                        for _, playermeta2 in pairs(script_data.players) do
                            if playermeta2.unit_number == entity.unit_number then
                                playermeta2.request_flow.clear()
                                playermeta2:request_tab(wagondata.request)
                                playermeta2.blacklist_flow.clear()
                                playermeta2:blacklist_tab(wagondata.blacklist)
                            end
                        end
                    else
                        player.print({"Cargo.NotFiltered"})
                    end
                elseif number == "02" then
                    local id = tostring(entity.train.id)
                    local traindata = script_data.trains[id]

                    remove_wagon(traindata, entity)

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2:clear()
                            playermeta2:gui({entity = entity})
                        end
                    end

                    if table_size(traindata.wagons) == 0 then
                        script_data.trains[id] = nil
                    end
                elseif number == "03" then
                    local train = entity.train
                    local id = tostring(train.id)
                    local traindata = {}

                    if script_data.trains[id] then
                        traindata = script_data.trains[id]
                    else
                        traindata = new_train(train)
                        script_data.trains[id] = traindata
                    end

                    add_wagon(traindata, entity)

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2:clear()
                            playermeta2:gui(traindata.wagons[tostring(entity.unit_number)])
                        end
                    end
                elseif number == "04" then
                    local wagondata = script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)]
                    local index = tonumber(name:sub(15))

                    if #wagondata.request == index then
                        player.print({"Cargo.LastEntry"})
                    else
                        local item = wagondata.request[index].item

                        if type(item) == "string" then
                            wagondata.request_items[item] = nil
                        end

                        table.remove(wagondata.request, index)

                        for _, playermeta2 in pairs(script_data.players) do
                            if playermeta2.unit_number == entity.unit_number then
                                playermeta2.request_flow.clear()
                                playermeta2:request_tab(wagondata.request)
                            end
                        end
                    end
                elseif number == "05" then
                    local wagondata = script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)]
                    local index = tonumber(name:sub(15))

                    if #wagondata.blacklist == index then
                        player.print({"Cargo.LastEntry"})
                    else
                        local item = wagondata.blacklist[index].item

                        if type(item) == "string" then
                            wagondata.blacklist_items[item] = nil
                        end

                        table.remove(wagondata.blacklist, index)

                        for _, playermeta2 in pairs(script_data.players) do
                            if playermeta2.unit_number == entity.unit_number then
                                playermeta2.blacklist_flow.clear()
                                playermeta2:blacklist_tab(wagondata.blacklist)
                            end
                        end
                    end
                end
            end
        end,
        [definesevents.on_gui_closed] = function(event)
            if event.gui_type == defines.gui_type.entity then
                local entity = event.entity

                if cargotypes[entity.type] then
                    local playermeta = script_data.players[tostring(event.player_index)]

                    if playermeta.frame then
                        playermeta:clear()
                    end
                end
            end
        end,
        [definesevents.on_gui_confirmed] = function(event)
            local element = event.element
            local name = element.name

            if name:sub(1, 15) == "CARGO_CONFIRMED" then
                local playermeta = script_data.players[tostring(event.player_index)]
                local entity = playermeta.wagon
                local wagondata = script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)]
                local amount = tonumber(element.text)
                local number = name:sub(16, 17)
                local index = tonumber(name:sub(19))

                if number == "01" then
                    local request = wagondata.request[index]
                    local blacklist_item = wagondata.blacklist_items[request.item]
                    local update = false

                    if amount == 0 then
                        amount = 1
                        element.text = 1
                    end

                    request.amount = amount

                    if blacklist_item then
                        local blacklist = wagondata.blacklist[blacklist_item]
                        local check_amount = blacklist.amount

                        if amount > check_amount then
                            blacklist.amount = amount
                            update = true
                        end
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.request_textfields[index].text = amount
                            playermeta2.request_sliders[index].slider_value = amount

                        if update then
                            playermeta2.blacklist_textfields[blacklist_item].text = amount
                            playermeta2.blacklist_sliders[blacklist_item].slider_value = amount
                        end
                    end
                end
                elseif number == "02" then
                    local blacklist = wagondata.blacklist[index]
                    local request_item = wagondata.request_items[blacklist.item]

                    if request_item then
                        local check_amount = wagondata.request[request_item].amount

                        if amount < check_amount then
                            amount = check_amount
                            element.text = check_amount
                        end
                    end

                    blacklist.amount = amount

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.blacklist_textfields[index].text = amount
                            playermeta2.blacklist_sliders[index].slider_value = amount
                        end
                    end
                end
            end
        end,
        [definesevents.on_gui_elem_changed] = function(event)
            local element = event.element
            local name = element.name

            if name:sub(1, 12) == "CARGO_CHOOSE" then
                local player_id = event.player_index
                local player = game.players[player_id]
                local playermeta = script_data.players[tostring(player_id)]
                local entity = playermeta.wagon
                local wagondata = script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)]
                local item = element.elem_value
                local number = name:sub(13, 14)
                local index = tonumber(name:sub(16))

                if number == "01" then
                    local requests = wagondata.request
                    local request = requests[index]

                    if type(item) == "string" then
                        if wagondata.request_items[item] then
                            element.elem_value = request.item

                            player.print({"Cargo.AlreadyRequested"})
                        else
                            local amount = game.item_prototypes[item].stack_size

                            wagondata.request_items[item] = index

                            if type(request.item) == "string" then
                                wagondata.request_items[request.item] = nil
                            end

                            request.item = item
                            request.amount = amount

                            if #requests == index then
                                requests[index + 1] = {item = nil, amount = 0}
                            end
                        end
                    else
                        if #requests == index then
                            if wagondata.request_items[request.item] then
                                wagondata.request_items[request.item] = nil
                            end

                            request.item = nil
                            request.amount = 0
                        else
                            table.remove(requests, index)
                        end
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.wagon and playermeta2.wagon.unit_number == entity.unit_number then
                            playermeta2.request_flow.clear()
                            playermeta2:request_tab(requests)
                        end
                    end
                elseif number == "02" then
                    local blacklists = wagondata.blacklist
                    local blacklist = blacklists[index]

                    if type(item) == "string" then
                        if wagondata.blacklist_items[item] then
                            element.elem_value = blacklist.item

                            player.print({"Cargo.AlreadyBlacklisted"})
                        else
                            local amount = game.item_prototypes[item].stack_size
                            local request_item = wagondata.request_items[item]

                            if request_item then
                                local check_amount = wagondata.request[request_item].amount

                                if amount < check_amount then
                                    amount = check_amount
                                end
                            end

                            wagondata.blacklist_items[item] = index

                            if type(blacklist.item) == "string" then
                                wagondata.blacklist_items[blacklist.item] = nil
                            end

                            blacklist.item = item
                            blacklist.amount = amount

                            if #blacklists == index then
                                blacklists[index + 1] = {item = nil, amount = 0}
                            end
                        end
                    else
                        if #blacklists == index then
                            if wagondata.blacklist_items[blacklist.item] then
                                wagondata.blacklist_items[blacklist.item] = nil
                            end

                            blacklist.item = nil
                            blacklist.amount = 0
                        else
                            table.remove(blacklists, index)
                        end
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.blacklist_flow.clear()
                            playermeta2:blacklist_tab(blacklists)
                        end
                    end
                end
            end
        end,
        [definesevents.on_gui_location_changed] = function(event)
            local playermeta = script_data.players[tostring(event.player_index)]
            local element = event.element

            if playermeta.frame and element.index == playermeta.frame.index then
                playermeta.location = element.location
            end
        end,
        [definesevents.on_gui_opened] = function(event)
            if event.gui_type == defines.gui_type.entity then
                local entity = event.entity
                local type = entity.type

                if cargotypes[type] then
                    local wagondata = {entity = entity}
                    local traindata = script_data.trains[tostring(entity.train.id)]

                    if traindata then
                        local wagondata2 = traindata.wagons[tostring(entity.unit_number)]

                        if wagondata2 then
                            wagondata = wagondata2
                        end
                    end

                    script_data.players[tostring(event.player_index)]:gui(wagondata)
                end
            end
        end,
        [definesevents.on_gui_value_changed] = function(event)
            local element = event.element
            local name = element.name

            if name:sub(1, 12) == "CARGO_SLIDER" then
                local playermeta = script_data.players[tostring(event.player_index)]
                local entity = playermeta.wagon
                local wagondata = script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)]
                local amount = element.slider_value
                local number = name:sub(13, 14)
                local index = tonumber(name:sub(16))

                if number == "01" then
                    local request = wagondata.request[index]
                    local blacklist_item = wagondata.blacklist_items[request.item]
                    local update = false

                    if amount == 0 then
                        amount = 1
                        element.slider_value = 1
                    end

                    request.amount = amount

                    if blacklist_item then
                        local blacklist = wagondata.blacklist[blacklist_item]
                        local check_amount = blacklist.amount

                        if amount > check_amount then
                            blacklist.amount = amount
                            update = true
                        end
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.request_textfields[index].text = amount
                            playermeta2.request_sliders[index].slider_value = amount

                            if update then
                                playermeta2.blacklist_textfields[blacklist_item].text = amount
                                playermeta2.blacklist_sliders[blacklist_item].slider_value = amount
                            end
                        end
                    end
                elseif number == "02" then
                    local blacklist = wagondata.blacklist[index]
                    local request_item = wagondata.request_items[blacklist.item]

                    if request_item then
                        local check_amount = wagondata.request[request_item].amount

                        if amount < check_amount then
                            amount = check_amount
                            element.slider_value = check_amount
                        end
                    end

                    blacklist.amount = amount

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.blacklist_textfields[index].text = amount
                            playermeta2.blacklist_sliders[index].slider_value = amount
                        end
                    end
                end
            end
        end,
        [definesevents.on_player_created] = function(event)
            playerstart(event.player_index)
        end,
        [definesevents.on_player_mined_entity] = on_entity_removed,
        [definesevents.on_player_removed] = function(event)
            script_data.players[tostring(event.player_index)] = nil
        end,
        [definesevents.on_robot_mined_entity] = on_entity_removed,
        [definesevents.on_train_created] = function(event)
            local trains = script_data.trains
            local oldtrain1 = trains[tostring(event.old_train_id_1)]
            local oldtrain2 = trains[tostring(event.old_train_id_2)]

            if oldtrain1 then
                for _, data in pairs(oldtrain1.wagons) do
                    local entity = data.entity

                    if entity.valid then
                        local train = entity.train
                        local trainid = tostring(train.id)
                        local traindata = trains[trainid]

                        if traindata then
                            if not traindata.wagons[tostring(entity.unit_number)] then
                                add_wagon(traindata, entity)
                                
                                traindata.wagons[tostring(entity.unit_number)] = data
                            end
                        else
                            traindata = new_train(train)

                            script_data.trains[trainid] = traindata

                            add_wagon(traindata, entity)

                            traindata.wagons[tostring(entity.unit_number)] = data
                        end
                    end
                end

                trains[tostring(event.old_train_id_1)] = nil
            end

            if oldtrain2 then
                for _, data in pairs(oldtrain2.wagons) do
                    local entity = data.entity

                    if entity.valid then
                        local train = entity.train
                        local trainid = tostring(train.id)
                        local traindata = trains[trainid]

                        if traindata then
                            if not traindata.wagons[tostring(entity.unit_number)] then
                                add_wagon(traindata, entity)
                                
                                traindata.wagons[tostring(entity.unit_number)] = data
                            end
                        else
                            traindata = new_train(train)
                            script_data.trains[trainid] = traindata
                            
                            add_wagon(traindata, entity)
                            
                            traindata.wagons[tostring(entity.unit_number)] = data
                        end
                    end
                end
                trains[tostring(event.old_train_id_2)] = nil
            end
        end,
        [definesevents.script_raised_destroy] = on_entity_removed,
    }
}