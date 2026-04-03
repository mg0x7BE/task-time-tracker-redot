extends Control

## Preloaded assets
const ICON_PLAY := preload("res://assets/gfx/play.svg")
const ICON_PAUSE := preload("res://assets/gfx/pause.svg")
const ICON_DELETE := preload("res://assets/gfx/delete.svg")

## Configuration
const SAVE_PATH := "user://TaskTimeTracker.json"
const AUTOSAVE_INTERVAL := 60.0
const DEFAULT_TASK_NAME := "New Task"
const ACTIVE_COLOR := Color(0, 1, 0)
const INACTIVE_COLOR := Color(1, 1, 1)
const SCROLLBAR_COLOR := Color("#F50078")

## Node references
@onready var task_list_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
@onready var add_task_button: Button = $VBoxContainer/MarginContainer2/HBoxContainer2/ButtonAddTask
@onready var reset_all_button: Button = $VBoxContainer/MarginContainer2/HBoxContainer2/ButtonResetAll
@onready var total_time_label: Label = $VBoxContainer/MarginContainer2/HBoxContainer2/LabelTotalTime
@onready var title_label: Label = $VBoxContainer/MarginContainer/HBoxContainer/LabelHackingTime

var tasks: Array = []
var active_task: Task = null
var timer: Timer = null


class Task:
	var name: String
	var elapsed_time: float
	var is_running: bool

	func _init(task_name: String) -> void:
		name = task_name
		elapsed_time = 0.0
		is_running = false

	static func format_time(seconds_total: float) -> String:
		var total := int(seconds_total)
		var hours := total / 3600
		var minutes := (total % 3600) / 60
		var seconds := total % 60
		return "%02d:%02d:%02d" % [hours, minutes, seconds]


func _ready() -> void:
	_setup_theme()
	_setup_scrollbar()
	_setup_timers()

	add_task_button.pressed.connect(_on_add_task_pressed)
	reset_all_button.pressed.connect(_on_reset_all_pressed)

	load_tasks()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_tasks()
		get_tree().quit()


func _setup_theme() -> void:
	var empty_style := StyleBoxEmpty.new()
	add_theme_stylebox_override("focus", empty_style)
	theme = Theme.new()
	theme.set_stylebox("focus", "Button", empty_style)
	theme.set_stylebox("focus", "LineEdit", empty_style)


func _setup_scrollbar() -> void:
	var scroll := task_list_container.get_parent() as ScrollContainer
	scroll.get_v_scroll_bar().modulate = SCROLLBAR_COLOR


func _setup_timers() -> void:
	timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)

	var autosave_timer := Timer.new()
	autosave_timer.wait_time = AUTOSAVE_INTERVAL
	autosave_timer.timeout.connect(save_tasks)
	add_child(autosave_timer)
	autosave_timer.start()


# --- Persistence ---

func save_tasks() -> void:
	var tasks_data := []
	for task in tasks:
		tasks_data.append({
			"name": task.name,
			"elapsed_time": task.elapsed_time,
		})

	var json_string := JSON.stringify(tasks_data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()


func load_tasks() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return

	var json_string := file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_string)
	if data is Array:
		for task_data in data:
			var task := Task.new(task_data["name"])
			task.elapsed_time = task_data["elapsed_time"]
			tasks.append(task)
			_add_task_ui(task)


# --- Task UI ---

func _add_task_ui(task: Task) -> void:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.set_meta("task", task)

	var spacer := Label.new()

	var delete_btn := Button.new()
	delete_btn.icon = ICON_DELETE
	delete_btn.pressed.connect(_on_delete_task.bind(task, grid))

	var name_edit := LineEdit.new()
	name_edit.text = task.name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(_on_task_renamed.bind(task))
	name_edit.focus_entered.connect(_on_name_focus_entered.bind(name_edit))
	name_edit.focus_exited.connect(_on_name_focus_exited.bind(name_edit))

	var play_btn := Button.new()
	play_btn.name = "PlayButton"
	play_btn.icon = ICON_PLAY
	play_btn.pressed.connect(_on_play_pause.bind(task, play_btn))
	name_edit.gui_input.connect(_on_name_input.bind(task, play_btn))

	var time_label := Label.new()
	time_label.name = "TimeLabel"
	time_label.text = Task.format_time(task.elapsed_time)
	time_label.mouse_filter = Control.MOUSE_FILTER_PASS
	time_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_play_pause(task, play_btn)
	)

	grid.add_child(spacer)
	grid.add_child(delete_btn)
	grid.add_child(name_edit)
	grid.add_child(play_btn)
	grid.add_child(time_label)

	task_list_container.add_child(grid)


# --- Event Handlers ---

func _on_add_task_pressed() -> void:
	var task := Task.new(DEFAULT_TASK_NAME)
	tasks.append(task)
	_add_task_ui(task)


func _on_reset_all_pressed() -> void:
	for task in tasks:
		task.elapsed_time = 0.0
		task.is_running = false

	if not timer.is_stopped():
		timer.stop()

	active_task = null
	_reset_title_label()

	for grid in task_list_container.get_children():
		if grid is GridContainer:
			var play_button := grid.get_node("PlayButton") as Button
			play_button.icon = ICON_PLAY

			var time_label := grid.get_node("TimeLabel") as Label
			time_label.add_theme_color_override("font_color", INACTIVE_COLOR)

	_update_time_displays()


func _on_play_pause(task: Task, button: Button) -> void:
	if active_task == task:
		active_task = null
		task.is_running = false
		button.icon = ICON_PLAY
		timer.stop()
		_reset_title_label()
		_set_all_time_labels_color(INACTIVE_COLOR)
	else:
		if active_task:
			active_task.is_running = false

		_reset_all_play_buttons()
		_set_all_time_labels_color(INACTIVE_COLOR)

		active_task = task
		task.is_running = true
		button.icon = ICON_PAUSE
		timer.start()

		title_label.text = "Hacking time!"
		title_label.add_theme_color_override("font_color", ACTIVE_COLOR)

		var active_grid := _find_grid_for_task(task)
		if active_grid:
			var time_label := active_grid.get_node("TimeLabel") as Label
			time_label.add_theme_color_override("font_color", ACTIVE_COLOR)


func _on_delete_task(task: Task, grid: GridContainer) -> void:
	tasks.erase(task)
	if task == active_task:
		active_task = null
		timer.stop()
		_reset_title_label()
	grid.queue_free()
	_update_total_time()


func _on_task_renamed(new_text: String, task: Task) -> void:
	task.name = new_text


func _on_name_focus_entered(line_edit: LineEdit) -> void:
	if line_edit.text == DEFAULT_TASK_NAME:
		line_edit.text = ""


func _on_name_focus_exited(line_edit: LineEdit) -> void:
	if line_edit.text == "":
		line_edit.text = DEFAULT_TASK_NAME


func _on_name_input(event: InputEvent, task: Task, play_btn: Button) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER):
			_on_play_pause(task, play_btn)


func _on_timer_timeout() -> void:
	if active_task:
		active_task.elapsed_time += 1.0
		_update_time_displays()


# --- UI Helpers ---

func _reset_title_label() -> void:
	title_label.text = "It's time to hack time!"
	title_label.remove_theme_color_override("font_color")
	title_label.remove_theme_stylebox_override("normal")


func _find_grid_for_task(task: Task) -> GridContainer:
	for grid in task_list_container.get_children():
		if grid is GridContainer and grid.get_meta("task") == task:
			return grid
	return null


func _reset_all_play_buttons() -> void:
	for grid in task_list_container.get_children():
		if grid is GridContainer:
			var play_button := grid.get_node("PlayButton") as Button
			play_button.icon = ICON_PLAY


func _set_all_time_labels_color(color: Color) -> void:
	for grid in task_list_container.get_children():
		if grid is GridContainer:
			var time_label := grid.get_node("TimeLabel") as Label
			time_label.add_theme_color_override("font_color", color)


func _update_time_displays() -> void:
	for grid in task_list_container.get_children():
		if grid is GridContainer:
			var task: Task = grid.get_meta("task")
			var time_label := grid.get_node("TimeLabel") as Label
			var play_button := grid.get_node("PlayButton") as Button

			time_label.text = Task.format_time(task.elapsed_time)
			play_button.icon = ICON_PAUSE if task == active_task else ICON_PLAY

	_update_total_time()


func _update_total_time() -> void:
	var total := 0.0
	for task in tasks:
		total += task.elapsed_time
	if total_time_label:
		total_time_label.text = Task.format_time(total)
