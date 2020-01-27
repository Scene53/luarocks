--- A purelua build system
--[[

--]]

local purelua = {}
local fs = require("luarocks.fs")
local path = require("luarocks.path")
local util = require("luarocks.util")
local cfg = require("luarocks.core.cfg")
local dir = require("luarocks.dir")
local json = require("luarocks.tools.json")

--- Run a command displaying its execution on standard output.
-- @return boolean: true if command succeeds (status code 0), false
-- otherwise.
local function execute(...)
    io.stdout:write(table.concat({...}, " ").."\n")
    return fs.execute(...)
end


do -- this is the run chunk
    local function func(string_arr, str)
        for _, str_to_check in pairs(string_arr) do
            if str:match(str_to_check) then
                return true
            end
        end
    end

    local function is_file_excluded(file, build)
        local file_name = dir.base_name(file)
        local dir_name = dir.dir_name(file)
        local is_lua_file = file:match("(.*)%.lua$")
        if is_lua_file then
            if func(build.file_name_restrections or {}, file_name) or func(build.dir_name_restrections or {}, dir_name) then
                return true
            else
                return false
            end
        end
        return true
    end

    local function add_module_to_map(map, file, luadir, build)
        if not is_file_excluded(file, build) then
            local dest = dir.path(luadir, file)
            map[file] = dest
        end
    end

    local function should_iterate_recursively(module_data)
        -- this can maybe later move to some annotations manager...
        local asterisks = module_data:match('*+')
        if not asterisks then
        else
            local num_astrisks = asterisks:len()
            if num_astrisks == 1 then
                return false
            elseif num_astrisks == 2 then
                return true
            else
            end
        end
    end

    local function parse_module_path(module_data)
        local module_path = string.gsub(module_data, '(/)*+', "")
        local should_iterate_recursively = should_iterate_recursively(module_data)
        return module_path, should_iterate_recursively
    end

    local function create_module_to_destination_map(rockspec)
        local modules_to_destination = {}
        local build = rockspec.build
        local luadir = path.lua_dir(rockspec.name, rockspec.version)

        -- module_data is the module path with an annotation attached to it (/*, /**)
        -- this annotation announce the way purelua will iterate dirs

        for _, module_data in pairs(build.modules) do
            local module_path, should_iterate_recursively = parse_module_path(module_data)

            if should_iterate_recursively then
                for _, file in ipairs(fs.find(module_path)) do
                    local file_path = module_path .. "/" .. file
                    add_module_to_map(modules_to_destination, file_path, luadir, build)
                end
            else
                for file in fs.dir(module_path) do
                    local file_path = module_path .. "/" .. file
                    if fs.is_file(file_path) then
                        add_module_to_map(modules_to_destination, file_path, luadir, build)
                    end
                end
            end
        end

        return modules_to_destination
    end


    local function write_new_file(filename, str)
        local fh = io.open(filename, "wb")
        if not fh then return false end
        fh:write(str)
        fh:close()
        return true
    end

    local function  get_meta_data_defaults(rockspec)
        local build_meta_data_defaults = {
            type = "code", -- default value
            id = rockspec.package,
            version = rockspec.version
            -- deps??
        }

        return build_meta_data_defaults

    end




    local function get_build_meta_data(rockspec)
        assert(rockspec:type() == "rockspec")
        local build_meta_data = rockspec.build.meta or {}
        local build_meta_data_defaults = get_meta_data_defaults(rockspec)

        for k, v in pairs(build_meta_data_defaults) do
            build_meta_data[k] = build_meta_data[k] or build_meta_data_defaults[k]
        end

        return build_meta_data
    end


    --- Driver function for the purelua build back-end.
    -- it iterates modules and copy them to the lib dir
    -- @param rockspec table: the loaded rockspec.
    -- @return boolean or (nil, string): true if no errors ocurred,
    -- nil and an error message otherwise.
    function purelua.run(rockspec, extraParams)
        assert(rockspec:type() == "rockspec")

        local obfuscate = extraParams.obfuscate
        local modules_to_destination = create_module_to_destination_map(rockspec)
        local perms = "read"
        for name, dest in pairs(modules_to_destination) do
            fs.make_dir(dir.dir_name(dest))
            ok, err = fs.copy(name, dest, perms)
            if not ok then
                return nil, "Failed installing "..name.." in "..dest..": "..err
            end
            if obfuscate then
                local dir_name = dir.dir_name(dest)
                local file_name = dir.base_name(dest)

                -- chaging dir cause scriptEncryptor can't hadndle dots (".") in path
                local ok, err = fs.change_dir(dir_name)
                if not ok then return nil, err end

                local ok, err = fs.encrypt_script(file_name)
                if ok then
                    fs.delete(dest)
                end
                fs.pop_dir()
            end
        end

        -- build meta data can be used by a build system that uses this rock
        local build_meta_data = get_build_meta_data(rockspec)
        --        local json_ok, json = util.require_json()
        --        if not json_ok then return nil, "A JSON library is required for this command. "..json end
        local stringify = json.stringify(build_meta_data)
        local deploy_dir = path.install_dir(rockspec.name, rockspec.version)     --path.lua_dir(rockspec.name, rockspec.version)
        local meta_build_file_name = "meta.json"
        local dest = dir.path(deploy_dir, meta_build_file_name)
        write_new_file(dest, stringify)



        return true
    end
end


-- delivering deafult build configuration
do
    local function autodetect_modules(rockspec)
        local modules = {}
        modules[rockspec.name] = "./**"
        return modules
    end

    local function get_deafult_dir_name_restrections()
        return {"test"}
    end

    local function get_deafult_file_name_restrections()
        return {"test"}
    end

    function purelua.get_default_build_config(rockspec)
        local build = {}
        build.type = "purelua"
        build.modules = autodetect_modules(rockspec)
        build.dir_name_restrections = get_deafult_dir_name_restrections()
        build.file_name_restrections = get_deafult_file_name_restrections()
        build.install_files_in_package_dir = true
        return build
    end
end

--[[
dir_name_restrections
]]--

return purelua
