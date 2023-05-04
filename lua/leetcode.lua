local M = {}

local ui = require("leetcode.ui")

function M.setup(opts)
	local cookie = os.getenv("NVIM_LEETCODE_COOKIE")
	if not cookie then
		vim.print("need cookie")
		return
	end

	local client = require("leetcode.client")
	client.cookie = cookie
	client.prefer_lang = opts.prefer_lang or "golang"

	local info = client:user()
	if not info then
		vim.print("wrong cookie")
		return
	end
	ui.client = client

	vim.api.nvim_create_user_command("LeetCode", function(opts)
		if #opts.fargs == 0 then
			ui.list(info, status, problemset)
		end
	end, {
		nargs = "?",
	})

	-- local problem = client:today()
	-- if not problem then
	-- 	return
	-- end

	-- local detail = client:data(problem.slug)
	-- if not detail then
	-- 	return
	-- end

	-- local result = client:interpret(detail)
	-- if not result then
	-- 	return
	-- end
	-- local result = client:submit(detail)
	-- local r = client:check(result.id)
end

return M
