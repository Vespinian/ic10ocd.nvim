local M = {}

local find_in_labels = function(labels, label)
	for _, v in pairs(labels) do
		-- print('"' .. label .. '" "' .. v.name .. '"')
		if label == v.name then
			return v.re
		end
	end
	return nil
end

M.minify_current_buf = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local og_ic10_file = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local ic10_file = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- find Labels
	local labels = {}
	local char_code = "a"
	for _, line in ipairs(ic10_file) do
		if string.sub(line, -1) == ":" then
			local label = {}
			label["name"] = string.sub(line, 1, -2)
			label["re"] = "ic10ocd_minifier_label_" .. char_code
			char_code = string.char(char_code:byte() + 1)
			table.insert(labels, label)
		end
	end
	-- print(vim.inspect(labels))

	local active_sem_hl = vim.lsp.semantic_tokens["__STHighlighter"]["active"]
	local lsp_highlights = active_sem_hl[bufnr]["client_state"][1]["current_result"]["highlights"]
	-- print(vim.inspect(lsp_highlights))
	if lsp_highlights ~= nil then
		for _, sem_token in pairs(lsp_highlights) do
			-- print(vim.inspect(sem_token))
			local label = string.sub(ic10_file[sem_token.line + 1], sem_token.start_col + 1, sem_token.end_col)
			-- print(label)
			local before = string.sub(ic10_file[sem_token.line + 1], 1, sem_token.start_col)
			local after = string.sub(ic10_file[sem_token.line + 1], sem_token.end_col + 1, -1)
			ic10_file[sem_token.line + 1] = before .. find_in_labels(labels, label) .. after
		end
	end
	-- print(vim.inspect(ic10_file))

	-- check for defines and aliases
	for _, line in ipairs(og_ic10_file) do
		local segments = {}
		for w in line:gmatch("%S+") do
			table.insert(segments, w)
		end
		if segments[1] == "define" or segments[1] == "alias" then
			local identifier = segments[2]
			local replacement = segments[3]
			for idx, modline in ipairs(ic10_file) do
				local modsegments = {}
				for w in modline:gmatch("%S+") do
					table.insert(modsegments, w)
				end
				for seg_idx, seg in ipairs(modsegments) do
					if seg == identifier then
						modsegments[seg_idx] = replacement
					end
				end
				ic10_file[idx] = table.concat(modsegments, " ")
			end
		end
	end
	-- prune alias and define lines
	for idx, line in ipairs(ic10_file) do
		local segments = {}
		for w in line:gmatch("%S+") do
			table.insert(segments, w)
		end
		if segments[1] == "define" or segments[1] == "alias" then
			ic10_file[idx] = nil
		end
	end
	-- reindex
	local clean_file = {}
	for _, line in pairs(ic10_file) do
		table.insert(clean_file, line)
	end
	ic10_file = clean_file

	-- check for hashes
	for line_idx, line in ipairs(ic10_file) do
		line = string.gsub(line, '%b""', function(quoted)
			return quoted:gsub(" ", "xXic10ocdspacesXx")
		end)
		-- print(line)
		local segments = {}
		for w in line:gmatch("%S+") do
			table.insert(segments, w)
		end
		for idx, segment in ipairs(segments) do
			segment = string.gsub(segment, "xXic10ocdspacesXx", " ")
			if string.find(segment, "HASH") then
				local tstart, tend = string.find(segment, '"([^"]+)')
				segment = require("crc32").crc_calc(nil, string.sub(segment, tstart + 1, tend))
			end
			segments[idx] = segment
		end
		ic10_file[line_idx] = table.concat(segments, " ")
	end
	-- reindex
	clean_file = {}
	for _, line in pairs(ic10_file) do
		table.insert(clean_file, line)
	end
	ic10_file = clean_file

	-- strip comments
	local lines_to_remove = {}
	for idx, line in ipairs(ic10_file) do
		local s, e
		s, e = string.find(line, "%S")
		if s ~= nil then
			local first_char = line:sub(s, e)
			if first_char == "#" then
				table.insert(lines_to_remove, idx)
			else
				s, e = string.find(line, "#")
				if s ~= nil then
					ic10_file[idx] = string.sub(line, 1, s - 1)
				end
			end
		end
	end
	for _, v in ipairs(lines_to_remove) do
		ic10_file[v] = nil
	end
	-- reindex
	clean_file = {}
	for _, line in pairs(ic10_file) do
		table.insert(clean_file, line)
	end
	ic10_file = clean_file

	-- BATCH_MODE for lb* instructions
	-- 0u8 => "Average",
	-- 1u8 => "Sum",
	-- 2u8 => "Minimum",
	-- 3u8 => "Maximum",
	for idx, line in ipairs(ic10_file) do
		local segments = {}
		for w in line:gmatch("%S+") do
			table.insert(segments, w)
		end
		-- print(vim.inspect(segments))
		if segments[1] and string.find(segments[1], "lb") ~= nil then
			print(vim.inspect(segments[#segments]))
			segments[#segments] = string.gsub(segments[#segments], "Average", "0")
			segments[#segments] = string.gsub(segments[#segments], "Sum", "1")
			segments[#segments] = string.gsub(segments[#segments], "Minimum", "2")
			segments[#segments] = string.gsub(segments[#segments], "Maximum", "3")
			ic10_file[idx] = table.concat(segments, " ")
		end
	end

	-- REAGEAT_MODE for lr device REAGENT_MODE int
	-- 0u8 => "Contents",
	-- 1u8 => "Required",
	-- 2u8 => "Recipe",
	-- 3u8 => "TotalContents",
	for idx, line in ipairs(ic10_file) do
		local segments = {}
		for w in line:gmatch("%S+") do
			table.insert(segments, w)
		end
		-- print(vim.inspect(segments))
		if segments[1] == "lr" then
			print(vim.inspect(segments[4]))
			segments[4] = string.gsub(segments[4], "TotalContents", "3")
			segments[4] = string.gsub(segments[4], "Contents", "0")
			segments[4] = string.gsub(segments[4], "Required", "1")
			segments[4] = string.gsub(segments[4], "Recipe", "2")
			ic10_file[idx] = table.concat(segments, " ")
		end
	end

	-- label switching to hard numbers
	-- WARNING:: This has to be the last step that can change line count since jump will not be valid anymore if the file line count changes again
	for _, label in pairs(labels) do
		-- find label index
		local label_idx = nil
		for idx, line in ipairs(ic10_file) do
			if line == label.re .. ":" then
				label_idx = idx
				break
			end
		end
		-- print(label_idx)
		if label_idx ~= nil then
			for idx, line in ipairs(ic10_file) do
				ic10_file[idx] = string.gsub(line, label.re, label_idx - 1)
			end
			ic10_file[label_idx] = nil
		end

		-- clean table indices
		clean_file = {}
		for _, line in pairs(ic10_file) do
			table.insert(clean_file, line)
		end
		ic10_file = clean_file
	end

	return ic10_file
end

return M
