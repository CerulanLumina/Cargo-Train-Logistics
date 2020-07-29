local s = data.raw["gui-style"].default

--Flows
s["cargorequestblacklistflow"] = {
    type = "horizontal_flow_style",
    vertical_align = "center",
    horizontal_align = "center",
    horizontally_stretchable = "on",
    horizontal_spacing = 10,
    top_padding = 10
}

--Widgets
s["cargodragwidget"] = {
    type = "empty_widget_style",
    parent = "draggable_space_header",
    horizontally_stretchable = "on",
    natural_height = 24,
    minimal_width = 24
}

s["cargowidget"] = {
    type = "empty_widget_style",
    horizontally_stretchable = "on",
    minimal_width = 0
}

--Tabbed pane
s["cargopane"] = {
    type = "tabbed_pane_style",
    parent = "tabbed_pane",
    tab_content_frame = {
        type = "frame_style",
        top_padding = 8,
        right_padding = 0,
        bottom_padding = 0,
        left_padding = 0,
        graphical_set = tabbed_pane_graphical_set
    },
    height = 400,
    top_padding = 12
}

--Scrollpanes
s["cargoscrollpane"] = {
    type = "scroll_pane_style",
    parent = "tab_scroll_pane",
    vertically_stretchable = "on",
    horizontal_scroll_policy = "off"
}

--Frames
s["cargosubheader"] = {
    type = "frame_style",
    parent = "subheader_frame",
    graphical_set = {
        base = {
            top = {position = {42, 0}, size = {1, 8}},
            center = {position = {256, 25}, size = {1, 1}},
            bottom = {position = {256, 26}, size = {1, 8}}
        },
        glow = {
            top = {position ={ 93, 0}, size = {1, 8}},
            draw_type = "outer"
        },
        shadow = bottom_shadow
    },
    top_padding = 1,
    height = 34
}

--Buttons
s["cargochooseelem28"] = {
    type = "button_style",
    parent = "slot_button_in_shallow_frame",
    size = 28
}