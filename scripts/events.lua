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
        data.storage_wagons[tostring(entity.unit_number)] = entity
    end

    return data
end

local function add_wagon(traindata, entity)
    traindata.wagons[tostring(entity.unit_number)] = {
        entity = entity,
        enabled = true,
        request = {},
        blacklist = {},
        inventory = entity.get_inventory(defines.inventory.cargo_wagon)
    }
    traindata.storage_wagons[tostring(entity.unit_number)] = nil
end

local function remove_wagon(traindata, entity)
    traindata.wagons[tostring(entity.unit_number)] = nil
    traindata.storage_wagons[tostring(entity.unit_number)] = entity
end

local function update_train(train)
    local storage_wagons = train.storage_wagons

    if table_size(storage_wagons) > 0 then
        for id, storage_wagon in pairs(storage_wagons) do
            if not storage_wagon.valid then
                storage_wagons[id] = nil
            end
        end

        for _, wagon in pairs(train.wagons) do
            if wagon.entity.valid and wagon.enabled then
                local request = table_deepcopy(wagon.request)
                local blacklist = wagon.blacklist

                for name, amount in pairs(wagon.inventory.get_contents()) do
                    if request[name] and request[name] > amount then
                        local number1 = request[name] - amount
                        local number2 = number1

                        for _, storage_wagon in pairs(storage_wagons) do
                            if storage_wagon.valid then
                                number2 = number2 - storage_wagon.remove_item({name = name, count = number2})

                                if number2 == 0 then
                                    break
                                end
                            end
                        end

                        if number1 ~= number2 then
                            wagon.entity.insert({name = name, count = ((number2 == 0 and number1) or (number1 - number2))})
                        end
                    elseif blacklist[name] and amount > blacklist[name] then
                        local number1 = amount - blacklist[name]
                        local number2 = number1

                        for _, storage_wagon in pairs(storage_wagons) do
                            if storage_wagon.valid then
                                number2 = number2 - storage_wagon.insert({name = name, count = number2})

                                if number2 == 0 then
                                    break
                                end
                            end
                        end

                        if number1 ~= number2 then
                            wagon.entity.remove_item({name = name, count = ((number2 == 0 and number1) or (number1 - number2))})
                        end
                    end

                    request[name] = nil
                end

                for name, amount in pairs(request) do
                    local number = amount

                    for _, storage_wagon in pairs(storage_wagons) do
                        if storage_wagon.valid then
                            number = number - storage_wagon.remove_item({name = name, count = number})

                            if number == 0 then
                                break
                            end
                        end
                    end

                    if amount ~= number then
                        wagon.entity.insert({name = name, count = ((number == 0 and amount) or (amount - number))})
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
                trainmeta.storage_wagons[tostring(entity.unit_number)] = nil
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
                local request = wagon.request
                local blacklist = wagon.blacklist

                for name, _ in pairs(request) do
                    if not game.item_prototypes[name] then
                        request[name] = nil
                    end
                end

                for name, _ in pairs(blacklist) do
                    if not game.item_prototypes[name] then
                        blacklist[name] = nil
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
                elseif oldchanges == "1.0.0" or oldchanges == "1.0.1" then
                    for _, train in pairs(script_data.trains) do
                        for id, storage_wagon in pairs(train.storage_wagons) do
                            train.storage_wagons[id] = storage_wagon.entity
                        end

                        for _, wagon in pairs(train.wagons) do
                            local t1 = {}
                            local t2 = {}
                            for _, data in pairs(wagon.request) do
                                t1[data.item] = data.amount
                            end

                            for _, data in pairs(wagon.blacklist) do
                                t2[data.item] = data.amount
                            end

                            wagon.request = table_deepcopy(t1)
                            wagon.blacklist = table_deepcopy(t2)
                            wagon.request_items = nil
                            wagon.blacklist_items = nil
                        end
                    end
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
                        local item_table = {}

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

                            item_table[itemname] = amount
                        end

                        wagondata.request = table_deepcopy(item_table)
                        wagondata.blacklist = table_deepcopy(item_table)

                        for _, playermeta2 in pairs(script_data.players) do
                            if playermeta2.unit_number == entity.unit_number then
                                playermeta2:request_tab(wagondata.request)
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
                    local item = name:sub(15)

                    wagondata.request[item] = nil

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2:request_tab(wagondata.request)
                        end
                    end
                elseif number == "05" then
                    local wagondata = script_data.trains[tostring(entity.train.id)].wagons[tostring(entity.unit_number)]
                    local item = name:sub(15)

                    wagondata.blacklist[item] = nil

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2:blacklist_tab(wagondata.blacklist)
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
                local request = wagondata.request
                local blacklist = wagondata.blacklist
                local amount = tonumber(element.text)
                local number = name:sub(16, 17)
                local item = name:sub(19)

                if number == "01" then
                    local update = false

                    if amount == 0 then
                        amount = 1
                        element.text = 1
                    end

                    request[item] = amount

                    if blacklist[item] and amount > blacklist[item] then
                        blacklist[item] = amount
                        update = true
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.request_textfields[item].text = tostring(amount)
                            playermeta2.request_sliders[item].slider_value = amount

                            if update then
                                playermeta2.blacklist_textfields[item].text = tostring(amount)
                                playermeta2.blacklist_sliders[item].slider_value = amount
                            end
                        end
                    end
                elseif number == "02" then
                    if request[item] and amount < request[item] then
                        amount = request[item]
                        element.text = request[item]
                    end

                    blacklist[item] = amount

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.blacklist_textfields[item].text = tostring(amount)
                            playermeta2.blacklist_sliders[item].slider_value = amount
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
                local request = wagondata.request
                local item = element.elem_value
                local number = name:sub(13, 14)
                local itemname = name:sub(16)

                if number == "01" then
                    if item then
                        if request[item] then
                            element.elem_value = (itemname ~= "cargodummy" and itemname) or nil

                            player.print({"Cargo.AlreadyRequested"})
                        else
                            if itemname ~= "cargodummy" then
                                request[itemname] = nil
                            end

                            request[item] = game.item_prototypes[item].stack_size
                        end
                    else
                        request[itemname] = nil
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2:request_tab(request)
                        end
                    end
                elseif number == "02" then
                    local blacklist = wagondata.blacklist

                    if item then
                        if wagondata.blacklist[item] then
                            element.elem_value = (itemname ~= "cargodummy" and itemname) or nil

                            player.print({"Cargo.AlreadyBlacklisted"})
                        else
                            local amount = game.item_prototypes[item].stack_size

                            if request[item] and amount < request[item] then
                                amount = request[item]
                            end

                            if itemname ~= "cargodummy" then
                                blacklist[itemname] = nil
                            end

                            blacklist[item] = amount
                        end
                    else
                        request[itemname] = nil
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2:blacklist_tab(blacklist)
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
                local request = wagondata.request
                local blacklist = wagondata.blacklist
                local amount = element.slider_value
                local number = name:sub(13, 14)
                local item = name:sub(16)

                if number == "01" then
                    local update = false

                    if amount == 0 then
                        amount = 1
                        element.slider_value = 1
                    end

                    request[item] = amount

                    if blacklist[item] and amount > blacklist[item] then
                        blacklist[item] = amount
                        update = true
                    end

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.request_textfields[item].text = tostring(amount)
                            playermeta2.request_sliders[item].slider_value = amount

                            if update then
                                playermeta2.blacklist_textfields[item].text = tostring(amount)
                                playermeta2.blacklist_sliders[item].slider_value = amount
                            end
                        end
                    end
                elseif number == "02" then
                    if request[item] and amount < request[item] then
                        amount = request[item]
                        element.slider_value = request[item]
                    end

                    blacklist[item] = amount

                    for _, playermeta2 in pairs(script_data.players) do
                        if playermeta2.unit_number == entity.unit_number then
                            playermeta2.blacklist_textfields[item].text = tostring(amount)
                            playermeta2.blacklist_sliders[item].slider_value = amount
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