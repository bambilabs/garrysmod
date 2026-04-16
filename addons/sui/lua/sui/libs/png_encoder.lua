local string = string
local table = table
local bit = bit

local char = string.char
local byte = string.byte

local concat = table.concat
local unpack = unpack

local bor = bit.bor
local bxor = bit.bxor
local band = bit.band
local bnot = bit.bnot
local lshift = bit.lshift
local rshift = bit.rshift

local ceil = math.ceil

local SIGNATURE = char(137, 80, 78, 71, 13, 10, 26, 10)

local crc_table = {}; do
	local n = 0
	while n < 256 do
		local c = n
		local k = 0
		while k < 8 do
			if band(c, 1) ~= 0 then
				c = bxor(0xedb88320, rshift(c, 1))
			else
				c = rshift(c, 1)
			end
			k = k + 1
		end
		crc_table[n + 1] = c
		n = n + 1
	end
end

local crc = function(buf)
	local c = 0xffffffff
	for i = 1, #buf do
		c = bxor(crc_table[band(bxor(c, byte(buf, i)), 0xff) + 1], rshift(c, 8))
	end
	return bxor(c, 0xffffffff)
end

local dword_as_string = function(dword)
	return char(
		rshift(band(dword, 0xff000000), 24),
		rshift(band(dword, 0x00ff0000), 16),
		rshift(band(dword, 0x0000ff00), 8),
		band(dword, 0x000000ff)
	)
end

local create_chunk = function(type, data, length)
	local CRC = crc(type .. data)
	return concat({
		dword_as_string(length or #data),
		type,
		data,
		dword_as_string(CRC)
	}, "", 1, 4)
end

local create_IHDR; do
	local ARGS = (
		-- bit depth
		char(8) ..
		-- color type: 6=truecolor with alpha
		char(6) ..
		-- compression method: 0=deflate, only allowed value
		char(0) ..
		-- filtering: 0=adaptive, only allowed value
		char(0) ..
		-- interlacing: 0=none
		char(0)
	)

	create_IHDR = function(w, h)
		return create_chunk("IHDR", concat({
			dword_as_string(w),
			dword_as_string(h),
			ARGS
		}, "", 1, 3), 13)
	end
end

local deflate_pack; do
	local BASE = 65521
	local NMAX = 5552
	local adler32 = function(str)
		local s1 = 1
		local s2 = 0
		local n = NMAX

		for i = 1, #str do
			s1 = s1 + byte(str, i)
			s2 = s2 + s1

			n = n - 1
			if n == 0 then
				s1 = s1 % BASE
				s2 = s2 % BASE
				n = NMAX
			end
		end

		s1 = s1 % BASE
		s2 = s2 % BASE

		return bor(lshift(s2, 16), s1)
	end

	local splitChunks = function(chunk, chunkSize)
		local numChunks = ceil(#chunk / chunkSize)
		local ret = {}
		for i = 1, numChunks do
			ret[i] = chunk:sub(((i - 1) * chunkSize) + 1, i * chunkSize)
		end
		return ret, numChunks
	end

	deflate_pack = function(str)
		local ret = {"\x78\x9c"}
		local n = 1

		local chunks, len = splitChunks(str, 0xFFFF)

		for i = 1, len do
			local chunk = chunks[i]
			local chunk_n = #chunk
			local nchunk_n = bnot(chunk_n)

			n = n + 1; ret[n] = i < len and "\x00" or "\x01"
			n = n + 1; ret[n] = char(band(chunk_n, 0xff), band(rshift(chunk_n, 8), 0xff))
			n = n + 1; ret[n] = char(band(nchunk_n, 0xff), band(rshift(nchunk_n, 8), 0xff))
			n = n + 1; ret[n] = chunk
		end

		local t = adler32(str)
		n = n + 1; ret[n] = char(
			band(rshift(t, 24), 0xff),
			band(rshift(t, 16), 0xff),
			band(rshift(t, 8), 0xff),
			band(t, 0xff)
		)

		return concat(ret)
	end
end

local create_IDAT; do
	local BATCH = 4000
	local ZERO = "\0"

	create_IDAT = function(w, h, chunk)
		local stride = w * 4
		local parts = {}
		local n = 0

		for y = 0, h - 1 do
			n = n + 1
			parts[n] = ZERO
			local base = y * stride
			local pos = 0
			while pos < stride do
				local count = stride - pos
				if count > BATCH then count = BATCH end
				local bytes = {}
				for j = 1, count do
					bytes[j] = band(chunk[base + pos + j - 1] or 0, 0xFF)
				end
				n = n + 1
				parts[n] = char(unpack(bytes, 1, count))
				pos = pos + count
			end
		end

		return create_chunk("IDAT", deflate_pack(concat(parts)))
	end
end

local IEND = create_chunk("IEND", "", 0)
local to_return = {SIGNATURE, nil, nil, IEND}
local generate_png = function(w, h, chunk)
	local IHDR = create_IHDR(w, h)
	local IDAT = create_IDAT(w, h, chunk)

	to_return[2] = IHDR
	to_return[3] = IDAT

	return concat(to_return, "", 1, 4)
end

return generate_png