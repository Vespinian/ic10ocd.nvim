local M = {
	---@class IC10info
	---@field name string
	---@field refid string
	---@field holder_name string
	---@field holder_refid string
	---@field compileErrorType string
	---@field compileErrorLineNumber string
	---@field on boolean
	selected_ic10 = nil,
	cached_list = nil,
}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- probably need to move this in mini.statusline conf?
local update_status_bar = function()
	local mini = require("mini.statusline")
	print(vim.inspect(mini.config.content.active))
	local mini_statusline = function()
		local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
		local git = MiniStatusline.section_git({ trunc_width = 40 })
		local diff = MiniStatusline.section_diff({ trunc_width = 75 })
		local diagnostics = MiniStatusline.section_diagnostics({ trunc_width = 75 })
		local lsp = MiniStatusline.section_lsp({ trunc_width = 75 })
		local filename = MiniStatusline.section_filename({ trunc_width = 140 })
		local fileinfo = MiniStatusline.section_fileinfo({ trunc_width = 120 })
		local location = MiniStatusline.section_location({ trunc_width = 75 })
		local search = MiniStatusline.section_searchcount({ trunc_width = 75 })

		local selectedIC10 = ""
		if M.selected_ic10 ~= nil then
			selectedIC10 = "IC10: " .. M.selected_ic10.name .. " in " .. M.selected_ic10.holder_name
		end

		return MiniStatusline.combine_groups({
			{ hl = mode_hl, strings = { mode } },
			{ hl = "MiniStatuslineDevinfo", strings = { git, diff, diagnostics, lsp } },
			"%<", -- Mark general truncate point
			{ strings = { selectedIC10 } },
			{ hl = "MiniStatuslineFilename", strings = { filename } },
			"%=", -- End left alignment
			{ hl = "MiniStatuslineFileinfo", strings = { fileinfo } },
			{ hl = mode_hl, strings = { search, location } },
		})
	end
	mini.config.content.active = mini_statusline
end

local function get_chip_info_from_game(refid)
	local curl = require("plenary.curl")
	local res = curl.get("localhost:8000/chip-info/" .. refid, {
		accept = "application/json",
		timeout = 1000,
	})
	return vim.fn.json_decode(res.body)
end

local function get_code_from_game(refid)
	local curl = require("plenary.curl")
	local res = curl.get("localhost:8000/chip-code/" .. refid, {
		accept = "application/json",
		timeout = 1000,
	})
	return vim.fn.json_decode(res.body).code
end

local function post_code_to_game(refid, code)
	local curl = require("plenary.curl")
	local res = curl.post("localhost:8000/chip-code/" .. refid, {
		headers = { content_type = "application/json" },
		body = vim.fn.json_encode({ code = table.concat(code, "\n") }),
		timeout = 1000,
	})
	return res.status
end

local function get_chip_dump(refid)
	local curl = require("plenary.curl")
	local res = curl.get("localhost:8000/chip-dump/" .. refid, {
		accept = "application/json",
		timeout = 1000,
	})
	return vim.fn.json_decode(res.body)
end

local get_connected_devices = function(refid)
	local curl = require("plenary.curl")
	local res = curl.get("localhost:8000/chip-network-device-list/" .. refid, {
		accept = "application/json",
		timeout = 1000,
	})
	return vim.fn.json_decode(res.body)
end

local get_ic10_list = function()
	local curl = require("plenary.curl")
	local result, res = pcall(curl.get, "localhost:8000/list-chips", {
		accept = "application/json",
		timeout = 1000,
	})
	if result == true then
		return vim.fn.json_decode(res.body)
	else
		return nil
	end
end

local get_ic10_code = function(refid)
	local code = get_code_from_game(refid)
	-- print(code)
	local lines = {}
	for line in string.gmatch(code, "[^\n]+") do
		table.insert(lines, line)
	end
	return lines
end

M.get_ic10_code_to_buffer = function()
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local lines = get_ic10_code(M.selected_ic10.refid)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

M.get_ic10_code_to_file = function()
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local lines = get_ic10_code(M.selected_ic10.refid)
	vim.fn.writefile(lines, M.selected_ic10.holder_name .. ".ic10")
end

M.get_all_ic10_code_to_files = function()
	local ic10s = get_ic10_list()
	if ic10s == nil then
		return
	end
	for _, ic10 in pairs(ic10s) do
		local lines = get_ic10_code(ic10.refid)
		vim.fn.writefile(lines, ic10.holder_name .. ".ic10")
	end
end

M.post_ic10_code = function()
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local code = vim.api.nvim_buf_get_lines(0, 0, -1, true)
	print(post_code_to_game(M.selected_ic10.refid, code))
end

M.print_selected = function()
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	M.selected_ic10 = get_chip_info_from_game(M.selected_ic10.refid)
	local chip = M.selected_ic10
	local booltostring = { [true] = "true", [false] = "false" }
	if chip ~= nil then
		print(
			"Id: "
				.. chip.refid
				.. " Name: "
				.. chip.name
				.. " Holder: "
				.. chip.holder_name
				.. " Holder Id: "
				.. chip.holder_refid
				.. " Error: "
				.. chip.compileErrorType
				.. " Error Line: "
				.. chip.compileErrorLineNumber
				.. " On: "
				.. booltostring[chip.on]
		)
	else
		print("No chip seleted")
	end
end

M.selected_toggle_onoff = function()
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local curl = require("plenary.curl")
	local res = curl.post("localhost:8000/toggle-chip-power/" .. M.selected_ic10.refid, {
		body = "",
		timeout = 1000,
	})
	print(res.status)
end

M.pick_connected_device = function(opts, insert_word_in_default_text)
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local default_text = ""
	if insert_word_in_default_text then
		default_text = vim.fn.expand("<cword>")
	end
	opts = opts or {}
	pickers
		.new(opts, {
			default_text = default_text,
			prompt_title = "IC10 connected devices found",
			finder = finders.new_table({
				results = get_connected_devices(M.selected_ic10.refid),
				entry_maker = function(entry)
					if entry.uplink ~= "" then
						return {
							value = string.format("$%X", tonumber(entry.refid)),
							display = string.format("$%X", tonumber(entry.refid))
								.. ': From Uplink "'
								.. entry.uplink
								.. '" | '
								.. entry.name,
							ordinal = string.format("$%X", tonumber(entry.refid))
								.. ": From Uplink "
								.. entry.uplink
								.. " | "
								.. entry.name,
						}
					else
						return {
							value = string.format("$%X", tonumber(entry.refid)),
							display = string.format("$%X", tonumber(entry.refid)) .. ": " .. entry.name,
							ordinal = string.format("$%X", tonumber(entry.refid)) .. ": " .. entry.name,
						}
					end
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					-- M.selected_ic10 = selection.index
					-- print(vim.inspect(selection))
					vim.fn.setreg("+", selection.value)
					vim.api.nvim_paste(selection.value, false, -1)
				end)
				return true
			end,
		})
		:find()
end

M.pick_ic10 = function(opts)
	opts = opts or {}
	pickers
		.new(opts, {
			prompt_title = "IC10 chips found",
			finder = finders.new_table({
				results = get_ic10_list(),
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.name .. " in " .. entry.holder_name,
						ordinal = entry.holder_name,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					M.selected_ic10 = selection.value
					update_status_bar()
					-- print(vim.inspect(selection.value))
				end)
				return true
			end,
		})
		:find()
end

M.post_json_to_chip_mem = function()
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local json_buf = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	-- print(vim.inspect(json_buf))
	local json_decoded = vim.fn.json_decode(json_buf)
	-- print(vim.inspect(json_decoded))
	local curl = require("plenary.curl")
	local res = curl.post("localhost:8000/chip-mem-slices/" .. M.selected_ic10.refid, {
		headers = { content_type = "application/json" },
		body = vim.fn.json_encode(json_decoded),
		timeout = 1000,
	})
	-- return res.status
	print(vim.inspect(res.status))
end

M.chip_dump_to_file = function()
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local json_dump = get_chip_dump(M.selected_ic10.refid)
	print(vim.inspect(json_dump))
end

M.browse_chip_dump = function(opts)
	opts = opts or {}
	if M.selected_ic10 == nil then
		print("No selected chip")
		return
	end
	local json_dump = get_chip_dump(M.selected_ic10.refid)
	-- print(vim.inspect(json_dump))
	local dump_table = {}
	table.insert(dump_table, "Line number: " .. json_dump.lineNumber)
	for idx, reg in ipairs(json_dump.registers) do
		local regname = "r" .. (idx - 1)
		if idx == 17 then
			regname = regname .. "|sp"
		elseif idx == 18 then
			regname = regname .. "|ra"
		end
		table.insert(dump_table, regname .. ": " .. reg)
	end
	for idx, stack in ipairs(json_dump.stack) do
		table.insert(dump_table, "s" .. (idx - 1) .. ": " .. stack)
	end
	-- print(vim.inspect(dump_table))
	pickers
		.new(opts, {
			prompt_title = "IC10 Dump",
			finder = finders.new_table({
				results = dump_table,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
				end)
				return true
			end,
		})
		:find()
end

M.find_hash = function(opts, insert_default_text)
	local default_text = nil
	if insert_default_text then
		default_text = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."))[1]
	end
	opts = opts or {}
	pickers
		.new(opts, {
			default_text = default_text,
			prompt_title = "Prefab Hashes",
			finder = finders.new_table({
				results = require("stationpedia").hash_table,
				entry_maker = function(entry)
					local hex_entry = string.format("%08x", tonumber(entry.hash, 10))
					if hex_entry:len() > 8 then
						hex_entry = hex_entry.sub(hex_entry, 9)
					end
					return {
						value = entry,
						display = string.format("%d ($%s) : ", tonumber(entry.hash, 10), hex_entry) .. entry.name,
						ordinal = string.format("%d ($%s) : ", tonumber(entry.hash, 10), hex_entry) .. entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection == nil then
						return
					end
					-- print(vim.inspect(selection.value))
					vim.fn.setreg("+", selection.value.name)
					vim.api.nvim_paste(selection.value.name, false, -1)
				end)
				return true
			end,
		})
		:find()
end

M.clear = function()
	M.selected_ic10 = nil
	M.cached_list = nil
	vim.api.nvim_del_augroup_by_name("ic10ocd")
end

M.calc_crc = function(fmt)
	local word_to_crc = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."))[1]
	-- local word_to_crc = vim.fn.expand("<cword>")
	print(vim.inspect(word_to_crc))
	if word_to_crc == nil then
		return
	end

	local text_num = require("crc32").crc_calc(fmt, word_to_crc)
	-- print(string.format("%d", text_num))
	vim.fn.setreg("+", text_num)
	vim.api.nvim_feedkeys("p", "v", false)
end

local get_buf_filename = function()
	local path = {}
	for str in string.gmatch(vim.api.nvim_buf_get_name(0), "([^/]+)") do
		table.insert(path, str)
	end
	local full_filename = path[#path]
	return full_filename:match("(.*)%.")
end

local find_chip_associated_with_filename = function()
	if M.cached_list == nil then
		local _, ic10s = pcall(get_ic10_list)
		if ic10s == nil then
			return nil
		end
		M.cached_list = ic10s
	end
	vim.bo.commentstring = "# %s"
	local filename = get_buf_filename()
	if filename == nil then
		return false
	end
	-- check ic names
	for _, ic10 in pairs(M.cached_list) do
		if ic10.name == filename then
			-- print("found ic10 by name " .. ic10.name .. " " .. ic10.refid)
			M.selected_ic10 = ic10
			M.print_selected()
			return true
		end
	end
	-- check holder_name
	for _, ic10 in pairs(M.cached_list) do
		if ic10.holder_name == filename then
			-- print("found ic10 by holder_name " .. ic10.holder_name .. " " .. ic10.refid)
			M.selected_ic10 = ic10
			M.print_selected()
			return true
		end
	end
end

M.attach_aucommands = function()
	local ok = find_chip_associated_with_filename()
	if ok == nil then
		return
	else
		vim.api.nvim_create_autocmd("BufEnter", {
			group = vim.api.nvim_create_augroup("ic10ocd", {}),
			pattern = "*.ic10",
			callback = function()
				if M.cached_list == nil then
					local _, ic10s = pcall(get_ic10_list)
					if ic10s == nil then
						return
					end
					M.cached_list = ic10s
				end
				vim.bo.commentstring = "# %s"
				local path = {}
				for str in string.gmatch(vim.api.nvim_buf_get_name(0), "([^/]+)") do
					table.insert(path, str)
				end
				local full_filename = path[#path]
				local filename = full_filename:match("(.*)%.ic10")
				if filename == nil then
					return
				end
				-- check ic names
				for _, ic10 in pairs(M.cached_list) do
					if ic10.name == filename then
						-- print("found ic10 by name " .. ic10.name .. " " .. ic10.refid)
						M.selected_ic10 = ic10
						M.print_selected()
						return
					end
				end
				-- check holder_name
				for _, ic10 in pairs(M.cached_list) do
					if ic10.holder_name == filename then
						-- print("found ic10 by holder_name " .. ic10.holder_name .. " " .. ic10.refid)
						M.selected_ic10 = ic10
						M.print_selected()
						return
					end
				end
			end,
		})
	end
end

M.minify = function()
	local minified_code = require("ic10mini").minify_current_buf()
	vim.fn.writefile(minified_code, get_buf_filename() .. ".mini.ic10")
end

local wrap = function(func, ...)
	local args = { ... }
	return function()
		func(unpack(args))
	end
end
M.setup = function()
	-- normal mode
	vim.keymap.set("n", "<leader>ii", M.get_ic10_code_to_buffer, { desc = "[I]mport IC10 Code to buffer" })
	vim.keymap.set("n", "<leader>iwf", M.get_ic10_code_to_file, { desc = "[W]rite IC10 Code to new [F]ile" })
	vim.keymap.set("n", "<leader>iwa", M.get_all_ic10_code_to_files, { desc = "[W]rite [A]ll IC10 Codes to new files" })
	vim.keymap.set("n", "<leader>ie", M.post_ic10_code, { desc = "[E]xport IC10 Code" })
	vim.keymap.set("n", "<leader>ip", M.print_selected, { desc = "[P]rint Selected IC10" })
	vim.keymap.set("n", "<leader>io", M.selected_toggle_onoff, { desc = "Toggle Selected Chip [O]n/Off" })
	vim.keymap.set("n", "<leader>ic", M.clear, { desc = "[C]lear Plugin" })
	vim.keymap.set("n", "<leader>im", M.minify, { desc = "[M]inify" })
	vim.keymap.set("n", "<leader>ish", wrap(M.find_hash, {}, false), { desc = "[S]earch [H]ash" })
	vim.keymap.set("n", "<leader>isi", M.pick_ic10, { desc = "[S]earch [I]C10 Chip" })
	vim.keymap.set(
		"n",
		"<leader>isn",
		wrap(M.pick_connected_device, {}, false),
		{ desc = "[S]earch [N]etwork Device for Refids" }
	)
	vim.keymap.set(
		"n",
		"<leader>isr",
		wrap(M.pick_connected_device, {}, true),
		{ desc = "[S]earch [R]efid in Network Devices" }
	)
	vim.keymap.set("n", "<leader>ia", M.attach_aucommands, { desc = "[A]ttach Autocmds" })
	vim.keymap.set("n", "<leader>id", M.browse_chip_dump, { desc = "Browse Chip [d]ump" })
	vim.keymap.set("n", "<leader>iD", M.chip_dump_to_file, { desc = "Chip [D]ump to file" })
	vim.keymap.set("n", "<leader>ij", M.post_json_to_chip_mem, { desc = "Post [J]SON to Chip Mem" })
	-- visual mode
	vim.keymap.set("v", "<leader>ix", wrap(M.calc_crc, "%x"), { desc = "Calculate CRC as he[X]" })
	vim.keymap.set("v", "<leader>ii", wrap(M.calc_crc, "%d"), { desc = "Calculate CRC as [I]nt" })
	vim.keymap.set("v", "<leader>is", wrap(M.find_hash, {}, true), { desc = "[S]earch Hashes" })
end

M.setup()

return M
