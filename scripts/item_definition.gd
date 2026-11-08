extends Resource
## Shared catalog data; mutable ownership and upgrades belong to ItemInstance.
@export var item_type_id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
@export var category: StringName = &"misc"
@export var icon: Texture2D
@export_range(1,999999,1) var max_stack := 1
@export var is_equippable := false
@export var is_droppable := true
@export var is_tradeable := true
@export var custom_properties: Dictionary = {}
