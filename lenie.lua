#!/usr/bin/luajit
-- TODO where to put the asserts? Needs consistent solution.


CONF = { initialized = false }


--{{{ UTIL FUNCTIONS
-- Replacement for dofile that respects the environment of the caller function rather than
-- executing in the global environment.
function importfile(fname)
	local f,e = loadfile(fname)
	if not f then error(e, 2) end
	setfenv(f, getfenv(2))
	return f()
end

function file_exists(fname)
	local fd = io.open(fname, 'r')
	if io.type(fd) ~= nil then
		fd:close()
		return true
	else
		return false
	end
end

function installed(pname)
	local path = "/usr/bin/" .. pname
	return file_exists(path)
end

-- Get sha1 of most recent commit from the blogs git repository
function get_revision()
	-- TODO assert we are in the right directory
	local fd = io.popen("git log -1 | grep commit | awk '{ print $2 }'")
	local rev = fd:read("*a")
	fd:close()
	return rev
end

-- In the src directory there is a file "rev" that stores the sha1 of the commit associated with
-- the current state of the blog. Note that this is not necessarily the commit that is checked
-- out in the src directory; it refers to the generated HTML files and indicates whether the
-- blog - as seen by the web server - is out of sync with the blogs repository.
-- This function does the comparison and returns true if the blog is in sync with the repo.
function up_to_date(srcdir)
	local fd = io.open(srcdir.."/rev", 'r')
	if fd then
		local checked_out = fd:read("*l")
		fd:close()
		if get_revision() == checked_out then return true end
	end
	return false
end

-- Read the runtime config and return a table with the configuration state. If there is no rc
-- file, return default values. This function is sandboxed in its own environment for security
-- reasons and it expects the table for that environment as second argument. The runtime config
-- will be stored in that table.
function read_rc(srcdir, rc)
	-- Setting up the environment of the sandbox
	local type, assert, print = type, assert, print
	local sprintf = string.format
	local file_exists, importfile = file_exists, importfile
	setfenv(1, rc)

	local fname = srcdir.."/rc.lua"
	if file_exists(fname) then
		importfile(fname)
		assert(type(color) == "string")
		assert(type(background) == "string")
		assert(type(padding) == "table")
		assert(type(padding.top) == "string")
	else
		print( sprintf("WARNING: No rc.lua in %q, using default config", srcdir) )
		color = "#000"
		background = "#fff"
		padding = { top="50px", right="20%", bottom="50px", left="20%" }
		blog_title = "default blog title"
		blog_subtitle = "powered by lenie; free of js, php, java, flash"
		verbose = true
	end

	return true		-- completed succesfully
end

-- Set up and configure the bare repository to automatically create static HTML files for the
-- web server upon receiving blog pusts via git push
function prepare(srcdir)
	-- Make sure all programs required to run this script are installed
	local req_progs = {"markdown", "git", "grep", "awk"}
	for ix,prog in ipairs(req_progs) do
		if not installed(prog) then
			print(string.format("ERROR: The program %q is required but can't be found", prog))
			os.exit()
		end
	end

	-- Read runtime config from rc.lua, store it in the global table "conf" and set its
	-- "initialized" flag
	CONF.initialized = read_rc(srcdir, CONF)

	--[[ If no style.css exists, create a template
	-- TODO re-evaluate
	local fname = PWD.."/style.css"
	if not file_exists(fname) then
		local fd = io.open(fname, 'w')
		local css = "body{color: #fff; background: #000; padding: 50px 20% 50px 20%}"
		fd:write(css)
		fd:close()
	end
	]]
	return true
end
--}}}


--{{{ PATH 1: GENERATING STATIC HTML
-- Create table with files that need to be generated, sorted by date of modification
function gather_mdfiles(src)
	if CONF.verbose then print("Sourcing markdown files from "..src) end
	local mdfiles = {}
	for fname in io.popen('ls -t "' .. src .. '"'):lines() do
		local mdfile = fname:match('^.+%.md$')
		if mdfile then
			mdfiles[#mdfiles+1] = mdfile
		end
	end
	return mdfiles
end

function gen_html(src, mdfiles, rc)
	assert(rc.initialized, "Runtime config has to be initialized before generating HTML")
	assert(type(src) == "string", "first argument needs to be a string describing the path to the source directory")
	assert(type(mdfiles) == "table", "second argument needs to be an array containing markdown files as strings")

	-- Convert markdown files to HTML and store each one as string in an array "posts"
	local posts = {}
	for ix,fname in ipairs(mdfiles) do
		-- TODO Extract info about file creation- and modification-date from git index
		local fd = io.popen("markdown --html4tags " .. src .. "/" .. fname)
		posts[ix] = fd:read('*a')
		fd:close()
	end

	-- Create HTML based on runtime conf and concatenate it with the previously generated post
	-- bodies.
	local html = {}
	-- Header
	html[#html+1] = [[
	<html>
	<link href="style.css" rel="stylesheet">
	<body>
	]]
	html[#html+1] = string.format("<h1>%s</h1>", rc.blog_title)
	html[#html+1] = string.format("<h2>%s</h2>", rc.blog_subtitle)
	-- Posts
	local separator = "\n<br /><hr><br />\n"
	html[#html+1] = table.concat(posts, separator)
	-- Footer
	html[#html+1] = [[
	</body>
	</html>
	]]
	return table.concat(html, "\n")
end

function gen_css(rc)
	assert(rc.initialized, "Runtime config has to be initialized before generating CSS")
	-- TODO Test if it is necessary to generate the CSS or if the style.css is still up to date
	local css = {}
	local col, bg = rc.color, rc.background
	local pad = string.format("%s %s %s %s", rc.padding.top, rc.padding.right, rc.padding.bottom, rc.padding.left)
	css[#css+1] = string.format("body {color: %s; background: %s; padding: %s;}", col, bg, pad)
	col = rc.link_color or col
	bg = rc.link_background or bg
	css[#css+1] = string.format("a {color: %s; background: %s;}", col, bg)
	col = rc.h1_color or col
	bg = rc.h1_background or bg
	css[#css+1] = string.format("h1 {color: %s; background: %s;}", col, bg)
	col = rc.h2_color or col
	bg = rc.h2_background or bg
	css[#css+1] = string.format("h2 {color: %s; background: %s;}", col, bg)
	col = rc.h3_color or col
	bg = rc.h3_background or bg
	css[#css+1] = string.format("h3 {color: %s; background: %s;}", col, bg)
	return table.concat(css, "\n")
end

-- Read all files in the specified source directory "src" and generate HTML code to be stored in
-- destination directory "dst"
function generate(src, dst)
	if up_to_date(src) then return "Blog already up to date" end

	local mdfiles = gather_mdfiles(src)
	local index_html = gen_html(src, mdfiles, CONF)
	local style_css = gen_css(CONF)

	-- Write HTML file
	do
		local fname = dst.."/index.html"
		if CONF.verbose then print(string.format("Writing HTML to %s", fname)) end
		local fd = io.open(fname, 'w')
		fd:write(index_html)
		fd:close()
	end

	-- Write CSS file
	do
		local fname = dst.."/style.css"
		if CONF.verbose then print(string.format("Writing CSS to %s", fname)) end
		local fd = io.open(fname, 'w')
		fd:write(style_css)
		fd:close()
	end

	-- Update rev file to most recent commit hash
	do
		local fd = io.open(src.."/rev", 'w+')
		fd:write( get_revision() )
		fd:close()
	end

	return "Blog updated!"
end
--}}}


--{{{ PATH 2: INITIAL SETUP
-- Initialize the git repository for the server and configure it.
function init( repo_path, www_path )
	-- TODO create directory repo_path, repo_path/src
	-- TODO create bare repository in repo_path/git
	-- TODO add post-receive hook
	local hints = {
		[[Don't forget to add the SSH keys of everyone who should be able to push to this blog
		to '$HOME/.ssh/authorized_keys'. See man ssh for details.]],
		[[Make sure the permissions of the directory where the HTML pages should be written are
		set properly. The user calling "lenie generate" must have permission to write there and
		the webserver must have permission to read the files there.]],
	}
	print("Setup completed. The blog repository has been created at " .. repo_path ..
	" and has been configured to save all generated HTML files to " .. www_path)
	for ix,str in ipairs( hints ) do
		print("Hint " .. ix .. ": " .. str)
	end
end
--}}}


--{{{ MAIN
function print_usage()
	local usage = {
		[[lenie init <path of repo> <path to www dir observed by webserver>]],
		[[lenie generate <path to src dir> <path to dest dir>]],
	}
	for ix,str in ipairs(usage) do
		print("usage ["..ix.."]: " .. str)
	end
end

-- Parse input arguments
if arg[1] == "generate" or arg[1] == "gen" then
	local srcdir, dstdir = arg[2], arg[3]
	if srcdir == nil or dstdir == nil then
		print("ERROR: Arguments missing.")
		print_usage()
		os.exit()
	end
	assert( prepare(srcdir), "Failure during preparation phase" )
	local result = generate(srcdir, dstdir)
	if CONF.verbose then print( result ) end
elseif arg[1] == "initialize" or arg[1] == "init" then
	local repo_path, www_path = arg[2], arg[3]
	if not repo_path or not www_path then
		print("ERROR: Arguments missing.")
		print_usage()
		os.exit()
	end
	print("Sorry, this feature has not yet been fully implemented")
else
	print_usage()
	os.exit()
end
--}}}