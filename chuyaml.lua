--[[
A minimal YAML-like parser and serializer where full YAML support is unnecessary.

- chuyaml.parse(yaml: string) -> table
    Parses a simple, indentation-based YAML-like string into a Lua table.
    Supports strings, numbers, booleans, and nested mappings
    Does not support lists, quoted strings, or complex YAML features.
- chuyaml.to_yaml(tbl: table[, indent: number]) -> string
    Serializes a Lua table into a YAML-like formatted string.
    Supports nested tables and scalar values (string, number, boolean).
]]

local chuyaml = {}

-- Parses a simple YAML-like string into a Lua table
function chuyaml.parse(yaml)
    local result = {}
    -- Stack to manage nested tables
    local stack = {result}
    -- Track indentation levels
    local indent_levels = {0}

    for line in yaml:gmatch("[^\r\n]+") do
        -- Match indentation, key, and value from the current line
        -- local indent, key, value = line:match("^(%s*)([%w_%-]+):%s*(.*)$")
        local indent, key, value = line:match("^(%s*)([^:]+):%s*(.*)$")

        -- Trim whitespace, convert numbers to numeric keys
        key = key:match("^%s*(.-)%s*$")
        local numkey = tonumber(key)
        if numkey then key = numkey end

        if indent then
            -- Convert indentation to number of spaces, normalize empty string to nil
            indent = #indent
            value = (#value > 0) and value or nil

            -- Pop from the stack if the current indentation is less or equal than the last one
            while #indent_levels > 1 and indent <= indent_levels[#indent_levels] do
                table.remove(stack)
                table.remove(indent_levels)
            end

            -- Get the current table context
            local current = stack[#stack]
            -- Try to convert the value to appropriate Lua types
            if value then
                if tonumber(value) then
                    value = tonumber(value)
                elseif value == "true" then
                    value = true
                elseif value == "false" then
                    value = false
                end
                current[key] = value
            else
                -- Start a new nested table
                current[key] = {}
                table.insert(stack, current[key])
                table.insert(indent_levels, indent)
            end
        end
    end

    return result
end

-- Converts a Lua table into a simple YAML-like string
function chuyaml.to_yaml(tbl, indent)
    -- Helper function to check if a value is a scalar
    local function is_scalar(val)
        local t = type(val)
        return t == "string" or t == "number" or t == "boolean"
    end

    -- Optional argument - default indent level
    indent = indent or 0
    -- List of YAML lines
    local lines = {}
    -- Indent prefix
    local prefix = string.rep("  ", indent)

    for k, v in pairs(tbl) do
        if is_scalar(v) then
            -- Convert boolean values to YAML-style strings
            if type(v) == "boolean" then
                v = v and "true" or "false"
            end
            -- Add a scalar key-value line
            table.insert(lines, string.format("%s%s: %s", prefix, tostring(k), tostring(v)))
        elseif type(v) == "table" then
            -- Start a new nested section
            table.insert(lines, string.format("%s%s:", prefix, tostring(k)))
            local nested_yaml = chuyaml.to_yaml(v, indent + 1)
            table.insert(lines, nested_yaml)
        else
            error("Unsupported value type: " .. type(v))
        end
    end

    return table.concat(lines, "\n")
end


return chuyaml