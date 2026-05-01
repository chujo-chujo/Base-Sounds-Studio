-- Pure Lua MD5 module

-- Works in Lua 5.3+ (requires bitwise operators like <<, &, ~).
-- Provides minimal API:
	-- md5.sum(data)      → returns hex digest
	-- md5.sum_file(path) → convenience wrapper

-- Note: The script is not optimized, it reads the entire file into memory at once.
--       It might struggle with larger files?

local md5 = {}

local function left_rotate(x, c)
	return ((x << c) | (x >> (32 - c))) & 0xFFFFFFFF
end

local function to_bytes_le(n)
	return string.char(
		n & 0xFF,
		(n >> 8) & 0xFF,
		(n >> 16) & 0xFF,
		(n >> 24) & 0xFF
	)
end

local function from_bytes_le(s, i)
	local b1, b2, b3, b4 = s:byte(i, i+3)
	return b1 | (b2 << 8) | (b3 << 16) | (b4 << 24)
end

local function to_hex_le(n)
	return string.format("%02x%02x%02x%02x",
		n & 0xFF,
		(n >> 8) & 0xFF,
		(n >> 16) & 0xFF,
		(n >> 24) & 0xFF
	)
end

function md5.sum(message)
	local msg_len = #message

	-- Pre-processing (padding)
	message = message .. "\128"
	local padding = (56 - (#message % 64)) % 64
	message = message .. string.rep("\0", padding)

	-- Append original length in bits (64-bit little endian)
	local bit_len = msg_len * 8
	message = message .. to_bytes_le(bit_len & 0xFFFFFFFF)
	message = message .. to_bytes_le((bit_len >> 32) & 0xFFFFFFFF)

	-- Initialize variables
	local a0 = 0x67452301
	local b0 = 0xEFCDAB89
	local c0 = 0x98BADCFE
	local d0 = 0x10325476

	-- Constants
	local s = {
		7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
		5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
		4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
		6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
	}

	local K = {}
	for i = 1, 64 do
		K[i] = math.floor(math.abs(math.sin(i)) * 2^32) & 0xFFFFFFFF
	end

	-- Process in 512-bit chunks
	for i = 1, #message, 64 do
		local M = {}
		for j = 0, 15 do
			M[j] = from_bytes_le(message, i + j*4)
		end

		local A, B, C, D = a0, b0, c0, d0

		for i2 = 0, 63 do
			local F, g

			if i2 < 16 then
				F = (B & C) | ((~B) & D)
				g = i2
			elseif i2 < 32 then
				F = (D & B) | ((~D) & C)
				g = (5*i2 + 1) % 16
			elseif i2 < 48 then
				F = B ~ C ~ D
				g = (3*i2 + 5) % 16
			else
				F = C ~ (B | (~D))
				g = (7*i2) % 16
			end

			F = (F + A + K[i2+1] + M[g]) & 0xFFFFFFFF
			A = D
			D = C
			C = B
			B = (B + left_rotate(F, s[i2+1])) & 0xFFFFFFFF
		end

		a0 = (a0 + A) & 0xFFFFFFFF
		b0 = (b0 + B) & 0xFFFFFFFF
		c0 = (c0 + C) & 0xFFFFFFFF
		d0 = (d0 + D) & 0xFFFFFFFF
	end

	return to_hex_le(a0) .. to_hex_le(b0) .. to_hex_le(c0) .. to_hex_le(d0)
end

-- Convenience wrapper to hash a file
function md5.sum_file(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	else
		local content = f:read("*all")
		f:close()
		return md5.sum(content)
	end
end

return md5