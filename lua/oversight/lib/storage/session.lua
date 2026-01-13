-- Review session state management
-- Note: Sessions are ephemeral and not persisted between Neovim sessions

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
---@field diff_hash? string Hash of the diff content (for change detection)

---@class File
---@field path string File path relative to repo root
---@field status string Git status (A, M, D, R, C)
---@field reviewed boolean Whether file has been reviewed
---@field old_path? string Original path for renamed files

---@class CommentContext
---@field file string File path
---@field line? number Line number (nil for file-level comments)
---@field side? "old"|"new" Which side of the diff (nil for file-level)

---@class CommentData
---@field id? string Comment ID (present when editing existing comment)
---@field file string File path
---@field line? number Line number
---@field side? "old"|"new" Diff side
---@field type "note"|"suggestion"|"issue"|"praise" Comment type
---@field text string Comment text

---@class LineInfo
---@field type string Line type ("diff_line", "comment", "hunk_header", etc.)
---@field line_no_old? number Old line number
---@field line_no_new? number New line number
---@field file? string File path
---@field comment_id? string Comment ID (for comment lines)

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
	local result = string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)
	return result
end

---Get current ISO 8601 timestamp
---@return string timestamp ISO 8601 formatted timestamp
local function iso_timestamp()
	return os.date("!%Y-%m-%dT%H:%M:%SZ") --[[@as string]]
end

---Compute a simple hash of a string (djb2 algorithm)
---@param str string String to hash
---@return string hash Hex string hash
local function compute_hash(str)
	local hash = 5381
	for i = 1, #str do
		hash = ((hash * 33) + str:byte(i)) % 0x100000000
	end
	return string.format("%08x", hash)
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

---Create a new session for a repository
---Sessions are ephemeral and not persisted between Neovim sessions
---@param repo_root string Repository root path
---@param base_ref string Current HEAD ref
---@return ReviewSession session New session
function Session.load_or_create(repo_root, base_ref)
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

---No-op for backwards compatibility (sessions are no longer persisted)
---@return boolean success Always returns true
function Session:save()
	self.updated_at = iso_timestamp()
	return true
end

---Initialize file in session if not present, or reset if diff changed
---@param path string File path
---@param git_status string Git status
---@param diff_content? string Optional diff content to compute hash from
---@return boolean changed True if file was reset due to diff change
function Session:ensure_file(path, git_status, diff_content)
	local diff_hash = diff_content and compute_hash(diff_content) or nil

	if not self.files[path] then
		self.files[path] = {
			path = path,
			git_status = git_status,
			reviewed = false,
			diff_hash = diff_hash,
		}
		return false
	end

	-- Check if diff changed (only if we have both old and new hashes)
	local existing = self.files[path]
	if diff_hash and existing.diff_hash and diff_hash ~= existing.diff_hash then
		-- Diff changed - reset file status and remove comments
		self:reset_file(path)
		existing.diff_hash = diff_hash
		existing.git_status = git_status
		return true
	end

	-- Update hash if we have one now but didn't before
	if diff_hash and not existing.diff_hash then
		existing.diff_hash = diff_hash
	end

	return false
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

---Reset a file's review status and remove all its comments
---@param path string File path
function Session:reset_file(path)
	if self.files[path] then
		self.files[path].reviewed = false
	end

	-- Remove all comments for this file
	local i = 1
	while i <= #self.comments do
		if self.comments[i].file == path then
			table.remove(self.comments, i)
		else
			i = i + 1
		end
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

---Get a comment by ID
---@param comment_id string Comment ID
---@return Comment|nil comment The comment or nil if not found
function Session:get_comment(comment_id)
	for _, comment in ipairs(self.comments) do
		if comment.id == comment_id then
			return comment
		end
	end
	return nil
end

---Update an existing comment
---@param comment_id string Comment ID
---@param comment_type "note"|"suggestion"|"issue"|"praise" Comment type
---@param text string Comment text
---@return boolean success True if comment was updated
function Session:update_comment(comment_id, comment_type, text)
	for _, comment in ipairs(self.comments) do
		if comment.id == comment_id then
			comment.type = comment_type
			comment.text = text
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
