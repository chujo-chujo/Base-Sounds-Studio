--[[
Base Sounds Studio, v1.0.0 (2026-05-01)
https://github.com/chujo-chujo/Base-Sounds-Studio
Author: chujo
License: CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)

You may use, modify, and distribute this script for non-commercial purposes only (attribution required).
Any modifications or derivative works must be licensed under the same terms.

----------------------------------------------------------------------------

A GUI application that creates Base-Sounds Sets for OpenTTD.

Dependencies: 
— IUP Portable User Interface (MIT)         : GUI creation
— LuaCom (MIT)                              : for a WScript.Shell COM Object
— LuaFileSystem (MIT)                       : for directory manipulation
— fmedia (BSD 2-Clause)                     : sound playback/conversion
— catcodec.exe (GPLv2)                      : encodes samples into a CAT file
— 7za (LGPL v2.1)                           : creates TAR archives
— OpenSFX (CC BY-SA 3.0, GPLv2, CDDL 1.1)   : default OpenTTD sound pack

----------------------------------------------------------------------------

*** Quick Guide ***

1. Fill in all Metadata fields:
   — Name: The name of your base-sound set displayed in "Game Options".
   — Shortname: A four-character string, a unique identifier of your set. Use the button to generate a random valid shortname.
   — Version: The version number of your sound set. The highest version of sets with the same shortname will be listed.
   — Description: A brief description of the set.

2. The list of sounds always starts preloaded with OpenSFX sound effects, providing a reference starting point.
   Base Sounds Studio supports a wide range of common audio formats:
   .mp3, .ogg, .opus, .m4a/.mp4, .mka/.mkv, .avi, .aac, .mpc, .flac, .ape, .wv, .wav
   
   (OpenTTD supports only mono OPUS or 16-bit, 44.1 kHz mono WAV audio files,
   so all other formats are automatically converted during encoding.)

3. Save/load your project by using the "Save" (Ctrl+S) and "Open" (Ctrl+O) buttons.
   If you move or rename your files, you will need to reload them to update their paths.

4. Press "Encode" to create a TAR archive, which can be then copied to
   C:\Users\<username>\Documents\OpenTTD\baseset

   (Press Ctrl+W to force Base Sounds Studio to encode your sound effects as WAV files
   for compatibility with OpenTTD versions < 15.0)
]]


require("iuplua")
require("iupluacontrols")
require("iupluaim")
require("luacom")
local lfs = require("lfs")
local yaml = require("chuyaml")
local md5 = require("md5")
math.randomseed(os.time())


-- #### FORWARD DECLARATION, GLOBAL VARIABLES ######################################################
-- Set 'default folder' as the one contaning "START.bat"
lfs.chdir("..")
default_folder = lfs.currentdir()
last_folder = default_folder

-- WScript.Shell COM Object
local shell = luacom.CreateObject("WScript.Shell")

-- Names of sounds from OpenSFX
local sound_names = {
	"Good Year",
	"Bad Year",
	"Building docks/canals/river",
	"Factory whistle",
	"Steam train station departure",
	"Steam engine going in tunnel",
	"Ship horn",
	"Ferry horn",
	"Propeller plane take off",
	"Early jet take off",
	"Diesel/electric train departure",
	"Mining machinery",
	"Electric sparking",
	"Steam (from a steam engine)",
	"Level crossing",
	"Road vehicle breakdown",
	"Train/ship breakdown",
	"Crash",
	"Explosion",
	"Big crash",
	"Cash till",
	"Beep (GUI button click)",
	"News (Morse)",
	"Plane wheels touching ground",
	"Helicopter",
	"Truck/old bus start, pull away",
	"Truck/old bus start, pull away, horn",
	"Modern bus start",
	"Old bus start",
	"Applause",
	"Oooh",
	"Terraform/non-rail builds",
	"Building railroad",
	"Jackhammer (roadwork)",
	"Unused/Nothing",
	"Modern car horn",
	"Sheep",
	"Cow",
	"Horse",
	"Building bridge",
	"Sawmill",
	"Toyland: Sugar mine (1)",
	"Toyland: Toy factory (1)",
	"Toyland: Toy factory (2)",
	"Toyland: Toy factory (3)",
	"Toyland: Sugar mine (2)",
	"Toyland: Bubble generated",
	"Toyland: Bubble plop",
	"Toyland: Toffee quarry",
	"Toyland: Bubble slurped",
	"Unused/Nothing",
	"Toyland: Plastic mine",
	"Wind",
	"Toyland: Road vehicle breakdown",
	"Lumber mill: Crashing tree",
	"Lumber mill: Falling tree",
	"Lumber mill: Chainsaw",
	"Heavy wind",
	"Toyland: Train breakdown",
	"Supersonic jet take off",
	"Toyland: Comedy bus start (1)",
	"Modern jet take off",
	"Toyland: Comedy bus start (2)",
	"Toyland: Comedy truck start (1)",
	"Toyland: Comedy truck start (2)",
	"Maglev train station departure",
	"Tropical: Bird (1)",
	"Tropical: Jaguar roar",
	"Tropical: Monkeys",
	"Toyland: Propeller plane take off",
	"Toyland: Jet take off",
	"Monorail train station departure",
	"Tropical: Bird (2)"
}

-- Default filepaths → folder "opensfx"; new filepaths start as a copy, store full paths of new audio files
local sound_filepaths_default = {}
local sound_filepaths = {}
local n = 1
for i, name in ipairs(sound_names) do
	if name == "Unused/Nothing" then
		sound_filepaths_default[i] = "opensfx\\muted.wav"
	else
		sound_filepaths_default[i] = string.format("opensfx\\osfx_%02d.opus", n)
		n = n + 1
	end
	sound_filepaths[i] = sound_filepaths_default[i]
end

-- Toggle audio format
local FILETYPE = "opus"
local wav_warning = true

-- Style variables
local LAST_CELL = {lin = 0, col = 0}
local BACKGROUND_COLOR = "240 240 240"
local hover_lin = nil
local hover_col = nil



-- #### FUNCTIONS ##################################################################################
local function wait(t)
	local t0 = os.clock()
	while os.clock() - t0 <= t do end
end

local function get_rastersize(widget)
	-- Returns width, height as separate strings
	local size = iup.GetAttribute(widget, "RASTERSIZE")
	return size:match("(%d+)x(%d+)")
end

-- Remove leading and trailing whitespace
local function trim(str)
	return str:match("^%s*(.-)%s*$")
end

local function string_isspace(str)
	-- Returns "true" if str is a string and made only of whitespace characters
	return type(str) == "string" and str:match("^%s+$") ~= nil
end

-- Check if "substring" is in "full_string"
local function string_in(substring, full_string)
	if full_string:find(substring, 1, true) then
	    return true
	else
	    return false
	end
end

local function get_parent_dir(path)
	return path:match("(.*)[\\/]")
end

-- Returns a "sanitized" string safe for use as a Windows filename
local function windows_safe_filename(name)
	local safe = name:gsub('[\\/:*?"<>| ]', '_')
	safe = safe:gsub('[%. ]+$', '')
	safe = safe:gsub('[%.,]', '')

	-- Replace reserved filenames
	local reserved = {
		"CON", "PRN", "AUX", "NUL",
		"COM[1-9]", "LPT[1-9]"
	}
	for _, pattern in ipairs(reserved) do
		if safe:match('^' .. pattern .. '$') then
			safe = '_' .. safe
			break
		end
	end

	return safe
end

local function get_filename_and_ext(path)
	-- Extract full filename (part after last / or \)
	local filename = path:match("^.+[\\/](.+)$") or path

	-- Extract stem and extension
	local stem, ext = filename:match("^(.*)%.([^%.]+)$")

	if not stem or not ext then return nil end

	return stem, ext:lower()
end

local function file_exists(path)
	local f = io.open(path, "r")
	if f then f:close() end
	return f ~= nil
end

local function show_message(type, title, text, buttons)
	-- Wrapper function to display "iup.messagedlg"
	-- returns the number (as type NUMBER 1, 2 or 3) of the pressed button
	local msg = iup.messagedlg{
		dialogtype = type,
		title = title,
		value = text,
		buttons = buttons
	}
	msg:popup(iup.ANYWHERE, iup.ANYWHERE)
	return tonumber(msg.buttonresponse)
end

local function close_app()
	local response = show_message(
		"QUESTION",
		"", 
		"  Are you sure you want to exit?", 
		"YESNO")
	if response == 1 then
		local cmd = 'cmd /c rmdir /s /q "' .. default_folder .. '\\_temp"'
		shell:Run(cmd, 0, false)
		local cmd = 'cmd /c rmdir /s /q "' .. default_folder .. '\\_temp_sfx"'
		shell:Run(cmd, 0, false)
		return true
	else
		return false
	end
end

local function open_file_sound(path_to_current_file)
	local default_path = path_to_current_file
	if last_folder ~= default_folder then
		default_path = last_folder .. "\\audio"
	end

	local file_dlg = iup.filedlg{
		dialogtype = "OPEN",
		file  = default_path
	}
	file_dlg:popup(iup.ANYWHERE, iup.ANYWHERE)
	if file_dlg.status ~= "-1" then
		filepath = file_dlg.value
		last_folder = filepath:match("^(.*)[/\\][^/\\]+$")

		return filepath
	else
		return nil
	end
end

-- Get the parameters of an audio file
local function get_audio_info()
	local sound_info = {}

	local paths = table.concat(sound_filepaths, '" "')
	local tmp = default_folder .. "\\_temp\\" .. "sounds.info"

	-- fmedia info string (use concatenated paths and temporary file to dump info)
	local cmd = 'cmd /c ""files\\fmedia.exe" "' .. paths .. '" --info > "' .. tmp .. '" 2>&1"'
	shell:Run(cmd, 0, true)

	-- Parse temp file with info
	local bitrate, samplefmt, samplerate, channels
	local i = 1
	for line in io.lines(tmp) do
		if line:sub(1, 1) == "#" then
			-- Match values after "(... samples) " → bitrate, codec, samplefmt, samplerate, channels
			bitrate, _, samplefmt, samplerate, channels = line:match(".* samples%)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
			
			sound_info[i] = {}
			sound_info[i].bitrate    = bitrate:gsub("%D", "")
			sound_info[i].samplefmt  = samplefmt
			sound_info[i].samplerate = samplerate
			sound_info[i].channels   = channels

			i = i + 1
		end
	end


	return sound_info
end

local function convert_audio()
	local sound_filepaths_temp = {}
	local sound_info = get_audio_info()

	for i, path in ipairs(sound_filepaths) do

		-- Skip default sounds (unless they need  to be converted to WAV)
		if get_parent_dir(path) == "opensfx" and FILETYPE == "opus" then
			sound_filepaths_temp[i] = path
			goto continue
		end

		local stem, ext = get_filename_and_ext(path)

		-- Skip muted sounds
		if stem .. "." .. ext == "muted.wav" then
			sound_filepaths_temp[i] = path
			goto continue
		end

		-- Get audio parameters from parsed temporary file
		local bitrate = sound_info[i].bitrate
		local samplefmt = sound_info[i].samplefmt
		local samplerate = sound_info[i].samplerate
		local channels =  sound_info[i].channels

		-- Conversion decision tree
		local fmt = ""

		if FILETYPE == "opus" then
			if ext == "opus" and channels == "mono" then
				sound_filepaths_temp[i] = path
				goto continue
			elseif ext == "opus" and channels ~= "mono" then
				if tonumber(bitrate) > 200 then
					fmt = '.opus" --opus-bitrate=160 --channels=mono --overwrite'
				else
					fmt = '.opus" --opus-bitrate=' .. bitrate .. ' --channels=mono --overwrite'
				end
			elseif ext ~= "opus" then
				fmt = '.opus" --opus-bitrate=160 --channels=mono --overwrite'
			end

		elseif FILETYPE == "wav" then
			if ext == "wav" and samplefmt == "int16" and samplerate == "44100Hz" and channels == "mono" then
				sound_filepaths_temp[i] = path
				goto continue
			elseif ext == "wav" and (samplefmt ~= "int16" or samplerate ~= "44100Hz" or channels ~= "mono") then
				fmt = '.wav" --format=int16 --rate=44100 --channels=mono --overwrite'
			elseif ext ~= "wav" then
				fmt = '.wav" --format=int16 --rate=44100 --channels=mono --overwrite'
			end
		end

		if fmt ~= "" then
			local cmd = '"files\\fmedia.exe" "' .. path .. 
						'" --out="' .. default_folder ..
						"\\_temp_sfx\\" .. stem .. fmt
			shell:Run(cmd, 0, true)
			sound_filepaths_temp[i] = default_folder .. "\\_temp_sfx\\" .. stem .. '.' .. FILETYPE
		end

		::continue::
	end

	return sound_filepaths_temp
end

local function save_project()
	local filename = "my_base_sounds_set.yaml"
	if trim(text_name.value) ~= "" then
		filename = string.lower(windows_safe_filename(trim(text_name.value))) .. ".yaml"
	end

	local file_dlg = iup.filedlg{
		dialogtype = "SAVE",
		file       = default_folder .. "\\" .. filename,
		filter     = "*.yaml",
		filterinfo = "YAML (*.yaml)",
	}
	file_dlg:popup(iup.ANYWHERE, iup.ANYWHERE)
	if file_dlg.status ~= "-1" then
		filepath = file_dlg.value
		if not filepath:lower():match("%.yaml$") then
			filepath = filepath .. ".yaml"
		end
	else
		return iup.DEFAULT
	end

	local table_with_data = {
		name = text_name.value,
		shortname = text_shortname.value,
		ver = text_ver.value,
		desc = text_desc.value:gsub("[\n\t]+", "  "),
		sounds = {}
	}
	for i = 1, #sound_filepaths_default do
		table_with_data.sounds[i] = sound_filepaths[i]
	end

	-- Convert table to YAML and write into a file
	local yaml_file = io.open(filepath, "w")

	local yaml_string = yaml.to_yaml(table_with_data)
	yaml_file:write(yaml_string):close()

	return iup.DEFAULT
end

local function open_project(filepath)
	local filepath = filepath or nil
	if not filepath then
		local file_dlg = iup.filedlg{
			dialogtype = "OPEN",
			file  = default_folder .. "\\.yaml",
			filter     = "*.yaml",
			filterinfo = "YAML (*.yaml)",
		}
		file_dlg:popup(iup.ANYWHERE, iup.ANYWHERE)
		if file_dlg.status ~= "-1" then
			filepath = file_dlg.value
			last_folder = filepath:match("^(.*)[/\\][^/\\]+$")
		else
			return iup.DEFAULT
		end
	end

	local yaml_file, err = io.open(filepath, "r")
	if not yaml_file then
		show_message("ERROR", "Error", "  Could not open file: " .. filepath .. "\n  Error: " .. err, "OK")
		return
	end

	local yaml_string = yaml_file:read("*all")
	yaml_file:close()

	local table_with_data = yaml.parse(yaml_string)

	text_name.value = table_with_data.name
	text_shortname.value = table_with_data.shortname
	text_ver.value = table_with_data.ver
	text_desc.value = table_with_data.desc

	for i = 1, #sound_filepaths_default do
		local filename = string.format(" %s.%s", get_filename_and_ext(table_with_data.sounds[i]))
		if filename == " muted.wav" then
			filename = " muted"
		end
		matrix_sounds[i .. ":2"] = filename
		sound_filepaths[i] = table_with_data.sounds[i]
	end

	matrix_sounds.redraw = "ALL"

	return iup.DEFAULT
end

local function stop_sound()
	local cmd = '"files\\fmedia.exe" --globcmd.pipe-name=fmedia_pipe --globcmd=quit'
    -- shell:Run('taskkill /f /im fmedia.exe', 0, false)
	shell:Run(cmd, 0, false)
end

local function play_sound(filepath)
	filepath = filepath or ""
	local cmd = string.format('"files\\fmedia.exe" "%s" --gain=-6 --globcmd.pipe-name=fmedia_pipe --globcmd=listen', filepath)
	shell:Run(cmd, 0, false)
end

local function inputs_are_ok()
	if trim(text_name.value) == "" or trim(text_ver.value) == "" or trim(text_desc.value) == "" or trim(text_shortname.value) == "" then
		show_message(
			"WARNING",
			"Required field missing", 
			'  Input fields "Name", "Shortname", "Version"\n  and "Description" are all required.', 
			"OK")
		return false
	elseif #trim(text_shortname.value) < 4 then
		show_message(
			"WARNING",
			"Shortname", 
			'  "Shortname" has to be 4 characters long.', 
			"OK")
	else
		return true
	end
end

local function encode()
	local filename = string.lower(windows_safe_filename(trim(text_name.value)))
	local shortname = string.upper(text_shortname.value)

	-- Check if TAR already exists
	if file_exists(default_folder .. '\\' .. filename .. '.tar') then
		local re = show_message("QUESTION", "Overwrite?",
			'  File "'.. filename .. '.tar" already exists.\n  Overwrite?',
			"OKCANCEL")
		if re ~= 1 then
			return iup.DEFAULT
		end
	end

	-- Info dialog
	local dlg_encoding = iup.dialog{
		iup.label{title = "Encoding...", rastersize = "300x100", alignment = "ACENTER"},
		maxbox  = "NO",
		minbox  = "NO",
		menubox = "NO",
		resize  = "NO",
		title   = nil,
		background   = "209 210 222",
		parentdialog = iup.GetDialog(dlg),
	}
	iup.SetAttribute(iup.GetChild(dlg_encoding, 0), "FONTSTYLE", "Bold")
	dlg_encoding:showxy(iup.CENTERPARENT, iup.CENTERPARENT)

	-- Create a temporary folders (later deleted)
	lfs.mkdir(default_folder .. "\\_temp")
	lfs.mkdir(default_folder .. "\\_temp_sfx")

	-- Convert sounds if necessary
	local sound_filepaths_temp = convert_audio()


	-- Create SFO file
	local table_sfo = {}
	for i, v in ipairs(sound_filepaths_temp) do
		table_sfo[i] = '"' .. v .. '" "' .. sound_names[i] .. '" '
	end
	local string_sfo = table.concat(table_sfo, "\n")
	local sfo_file = io.open(default_folder .. "\\_temp\\" .. filename .. ".sfo", "w")
	sfo_file:write(string_sfo):close()

	iup.SetAttribute(iup.GetChild(dlg_encoding, 0), "TITLE", "SFO file created...")
	iup.Refresh(dlg_encoding)
	wait(0.7)


	-- Create CAT file
	local cmd = 'files\\catcodec.exe -e "' .. default_folder .. '\\_temp\\' .. filename .. '.cat"'
	local pipe = io.popen(cmd .. " 2>&1")
	local output = pipe:read("*all")
	pipe:close()


	-- Test if the CAT file exists
	if file_exists(default_folder .. "\\_temp\\" .. filename .. ".cat") then
		iup.SetAttribute(iup.GetChild(dlg_encoding, 0), "TITLE", "CAT file encoded...")
		iup.Refresh(dlg_encoding)
		wait(0.7)
	else
		local log_file = io.open(default_folder .. "\\log.txt", "w")
		log_file:write(output):close()

		dlg_encoding:destroy()
		show_message("ERROR", "Sum Ting Wong", '  Failed to create CAT file.\n  Check "log.txt".', "OK")
		local cmd = 'cmd /c rmdir /s /q "' .. default_folder .. '\\_temp"'
		shell:Run(cmd, 0, true)
		local cmd = 'cmd /c rmdir /s /q "' .. default_folder .. '\\_temp_sfx"'
		shell:Run(cmd, 0, true)
		return iup.DEFAULT
	end


	-- Create OBS file
	iup.SetAttribute(iup.GetChild(dlg_encoding, 0), "TITLE", "Calculating MD5 checksum...")
	iup.Refresh(dlg_encoding)

	local string_MD5 = md5.sum_file(default_folder .. "\\_temp\\" .. filename .. ".cat")
	if not string_MD5 then
		dlg_encoding:destroy()
		show_message("ERROR", "Sum Ting Wong","  MD5: Failed to read the file\n  " .. default_folder .. "\\_temp\\" .. filename .. ".cat", "OK")
		return iup.DEFAULT
	end

	local table_obs = {
		"[metadata]",
		string.format("name        = %s", trim(text_name.value)),
		string.format("shortname   = %s", shortname),
		string.format("version     = %s", trim(text_ver.value)),
		string.format("description = %s", trim(text_desc.value):gsub("[\n\t]+", "  ")),
		"",
		"[files]",
		string.format("samples = %s.cat", filename),
		"",
		"[md5s]",
		string.format("%s.cat = %s", filename, string_MD5),
		"",
		"[origin]",
		"default = Base Sounds Studio by chujo"
	}
	local string_obs = table.concat(table_obs, "\n")

	local obs_file = io.open(default_folder .. "\\_temp\\" .. filename .. ".obs", "w")
	obs_file:write(string_obs):close()

	iup.SetAttribute(iup.GetChild(dlg_encoding, 0), "TITLE", "OBS file created...")
	iup.Refresh(dlg_encoding)
	wait(0.7)


	-- Create TAR archive
	local cat_filepath = default_folder .. "\\_temp\\" .. filename .. ".cat"
	local obs_filepath = default_folder .. "\\_temp\\" .. filename .. ".obs"
	local cmd = '"files\\7za.exe" a -ttar "' .. default_folder .. '\\' .. filename .. '.tar" "' .. cat_filepath .. '" "' .. obs_filepath .. '"'
	shell:Run(cmd, 0, true)

	-- Test if the TAR file exists
	if file_exists(default_folder .. '\\' .. filename .. '.tar') then
		iup.SetAttribute(iup.GetChild(dlg_encoding, 0), "TITLE", "TAR archive created...")
		iup.Refresh(dlg_encoding)
	else
		show_message("ERROR", "Sum Ting Wong", '  Failed to create TAR archive.', "OK")
		dlg_encoding:destroy()
		return iup.DEFAULT
	end


	-- Remove the "_temp", "_temp_sfx" folders
	local cmd = 'cmd /c rmdir /s /q "' .. default_folder .. '\\_temp"'
	shell:Run(cmd, 0, true)
	local cmd = 'cmd /c rmdir /s /q "' .. default_folder .. '\\_temp_sfx"'
	shell:Run(cmd, 0, true)

	if lfs.attributes(default_folder .. "\\_temp") ~= nil then
		show_message("WARNING", "Error", '  Failed to remove the "_temp" folder.\n  (you can delete it manually)', "OK")
	end
	if lfs.attributes(default_folder .. "\\_temp_sfx") ~= nil then
		show_message("WARNING", "Error", '  Failed to remove the "_temp_sfx" folder.\n  (you can delete it manually)', "OK")
	end

	local username = iup.GetGlobal("USERNAME")
	show_message("INFORMATION", "",
		'  Done!\n\n  You can copy "' .. filename .. '.tar" to\n  "C:\\Users\\' .. username .. '\\Documents\\OpenTTD\\baseset"', "OK")
	dlg_encoding:destroy()
end

-- Switch file type between "opus" and "wav" (or set new type explicitly)
local function toggle_filetype(new_type)
	if new_type then
		FILETYPE = new_type
	else
		FILETYPE = (FILETYPE == "opus") and "wav" or "opus"
	end

	if FILETYPE == "wav" then
		btn_encode.image = img_encode2
		iup.Update(btn_encode)
	else
		btn_encode.image = img_encode
		iup.Update(btn_encode)
	end
end



-- ########################################################################################################

local function build_gui()
	-- Load images and icons
	local img_favicon = iup.LoadImage("files/gui/icon.png")
	local img_random  = iup.LoadImage("files/gui/random.png")
	local img_save    = iup.LoadImage("files/gui/save.png")
	local img_open    = iup.LoadImage("files/gui/open.png")
	img_encode  = iup.LoadImage("files/gui/encode.png")
	img_encode2 = iup.LoadImage("files/gui/encode_wav.png")
	local img_play    = iup.LoadImage("files/gui/play.png")
	local img_stop    = iup.LoadImage("files/gui/stop.png")
	local img_open_m  = iup.LoadImage("files/gui/open_mini.png")
	local img_mute    = iup.LoadImage("files/gui/mute.png")

	-- Define the main dialog window
	local dlg_width  = 560
	local dlg_height = 735

	dlg = iup.dialog{
		title = "Base Sounds Studio v1.0.0",
		rastersize = dlg_width .. "x" .. dlg_height,
		bgcolor = BACKGROUND_COLOR,
		resize = "NO",
		maxbox = "NO",
		icon = img_favicon,
		dropfilestarget = "YES",
		dropfiles_cb = function(self, filepath, num, x, y) open_project(filepath) return iup.DEFAULT end,
		close_cb = function()
			stop_sound()
			if close_app() then
				return iup.CLOSE
			else
				return iup.IGNORE
			end
		end
	}

	function dlg:k_any(key)
		if key == iup.K_cQ or key == iup.K_ESC or key == iup.K_F10 then
			stop_sound()
			if close_app() then
				return iup.CLOSE
			end
		elseif key == iup.K_F3 or key == iup.K_cS then
			stop_sound()
			save_project()
		elseif key == iup.K_F9 or key == iup.K_cO then
			stop_sound()
			open_project()
		elseif key == iup.K_F5 or key == iup.K_cE then
			encode()
		elseif key == iup.K_cW then
			stop_sound()
			toggle_filetype()
			if FILETYPE == "wav" and wav_warning then
				show_message("WARNING",
					"WAV Format",
					"  Exporting audio in WAV format ensures compatibility\n" ..
					"  with OpenTTD versions prior to 15.0.\n\n" ..
					"  But at the cost of significantly increased file size!",
					"OK")
				wav_warning = false
			end
		elseif key == iup.K_F1 or key == iup.K_cH then
			local url = default_folder .. "\\Manual.html"
			if not file_exists(url) then
				local response = show_message("QUESTION", "Manual", "  The manual could not be found locally.\n  Would you like to open the online version?", "OKCANCEL")
				if response == 1 then
					url = "https://chujo-chujo.github.io/Base-Sounds-Studio/"
				else
					return iup.DEFAULT
				end
			end

			os.execute('start "" "' .. url .. '"')

			return iup.DEFAULT
		end
	end

	-- #### METADATA ###########################################################################################

	local label_name = iup.label{title = "Name:", tip = 'Name displayed in "Game Options"'}
	local label_shortname = iup.label{title = "Shortname:", tip = 'Four characters (A-Z, 0-9).\nUsed as a unique identifier.'}
	local label_ver  = iup.label{title = "Version:", tip = 'E.g.: 1.0'}
	local label_desc = iup.label{title = "Description:", tip = 'Text displayed in "Game Options"'}

	text_name = iup.text{rastersize = "330x", nohidesel = "NO", bgcolor = "255 255 255", tip = 'Name displayed in "Game Options"'}
	text_shortname = iup.text{rastersize = "105x", nohidesel = "NO", bgcolor = "255 255 255", nc = 4, mask = "[0-9a-zA-Z]*", tip = 'Four characters (A-Z, 0-9).\nUsed as a unique identifier.'}
	text_ver  = iup.text{rastersize = "105x", nohidesel = "NO", bgcolor = "255 255 255", tip = 'E.g.: 1.0'}
	text_desc = iup.text{rastersize = "330x60", nohidesel = "NO", bgcolor = "255 255 255", multiline = "YES", wordwrap = "YES", tip = 'Text displayed in "Game Options"'}
	function text_shortname:killfocus_cb()
		self.value = self.value:upper()
	end

	local btn_random_shortname = iup.flatbutton{
		image = img_random,
		rastersize = "30x25",
		tip = "Generate random shortname"
	}
	function btn_random_shortname:flat_action()
		local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		local result = {}
		for i = 1, 4 do
			local index = math.random(1, tonumber(#chars))
			table.insert(result, chars:sub(index, index))
		end
		text_shortname.value = table.concat(result, "")
	end

	label_name.cx = 10
	label_name.cy = 10
	text_name.cx  = 80
	text_name.cy  = label_name.cy - 2

	label_shortname.cx = 10
	label_shortname.cy = label_name.cy + 1 * 30
	text_shortname.cx  = text_name.cx
	text_shortname.cy  = label_shortname.cy - 2
	
	btn_random_shortname.cx = text_shortname.cx + 105
	btn_random_shortname.cy = label_shortname.cy - 4

	label_ver.cx  = text_shortname.cx + 175
	label_ver.cy  = label_name.cy + 1 * 30
	text_ver.cx   = label_ver.cx + 50
	text_ver.cy   = label_ver.cy - 2

	label_desc.cx = label_name.cx
	label_desc.cy = label_name.cy + 2 * 30
	text_desc.cx  = text_name.cx
	text_desc.cy  = label_desc.cy - 2
	

	local frame_header = iup.frame{
		iup.cbox{
			label_name,
			text_name,
			label_shortname,
			text_shortname,
			btn_random_shortname,
			label_ver,
			text_ver,
			label_desc,
			text_desc,
		},
		rastersize = "425x155",
		expand = "NO",
		title = " Metadata ",
	}

	iup.SetAttribute(frame_header, "FONTSTYLE", "Bold")

	for i = 0, iup.GetChildCount(frame_header) - 1 do
		local child = iup.GetChild(frame_header, i)
		iup.SetAttribute(child, "FONTSTYLE", "Normal")
	end


	-- #### SOUNDS ###########################################################################################

	-- Create sound widgets as cells in a matrix 
	matrix_sounds = iup.matrixex{
		numcol = 6,
		numlin = #sound_filepaths_default,
		rasterheight0 = "1",
		rasterwidth1 = "190",
		rasterwidth2 = "140",
		rasterwidth3 = "25",
		rasterwidth4 = "25",
		rasterwidth5 = "25",
		rasterwidth6 = "25",
		framecolor = "220 220 220",
		bgcolor = BACKGROUND_COLOR,
		alignment1 = "ALEFT",
		alignment2 = "ALEFT",
		readonly = "YES",
		frametitlehighlight = "NO",
		menucontext = "NO",
		hiddentextmarks = "YES",
		hidefocus = "YES",
		rastersize = dlg_width-55 .. "x" .. dlg_height-255,
		cx = 10,
		cy = 0,
	}

	iup.SetAttribute(matrix_sounds, "BGCOLOR*:2", "255 255 255")
	iup.SetAttribute(matrix_sounds, "TYPE*:3", "IMAGE")
	iup.SetAttribute(matrix_sounds, "TYPE*:4", "IMAGE")
	iup.SetAttribute(matrix_sounds, "TYPE*:5", "IMAGE")
	iup.SetAttribute(matrix_sounds, "TYPE*:6", "IMAGE")
	
	function matrix_sounds:mousemove_cb(lin, col)
		if col >= 3 then
			self.cursor = "HAND"
		else
			self.cursor = "ARROW"
		end

		-- Logic to apply highlight to cells
		if lin > 0 and col >= 3 then
			-- If still on the same cell → do nothing
			if lin == hover_lin and col == hover_col then return iup.DEFAULT end
			-- Restore previous cell
			if hover_lin and hover_col then
				iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", hover_lin, hover_col), nil)
			end
			-- Highlight current cell
			-- iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", lin, col), "200 220 255")
			iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", lin, col), "215 220 235")

			hover_lin = lin
			hover_col = col

			iup.Update(self)
		else
			-- If mouse left matrix → restore previous cell
			if hover_lin and hover_col then
				iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", hover_lin, hover_col), nil)
				hover_lin = nil
				hover_col = nil
				iup.Update(self)
			end
		end
		return iup.DEFAULT
	end

	function matrix_sounds:leavewindow_cb()
		if hover_lin and hover_col then
			iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", hover_lin, hover_col), nil)
			hover_lin = nil
			hover_col = nil
			iup.Update(self)
		end
		return iup.DEFAULT
	end

	function matrix_sounds:enteritem_cb(lin, col)
		if LAST_CELL.col == 1 then
			iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", LAST_CELL.lin, LAST_CELL.col), BACKGROUND_COLOR)
		elseif LAST_CELL.col == 2 then
			iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", LAST_CELL.lin, LAST_CELL.col), "255 255 255")
		end

		-- Mark new cell
		if col == 1 then
			iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", lin, col), "214 229 255")
		elseif col == 2 then
			iup.SetAttribute(matrix_sounds, string.format("BGCOLOR%d:%d", lin, col), "235 242 255")
		end

		LAST_CELL.lin = lin
		LAST_CELL.col = col
	end


	-- Make cells with icons work as buttons
	function matrix_sounds:click_cb(lin, col)
		-- Skip rows with "Unused/Nothing"
		if matrix_sounds[lin..":1"] == "Unused/Nothing:" then return iup.DEFAULT end

		-- Play sound
		if col == 3 then
			stop_sound()
			play_sound(sound_filepaths[lin])
		-- Stop playback
		elseif col == 4 then
			stop_sound()
		-- Load new sound
		elseif col == 5 then
			stop_sound()
			local new_filepath = open_file_sound(sound_filepaths[lin])
			if new_filepath then
				sound_filepaths[lin] = new_filepath
				matrix_sounds[lin .. ":2"] = string.format(" %s.%s", get_filename_and_ext(sound_filepaths[lin]))
			end
		-- Mute sound effect
		elseif col == 6 then
			stop_sound()
			if matrix_sounds[lin .. ":2"] == " muted" then
				sound_filepaths[lin] = sound_filepaths_default[lin]
				matrix_sounds[lin .. ":2"] = string.format(" %s.%s", get_filename_and_ext(sound_filepaths[lin]))
			else
				sound_filepaths[lin] = "opensfx\\muted.wav"
				matrix_sounds[lin .. ":2"] = " muted"
			end
		end
	end

	-- Fill matrix with data
	for i = 1, #sound_filepaths_default do
		if sound_names[i] == "Unused/Nothing" then
		-- 	iup.SetAttribute(matrix_sounds, "FGCOLOR" .. i .. ":1", "120 120 120") 
		-- 	iup.SetAttribute(matrix_sounds, "FGCOLOR" .. i .. ":2", "120 120 120") 
			matrix_sounds["height"..i] = 0
		else
			matrix_sounds[i .. ":1"] = sound_names[i] .. ":"
			matrix_sounds[i .. ":2"] = string.format(" %s.%s", get_filename_and_ext(sound_filepaths[i]))
			matrix_sounds[i .. ":3"] = img_play
			matrix_sounds[i .. ":4"] = img_stop
			matrix_sounds[i .. ":5"] = img_open_m
			matrix_sounds[i .. ":6"] = img_mute
		end
	end
	matrix_sounds.redraw = "ALL"


	-- Create a rectangle to cover matrix title (a hacky way to make the first line look normal)
	local canvas_cover_title = iup.canvas{
		rastersize = "478x8",
		drawcolor = BACKGROUND_COLOR,
		drawstyle = "FILL",
		border = "NO",
		cx = 10,
		cy = 0,
		action = function(self)
			iup.DrawBegin(self)
			iup.DrawRectangle(self, 0, 0, 477, 7)
			iup.DrawEnd(self)
			return iup.DEFAULT
		end
	}
	

	local cbox_sounds = iup.cbox{
		canvas_cover_title,
		matrix_sounds,
		rastersize = dlg_width-40 .. "x" .. dlg_height-245
	}

	local frame_sounds = iup.frame{
		cbox_sounds,
		expand = "NO",
		title = " Sounds ",
	}

	iup.SetAttribute(frame_sounds, "FONTSTYLE", "Bold")
	for i = 0, iup.GetChildCount(frame_sounds) - 1 do
		local child = iup.GetChild(frame_sounds, i)
		iup.SetAttribute(child, "FONTSTYLE", "Normal")
	end


	-- #### BUTTONS ###########################################################################################

	local btn_open = iup.button{
		title = "Open",
		flat = "NO",
		image = img_open,
		imageposition = "top",
		rastersize = "41x60",
		action = function() open_project() return iup.DEFAULT end,
		canfocus = "NO",
		cx = 59,
		cy = 23,
		tip = "Load project from a file\n(or drag-n-drop)"
	}

	local btn_save = iup.button{
		title = "Save",
		flat = "NO",
		image = img_save,
		imageposition = "top",
		rastersize = "41x60",
		action = function() save_project() return iup.DEFAULT end,
		canfocus = "NO",
		cx = 10,
		cy = 23,
		tip = "Save project as..."
	}

	btn_encode = iup.button{
		flat = "NO",
		image = img_encode,
		imageposition = "LEFT",
		title = "  Encode",
		rastersize = "90x45",
		canfocus = "NO",
		cx = 10,
		cy = 95
	}
	iup.SetAttribute(btn_encode, "FONTSTYLE", "Bold")
	function btn_encode:action(...)
		if not inputs_are_ok() then
			return iup.DEFAULT
		else
			if iup.GetGlobal("MODKEYSTATE") ~= "    " then
				toggle_filetype("wav")

				local response = 1
				if wav_warning then
					response = show_message("WARNING",
						"WAV Format",
						"  Exporting audio in WAV format ensures compatibility\n" ..
						"  with OpenTTD versions prior to 15.0.\n\n" ..
						"  But at the cost of significantly increased file size!\n\n" ..
						"  Continue?",
						"OKCANCEL")
					wav_warning = false
				end

				if response == 1 then
					encode()
				else
					toggle_filetype("opus")
					return iup.DEFAULT
				end
			else
				encode()
			end
		end
	end

	-- Change icon under mouse while holding Shift, Ctrl or Alt
	function btn_encode:enterwindow_cb()
		if iup.GetGlobal("MODKEYSTATE") ~= "    " then
			self.image = img_encode2
			iup.Update(self)
		end
	end
	function btn_encode:leavewindow_cb()
		if FILETYPE ~= "wav" then
			self.image = img_encode
			iup.Update(self)
		end
	end


	local cbox_buttons = iup.cbox{
		btn_save,
		btn_open,
		btn_encode,
	}



	-- #### MAIN BOX ###########################################################################################

	local vbox_main = iup.vbox{
		iup.hbox{
			frame_header,
			cbox_buttons,
			margin = "0x0",
			gap = "0"
		},
		frame_sounds,
		margin = "10x10",
		gap = "10"
	}


	dlg:append(vbox_main)
	dlg:showxy(80, 5)


	if iup.MainLoopLevel() == 0 then
		iup.MainLoop()
		iup.Close()
	end

end


do
	build_gui()
end