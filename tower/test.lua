local open = io.open
local inspect = require('inspect')

local function read_file(path)
    local file = open(path, "rb") -- r read mode and b binary mode
    if not file then
        return nil
    end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

local fileContent = read_file("test.yaml");

obj = require('yaml').eval(fileContent)

local function test(obj)
    local health_status = {
        status = "Progressing",
        message = "Provisioning ..."
    }
    local ready = false

    if obj.status.repository.ok == false then
        health_status.status = "Degraded"
        health_status.message = obj.status.repository.message
        return health_status
    end

    for i, condition in ipairs(obj.status.conditions) do
        if condition.type == "LastAsyncOperation" then
            if condition.status == "False" then
                health_status.status = "Degraded"
                health_status.message = condition.message
                return health_status
            end
        end

        if condition.type == "Synced" then
            if condition.status == "False" then
                health_status.status = "Degraded"
                health_status.message = condition.message
                return health_status
            end
        end

        if condition.type == "Ready" then
            if condition.status == "True" then
                ready = true
            end
        end
    end

    if ready == false then
        return health_status
    end

    if obj.hasErrors == false then
        return health_status
    end

    local errors = ""
    for k, v in pairs(obj.status.report) do
        if k == "inputsValidation" then
            if v ~= "OK" then
                health_status.status = "Degraded"
                health_status.message = v
                return health_status
            end
        else
            for kk, vv in pairs(v) do
                if vv ~= "OK" then
                    errors = errors .. k .. "." .. kk .. ":" .. vv .. "\n"
                end
            end
        end
    end

    if errors ~= "" then
        health_status.status = "Degraded"
        health_status.message = errors
        return health_status
    end

    health_status.status = "Healthy"
    health_status.message = "Resource is up-to-date."
    return health_status
end

res = test(obj)
print(inspect(res))