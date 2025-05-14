--- @since 25.2.7
--- @sync peek
--- NOTE: REMOVE :parent() :name() :is_hovered() :ext() after upgrade to v25.4.4
--- https://github.com/sxyazi/yazi/pull/2572

local M = {}

local DEFAULT_COMPONENT_IDS = { 4, 6 }
local function remove_suffix(str, suffix)
	if str:sub(-#suffix) == suffix then
		return str:sub(1, -#suffix - 1)
	else
		return str
	end
end

local function to_unique_set(t)
	local result = {}
	for _, v in ipairs(t) do
		if type(v) == "number" then
			result[v] = true
		end
	end
	return result
end

---shorten string
---@param max_width number max characters
---@param long_string string string
---@param suffix? string file extentions or any thing which will shows at the end when file is truncated
---@return { result: string, suffix: string, suffix_len: number }
function M:shorten(max_width, long_string, suffix)
	suffix = suffix or ""
	max_width = max_width or 0
	long_string = long_string or ""
	local _suffix = "…" .. suffix
	local _suffix_len = utf8.len(_suffix)
	local s_removed_suffix = remove_suffix(long_string, suffix)
	if utf8.len(long_string) <= max_width then
		return { result = long_string, suffix = "", suffix_len = 0 }
	end
	local cut_width = max_width - _suffix_len
	if cut_width < 0 then
		return { result = _suffix:sub(1, max_width), suffix = _suffix, suffix_len = _suffix_len }
	end
	local result = s_removed_suffix:sub(1, cut_width) .. _suffix
	return { result = result, suffix = _suffix, suffix_len = _suffix_len }
end

--- Function to truncate entity
---@class entity Entity created entity object. For example: `local entity = Entity:new(f)`
---@param max_width number max width of the area entity will be rendered. For example: `area.w`
function M:smart_truncate_entity(entity, max_width)
	local thisPlugin = self
	entity._components = entity._components or {}
	local resizable_entity_children_ids_set = to_unique_set(thisPlugin.resizable_entity_children_ids)
	if thisPlugin.resizable_entity_children_ids and #thisPlugin.resizable_entity_children_ids > 0 then
		-- Override Entity.render function for this entity
		entity.redraw = function(entity_self)
			-- length of resizable entity's component/children
			local total_length_resizable = 0
			-- length of unresizable entity's component/children
			local total_length_unresizable = 0
			local count_resizable_component_with_length_not_zero = 0

			if not entity_self._components then
				entity_self._components = {}
			end
			-- loop through all entity children
			for _, c in ipairs(entity_self._children) do
				local child_component = ui.Line((type(c[1]) == "string" and entity_self[c[1]] or c[1])(entity_self))
					:style(entity_self:style())
				if not entity_self._components[c.id] then
					entity_self._components[c.id] = {}
				end
				entity_self._components[c.id].length = child_component:width()
				-- add some metadata for this commponent/children
				if resizable_entity_children_ids_set[c.id] and entity_self._components[c.id].length > 0 then
					entity_self._components[c.id].max_length = 0
					total_length_resizable = total_length_resizable + entity_self._components[c.id].length
					entity_self._components[c.id].resizable = true
					count_resizable_component_with_length_not_zero = count_resizable_component_with_length_not_zero + 1
				else
					entity_self._components[c.id].resizable = false
					total_length_unresizable = total_length_unresizable + entity_self._components[c.id].length
					entity_self._components[c.id].max_length = entity_self._components[c.id].length
				end
			end

			local usable_space = max_width - total_length_unresizable
			local max_length_size_each_component = count_resizable_component_with_length_not_zero <= 1 and usable_space
				or (usable_space / count_resizable_component_with_length_not_zero)
			local last_component_id

			-- Convert the table to an array of key-value pairs
			local components_array = {}
			for id, metadata in pairs(entity_self._components) do
				table.insert(components_array, { id = id, metadata = metadata })
			end
			-- sort by length, then calculate max_length for each resizable component/children
			table.sort(components_array, function(a, b)
				return a.metadata.length < b.metadata.length
			end)
			local avg_usable_space = -1
			-- calculate max_length for each resizable component/children
			for _, c in ipairs(components_array) do
				if c.metadata.resizable then
					if c.metadata.length <= max_length_size_each_component then
						entity_self._components[c.id].max_length = c.metadata.length
						count_resizable_component_with_length_not_zero = count_resizable_component_with_length_not_zero
							- 1
					else
						if avg_usable_space == -1 then
							avg_usable_space = usable_space / count_resizable_component_with_length_not_zero
						end
						entity_self._components[c.id].max_length = math.floor(avg_usable_space)
					end

					usable_space = usable_space - entity_self._components[c.id].max_length
					last_component_id = c.id
				end
			end
			-- add left over space to last/longest length resizable component
			-- NOTE: DE QUY longest -> shortest -> cong dan dan usable_space_left_over.
			-- Check if c.length - max_length <= usable_space_left_over_partial -> max_length = c.length && usable_space = usable_space - (c.length - max_length) -> De quy tiep
			-- else max_length = max_length + usable_space_left_over_partial
			if usable_space > 0 and last_component_id then
				entity_self._components[last_component_id].max_length = entity_self._components[last_component_id].max_length
					+ usable_space
			end

			local lines = {}
			for _, c in ipairs(entity_self._children) do
				if
					entity_self._components[c.id]
					and entity_self._components[c.id].resizable
					and thisPlugin.children_callbacks[c.id]
				then
					lines[#lines + 1] = thisPlugin.children_callbacks[c.id](entity_self)
				else
					lines[#lines + 1] = (type(c[1]) == "string" and entity_self[c[1]] or c[1])(entity_self)
				end
			end
			return ui.Line(lines):style(entity_self:style())
		end
	end
end

function M:render_parent_entities()
	local thisPlugin = self
	function Parent:redraw()
		if not self._folder then
			return {}
		end

		local items = {}
		local parent_tab_window_w = self._area.w
		for _, f in ipairs(self._folder.window) do
			local entity = Entity:new(f)
			thisPlugin:smart_truncate_entity(entity, parent_tab_window_w)
			items[#items + 1] = ui.Line({ entity:redraw() }):style(entity:style())
		end

		return {
			ui.List(items):area(self._area),
		}
	end
end

function M:render_current_entities()
	local thisPlugin = self
	function Current:redraw()
		local files = self._folder.window
		if #files == 0 then
			return self:empty()
		end

		local current_tab_window_w = self._area.w

		local entities, linemodes = {}, {}
		for _, f in ipairs(files) do
			local entity = Entity:new(f)
			local linemode_rendered = Linemode:new(f):redraw()
			local linemode_char_length = linemode_rendered:align(ui.Text.RIGHT):width()
			-- smart truncate
			thisPlugin:smart_truncate_entity(entity, current_tab_window_w - linemode_char_length)
			entities[#entities + 1] = ui.Line({ entity:redraw() }):style(entity:style())
			linemodes[#linemodes + 1] = linemode_rendered
		end

		return {
			ui.List(entities):area(self._area),
			ui.Text(linemodes):area(self._area):align(ui.Text.RIGHT),
		}
	end
end

function M:peek(job)
	local folder = cx.active.preview.folder
	if not folder or folder.cwd ~= job.file.url then
		return
	end

	local bound = math.max(0, #folder.files - job.area.h)
	if job.skip > bound then
		return ya.emit("peek", { bound, only_if = job.file.url, upper_bound = true })
	end

	if #folder.files == 0 then
		local done, err = folder.stage()
		local s = not done and "Loading..." or not err and "No items" or string.format("Error: %s", err)
		return ya.preview_widget(job, ui.Line(s):area(job.area):align(ui.Line.CENTER))
	end

	local entities = {}
	for _, f in ipairs(folder.window) do
		local entity = Entity:new(f)
		-- smart truncate
		self:smart_truncate_entity(entity, job.area.w)
		entities[#entities + 1] = ui.Line({ entity:redraw() }):style(entity:style())
	end

	ya.preview_widget(job, {
		ui.List(entities):area(job.area),
		table.unpack(Marker:new(job.area, folder):redraw()),
	})
end

function M:seek(job)
	local folder = cx.active.preview.folder
	if folder and folder.cwd == job.file.url then
		local step = math.floor(job.units * job.area.h / 10)
		local bound = math.max(0, #folder.files - job.area.h)
		ya.emit("peek", {
			ya.clamp(0, cx.active.preview.skip + step, bound),
			only_if = job.file.url,
		})
	end
end

function M:render_entities()
	if self.render_parent then
		self:render_parent_entities()
	end
	if self.render_current then
		self:render_current_entities()
	end
end

function Entity:get_component_max_length(component_id_or_fn_name)
	if type(component_id_or_fn_name) == "string" then
		component_id_or_fn_name = Entity:get_component_id_by_fn_name(component_id_or_fn_name)
	end
	return self._components
		and self._components[component_id_or_fn_name]
		and self._components[component_id_or_fn_name].max_length
end

function Entity:get_component_id_by_fn_name(component_fn_name)
	for _, c in ipairs(self._children) do
		if type(c[1]) == "string" and c[1] == component_fn_name then
			return c.id
		end
	end
end

function M:init_default_callbacks()
	local thisPlugin = self
	thisPlugin:children_add("highlights", function(entity_self)
		-- override these resizeable components/children render function then re-render the whole entity with truncated/shortened value
		local suffix = ""
		local shortened_name
		local name = entity_self._file.name:gsub("\r", "?", 1)

		---------------------------
		-- get max_length if highlight is resizable
		local max_length = entity_self:get_component_max_length("highlights") or 0
		if entity_self._file.cha.is_dir then
			shortened_name = M:shorten(max_length, name, "")
		else
			local ext = (
				type(entity_self._file.url.ext) == "function" and entity_self._file.url:ext()
				or entity_self._file.url.ext
			) or ""

			suffix = (not ext or ext == "") and "" or ("." .. ext)
			shortened_name = M:shorten(max_length, name, suffix)
		end

		local highlights = entity_self._file:highlights()
		if not highlights or #highlights == 0 then
			return shortened_name.result
		end

		-- This will run when use find command
		---@see https://yazi-rs.github.io/docs/configuration/keymap#manager.find
		local highlight_spans, last = {}, 0

		for _, h in ipairs(highlights) do
			if h[2] > utf8.len(shortened_name.result) - shortened_name.suffix_len then
				h[2] = utf8.len(shortened_name.result) - shortened_name.suffix_len
				if h[2] <= 0 then
					-- escape when highlight position is hidden
					goto break_highlight_loop
				end
			end
			if h[1] > utf8.len(shortened_name.result) - shortened_name.suffix_len then
				-- escape when highlight position is hidden
				goto break_highlight_loop
			end
			-- find command result not matched part
			-- from last to h1
			if h[1] > last then
				highlight_spans[#highlight_spans + 1] = ui.Span(shortened_name.result:sub(last + 1, h[1]))
			end
			-- find command result matched part
			-- from h1 to h2
			highlight_spans[#highlight_spans + 1] = ui.Span(shortened_name.result:sub(h[1] + 1, h[2]))
				:style((th.mgr or THEME.manager).find_keyword)
			last = h[2]
		end

		::break_highlight_loop::
		-- the rest not matched
		-- from h2 to the end of file/folder name
		if last < utf8.len(shortened_name.result) then
			highlight_spans[#highlight_spans + 1] = ui.Span(shortened_name.result:sub(last + 1))
		end

		return ui.Line(highlight_spans)
	end)

	thisPlugin:children_add("symlink", function(entity_self)
		-- override these resizeable components/children render function then re-render the whole entity with truncated/shortened value

		-- override symlink Entity:symlink function
		if not (rt and rt.mgr or MANAGER).show_symlink then
			return ""
		end

		local link_to = entity_self._file.link_to
		if not link_to then
			return ""
		end

		local prefix = " -> "
		local max_length = entity_self:get_component_max_length("symlink") or 0

		local to_extension = type(link_to.ext) == "function" and link_to:ext() or link_to.ext
		local suffix = (not to_extension or to_extension == "") and "" or ("." .. to_extension)
		local shortened = M:shorten(max_length, prefix .. tostring(link_to), suffix)

		return ui.Span(shortened.result):style((th.mgr or THEME.manager).symlink_target)
	end)
end

function M:setup(opts)
	self.resizable_entity_children_ids = {}
	if type(opts) == "table" then
		self.render_parent = opts.render_parent ~= nil and opts.render_parent
		self.render_current = opts.render_current ~= nil and opts.render_current
		if type(opts.resizable_entity_children_ids) == "table" then
			self.resizable_entity_children_ids = opts.resizable_entity_children_ids
		end
	end
	self.children_callbacks = {}
	self:init_default_callbacks()
	self:render_entities()
end

--- Add a callback function for a component
---@param children string|number component/children id or children function name. For example: `"highlights"` or `4` or `"symlink"` or `6`
---@param callback function callback function when component/children is resized
function M:children_add(children, callback)
	if type(children) == "string" then
		children = Entity:get_component_id_by_fn_name(children)
		if not children then
			return
		end
	end
	self.resizable_entity_children_ids[#self.resizable_entity_children_ids + 1] = children
	self.children_callbacks[children] = callback
	self:render_entities()
end

function M:children_remove(children_id)
	for idx, id in ipairs(self.resizable_entity_children_ids) do
		if id == children_id then
			table.remove(self.resizable_entity_children_ids, idx)
			table.remove(self.children_callbacks, children_id)
			self:render_entities()
			return
		end
	end
end

return M
