-- Review session state management

local json = require("tuicr.lib.storage.json")
local logger = require("tuicr.logger")

---@class Comment
---@field id string UUID
---@field file string File path relative to repo root
---@field line number|nil Line number (nil for file-level comments)
---@field side "old"|"new"|nil Which side of the diff (nil for file-level)
---@field type "note"|"suggestion"|"issue"|"praise" Comment type
---@field text string Comment content
---@field created_at string ISO 8601 timestamp

---@class FileStatus
---@field path string File path relative to repo root
---@field git_status string Git status (A, M, D, R)
---@field reviewed boolean Whether file has been reviewed

---@class ReviewSession
---@field id string UUID
---@field version string Session format version
---@field repo_root string Absolute path to repository root
---@field base_ref string Base git ref (usually HEAD SHA)
---@field created_at string ISO 8601 timestamp
---@field updated_at string ISO 8601 timestamp
---@field files table<string, FileStatus> Map of path to status
---@field comments Comment[] All comments
local Session = {}
Session.__index = Session

local SESSION_VERSION = "1.0"

-- Seed random number generator once on module load
-- Use high-resolution timer for better entropy
local _seeded = false
local function ensure_seeded()
	if not _seeded then
		local seed = os.time() + (vim.uv and vim.uv.hrtime() or 0) % 1000000
		math.randomseed(seed)
		_seeded = true
	end
end

---Generate a UUID
---@return string uuid UUID string
local function generate_uuid()
	ensure_seeded()
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)
end

---Get current ISO 8601 timestamp
---@return string timestamp ISO 8601 formatted timestamp
local function iso_timestamp()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---Create a new session
---@param repo_root string Repository root path
---@param base_ref string Base git ref
---@return ReviewSession session New session
function Session.new(repo_root, base_ref)
	local instance = setmetatable({
		id = generate_uuid(),
		version = SESSION_VERSION,
		repo_root = repo_root,
		base_ref = base_ref or "",
		created_at = iso_timestamp(),
		updated_at = iso_timestamp(),
		files = {},
		comments = {},
	}, Session)

	return instance
end

---Load session from disk or create new one
---@param repo_root string Repository root path
---@param base_ref string Current HEAD ref
---@return ReviewSession session Loaded or new session
function Session.load_or_create(repo_root, base_ref)
	local path = json.session_path(repo_root)
	local data = json.read(path)

	if data then
		-- Validate the session matches current repo state
		if data.base_ref == base_ref then
			logger.info("Loaded existing session for %s", repo_root)
			local session = Session.from_json(data)
			return session
		else
			logger.info(
				"Session base_ref mismatch (expected %s, got %s), creating new session",
				base_ref,
				data.base_ref
			)
		end
	end

	return Session.new(repo_root, base_ref)
end

---Create session from JSON data
---@param data table JSON data
---@return ReviewSession session Session instance
function Session.from_json(data)
	local instance = setmetatable({
		id = data.id or generate_uuid(),
		version = data.version or SESSION_VERSION,
		repo_root = data.repo_root,
		base_ref = data.base_ref,
		created_at = data.created_at or iso_timestamp(),
		updated_at = data.updated_at or iso_timestamp(),
		files = data.files or {},
		comments = data.comments or {},
	}, Session)

	return instance
end

---Convert session to JSON-serializable table
---@return table data JSON data
function Session:to_json()
	return {
		id = self.id,
		version = self.version,
		repo_root = self.repo_root,
		base_ref = self.base_ref,
		created_at = self.created_at,
		updated_at = self.updated_at,
		files = self.files,
		comments = self.comments,
	}
end

---Save session to disk
---@return boolean success True if save succeeded
function Session:save()
	self.updated_at = iso_timestamp()
	local path = json.session_path(self.repo_root)
	return json.write(path, self:to_json())
end

---Initialize file in session if not present
---@param path string File path
---@param git_status string Git status
function Session:ensure_file(path, git_status)
	if not self.files[path] then
		self.files[path] = {
			path = path,
			git_status = git_status,
			reviewed = false,
		}
	end
end

---Get file status
---@param path string File path
---@return FileStatus|nil status File status or nil
function Session:get_file_status(path)
	return self.files[path]
end

---Check if file is reviewed
---@param path string File path
---@return boolean reviewed True if file is reviewed
function Session:is_file_reviewed(path)
	local status = self.files[path]
	return status and status.reviewed or false
end

---Toggle file reviewed status
---@param path string File path
---@return boolean new_status New reviewed status
function Session:toggle_file_reviewed(path)
	if self.files[path] then
		self.files[path].reviewed = not self.files[path].reviewed
		return self.files[path].reviewed
	end
	return false
end

---Set file reviewed status
---@param path string File path
---@param reviewed boolean Reviewed status
function Session:set_file_reviewed(path, reviewed)
	if self.files[path] then
		self.files[path].reviewed = reviewed
	end
end

---Add a comment
---@param file string File path
---@param line number|nil Line number (nil for file-level)
---@param side "old"|"new"|nil Diff side (nil for file-level)
---@param comment_type "note"|"suggestion"|"issue"|"praise" Comment type
---@param text string Comment text
---@return Comment comment New comment
function Session:add_comment(file, line, side, comment_type, text)
	local comment = {
		id = generate_uuid(),
		file = file,
		line = line,
		side = side,
		type = comment_type,
		text = text,
		created_at = iso_timestamp(),
	}

	table.insert(self.comments, comment)
	return comment
end

---Get comments for a file
---@param path string File path
---@return Comment[] comments Comments for this file
function Session:get_file_comments(path)
	local result = {}
	for _, comment in ipairs(self.comments) do
		if comment.file == path then
			table.insert(result, comment)
		end
	end
	return result
end

---Get comments for a specific line
---@param path string File path
---@param line number Line number
---@param side "old"|"new" Diff side
---@return Comment[] comments Comments for this line
function Session:get_line_comments(path, line, side)
	local result = {}
	for _, comment in ipairs(self.comments) do
		if comment.file == path and comment.line == line and comment.side == side then
			table.insert(result, comment)
		end
	end
	return result
end

---Delete a comment by ID
---@param comment_id string Comment ID
---@return boolean success True if comment was deleted
function Session:delete_comment(comment_id)
	for i, comment in ipairs(self.comments) do
		if comment.id == comment_id then
			table.remove(self.comments, i)
			return true
		end
	end
	return false
end

---Get review progress
---@return number reviewed Number of reviewed files
---@return number total Total number of files
function Session:get_progress()
	local reviewed = 0
	local total = 0

	for _, status in pairs(self.files) do
		total = total + 1
		if status.reviewed then
			reviewed = reviewed + 1
		end
	end

	return reviewed, total
end

---Get comment counts by type
---@return table<string, number> counts Map of type to count
function Session:get_comment_counts()
	local counts = {
		note = 0,
		suggestion = 0,
		issue = 0,
		praise = 0,
	}

	for _, comment in ipairs(self.comments) do
		if counts[comment.type] then
			counts[comment.type] = counts[comment.type] + 1
		end
	end

	return counts
end

---Check if session has any comments
---@return boolean has_comments True if there are comments
function Session:has_comments()
	return #self.comments > 0
end

---Clear all session data
function Session:clear()
	self.files = {}
	self.comments = {}
	self.updated_at = iso_timestamp()
end

return Session
