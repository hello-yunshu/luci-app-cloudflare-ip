module("luci.controller.cloudflare-ip", package.seeall)

function index()
	local nixio = require("nixio")

	-- Legacy LuCI controller compatibility for optional proxy pages. The
	-- package menu.d file owns the core routes; these entries are registered
	-- only when the corresponding plugin is actually installed.
	local plugins = {
		{ id = "openclash", init = "/etc/init.d/openclash", title = "OpenClash", order = 30 },
		{ id = "passwall",  init = "/etc/init.d/passwall",  title = "PassWall",  order = 40 },
		{ id = "passwall2", init = "/etc/init.d/passwall2", title = "PassWall2", order = 42 },
		{ id = "homeproxy", init = "/etc/init.d/homeproxy", title = "HomeProxy", order = 45 },
	}

	for _idx, p in ipairs(plugins) do
		if nixio.fs.access(p.init, "x") then
			entry({"admin", "services", "cf_ip", p.id},
				view("cloudflare-ip/" .. p.id),
				_(p.title), p.order)
		end
	end
end
