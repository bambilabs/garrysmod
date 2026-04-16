local byte = string.byte
local sub = string.sub
local lshift = bit.lshift
local rshift = bit.rshift
local bor = bit.bor
local band = bit.band

local GIFDecoder = {}
local GIFDecoderMethods = {}
local GIFDecoder_meta = {__index = GIFDecoderMethods}

function GIFDecoder.new(buf)
	local buf_n = #buf
	local this = setmetatable({
		p = 1,
		buf = buf
	}, GIFDecoder_meta)

	local version = this:read(6)
	assert(version == "GIF89a" or version == "GIF87a", "wrong file format")

	this.width = this:word()
	this.height = this:word()

	local pf0 = this:byte()
	local global_palette_flag = rshift(pf0, 7)
	local num_global_colors_pow2 = band(pf0, 0x7)
	local num_global_colors = lshift(1, num_global_colors_pow2 + 1)
	this:skip(2)

	local global_palette_offset = nil
	local global_palette_size = nil

	if global_palette_flag > 0 then
		global_palette_offset = this.p
		this.global_palette_offset = global_palette_offset
		global_palette_size = num_global_colors
		this:skip(num_global_colors * 3)
	end

	local no_eof = true

	local frames = {}

	local delay = 0
	local transparent_index = nil
	local disposal = 0

	while no_eof and this.p <= buf_n do
		local b = this:byte()
		if b == 0x3b then
			no_eof = false
		elseif b == 0x2c then
			local x, y, w, h = this:word(), this:word(), this:word(), this:word()
			local pf2 = this:byte()
			local local_palette_flag = rshift(pf2, 7)
			local interlace_flag = band(rshift(pf2, 6), 1)
			local num_local_colors_pow2 = band(pf2, 0x7)
			local num_local_colors = lshift(1, num_local_colors_pow2 + 1)
			local palette_offset = global_palette_offset
			local palette_size = global_palette_size
			local has_local_palette = false
			if local_palette_flag ~= 0 then
				has_local_palette = true
				palette_offset = this.p
				palette_size = num_local_colors
				this:skip(num_local_colors * 3)
			end

			local data_offset = this.p

			this:skip(1)
			this:skip_eob()

			table.insert(frames, {
				x = x,
				y = y,
				width = w,
				height = h,
				has_local_palette = has_local_palette,
				palette_offset = palette_offset,
				palette_size = palette_size,
				data_offset = data_offset,
				data_length = this.p - data_offset,
				transparent_index = transparent_index,
				interlaced = interlace_flag > 0,
				delay = delay,
				disposal = disposal
			})

			-- Reset GCE state after consumption
			delay = 0
			transparent_index = nil
			disposal = 0
		elseif b == 0x21 then
			local b2 = this:byte()
			if b2 == 0xf9 then
				local len, flags = this:bytes(2)
				delay = this:word()
				local transparent, terminator = this:bytes(2)

				assert(len == 4 and terminator == 0, "Invalid graphics extension block.")

				if flags % 2 == 1 then
					transparent_index = transparent
				else
					transparent_index = nil
				end

				disposal = math.floor(flags / 4) % 8
			elseif b2 == 0xff then
				this:read(this:byte())
				this:skip_eob()
			else
				this:skip_eob()
			end
		end
	end

	this.frames = frames

	return this
end

function GIFDecoderMethods:skip(offset)
	self.p = self.p + offset
end

-- skip to end of block
function GIFDecoderMethods:skip_eob()
	repeat
		local size = self:byte()
		self:skip(size)
	until size == 0
end

function GIFDecoderMethods:byte()
	local b = byte(self.buf, self.p)
	self:skip(1)
	return b
end

function GIFDecoderMethods:bytes(len)
	local _p = self.p
	self:skip(len)
	return byte(self.buf, _p, len + _p - 1)
end

function GIFDecoderMethods:read(len)
	local _p = self.p
	self:skip(len)
	return sub(self.buf, _p, len + _p - 1)
end

function GIFDecoderMethods:word()
	return bor(self:byte(), lshift(self:byte(), 8))
end

local GifReaderLZWOutputIndexStream = function(this, output, output_length)
	local min_code_size = this:byte()
	local clear_code = lshift(1, min_code_size)
	local eoi_code = clear_code + 1
	local next_code = eoi_code + 1
	local cur_code_size = min_code_size + 1

	local code_mask = lshift(1, cur_code_size) - 1
	local cur_shift = 0
	local cur = 0
	local op = 0

	local subblock_size = this:byte()

	local code_table = {}

	local prev_code = nil

	while true do
		while cur_shift < 16 do
			if subblock_size == 0 then break end

			cur = bor(cur, lshift(this:byte(), cur_shift))
			cur_shift = cur_shift + 8

			if subblock_size == 1 then
				subblock_size = this:byte()
			else
				subblock_size = subblock_size - 1
			end
		end

		if cur_shift < cur_code_size then break end

		local code = band(cur, code_mask)
		cur = rshift(cur, cur_code_size)
		cur_shift = cur_shift - cur_code_size

		if code == clear_code then
			next_code = eoi_code + 1
			cur_code_size = min_code_size + 1
			code_mask = lshift(1, cur_code_size) - 1

			prev_code = nil
			goto _continue_
		elseif code == eoi_code then
			break
		end

		if prev_code == nil and code >= next_code then
			Error("Warning, invalid LZW code after clear.")
			return
		end

		local chase_code = code < next_code and code or prev_code
		local chase_length = 0
		local chase = chase_code
		while chase > clear_code do
			chase = rshift(code_table[chase], 8)
			chase_length = chase_length + 1
		end

		local k = chase
		local op_end = op + chase_length + (chase_code ~= code and 1 or 0)
		if op_end > output_length then
			Error("Warning, gif stream longer than expected.")
			return
		end

		output[op] = k; op = op + 1
		op = op + chase_length

		local b = op

		if chase_code ~= code then
			output[op] = k; op = op + 1
		end
		chase = chase_code

		while chase_length > 0 do
			chase_length = chase_length - 1
			chase = code_table[chase]
			b = b - 1
			output[b] = band(chase, 0xff)

			chase = rshift(chase, 8)
		end

		if prev_code ~= nil and next_code < 4096 then
			code_table[next_code] = bor(lshift(prev_code, 8), k)
			next_code = next_code + 1

			if next_code >= code_mask + 1 and cur_code_size < 12 then
				cur_code_size = cur_code_size + 1
				code_mask = bor(lshift(code_mask, 1), 1)
			end
		end

		prev_code = code

		::_continue_::
	end

	if op ~= output_length then
		Error("Warning, gif stream shorter than expected.")
	end

	return output
end

-- GIF interlace pass definitions per spec:
-- Pass 1: start row 0, stride 8
-- Pass 2: start row 4, stride 8
-- Pass 3: start row 2, stride 4
-- Pass 4: start row 1, stride 2
local interlace_starts  = { 0, 4, 2, 1 }
local interlace_strides = { 8, 8, 4, 2 }

-- Build a mapping from sequential pixel index to actual row for interlaced frames.
-- Returns an array where result[i] = the destination row for the i-th pixel row
-- in the order they appear in the LZW stream.
local function build_interlace_row_map(frame_height)
	local row_map = {}
	local idx = 0
	for pass = 1, 4 do
		local row = interlace_starts[pass]
		while row < frame_height do
			row_map[idx] = row
			idx = idx + 1
			row = row + interlace_strides[pass]
		end
	end
	return row_map
end

function GIFDecoderMethods:decode_and_blit_frame_RGBA(frame_num, pixels)
	local frame = self.frames[frame_num]
	local num_pixels = frame.width * frame.height
	local index_stream = {}

	self.p = frame.data_offset
	GifReaderLZWOutputIndexStream(self, index_stream, num_pixels)
	local palette_offset = frame.palette_offset

	local trans = frame.transparent_index
	if trans == nil then
		trans = 256
	end

	local canvas_width = self.width
	local frame_width = frame.width
	local frame_height = frame.height
	local frame_x = frame.x
	local frame_y = frame.y
	local buf = self.buf

	if frame.interlaced then
		local row_map = build_interlace_row_map(frame_height)
		local i = 0
		for stream_row = 0, frame_height - 1 do
			local actual_row = row_map[stream_row]
			local row_op = ((frame_y + actual_row) * canvas_width + frame_x) * 4
			for col = 0, frame_width - 1 do
				local index = index_stream[i]
				if index ~= trans then
					local ci = palette_offset + index * 3
					pixels[row_op + 0] = byte(buf, ci)
					pixels[row_op + 1] = byte(buf, ci + 1)
					pixels[row_op + 2] = byte(buf, ci + 2)
					pixels[row_op + 3] = 255
				end
				row_op = row_op + 4
				i = i + 1
			end
		end
	else
		local op = (frame_y * canvas_width + frame_x) * 4
		local scanstride = (canvas_width - frame_width) * 4
		local xleft = frame_width
		local i = 0
		while i < num_pixels do
			local index = index_stream[i]

			if index ~= trans then
				local ci = palette_offset + index * 3
				pixels[op + 0] = byte(buf, ci)
				pixels[op + 1] = byte(buf, ci + 1)
				pixels[op + 2] = byte(buf, ci + 2)
				pixels[op + 3] = 255
			end

			op = op + 4
			i = i + 1
			xleft = xleft - 1
			if xleft == 0 then
				op = op + scanstride
				xleft = frame_width
			end
		end
	end
end

function GIFDecoderMethods:clear_frame(frame_num, pixels)
	local frame = self.frames[frame_num]

	local canvas_width = self.width
	local frame_width = frame.width
	local frame_height = frame.height
	local frame_x = frame.x
	local frame_y = frame.y

	for row = 0, frame_height - 1 do
		local row_op = ((frame_y + row) * canvas_width + frame_x) * 4
		for _ = 0, frame_width - 1 do
			pixels[row_op + 0] = 0
			pixels[row_op + 1] = 0
			pixels[row_op + 2] = 0
			pixels[row_op + 3] = 0
			row_op = row_op + 4
		end
	end
end

-- Copy only the rectangular region of a frame from src to dst pixel buffers.
-- This avoids copying the entire canvas when only a sub-region is affected.
local function copy_frame_region(dst, src, canvas_width, frame)
	local frame_x = frame.x
	local frame_y = frame.y
	local frame_width = frame.width
	local frame_height = frame.height
	for row = 0, frame_height - 1 do
		local row_start = ((frame_y + row) * canvas_width + frame_x) * 4
		local row_end = row_start + frame_width * 4 - 1
		for k = row_start, row_end do
			dst[k] = src[k]
		end
	end
end

local function clone_pixels(src, num_pixels)
	local dst = {}
	for k = 0, num_pixels - 1 do
		dst[k] = src[k]
	end
	return dst
end

function GIFDecoderMethods:get_frames()
	local canvas_width = self.width
	local num_pixels = canvas_width * self.height * 4
	local frames = {}
	local numFrames = #self.frames
	local last_frame
	local restore_from
	for i = 1, numFrames do
		local frame = self.frames[i]

		local data = {}

		if last_frame then
			local _data = last_frame.data
			for k = 0, num_pixels - 1 do
				data[k] = _data[k]
			end
		end

		local disposal = frame.disposal
		if disposal ~= 3 then
			restore_from = clone_pixels(data, num_pixels)
		end

		if i > 1 then
			local prev_frame = self.frames[i - 1]
			local last_disposal = last_frame.disposal
			if last_disposal == 3 then
				if restore_from then
					copy_frame_region(data, restore_from, canvas_width, prev_frame)
				else
					self:clear_frame(i - 1, data)
				end
			end

			if last_disposal == 2 then
				self:clear_frame(i - 1, data)
			end
		end

		self:decode_and_blit_frame_RGBA(i, data)

		local delay = frame.delay
		if delay < 2 then
			delay = 10
		end

		last_frame = {
			data = data,
			delay = delay,
			disposal = disposal
		}
		frames[i] = last_frame
	end

	return frames
end

return GIFDecoder.new