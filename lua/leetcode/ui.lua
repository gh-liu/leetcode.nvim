local uv = vim.loop
local M = {
	client = nil,
}

local function open_floating_win(bufnr)
	local screen_w = vim.opt.columns:get()
	local screen_h = vim.opt.lines:get() - vim.opt.cmdheight:get()
	local window_w = screen_w * 0.8
	local window_h = screen_h * 0.8
	local window_w_int = math.floor(window_w)
	local window_h_int = math.floor(window_h)
	local center_x = (screen_w - window_w) / 2
	local center_y = ((vim.opt.lines:get() - window_h) / 2) - vim.opt.cmdheight:get()

	local winnr = vim.api.nvim_open_win(bufnr, true, {
		border = "single",
		relative = "editor",
		row = center_y,
		col = center_x,
		width = window_w_int,
		height = window_h_int,
	})

	-- vim.api.nvim_win_set_option(winnr, "number", true)
	-- vim.api.nvim_win_set_option(winnr, "relativenumber", true)
	return winnr
end

M.list = function()
	local problemset = M.client:problemset()
	if not problemset then
		return
	end

	local info = M.client:session()
	if not info then
		return
	end

	local status = M.client:status(info.slug)
	if not status then
		return
	end

	local lines = {}
	table.insert(lines, string.format("user: %s(%s)", info.realname, info.name))
	for i, v in ipairs(problemset) do
		table.insert(lines, string.format("[%d]", v.id) .. " " .. v.title_cn)
	end

	vim.cmd.new()
	local winnr = vim.api.nvim_get_current_win()

	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, #lines, false, lines)
	vim.api.nvim_buf_set_option(bufnr, "bt", "nofile")
	vim.api.nvim_buf_set_option(bufnr, "ft", "leetcode-list")
	vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

	vim.keymap.set("n", "p", function()
		local lnum = vim.fn.line(".")
		if lnum > 1 then
			local slug = problemset[lnum - 1].slug
			M.preview(slug)
		end
	end, { silent = true, buffer = bufnr })

	vim.keymap.set("n", "o", function()
		local lnum = vim.fn.line(".")
		if lnum > 1 then
			local slug = problemset[lnum - 1].slug
			M.code(slug)
		end
	end, { silent = true, buffer = bufnr })

	vim.api.nvim_win_set_option(winnr, "number", false)
	vim.api.nvim_win_set_option(winnr, "relativenumber", false)
	vim.api.nvim_win_set_buf(winnr, bufnr)
end

M.preview = function(slug)
	local bufnr = vim.api.nvim_create_buf(false, true)
	-- vim.api.nvim_buf_set_name(bufnr, "lc-detail")
	-- vim.api.nvim_buf_set_option(bufnr, "bt", "")
	vim.api.nvim_buf_set_option(bufnr, "ft", "markdown")
	vim.api.nvim_buf_set_option(bufnr, "bt", "nowrite")
	vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")

	vim.keymap.set("n", "q", function()
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end, { silent = true, buffer = bufnr })

	local winnr = open_floating_win(bufnr)

	local lines = {}
	local detail = M.client:data(slug)
	local content = detail.content_cn
	local stdin = uv.new_pipe()
	local stdout = uv.new_pipe()
	local stderr = uv.new_pipe()
	-- https://github.com/suntong/html2md
	if vim.fn.executable("html2md") then
		local handle, pid = uv.spawn("html2md", {
			args = { "-i" },
			stdio = { stdin, stdout, stderr },
		}, function(code, signal) -- on exit
		end)
		uv.read_start(stdout, function(err, data)
			assert(not err, err)
			if data then
				for s in data:gmatch("[^\r\n]+") do
					table.insert(lines, s)
				end

				vim.schedule(function()
					vim.api.nvim_buf_set_lines(bufnr, 0, #lines, false, lines)
					vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
				end)
			else
				-- vim.print("no data")
			end
		end)

		uv.write(stdin, content)
		uv.shutdown(stdin, function()
			-- uv.close(handle, function() end)
		end)
	end
	vim.api.nvim_set_current_win(winnr)
end

local ft = {
	golang = "go",
}

M.code = function(slug)
	local detail = M.client:data(slug)
	local lang = detail.lang
	local code = detail.code_definition
	local lines = {}
	for s in code:gmatch("[^\r\n]+") do
		table.insert(lines, s)
	end

	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(bufnr, "bt", "")
	vim.api.nvim_buf_set_option(bufnr, "ft", ft[lang] or lang)

	vim.api.nvim_buf_set_lines(bufnr, 0, #lines, false, lines)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

	vim.cmd.vnew()
	local winnr = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(winnr, bufnr)
	-- vim.api.nvim_set_current_win(winnr)
end

return M
